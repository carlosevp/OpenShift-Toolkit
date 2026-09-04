function Get-OcpCliPath {
    [CmdletBinding()]
    param()

    if ($env:OPENSHIFTOPS_OC_PATH -and (Test-Path -LiteralPath $env:OPENSHIFTOPS_OC_PATH)) {
        return $env:OPENSHIFTOPS_OC_PATH
    }

    $command = Get-Command -Name oc -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw [OcpCliException]::new(
        "The oc CLI was not found on PATH. Install the OpenShift CLI and ensure it is available to this session.",
        -1,
        'oc not found',
        @()
    )
}

function Invoke-OcpCli {
    <#
    .SYNOPSIS
        Executes oc with an argument array. Never uses Invoke-Expression.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,

        [switch]$Json,

        [int]$TimeoutSeconds = 180,

        [switch]$AllowNonZeroExit,

        [switch]$Interactive
    )

    if ($Interactive -and $Json) {
        throw [OcpValidationException]::new('Invoke-OcpCli cannot combine -Interactive with -Json.')
    }

    $ocPath = Get-OcpCliPath
    $safeArgs = Protect-OcpArgumentList -ArgumentList $ArgumentList
    Write-OcpLog -Level Verbose -Message "Executing oc $($safeArgs -join ' ')"

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $ocPath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = -not $Interactive
    $psi.RedirectStandardOutput = -not $Interactive
    $psi.RedirectStandardError = -not $Interactive
    if (-not $Interactive) {
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    }

    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi

    try {
        if (-not $process.Start()) {
            throw [OcpCliException]::new('Failed to start oc process.', -1, '', $safeArgs)
        }

        $stdoutTask = $null
        $stderrTask = $null
        if (-not $Interactive) {
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
        }

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                $process.Kill($true)
            }
            catch {
                Write-OcpLog -Level Warning -Message "Timed out waiting for oc and failed to kill the process."
            }
            throw [OcpTimeoutException]::new("oc timed out after $TimeoutSeconds seconds: $($safeArgs -join ' ')")
        }

        $stdout = ''
        $stderr = ''
        if ($stdoutTask) {
            $stdout = $stdoutTask.GetAwaiter().GetResult()
        }
        if ($stderrTask) {
            $stderr = $stderrTask.GetAwaiter().GetResult()
        }
        $exitCode = $process.ExitCode
    }
    finally {
        $process.Dispose()
    }

    $stdout = if ($null -eq $stdout) { '' } else { $stdout }
    $stderr = if ($null -eq $stderr) { '' } else { $stderr }

    $parsed = $null
    if ($Json -and $exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($stdout)) {
        try {
            $parsed = $stdout | ConvertFrom-Json
        }
        catch {
            throw [OcpCliException]::new(
                "oc returned invalid JSON for: $($safeArgs -join ' ')",
                $exitCode,
                (Protect-OcpSensitiveValue -Text $stderr),
                $safeArgs
            )
        }
    }

    $result = [pscustomobject]@{
        PSTypeName     = 'OpenShiftOps.CliResult'
        ExitCode       = $exitCode
        Succeeded      = ($exitCode -eq 0)
        StandardOutput = $stdout
        StandardError  = $stderr
        Json           = $parsed
        Arguments      = $safeArgs
    }

    if (-not $result.Succeeded -and -not $AllowNonZeroExit) {
        $errorText = Protect-OcpSensitiveValue -Text ($stderr + $stdout)
        throw [OcpCliException]::new(
            "oc failed (exit $exitCode): $($safeArgs -join ' '). $errorText",
            $exitCode,
            $errorText,
            $safeArgs
        )
    }

    return $result
}
