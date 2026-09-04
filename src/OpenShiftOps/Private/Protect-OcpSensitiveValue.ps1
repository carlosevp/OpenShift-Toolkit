function Protect-OcpSensitiveValue {
    <#
    .SYNOPSIS
        Redacts credentials, tokens, and secret-like values from log or error text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    process {
        if ([string]::IsNullOrEmpty($Text)) {
            return $Text
        }

        $redacted = $Text
        $replacements = @(
            @{ Pattern = '(?i)(bearer\s+)[A-Za-z0-9\-._~+/]+=*'; Replacement = '${1}***REDACTED***' }
            @{ Pattern = '(?i)(authorization:\s*bearer\s+)[A-Za-z0-9\-._~+/]+=*'; Replacement = '${1}***REDACTED***' }
            @{ Pattern = '(?i)(--token=)\S+'; Replacement = '${1}***REDACTED***' }
            @{ Pattern = '(?i)(--token\s+)\S+'; Replacement = '${1}***REDACTED***' }
            @{ Pattern = '(?i)(sha256~)\S+'; Replacement = '${1}***REDACTED***' }
            @{ Pattern = '(?i)(--password=)\S+'; Replacement = '${1}***REDACTED***' }
            @{ Pattern = '(?i)(password\s*[:=]\s*)\S+'; Replacement = '${1}***REDACTED***' }
            @{ Pattern = '(?i)(client-key-data\s*[:=]\s*)\S+'; Replacement = '${1}***REDACTED***' }
            @{ Pattern = '(?i)(client-certificate-data\s*[:=]\s*)\S+'; Replacement = '${1}***REDACTED***' }
            @{ Pattern = '(?i)((?:kube)?config(?:data)?\s*[:=]\s*)\S+'; Replacement = '${1}***REDACTED***' }
            @{ Pattern = '(?i)("(?:data|stringData)"\s*:\s*\{)[^}]+(\})'; Replacement = '${1}***REDACTED***${2}' }
            @{ Pattern = '(?i)(eyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+)'; Replacement = '***REDACTED-JWT***' }
        )

        foreach ($item in $replacements) {
            $redacted = [regex]::Replace($redacted, $item.Pattern, $item.Replacement)
        }

        return $redacted
    }
}

function Protect-OcpKnownSecret {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Secret
    )

    $safe = Protect-OcpSensitiveValue -Text $Text
    if ([string]::IsNullOrEmpty($safe) -or [string]::IsNullOrWhiteSpace($Secret)) {
        return $safe
    }

    return $safe.Replace($Secret, '***REDACTED***', [System.StringComparison]::Ordinal)
}

function Protect-OcpArgumentList {
    [CmdletBinding()]
    param(
        [string[]]$ArgumentList
    )

    if (-not $ArgumentList) {
        return @()
    }

    $redacted = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $ArgumentList.Count; $i++) {
        $arg = $ArgumentList[$i]
        if ($arg -match '(?i)^--token=') {
            $redacted.Add('--token=***REDACTED***')
            continue
        }
        if ($arg -match '(?i)^(--token|--password|-p)$' -and ($i + 1) -lt $ArgumentList.Count) {
            $redacted.Add($arg)
            $redacted.Add('***REDACTED***')
            $i++
            continue
        }
        $redacted.Add((Protect-OcpSensitiveValue -Text $arg))
    }

    return $redacted.ToArray()
}
