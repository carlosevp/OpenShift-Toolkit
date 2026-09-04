function Get-OcpExecutionMode {
    [CmdletBinding()]
    param()

    if ($env:TF_BUILD -eq 'True' -or $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI) {
        return 'AzureDevOps'
    }

    return 'Interactive'
}

function Get-OcpRequestedBy {
    [CmdletBinding()]
    param()

    if ($env:BUILD_REQUESTEDFOREMAIL) { return $env:BUILD_REQUESTEDFOREMAIL }
    if ($env:BUILD_REQUESTEDFOR) { return $env:BUILD_REQUESTEDFOR }
    if ($env:SYSTEM_ACCESSTOKEN) {
        # Identity only; never return the token.
        if ($env:BUILD_REQUESTEDFOR) { return $env:BUILD_REQUESTEDFOR }
    }

    $user = $env:USERNAME
    if (-not $user) { $user = $env:USER }
    if (-not $user) { $user = $env:LOGNAME }
    return $user
}
