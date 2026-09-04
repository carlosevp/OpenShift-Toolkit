function Test-OcpPermission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Verb,

        [Parameter(Mandatory = $true)]
        [string]$Resource,

        [string]$Namespace,

        [string]$Name
    )

    $arguments = @('auth', 'can-i', $Verb, $Resource)
    if ($Namespace) {
        Assert-OcpProjectName -Name $Namespace
        $arguments += @('-n', $Namespace)
    }
    if ($Name) {
        $arguments += @($Name)
    }

    $result = Invoke-OcpCli -ArgumentList $arguments -AllowNonZeroExit
    $answer = $result.StandardOutput.Trim().ToLowerInvariant()
    $allowed = $answer -eq 'yes'

    return [pscustomobject]@{
        PSTypeName = 'OpenShiftOps.Permission'
        Verb       = $Verb
        Resource   = $Resource
        Namespace  = $Namespace
        Name       = $Name
        Allowed    = $allowed
        Raw        = $result.StandardOutput.Trim()
    }
}

function Assert-OcpPermission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Verb,

        [Parameter(Mandatory = $true)]
        [string]$Resource,

        [string]$Namespace,

        [string]$Name
    )

    $result = Test-OcpPermission @PSBoundParameters
    if (-not $result.Allowed) {
        $scope = if ($Namespace) { " in namespace '$Namespace'" } else { ' at cluster scope' }
        throw [OcpPermissionException]::new(
            "Not authorized to $Verb $Resource$scope. The current identity lacks the minimum RBAC for this OpenShiftOps operation."
        )
    }

    return $result
}
