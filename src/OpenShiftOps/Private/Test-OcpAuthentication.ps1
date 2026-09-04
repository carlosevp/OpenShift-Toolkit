function Get-OcpVersionInfo {
    <#
    .SYNOPSIS
        Safely reads oc version JSON. Missing fields are empty, never fatal.
    #>
    [CmdletBinding()]
    param($Json)

    try {
        $openshift = [string](Get-OcpProperty -InputObject $Json -Name 'openshiftVersion' -Default '')
        if ([string]::IsNullOrWhiteSpace($openshift)) {
            $serverInfo = Get-OcpProperty -InputObject $Json -Name 'serverInfo'
            $openshift = [string](Get-OcpProperty -InputObject $serverInfo -Name 'openshiftVersion' -Default '')
        }

        $serverVersion = Get-OcpProperty -InputObject $Json -Name 'serverVersion'
        $kubernetes = [string](Get-OcpProperty -InputObject $serverVersion -Name 'gitVersion' -Default '')
        if ([string]::IsNullOrWhiteSpace($kubernetes)) {
            $kubernetes = [string](Get-OcpProperty -InputObject $Json -Name 'kubernetesVersion' -Default '')
        }

        $clientVersion = Get-OcpProperty -InputObject $Json -Name 'clientVersion'
        $client = [string](Get-OcpProperty -InputObject $clientVersion -Name 'gitVersion' -Default '')
        if ([string]::IsNullOrWhiteSpace($client)) {
            $client = [string](Get-OcpProperty -InputObject $Json -Name 'releaseClientVersion' -Default '')
        }

        return [pscustomobject]@{
            PSTypeName        = 'OpenShiftOps.VersionInfo'
            OpenShiftVersion  = $openshift
            KubernetesVersion = $kubernetes
            ClientVersion     = $client
        }
    }
    catch {
        Write-OcpLog -Level Verbose -Message 'Unable to parse oc version JSON; leaving version fields empty.'
        return [pscustomobject]@{
            PSTypeName        = 'OpenShiftOps.VersionInfo'
            OpenShiftVersion  = ''
            KubernetesVersion = ''
            ClientVersion     = ''
        }
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

    $info = [pscustomobject]@{
        OpenShiftVersion  = ''
        KubernetesVersion = ''
        ClientVersion     = ''
    }
    $rawVersion = $null
    try {
        $version = Invoke-OcpCli -ArgumentList @('version', '-o', 'json') -Json -AllowNonZeroExit
        if ((Get-OcpProperty -InputObject $version -Name 'Succeeded' -Default $false) -eq $true) {
            $rawVersion = Get-OcpProperty -InputObject $version -Name 'Json'
            $info = Get-OcpVersionInfo -Json $rawVersion
        }
        else {
            Write-OcpLog -Level Verbose -Message 'oc version returned a non-zero exit; continuing with whoami identity only.'
        }
    }
    catch {
        Write-OcpLog -Level Verbose -Message 'oc version is unavailable; continuing with whoami identity only.'
    }

    return [pscustomobject]@{
        PSTypeName        = 'OpenShiftOps.Authentication'
        Username          = $username
        Server            = $serverUrl
        OpenShiftVersion  = [string](Get-OcpProperty -InputObject $info -Name 'OpenShiftVersion' -Default '')
        KubernetesVersion = [string](Get-OcpProperty -InputObject $info -Name 'KubernetesVersion' -Default '')
        ClientVersion     = [string](Get-OcpProperty -InputObject $info -Name 'ClientVersion' -Default '')
        Authenticated     = $true
        RawVersion        = $rawVersion
    }
}
