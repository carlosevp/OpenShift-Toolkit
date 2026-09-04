function ConvertTo-OcpLabelSafeValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $safe = [regex]::Replace($Value, '[^A-Za-z0-9._-]', '-')
    $safe = $safe.Trim('-', '.', '_')
    if ($safe.Length -gt 63) {
        $safe = $safe.Substring(0, 63).Trim('-', '.', '_')
    }
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'unknown'
    }
    return $safe
}

function Apply-OcpProjectQuotaFromBaseline {
    param(
        [string]$Namespace,
        $Baseline
    )

    $name = if ($Baseline.name) { [string]$Baseline.name } else { 'project-quota' }
    $hard = $Baseline.spec.hard
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($key in $hard.Keys) {
        $parts.Add("$key=$($hard[$key])")
    }
    $specHard = $parts -join ','
    Invoke-OcpCli -ArgumentList @('create', 'quota', $name, '-n', $Namespace, "--hard=$specHard") | Out-Null
}

function Apply-OcpProjectLimitRangeFromBaseline {
    param(
        [string]$Namespace,
        $Baseline
    )

    $name = if ($Baseline.name) { [string]$Baseline.name } else { 'project-limits' }
    $file = Join-Path ([System.IO.Path]::GetTempPath()) ("ocp-limitrange-{0}.json" -f [guid]::NewGuid())
    try {
        $limits = @()
        foreach ($item in @($Baseline.spec.limits)) {
            $limits += $(if ($item -is [hashtable] -or $item -is [System.Collections.IDictionary]) {
                [pscustomobject]$item
            } else {
                $item
            })
        }
        $resource = [pscustomobject]@{
            apiVersion = 'v1'
            kind       = 'LimitRange'
            metadata   = [pscustomobject]@{
                name      = $name
                namespace = $Namespace
            }
            spec = [pscustomobject]@{
                limits = $limits
            }
        }
        Set-Content -LiteralPath $file -Value ($resource | ConvertTo-Json -Depth 12) -Encoding UTF8
        Invoke-OcpCli -ArgumentList @('apply', '-n', $Namespace, '-f', $file) | Out-Null
    }
    finally {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
    }
}
