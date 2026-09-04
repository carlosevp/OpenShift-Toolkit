function Resolve-OcpCluster {
    <#
    .SYNOPSIS
        Resolves a canonical ID, friendly name, or alias to the configured cluster record.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Name')]
    param(
        [Parameter(ParameterSetName = 'Name', Position = 0)]
        [Alias('Alias')]
        [string]$Cluster,

        [Parameter(ParameterSetName = 'Server')]
        [string]$Server,

        [switch]$AllowUnknown
    )

    $config = Get-OcpConfiguration
    $clusters = $config.clusters

    if ($PSCmdlet.ParameterSetName -eq 'Name' -or $Cluster) {
        if ([string]::IsNullOrWhiteSpace($Cluster)) {
            throw [OcpValidationException]::new('Resolve-OcpCluster requires -Cluster or -Server.')
        }

        $key = ConvertTo-OcpClusterLookupKey -Name $Cluster
        $index = $config.clusterIndex
        if (-not $index -or -not $index.Contains($key)) {
            $known = (Get-OcpConfiguredClusterNames) -join ', '
            throw [OcpValidationException]::new(
                "Unknown cluster '$Cluster'. No configured canonical ID, friendly name, or alias matches. Known clusters: $known"
            )
        }

        $id = [string]$index[$key].ClusterId
        return New-OcpClusterRecord -Id $id -Cluster $clusters[$id]
    }

    if (-not $Server) {
        throw [OcpValidationException]::new('Resolve-OcpCluster requires -Cluster or -Server.')
    }

    $normalized = ConvertTo-OcpNormalizedServer -Server $Server
    foreach ($id in $clusters.Keys) {
        $candidate = $clusters[$id]
        if ((ConvertTo-OcpNormalizedServer -Server $candidate.server) -eq $normalized) {
            return New-OcpClusterRecord -Id $id -Cluster $candidate
        }
    }

    if ($AllowUnknown) {
        Write-OcpLog -Level Warning -Message "Authenticated server '$normalized' is not registered in clusters.yaml."
        return [pscustomobject]@{
            PSTypeName                   = 'OpenShiftOps.Cluster'
            Id                           = 'unregistered'
            ClusterId                    = 'unregistered'
            Alias                        = 'unregistered'
            ClusterAlias                 = 'unregistered'
            FriendlyName                 = 'Unregistered cluster'
            DisplayName                  = 'Unregistered cluster'
            Aliases                      = @()
            Server                       = $normalized
            Classification               = 'unknown'
            Location                     = $null
            Purpose                      = $null
            Description                  = $null
            Registered                   = $false
            ServiceConnection            = $null
            DestructiveServiceConnection = $null
        }
    }

    throw [OcpClusterIdentityException]::new(
        "Authenticated server '$normalized' is not registered in clusters.yaml. Refusing to continue."
    )
}

function New-OcpClusterRecord {
    param(
        [string]$Id,
        $Cluster
    )

    $ado = Get-OcpProperty -InputObject $Cluster -Name 'azureDevOps'
    $aliases = @()
    if ((Test-OcpHasProperty -InputObject $Cluster -Name 'aliases') -and $Cluster.aliases) {
        $aliases = @($Cluster.aliases | ForEach-Object { [string]$_ })
    }

    $friendly = [string](Get-OcpProperty -InputObject $Cluster -Name 'friendlyName')
    if (-not $friendly) {
        $friendly = [string](Get-OcpProperty -InputObject $Cluster -Name 'displayName')
    }

    return [pscustomobject]@{
        PSTypeName                   = 'OpenShiftOps.Cluster'
        Id                           = $Id
        ClusterId                    = $Id
        Alias                        = $Id
        ClusterAlias                 = $Id
        FriendlyName                 = $friendly
        DisplayName                  = $friendly
        Aliases                      = $aliases
        Server                       = ConvertTo-OcpNormalizedServer -Server $Cluster.server
        Classification               = [string]$Cluster.classification
        Location                     = [string](Get-OcpProperty -InputObject $Cluster -Name 'location')
        Purpose                      = [string](Get-OcpProperty -InputObject $Cluster -Name 'purpose')
        Description                  = [string](Get-OcpProperty -InputObject $Cluster -Name 'description')
        Registered                   = $true
        ServiceConnection            = [string](Get-OcpProperty -InputObject $ado -Name 'serviceConnection')
        ReadServiceConnection        = [string](Get-OcpProperty -InputObject $ado -Name 'readServiceConnection')
        MaintenanceServiceConnection = [string](Get-OcpProperty -InputObject $ado -Name 'maintenanceServiceConnection')
        DestructiveServiceConnection = [string](Get-OcpProperty -InputObject $ado -Name 'destructiveServiceConnection')
    }
}

function Get-OcpClusterServiceConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Cluster,

        [ValidateSet('read', 'maintenance', 'destructive')]
        [string]$Privilege = 'read'
    )

    switch ($Privilege) {
        'destructive' {
            if ($Cluster.DestructiveServiceConnection) { return $Cluster.DestructiveServiceConnection }
            return $Cluster.ServiceConnection
        }
        'maintenance' {
            if ($Cluster.MaintenanceServiceConnection) { return $Cluster.MaintenanceServiceConnection }
            return $Cluster.ServiceConnection
        }
        default {
            if ($Cluster.ReadServiceConnection) { return $Cluster.ReadServiceConnection }
            return $Cluster.ServiceConnection
        }
    }
}
