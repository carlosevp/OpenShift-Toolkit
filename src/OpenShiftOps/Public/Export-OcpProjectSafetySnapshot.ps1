function Export-OcpProjectSafetySnapshot {
    <#
    .SYNOPSIS
        Creates a project safety export (manifest snapshot) for recovery and audit.
    .DESCRIPTION
        Captures inventory plus sanitized restorable manifests. Secret values are
        excluded. PVC data is not included. Output is a recovery aid, not a
        disaster-recovery backup.
    .PARAMETER Name
        Project name.
    .PARAMETER OutputPath
        Optional root directory. Defaults to the OpenShiftOps artifact root.
    .EXAMPLE
        Export-OcpProjectSafetySnapshot -Name old-claims-dev
    .OUTPUTS
        OpenShiftOps.SafetySnapshot
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Project')]
        [string]$Name,

        [string]$Cluster,
        [string]$OutputPath,
        [string]$ChangeReference
    )

    process {
        Assert-OcpProjectName -Name $Name
        $context = New-OcpOperationContext -Operation 'Export-OcpProjectSafetySnapshot' -ClusterAlias $Cluster -Project $Name -ChangeReference $ChangeReference
        Assert-OcpPermission -Verb get -Resource namespaces -Name $Name | Out-Null

        $secretExportEnabled = [bool](Get-OcpConfiguration).safety.secretExport.enabled
        if ($secretExportEnabled) {
            throw [OcpSafetyException]::new('Secret value export is not implemented and cannot be enabled.')
        }

        $timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHHmmssZ')
        if (-not $OutputPath) {
            $OutputPath = Join-Path (Get-OcpArtifactRoot) $timestamp $context.OperationId
        }
        else {
            $OutputPath = Join-Path $OutputPath $timestamp $context.OperationId
        }

        New-Item -ItemType Directory -Path (Join-Path $OutputPath 'resources') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $OutputPath 'recovery') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $OutputPath 'inventory') -Force | Out-Null

        $warnings = New-Object System.Collections.Generic.List[string]
        $warnings.Add('Manifest exports do not back up persistent volume data.')
        $warnings.Add('Manifest exports do not contain secret values.')
        $warnings.Add('Manifests are recovery aids and not a replacement for enterprise backup/disaster recovery.')

        $inventory = Get-OcpProjectInventory -Namespace $Name -IncludePvcDetails -IncludeTransient
        $projectObject = $inventory.Project
        $sanitizedProject = ConvertTo-OcpRecoveryManifest -Resource $projectObject
        Set-Content -LiteralPath (Join-Path $OutputPath 'project.yaml') -Value (ConvertTo-OcpYamlDocument -Resource $sanitizedProject) -Encoding UTF8

        $discovered = @(Get-OcpNamespacedApiResource)
        $inventoryKinds = New-Object System.Collections.Generic.List[object]
        $inventoryCount = 0
        foreach ($kind in $discovered) {
            if ([string]::IsNullOrWhiteSpace($kind)) { continue }
            try {
                $items = @(Get-OcpJsonItems -ArgumentList @('get', $kind, '-n', $Name, '-o', 'json'))
                $names = @($items | ForEach-Object { [string]$_.metadata.name })
                $inventoryKinds.Add([pscustomobject]@{
                    Resource = $kind
                    Count    = $items.Count
                    Names    = $names
                    Transient = [bool]((Get-OcpTransientResourceKinds) -contains $kind)
                })
                $inventoryCount += $items.Count
            }
            catch {
                $warnings.Add("Inventory skipped for $kind : $($_.Exception.Message)")
            }
        }

        $inventoryDocument = [pscustomobject]@{
            project                 = $Name
            cluster                 = $context.FriendlyName
            clusterId               = $context.ClusterId
            clusterFriendlyName     = $context.FriendlyName
            collectedAt             = [DateTime]::UtcNow.ToString('o')
            resourceTypesDiscovered = $discovered.Count
            resources               = $inventoryKinds
            persistentVolumeClaims  = $inventory.PersistentVolumeClaims
            secretNames             = @($inventory.Collections.secrets | ForEach-Object {
                [pscustomobject]@{
                    name = [string]$_.metadata.name
                    type = [string]$_.type
                }
            })
        }
        Set-Content -LiteralPath (Join-Path $OutputPath 'inventory.json') -Value ($inventoryDocument | ConvertTo-Json -Depth 8) -Encoding UTF8

        $exportedTypes = 0
        $exportedCount = 0
        foreach ($kind in Get-OcpRestorableResourceKinds) {
            $path = Join-Path $OutputPath 'resources' $kind.File
            try {
                $count = Export-OcpResourceList -Namespace $Name -Resource $kind.Resource -OutputPath $path -Sanitize -ExcludeSecretData
                $exportedTypes++
                $exportedCount += $count
            }
            catch {
                $warnings.Add("Restorable export skipped for $($kind.Resource): $($_.Exception.Message)")
            }
        }

        $status = if ($exportedTypes -gt 0) { 'Success' } else { 'Failed' }
        $manifestPath = Join-Path $OutputPath 'backup-manifest.json'
        $backupManifest = New-OcpBackupManifest -Context $context -Project $Name -ExportStatus $status `
            -ResourceTypesDiscovered $discovered.Count -ResourceTypesExported $exportedTypes `
            -ResourceCount $exportedCount -PersistentVolumeCount $inventory.PVCCount `
            -Warnings $warnings.ToArray() -OutputPath $manifestPath

        $metadata = [ordered]@{
            operationId   = $context.OperationId
            cluster       = $context.FriendlyName
            clusterId     = $context.ClusterId
            clusterFriendlyName = $context.FriendlyName
            server        = $context.Server
            project       = $Name
            timestamp     = [DateTime]::UtcNow.ToString('o')
            requestedBy   = $context.RequestedBy
            authenticatedIdentity = $context.Username
            authenticationMethod = $context.AuthenticationMethod
            executionMode = $context.ExecutionMode
            provider      = 'ManifestExport'
            secretsPolicy = 'values-excluded'
            persistentDataBackup = $false
        }
        Set-Content -LiteralPath (Join-Path $OutputPath 'metadata.json') -Value ($metadata | ConvertTo-Json -Depth 6) -Encoding UTF8

        $restoreOrder = Get-OcpRestoreOrder
        Set-Content -LiteralPath (Join-Path $OutputPath 'recovery' 'restore-order.json') -Value ($restoreOrder | ConvertTo-Json) -Encoding UTF8
        $recoverySummary = @"
# Recovery summary (AID, not a guaranteed restore)

Project: $Name
Cluster: $($context.FriendlyName)
Cluster ID: $($context.ClusterId)
Operation: $($context.OperationId)

These files are **recovery aids**. They are not an enterprise disaster-recovery solution.

## What this snapshot DOES NOT protect

- Persistent volume data / PVC contents
- Kubernetes/OpenShift Secret values
- Transient objects (Pods, Events, replica-sets, endpoints, leases)
- Live image blobs unless they remain in an ImageStream/registry

Secrets should be recovered from their authoritative source (Vault, Azure Key Vault, External Secrets, GitOps, Sealed Secrets, or another enterprise mechanism). This toolkit does not assume a specific secret manager.

## Suggested restore order

$($restoreOrder | ForEach-Object { "- $_" } | Out-String)
"@
        Set-Content -LiteralPath (Join-Path $OutputPath 'recovery' 'recovery-summary.md') -Value $recoverySummary.Trim() -Encoding UTF8

        $summary = @"
# Safety export summary

Project: $Name
Cluster: $($context.FriendlyName)
Cluster ID: $($context.ClusterId)
Status: $status
Resource types discovered: $($discovered.Count)
Resource types exported: $exportedTypes
Restorable resource count: $exportedCount
PVCs: $($inventory.PVCCount)
Secrets excluded: true

Warnings:
$($warnings | ForEach-Object { "- $_" } | Out-String)
"@
        Set-Content -LiteralPath (Join-Path $OutputPath 'summary.md') -Value $summary.Trim() -Encoding UTF8

        if ($status -ne 'Success') {
            throw [OcpBackupException]::new("Safety export failed for project '$Name'. Destructive operations must fail closed.")
        }

        $verification = Test-OcpSafetySnapshot -ManifestPath $manifestPath
        [pscustomobject]@{
            PSTypeName              = 'OpenShiftOps.SafetySnapshot'
            OperationId             = $context.OperationId
            Cluster                 = $context.FriendlyName
            ClusterId               = $context.ClusterId
            FriendlyName            = $context.FriendlyName
            Project                 = $Name
            Path                    = $OutputPath
            ManifestPath            = $manifestPath
            ExportStatus            = $status
            ResourceTypesDiscovered = $discovered.Count
            ResourceTypesExported   = $exportedTypes
            ResourceCount           = $exportedCount
            PersistentVolumeCount   = $inventory.PVCCount
            SecretsExcluded         = $true
            PersistentDataBackup    = $false
            Warnings                = $warnings.ToArray()
            Verification            = $verification
            BackupManifest          = $backupManifest
        }
    }
}
