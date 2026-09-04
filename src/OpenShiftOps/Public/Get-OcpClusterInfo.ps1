function Get-OcpClusterInfo {
    <#
    .SYNOPSIS
        Lists configured clusters or returns details for one cluster.
    .DESCRIPTION
        Without -Cluster, returns the configured catalog (no live authentication).
        With -Cluster, returns the canonical record. If oc is authenticated to a
        different API server, the command fails closed.
    .PARAMETER Cluster
        Friendly name, alias, or canonical ID.
    .EXAMPLE
        Get-OcpClusterInfo
    .EXAMPLE
        Get-OcpClusterInfo -Cluster Akron-Prod
    .OUTPUTS
        OpenShiftOps.ClusterInfo
    #>
    [CmdletBinding()]
    param(
        [string]$Cluster
    )

    if (-not $Cluster) {
        $clusters = (Get-OcpConfiguration).clusters
        foreach ($id in ($clusters.Keys | Sort-Object)) {
            New-OcpClusterInfoRecord -Cluster (New-OcpClusterRecord -Id $id -Cluster $clusters[$id])
        }
        return
    }

    $target = Resolve-OcpCluster -Cluster $Cluster
    $live = $null
    try {
        $live = Test-OcpAuthentication
    }
    catch {
        Write-OcpLog -Level Verbose -Message 'No live oc authentication; returning catalog details only.'
    }

    if ($live) {
        $identity = Test-OcpClusterIdentity -Cluster $target.Id -ThrowOnMismatch:$false
        if (-not $identity.Match) {
            throw [OcpClusterIdentityException]::new(
                (New-OcpClusterIdentityMismatchMessage -Requested $target -ActualServer $identity.ActualServer)
            )
        }
    }

    New-OcpClusterInfoRecord -Cluster $target -Authentication $live -Detailed
}

function New-OcpClusterInfoRecord {
    param(
        [Parameter(Mandatory = $true)]
        $Cluster,
        $Authentication,
        [switch]$Detailed
    )

    $ado = [pscustomobject]@{
        ServiceConnection            = $Cluster.ServiceConnection
        ReadServiceConnection        = $Cluster.ReadServiceConnection
        MaintenanceServiceConnection = $Cluster.MaintenanceServiceConnection
        DestructiveServiceConnection = $Cluster.DestructiveServiceConnection
    }

    $record = [pscustomobject]@{
        PSTypeName        = 'OpenShiftOps.ClusterInfo'
        Id                = $Cluster.Id
        ClusterId         = $Cluster.Id
        FriendlyName      = $Cluster.FriendlyName
        ClusterAlias      = $Cluster.Id
        Aliases           = $Cluster.Aliases
        DisplayName       = $Cluster.FriendlyName
        Server            = $Cluster.Server
        Classification    = $Cluster.Classification
        Location          = $Cluster.Location
        Purpose           = $Cluster.Purpose
        Description       = $Cluster.Description
        Registered        = $Cluster.Registered
        AzureDevOps       = $ado
    }

    if ($Authentication) {
        $record | Add-Member -NotePropertyName OpenShiftVersion -NotePropertyValue $Authentication.OpenShiftVersion
        $record | Add-Member -NotePropertyName KubernetesVersion -NotePropertyValue $Authentication.KubernetesVersion
        $record | Add-Member -NotePropertyName Username -NotePropertyValue $Authentication.Username
        $record | Add-Member -NotePropertyName Authenticated -NotePropertyValue $true
        $record | Add-Member -NotePropertyName ExecutionMode -NotePropertyValue (Get-OcpExecutionMode)
        $record | Add-Member -NotePropertyName AuthenticationMethod -NotePropertyValue (Get-OcpAuthenticationMethod)
    }
    elseif ($Detailed) {
        $record | Add-Member -NotePropertyName Authenticated -NotePropertyValue $false
    }

    return $record
}
