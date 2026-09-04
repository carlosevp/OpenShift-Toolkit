function Test-OcpAuthentication {
    [CmdletBinding()]
    param()

    try {
        $who = Invoke-OcpCli -ArgumentList @('whoami')
        $server = Invoke-OcpCli -ArgumentList @('whoami', '--show-server')
        $version = Invoke-OcpCli -ArgumentList @('version', '-o', 'json') -Json
    }
    catch {
        throw [OcpAuthenticationException]::new(
            "OpenShift authentication check failed. Use Connect-OcpCluster, run 'oc login', or configure the Azure DevOps service connection. $($_.Exception.Message)"
        )
    }

    $username = $who.StandardOutput.Trim()
    $serverUrl = $server.StandardOutput.Trim()
    if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($serverUrl)) {
        throw [OcpAuthenticationException]::new('oc whoami did not return a username and server.')
    }

    return [pscustomobject]@{
        PSTypeName        = 'OpenShiftOps.Authentication'
        Username          = $username
        Server            = $serverUrl
        OpenShiftVersion  = [string]$version.Json.openshiftVersion
        KubernetesVersion = [string]$version.Json.serverVersion.gitVersion
        ClientVersion     = [string]$version.Json.clientVersion.gitVersion
        Authenticated     = $true
        RawVersion        = $version.Json
    }
}
