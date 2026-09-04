function Export-OcpResourceList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Namespace,

        [Parameter(Mandatory = $true)]
        [string]$Resource,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [switch]$Sanitize,
        [switch]$ExcludeSecretData
    )

    $items = @(Get-OcpJsonItems -ArgumentList @('get', $Resource, '-n', $Namespace, '-o', 'json'))
    $exported = New-Object System.Collections.Generic.List[object]
    foreach ($item in $items) {
        $current = $item
        if ($Sanitize) {
            $current = ConvertTo-OcpRecoveryManifest -Resource $item -ExcludeSecretData:$ExcludeSecretData
        }
        $exported.Add($current)
    }

    $list = [pscustomobject]@{
        apiVersion = 'v1'
        kind       = 'List'
        metadata   = [pscustomobject]@{
            resource = $Resource
            count    = $exported.Count
        }
        items      = @($exported)
    }

    $parent = Split-Path -Parent $OutputPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Set-Content -LiteralPath $OutputPath -Value (ConvertTo-OcpYamlDocument -Resource $list) -Encoding UTF8
    return $exported.Count
}

function Get-OcpNamespacedApiResource {
    [CmdletBinding()]
    param()

    $result = Invoke-OcpCli -ArgumentList @('api-resources', '--namespaced=true', '--verbs=list', '-o', 'name') -AllowNonZeroExit
    if (-not $result.Succeeded) {
        Write-OcpLog -Level Warning -Message 'oc api-resources failed; falling back to the curated resource list.'
        return @()
    }

    return @(
        $result.StandardOutput -split "`r?`n" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() }
    )
}
