function Get-OcpVersionInfo {
    <#
    .SYNOPSIS
        Safely reads oc version JSON. Missing fields are empty, never fatal.
    #>
    [CmdletBinding()]
    param($Json)

    $openshift = [string](Get-OcpProperty -InputObject $Json -Name 'openshiftVersion')
    if ([string]::IsNullOrWhiteSpace($openshift)) {
        $serverInfo = Get-OcpProperty -InputObject $Json -Name 'serverInfo'
        $openshift = [string](Get-OcpProperty -InputObject $serverInfo -Name 'openshiftVersion')
    }

    $serverVersion = Get-OcpProperty -InputObject $Json -Name 'serverVersion'
    $kubernetes = [string](Get-OcpProperty -InputObject $serverVersion -Name 'gitVersion')
    if ([string]::IsNullOrWhiteSpace($kubernetes)) {
        $kubernetes = [string](Get-OcpProperty -InputObject $Json -Name 'kubernetesVersion')
    }

    $clientVersion = Get-OcpProperty -InputObject $Json -Name 'clientVersion'
    $client = [string](Get-OcpProperty -InputObject $clientVersion -Name 'gitVersion')
    if ([string]::IsNullOrWhiteSpace($client)) {
        $client = [string](Get-OcpProperty -InputObject $Json -Name 'releaseClientVersion')
    }

    return [pscustomobject]@{
        PSTypeName        = 'OpenShiftOps.VersionInfo'
        OpenShiftVersion  = $openshift
        KubernetesVersion = $kubernetes
        ClientVersion     = $client
    }
}

function Test-OcpAuthentication {
    [CmdletBinding()]
    param()

    try {
        $who = Invoke-OcpCli -ArgumentList @('whoami')
        $server = Invoke-OcpCli -ArgumentList @('whoami', '--show-server')
    }
    catch {
        throw [OcpAuthenticationException]::new(
            "OpenShift authentication check failed. Use Connect-OcpCluster -Web, Connect-OcpCluster -Token, run 'oc login --web', or configure the Azure DevOps service connection. $($_.Exception.Message)"
        )
    }

    $username = $who.StandardOutput.Trim()
    $serverUrl = $server.StandardOutput.Trim()
    if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($serverUrl)) {
        throw [OcpAuthenticationException]::new('oc whoami did not return a username and server.')
    }

    $rawVersion = $null
    try {
        $version = Invoke-OcpCli -ArgumentList @('version', '-o', 'json') -Json -AllowNonZeroExit
        if ($version.Succeeded) {
            $rawVersion = $version.Json
        }
        else {
            Write-OcpLog -Level Verbose -Message 'oc version returned a non-zero exit; continuing with whoami identity only.'
        }
    }
    catch {
        Write-OcpLog -Level Verbose -Message 'oc version is unavailable; continuing with whoami identity only.'
    }

    $info = Get-OcpVersionInfo -Json $rawVersion

    return [pscustomobject]@{
        PSTypeName        = 'OpenShiftOps.Authentication'
        Username          = $username
        Server            = $serverUrl
        OpenShiftVersion  = $info.OpenShiftVersion
        KubernetesVersion = $info.KubernetesVersion
        ClientVersion     = $info.ClientVersion
        Authenticated     = $true
        RawVersion        = $rawVersion
    }
}
