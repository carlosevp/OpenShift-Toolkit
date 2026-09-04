function Remove-OcpProject {
    <#
    .SYNOPSIS
        Deletes an OpenShift project after live revalidation and a verified safety export.
    .DESCRIPTION
        Fail-closed deletion. Protected/system projects cannot be deleted. Projects with
        PVCs are blocked unless policy allows -AllowDeleteWithPersistentVolumes and that
        switch is explicitly provided. The function never trusts a stale plan: it rebuilds
        the plan and compares material conditions before deletion.
    .PARAMETER Name
        Project name.
    .PARAMETER ApprovedPlan
        Optional plan object previously returned by Get-OcpProjectRemovalPlan. Material
        differences abort the operation.
    .PARAMETER AllowDeleteWithPersistentVolumes
        Explicit, policy-gated override. Not equivalent to -Force. Disabled by default.
    .EXAMPLE
        Remove-OcpProject -Name old-claims-dev -WhatIf
    .EXAMPLE
        $plan = Get-OcpProjectRemovalPlan -Name old-claims-dev
        Remove-OcpProject -Name old-claims-dev -ApprovedPlan $plan -ChangeReference CHG123456
    .OUTPUTS
        OpenShiftOps.ProjectDeletion
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Project')]
        [string]$Name,

        [object]$ApprovedPlan,
        [switch]$AllowDeleteWithPersistentVolumes,
        [string]$Cluster,
        [string]$ChangeReference,
        [string]$SafetySnapshotPath
    )

    process {
        Assert-OcpProjectName -Name $Name
        $context = New-OcpOperationContext -Operation 'Remove-OcpProject' -ClusterAlias $Cluster -Project $Name -ChangeReference $ChangeReference
        $policy = (Get-OcpConfiguration).safety.projectDeletion

        Assert-OcpPermission -Verb delete -Resource projects | Out-Null
        Assert-OcpPermission -Verb get -Resource namespaces -Name $Name | Out-Null

        $livePlan = Get-OcpProjectRemovalPlan -Name $Name -Cluster $context.ClusterAlias -ChangeReference $ChangeReference
        if ($ApprovedPlan) {
            $comparison = Compare-OcpRemovalPlan -ApprovedPlan $ApprovedPlan -CurrentPlan $livePlan
            if ($comparison.MaterialChange) {
                $detail = $comparison.Changes -join '; '
                throw [OcpStalePlanException]::new(
                    "The approved deletion plan is stale and must be regenerated. $detail"
                )
            }
        }

        $labels = (Get-OcpProjectObject -Name $Name).metadata.labels
        Assert-OcpProjectNotProtected -Name $Name -Labels $labels | Out-Null

        $pvcBlocked = $false
        if ($livePlan.PersistentStorageDetected) {
            if ($policy.blockWhenPVCsExist -eq $true) {
                if (-not $policy.allowPersistentVolumeOverride) {
                    $pvcBlocked = $true
                }
                elseif (-not $AllowDeleteWithPersistentVolumes) {
                    $pvcBlocked = $true
                }
            }
        }

        if ($pvcBlocked) {
            $message = @"
BLOCKED

Project contains $($livePlan.PVCCount) PersistentVolumeClaims.

Manifest export does not protect persistent application data.

Use an approved backup/snapshot mechanism or provide an explicitly
authorized override after policy enables allowPersistentVolumeOverride.
"@
            $null = New-OcpAuditRecord -Context $context -Result 'Blocked' -Target $Name -PersistentVolumesDetected $true -Message $message.Trim()
            throw [OcpSafetyException]::new($message.Trim())
        }

        if ($AllowDeleteWithPersistentVolumes) {
            if (-not $policy.allowPersistentVolumeOverride) {
                throw [OcpSafetyException]::new(
                    '-AllowDeleteWithPersistentVolumes was requested but safety.projectDeletion.allowPersistentVolumeOverride is false.'
                )
            }
            Write-OcpLog -Level Audit -Message "HIGH SEVERITY OVERRIDE: AllowDeleteWithPersistentVolumes for $Name" -OperationId $context.OperationId
        }

        if (-not $livePlan.CanProceed -and -not ($AllowDeleteWithPersistentVolumes -and $livePlan.PersistentStorageDetected -and $livePlan.BlockingConditions.Count -eq 1)) {
            if ($livePlan.ProtectedProject -or $livePlan.SystemProject) {
                throw [OcpProtectedProjectException]::new(($livePlan.BlockingConditions -join ' '))
            }
            if (-not $AllowDeleteWithPersistentVolumes) {
                throw [OcpSafetyException]::new(($livePlan.BlockingConditions -join "`n"))
            }
        }

        $snapshot = $null
        if ($policy.requireSafetyExport -eq $true) {
            if ($SafetySnapshotPath) {
                $snapshot = Test-OcpSafetySnapshot -ManifestPath $SafetySnapshotPath
            }
            else {
                $snapshot = Export-OcpProjectSafetySnapshot -Name $Name -Cluster $context.ClusterAlias -ChangeReference $ChangeReference
            }
            if ($snapshot.ExportStatus -and $snapshot.ExportStatus -ne 'Success') {
                throw [OcpBackupException]::new('Safety export did not succeed. Deletion aborted (fail closed).')
            }
            if ($snapshot.Valid -eq $false) {
                throw [OcpBackupException]::new('Safety export verification failed. Deletion aborted (fail closed).')
            }
        }

        $target = $Name
        $action = "DELETE PROJECT '$Name' on $($context.FriendlyName) [$($context.ClusterId)] classification=$($context.Classification) risk=Destructive"
        if ($AllowDeleteWithPersistentVolumes) {
            $action += ' WITH PERSISTENT VOLUME OVERRIDE'
        }

        if (-not $PSCmdlet.ShouldProcess($target, $action)) {
            return [pscustomobject]@{
                PSTypeName              = 'OpenShiftOps.ProjectDeletion'
                Project                 = $Name
                Cluster                 = $context.FriendlyName
                ClusterId               = $context.ClusterId
                FriendlyName            = $context.FriendlyName
                Classification          = $context.Classification
                Result                  = 'WhatIf'
                Plan                    = $livePlan
                SafetySnapshot          = $snapshot
                PersistentVolumesDetected = $livePlan.PersistentStorageDetected
                OverrideUsed            = [bool]$AllowDeleteWithPersistentVolumes
                OperationId             = $context.OperationId
            }
        }

        # Revalidate immediately before the destructive call (approvals may have waited).
        Assert-OcpClusterIdentity -Cluster $context.ClusterId
        $revalidated = Get-OcpProjectRemovalPlan -Name $Name -Cluster $context.ClusterId -ChangeReference $ChangeReference
        $finalCompare = Compare-OcpRemovalPlan -ApprovedPlan $livePlan -CurrentPlan $revalidated
        if ($finalCompare.MaterialChange) {
            throw [OcpStalePlanException]::new(
                "Project state changed immediately before deletion: $($finalCompare.Changes -join '; ')"
            )
        }
        Assert-OcpProjectNotProtected -Name $Name -Labels (Get-OcpProjectObject -Name $Name).metadata.labels | Out-Null

        if ($revalidated.PersistentStorageDetected -and -not $AllowDeleteWithPersistentVolumes) {
            throw [OcpSafetyException]::new('PVCs are present immediately before deletion. Aborting.')
        }

        Invoke-OcpCli -ArgumentList @('delete', 'project', $Name) | Out-Null

        $stillThere = Get-OcpProjectObject -Name $Name
        $gone = $null -eq $stillThere
        $result = if ($gone) { 'Success' } else { 'PendingDeletion' }

        $audit = New-OcpAuditRecord -Context $context -Result $result -Target $Name `
            -SafetyExportStatus $(if ($snapshot) { 'Success' } else { 'Skipped' }) `
            -PersistentVolumesDetected $livePlan.PersistentStorageDetected `
            -Message "Remove-OcpProject $result override=$([bool]$AllowDeleteWithPersistentVolumes)" `
            -Warnings @($livePlan.Warnings)

        [pscustomobject]@{
            PSTypeName                = 'OpenShiftOps.ProjectDeletion'
            Project                   = $Name
            Cluster                   = $context.FriendlyName
            ClusterId                 = $context.ClusterId
            FriendlyName              = $context.FriendlyName
            Classification            = $context.Classification
            Result                    = $result
            VerifiedRemoved           = $gone
            Plan                      = $revalidated
            SafetySnapshot            = $snapshot
            PersistentVolumesDetected = $livePlan.PersistentStorageDetected
            OverrideUsed              = [bool]$AllowDeleteWithPersistentVolumes
            AuditPath                 = $audit.auditPath
            OperationId               = $context.OperationId
        }
    }
}
