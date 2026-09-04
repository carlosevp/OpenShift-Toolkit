function Get-OcpProjectDetails {
    <#
    .SYNOPSIS
        Returns a detailed inventory for a single OpenShift project.
    .PARAMETER Name
        Project / namespace name.
    .PARAMETER Cluster
        Optional cluster alias used to verify the current oc context.
    .EXAMPLE
        Get-OcpProjectDetails -Name claims-dev
    .OUTPUTS
        OpenShiftOps.ProjectDetails
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Project')]
        [string]$Name,

        [string]$Cluster
    )

    process {
        Assert-OcpProjectName -Name $Name
        $context = New-OcpOperationContext -Operation 'Get-OcpProjectDetails' -ClusterAlias $Cluster -Project $Name
        Assert-OcpPermission -Verb get -Resource namespaces -Name $Name | Out-Null

        $inventory = Get-OcpProjectInventory -Namespace $Name -IncludePvcDetails
        $standards = Test-OcpProjectStandards -Project $Name -Cluster $context.ClusterAlias -Quiet

        [pscustomobject]@{
            PSTypeName                = 'OpenShiftOps.ProjectDetails'
            Name                      = $inventory.Name
            Cluster                   = $context.FriendlyName
            ClusterId                 = $context.ClusterId
            FriendlyName              = $context.FriendlyName
            Classification            = $context.Classification
            Server                    = $context.Server
            Environment               = $inventory.Environment
            Owner                     = $inventory.Owner
            Application               = $inventory.Application
            Lifecycle                 = $inventory.Lifecycle
            Created                   = $inventory.Created
            AgeDays                   = $inventory.AgeDays
            PodCount                  = $inventory.PodCount
            RunningPodCount           = $inventory.RunningPodCount
            DeploymentCount           = $inventory.DeploymentCount
            ActiveDeploymentCount     = $inventory.ActiveDeploymentCount
            StatefulSetCount          = $inventory.StatefulSetCount
            DaemonSetCount            = $inventory.DaemonSetCount
            ServiceCount              = $inventory.ServiceCount
            RouteCount                = $inventory.RouteCount
            PVCCount                  = $inventory.PVCCount
            PersistentVolumeClaims    = $inventory.PersistentVolumeClaims
            SecretCount               = $inventory.SecretCount
            ConfigMapCount            = $inventory.ConfigMapCount
            CronJobCount              = $inventory.CronJobCount
            JobCount                  = $inventory.JobCount
            BuildConfigCount          = $inventory.BuildConfigCount
            ImageStreamCount          = $inventory.ImageStreamCount
            ProtectedProject          = $inventory.ProtectedProject
            CleanupProtected          = $inventory.CleanupProtected
            SystemProject             = $inventory.SystemProject
            ProtectionReasons         = $inventory.ProtectionReasons
            Standards                 = $standards
            Labels                    = $inventory.Labels
        }
    }
}
