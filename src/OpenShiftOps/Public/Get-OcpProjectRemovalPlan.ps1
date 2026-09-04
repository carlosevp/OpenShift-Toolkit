function Get-OcpProjectRemovalPlan {
    <#
    .SYNOPSIS
        Builds a deletion plan for a project without deleting anything.
    .DESCRIPTION
        Re-evaluates live cluster state. PVC presence, protected projects, and
        system namespaces set CanProceed to false. A plan is evidence, not approval
        to delete.
    .PARAMETER Name
        Project name.
    .PARAMETER Cluster
        Cluster alias that must match the current oc context.
    .EXAMPLE
        Get-OcpProjectRemovalPlan -Name old-claims-dev
    .OUTPUTS
        OpenShiftOps.ProjectRemovalPlan
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Project')]
        [string]$Name,

        [string]$Cluster,
        [string]$ChangeReference
    )

    process {
        Assert-OcpProjectName -Name $Name
        $context = New-OcpOperationContext -Operation 'Get-OcpProjectRemovalPlan' -ClusterAlias $Cluster -Project $Name -ChangeReference $ChangeReference
        Assert-OcpPermission -Verb get -Resource namespaces -Name $Name | Out-Null

        $inventory = Get-OcpProjectInventory -Namespace $Name -IncludePvcDetails
        $policy = (Get-OcpConfiguration).safety.projectDeletion
        $warnings = New-Object System.Collections.Generic.List[string]
        $blockers = New-Object System.Collections.Generic.List[string]

        if ($inventory.ProtectedProject -and $policy.blockProtectedProjects -eq $true) {
            $blockers.Add("Protected project. Reasons: $($inventory.ProtectionReasons -join ', '). There is no deletion override for protected or platform namespaces.")
        }
        if ($inventory.SystemProject -and $policy.blockSystemProjects -eq $true) {
            $blockers.Add('System/platform project detected. Deletion is refused.')
        }
        if ($inventory.PersistentStorageDetected -and $policy.blockWhenPVCsExist -eq $true) {
            $count = $inventory.PVCCount
            $blockers.Add(@"
Persistent volumes detected.

Project contains $count PersistentVolumeClaims.
Manifest export does not protect persistent application data.
Use an approved backup/snapshot mechanism or provide an explicitly
authorized override (-AllowDeleteWithPersistentVolumes) if policy permits.
"@.Trim())
        }

        if ($inventory.RunningPodCount -gt 0 -and $policy.blockWhenRunningWorkloadsExist -eq $true) {
            $blockers.Add("Running pods detected: $($inventory.RunningPodCount).")
        }
        elseif ($inventory.RunningPodCount -gt 0) {
            $warnings.Add("Project still has $($inventory.RunningPodCount) running pod(s).")
        }

        $warnings.Add('A YAML safety export is a Safety Export, not a Persistent Data Backup.')
        $warnings.Add('Secret values are excluded from normal safety exports.')
        $warnings.Add('This plan is not an approval. Remove-OcpProject re-validates live state before deletion.')

        $canProceed = $blockers.Count -eq 0
        $plan = [pscustomobject]@{
            PSTypeName                = 'OpenShiftOps.ProjectRemovalPlan'
            OperationId               = $context.OperationId
            Cluster                   = $context.FriendlyName
            ClusterId                 = $context.ClusterId
            FriendlyName              = $context.FriendlyName
            Server                    = $context.Server
            Project                   = $Name
            Environment               = $inventory.Environment
            Owner                     = $inventory.Owner
            Application               = $inventory.Application
            Classification            = $context.Classification
            CreatedDate               = $inventory.Created
            AgeDays                   = $inventory.AgeDays
            PodCount                  = $inventory.PodCount
            RunningPodCount           = $inventory.RunningPodCount
            DeploymentCount           = $inventory.DeploymentCount
            StatefulSetCount          = $inventory.StatefulSetCount
            RouteCount                = $inventory.RouteCount
            PVCCount                  = $inventory.PVCCount
            SecretCount               = $inventory.SecretCount
            ConfigMapCount            = $inventory.ConfigMapCount
            CronJobCount              = $inventory.CronJobCount
            PersistentStorageDetected = [bool]$inventory.PersistentStorageDetected
            PersistentVolumeClaims    = $inventory.PersistentVolumeClaims
            ProtectedProject          = [bool]$inventory.ProtectedProject
            CleanupProtected          = [bool]$inventory.CleanupProtected
            SystemProject             = [bool]$inventory.SystemProject
            Warnings                  = $warnings.ToArray()
            BlockingConditions        = $blockers.ToArray()
            Risk                      = 'Destructive'
            CanProceed                = $canProceed
            ChangeReference           = $ChangeReference
            GeneratedAt               = [DateTime]::UtcNow
        }

        $plan | Add-Member -NotePropertyName Markdown -NotePropertyValue (ConvertTo-OcpProjectRemovalPlanMarkdown -Plan $plan)
        $plan
    }
}
