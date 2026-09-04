function New-OcpClusterIdentityMismatchMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Requested,

        [Parameter(Mandatory = $true)]
        [string]$ActualServer
    )

    $name = if ($Requested.FriendlyName) { $Requested.FriendlyName } else { $Requested.Id }
    return @"
CLUSTER IDENTITY MISMATCH

Requested:
  $name
  $($Requested.Server)

Current authenticated context:
  $ActualServer

Operation blocked.
"@.Trim()
}

function Test-OcpClusterIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExpectedAlias')]
        [string]$Cluster,

        [switch]$ThrowOnMismatch
    )

    $expected = Resolve-OcpCluster -Cluster $Cluster
    $actualServer = (Invoke-OcpCli -ArgumentList @('whoami', '--show-server')).StandardOutput.Trim()
    $actualNormalized = ConvertTo-OcpNormalizedServer -Server $actualServer
    $match = $actualNormalized -eq $expected.Server

    $result = [pscustomobject]@{
        PSTypeName     = 'OpenShiftOps.ClusterIdentity'
        Cluster        = $Cluster
        ClusterId      = $expected.Id
        FriendlyName   = $expected.FriendlyName
        Alias          = $expected.Id
        ExpectedServer = $expected.Server
        ActualServer   = $actualNormalized
        Classification = $expected.Classification
        Match          = $match
    }

    if (-not $match) {
        $message = New-OcpClusterIdentityMismatchMessage -Requested $expected -ActualServer $actualNormalized
        Write-OcpLog -Level Error -Message $message
        if ($ThrowOnMismatch) {
            throw [OcpClusterIdentityException]::new($message)
        }
    }

    return $result
}

function Assert-OcpClusterIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExpectedAlias')]
        [string]$Cluster
    )

    Test-OcpClusterIdentity -Cluster $Cluster -ThrowOnMismatch | Out-Null
}
