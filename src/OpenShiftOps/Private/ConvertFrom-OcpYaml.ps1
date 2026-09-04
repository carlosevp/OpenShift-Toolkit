function ConvertFrom-OcpYaml {
    <#
    .SYNOPSIS
        Parses OpenShiftOps YAML configuration into hashtables.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    param(
        [Parameter(ParameterSetName = 'Content', Mandatory = $true, Position = 0)]
        [string]$Yaml,

        [Parameter(ParameterSetName = 'Path', Mandatory = $true)]
        [string]$Path
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw [OcpConfigurationException]::new("Configuration file not found: $Path")
        }
        $Yaml = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    }

    $convertFromYaml = Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -eq 'powershell-yaml' } |
        Select-Object -First 1

    if ($convertFromYaml) {
        return & $convertFromYaml -Yaml $Yaml
    }

    ConvertFrom-OcpSimpleYaml -Yaml $Yaml
}

function ConvertFrom-OcpSimpleYaml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Yaml
    )

    $lines = @()
    $rawLines = $Yaml -split "`r?`n"
    for ($i = 0; $i -lt $rawLines.Count; $i++) {
        $raw = $rawLines[$i]
        if ($raw -match '^\s*$') { continue }
        if ($raw -match '^\s*#') { continue }

        $indent = ($raw -replace '^(\s*).*$', '$1').Length
        $content = $raw.Trim()
        $lines += [pscustomobject]@{ Indent = $indent; Content = $content; Index = $i }
    }

    if ($lines.Count -eq 0) {
        return [ordered]@{}
    }

    $index = 0
    $root = ConvertFrom-OcpSimpleYamlBlock -Lines $lines -Index ([ref]$index) -MinIndent 0
    return $root
}

function ConvertFrom-OcpSimpleYamlBlock {
    param(
        [object[]]$Lines,
        [ref]$Index,
        [int]$MinIndent
    )

    if ($Index.Value -ge $Lines.Count) {
        return [ordered]@{}
    }

    $first = $Lines[$Index.Value]
    if ($first.Content -match '^\-') {
        return ConvertFrom-OcpSimpleYamlList -Lines $Lines -Index $Index -MinIndent $MinIndent
    }

    return ConvertFrom-OcpSimpleYamlMap -Lines $Lines -Index $Index -MinIndent $MinIndent
}

function ConvertFrom-OcpSimpleYamlMap {
    param(
        [object[]]$Lines,
        [ref]$Index,
        [int]$MinIndent
    )

    $map = [ordered]@{}
    while ($Index.Value -lt $Lines.Count) {
        $line = $Lines[$Index.Value]
        if ($line.Indent -lt $MinIndent) { break }
        if ($line.Content -match '^\-') { break }
        if ($line.Indent -ne $MinIndent -and $map.Count -eq 0) {
            throw [OcpConfigurationException]::new("Invalid YAML indentation near: $($line.Content)")
        }
        if ($line.Indent -gt $MinIndent) {
            throw [OcpConfigurationException]::new("Invalid YAML indentation near: $($line.Content)")
        }

        if ($line.Content -notmatch '^([^:]+):(.*)$') {
            throw [OcpConfigurationException]::new("Invalid YAML mapping line: $($line.Content)")
        }

        $key = $Matches[1].Trim()
        $remainder = $Matches[2]
        if ($map.Contains($key)) {
            throw [OcpConfigurationException]::new(
                "Duplicate YAML key '$key'. Canonical cluster IDs and other mapping keys must be unique. Fail closed."
            )
        }
        $Index.Value++

        if ($null -eq $remainder -or $remainder.Trim() -eq '') {
            if ($Index.Value -lt $Lines.Count -and $Lines[$Index.Value].Indent -gt $line.Indent) {
                $childIndent = $Lines[$Index.Value].Indent
                $map[$key] = ConvertFrom-OcpSimpleYamlBlock -Lines $Lines -Index $Index -MinIndent $childIndent
            }
            else {
                $map[$key] = $null
            }
        }
        else {
            $map[$key] = ConvertFrom-OcpYamlScalar -Value $remainder.Trim()
        }
    }

    return $map
}

