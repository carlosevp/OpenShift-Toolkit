function Get-OcpSession {
    [CmdletBinding()]
    param()

    if (-not $script:OcpSession) {
        $script:OcpSession = New-OcpEmptySession
    }
    return $script:OcpSession
}

function New-OcpEmptySession {
    [pscustomobject]@{
        AuthenticationMethod     = 'ExistingContext'
        ClusterId                = $null
        FriendlyName             = $null
        IsolatedKubeconfigPath   = $null
        OriginalKubeconfig       = $null
        OwnsIsolatedKubeconfig   = $false
    }
}

function Set-OcpSession {
    [CmdletBinding()]
    param(
        [string]$AuthenticationMethod,
        [string]$ClusterId,
        [string]$FriendlyName
    )

    $session = Get-OcpSession
    if ($AuthenticationMethod) { $session.AuthenticationMethod = $AuthenticationMethod }
    if ($ClusterId) { $session.ClusterId = $ClusterId }
    if ($FriendlyName) { $session.FriendlyName = $FriendlyName }
}

function Get-OcpAuthenticationMethod {
    [CmdletBinding()]
    param()

    return [string](Get-OcpSession).AuthenticationMethod
}

function ConvertFrom-OcpSecureString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [SecureString]$SecureString
    )

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-OcpTokenFromEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VariableName
    )

    if ($VariableName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw [OcpValidationException]::new("Token environment variable name '$VariableName' is invalid.")
    }

    $value = [Environment]::GetEnvironmentVariable($VariableName)
    if ($null -eq $value) {
        throw [OcpAuthenticationException]::new(
            "Environment variable '$VariableName' is not set. A token was not read from any other location."
        )
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw [OcpAuthenticationException]::new(
            "Environment variable '$VariableName' is empty. Token authentication failed closed."
        )
    }
    return $value
}

function New-OcpIsolatedKubeconfig {
    [CmdletBinding()]
    param()

    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('openshiftops-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false | Out-Null
    $path = Join-Path $dir 'kubeconfig'
    Set-Content -LiteralPath $path -Value '' -Encoding utf8 -WhatIf:$false

    if (-not $IsWindows) {
        $chmod = Get-Command -Name chmod -ErrorAction SilentlyContinue
        if ($chmod) {
            & chmod 700 $dir
            & chmod 600 $path
        }
    }

    Write-OcpLog -Level Verbose -Message 'Created isolated temporary kubeconfig for token authentication.'
    return $path
}

function Test-OcpIsolatedKubeconfigPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($Path -notmatch 'openshiftops-[0-9a-fA-F]{32}[/\\]kubeconfig$') { return $false }
    return $true
}

function Restore-OcpIsolatedKubeconfig {
    [CmdletBinding()]
    param(
        [switch]$BestEffort
    )

    $session = Get-OcpSession
    try {
        if ($session.OwnsIsolatedKubeconfig) {
            if ($null -eq $session.OriginalKubeconfig) {
                Remove-Item -Path Env:KUBECONFIG -ErrorAction SilentlyContinue
            }
            else {
                $env:KUBECONFIG = $session.OriginalKubeconfig
            }

            $path = [string]$session.IsolatedKubeconfigPath
            if (Test-OcpIsolatedKubeconfigPath -Path $path) {
                $dir = Split-Path -Parent $path
                if (Test-Path -LiteralPath $dir) {
                    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false
                }
            }
        }
    }
    catch {
        if (-not $BestEffort) { throw }
        Write-OcpLog -Level Warning -Message 'Best-effort cleanup of isolated kubeconfig failed.'
    }
    finally {
        $session.IsolatedKubeconfigPath = $null
        $session.OriginalKubeconfig = $null
        $session.OwnsIsolatedKubeconfig = $false
    }
}

function Switch-OcpIsolatedKubeconfig {
    [CmdletBinding()]
    param()

    $session = Get-OcpSession
    if ($session.OwnsIsolatedKubeconfig) {
        Restore-OcpIsolatedKubeconfig
    }

    $original = $env:KUBECONFIG
    $path = New-OcpIsolatedKubeconfig
    $session.OriginalKubeconfig = $original
    $session.IsolatedKubeconfigPath = $path
    $session.OwnsIsolatedKubeconfig = $true
    $env:KUBECONFIG = $path
    return $path
}