function ConvertFrom-OcpSimpleYamlList {
    param(
        [object[]]$Lines,
        [ref]$Index,
        [int]$MinIndent
    )

    $list = [System.Collections.Generic.List[object]]::new()
    while ($Index.Value -lt $Lines.Count) {
        $line = $Lines[$Index.Value]
        if ($line.Indent -lt $MinIndent) { break }
        if ($line.Indent -ne $MinIndent) { break }
        if ($line.Content -notmatch '^\-\s?(.*)$') { break }

        $itemText = $Matches[1]
        $dashIndent = $line.Indent
        $Index.Value++

        if ([string]::IsNullOrWhiteSpace($itemText)) {
            if ($Index.Value -lt $Lines.Count -and $Lines[$Index.Value].Indent -gt $dashIndent) {
                $childIndent = $Lines[$Index.Value].Indent
                $list.Add((ConvertFrom-OcpSimpleYamlBlock -Lines $Lines -Index $Index -MinIndent $childIndent))
            }
            else {
                $list.Add($null)
            }
        }
        elseif ($itemText -match '^([^:]+):(.*)$') {
            $key = $Matches[1].Trim()
            $remainder = $Matches[2]
            $itemMap = [ordered]@{}
            if ($null -eq $remainder -or $remainder.Trim() -eq '') {
                $itemMap[$key] = $null
            }
            else {
                $itemMap[$key] = ConvertFrom-OcpYamlScalar -Value $remainder.Trim()
            }

            while ($Index.Value -lt $Lines.Count) {
                $next = $Lines[$Index.Value]
                if ($next.Indent -le $dashIndent) { break }
                if ($next.Content -match '^\-') {
                    $nested = ConvertFrom-OcpSimpleYamlList -Lines $Lines -Index $Index -MinIndent $next.Indent
                    # Unusual: nested list immediately under a map item without a key.
                    $itemMap['_items'] = $nested
                    break
                }

                if ($next.Content -notmatch '^([^:]+):(.*)$') {
                    throw [OcpConfigurationException]::new("Invalid YAML mapping line: $($next.Content)")
                }

                $childKey = $Matches[1].Trim()
                $childRemainder = $Matches[2]
                $Index.Value++
                if ($null -eq $childRemainder -or $childRemainder.Trim() -eq '') {
                    if ($Index.Value -lt $Lines.Count -and $Lines[$Index.Value].Indent -gt $next.Indent) {
                        $childIndent = $Lines[$Index.Value].Indent
                        $itemMap[$childKey] = ConvertFrom-OcpSimpleYamlBlock -Lines $Lines -Index $Index -MinIndent $childIndent
                    }
                    else {
                        $itemMap[$childKey] = $null
                    }
                }
                else {
                    $itemMap[$childKey] = ConvertFrom-OcpYamlScalar -Value $childRemainder.Trim()
                }
            }

            $list.Add($itemMap)
        }
        else {
            $list.Add((ConvertFrom-OcpYamlScalar -Value $itemText.Trim()))
        }
    }

    return $list.ToArray()
}

function ConvertFrom-OcpYamlScalar {
    param([string]$Value)

    $Value = $Value.Trim()
    if ($Value -eq '' -or $Value -eq '~' -or $Value -eq 'null') {
        return $null
    }

    if (($Value.StartsWith('"') -and $Value.EndsWith('"')) -or ($Value.StartsWith("'") -and $Value.EndsWith("'"))) {
        return $Value.Substring(1, $Value.Length - 2)
    }

    if ($Value -in @('true', 'True', 'TRUE')) { return $true }
    if ($Value -in @('false', 'False', 'FALSE')) { return $false }

    if ($Value -match '^-?\d+$') {
        return [int]$Value
    }

    return $Value
}
