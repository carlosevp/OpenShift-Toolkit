function ConvertTo-OcpClusterLookupKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $normalized = $Name.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw [OcpValidationException]::new('Cluster name cannot be empty.')
    }
    return $normalized
}

function Assert-OcpClusterId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    if ($Id -notmatch '^[a-z][a-z0-9-]{0,61}$') {
        throw [OcpConfigurationException]::new(
            "Canonical cluster ID '$Id' is invalid. Use lowercase alphanumeric names with hyphens."
        )
    }
}

function Assert-OcpClusterAlias {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Alias
    )

    Assert-OcpClusterId -Id $Alias
}

function Get-OcpConfiguredClusterNames {
    [CmdletBinding()]
    param()

    $clusters = (Get-OcpConfiguration).clusters
    return @(
        $clusters.Keys | ForEach-Object {
            $item = $clusters[$_]
            [string](Get-OcpProperty -InputObject $item -Name 'friendlyName')
        } | Sort-Object
    )
}

function New-OcpClusterLookupIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Clusters
    )

    $index = [ordered]@{}
    foreach ($id in $Clusters.Keys) {
        $cluster = $Clusters[$id]
        $claims = [System.Collections.Generic.List[object]]::new()
        $claims.Add([pscustomobject]@{ Kind = 'canonical ID'; Value = $id })
        $friendly = [string](Get-OcpProperty -InputObject $cluster -Name 'friendlyName')
        if ($friendly) {
            $claims.Add([pscustomobject]@{ Kind = 'friendly name'; Value = $friendly })
        }
        foreach ($alias in @((Get-OcpProperty -InputObject $cluster -Name 'aliases'))) {
            if (-not [string]::IsNullOrWhiteSpace([string]$alias)) {
                $claims.Add([pscustomobject]@{ Kind = 'alias'; Value = [string]$alias })
            }
        }

        foreach ($claim in $claims) {
            $key = ConvertTo-OcpClusterLookupKey -Name $claim.Value
            if ($index.Contains($key)) {
                $existing = $index[$key]
                if ($existing.ClusterId -eq $id) {
                    # Same cluster: friendlyName Akron-Prod and alias akron-prod are equivalent, not ambiguous.
                    continue
                }
                throw [OcpConfigurationException]::new(
                    "Cluster name collision after normalization: '$($claim.Value)' ($($claim.Kind) of '$id') conflicts with $($existing.Kind) of '$($existing.ClusterId)'. Fail closed."
                )
            }
            $index[$key] = [pscustomobject]@{
                ClusterId = $id
                Kind      = $claim.Kind
                Value     = $claim.Value
            }
        }
    }

    return $index
}

function Assert-OcpProjectName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Name -notmatch '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$') {
        throw [OcpValidationException]::new(
            "Project name '$Name' is invalid. Kubernetes namespaces must be DNS-1123 labels (lowercase, numeric, hyphen, max 63)."
        )
    }
}

function Assert-OcpLabelKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    # Kubernetes label keys: optional prefix / name
    if ($Key -notmatch '^([A-Za-z0-9]([-A-Za-z0-9]*[A-Za-z0-9])?(\.[A-Za-z0-9]([-A-Za-z0-9]*[A-Za-z0-9])?)*\/)?[A-Za-z0-9]([-A-Za-z0-9_.]*[A-Za-z0-9])?$') {
        throw [OcpValidationException]::new("Label key '$Key' is not a valid Kubernetes label name.")
    }
    if ($Key.Length -gt 253) {
        throw [OcpValidationException]::new("Label key '$Key' exceeds 253 characters.")
    }
}

function Assert-OcpLabelValue {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return
    }
    if ($Value.Length -gt 63) {
        throw [OcpValidationException]::new("Label value '$Value' exceeds 63 characters.")
    }
    if ($Value -notmatch '^(([A-Za-z0-9][-A-Za-z0-9_.]*)?[A-Za-z0-9])$') {
        throw [OcpValidationException]::new("Label value '$Value' is not a valid Kubernetes label value.")
    }
}

function Assert-OcpChangeReference {
    [CmdletBinding()]
    param(
        [string]$ChangeReference,
        [string]$Classification,
        [string]$Risk
    )

    $config = Get-OcpConfiguration
    $requireForDeletion = [bool]$config.safety.projectDeletion.requireChangeReferenceForProduction
    $requireForMutation = [bool]$config.safety.mutations.requireChangeReferenceForProduction
    $isProduction = $Classification -eq 'production'
    $isDestructive = $Risk -in @('High', 'Destructive')

    $required = $false
    if ($isProduction -and $isDestructive -and $requireForDeletion) { $required = $true }
    if ($isProduction -and $requireForMutation) { $required = $true }

    if ($required -and [string]::IsNullOrWhiteSpace($ChangeReference)) {
        throw [OcpValidationException]::new(
            "A change reference is required for this $Risk operation against a production cluster. Pass -ChangeReference."
        )
    }

    if ($ChangeReference -and $ChangeReference -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{2,63}$') {
        throw [OcpValidationException]::new("Change reference '$ChangeReference' has an invalid format.")
    }
}

function Test-OcpBulkSafetyLimit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$TargetCount,

        [int]$Maximum,
        [switch]$AllowLargeBatch
    )

    $config = Get-OcpConfiguration
    if (-not $Maximum) {
        $Maximum = [int]$config.safety.defaultMaximumBulkMutationCount
    }

    if ($TargetCount -le $Maximum) {
        return [pscustomobject]@{
            Allowed     = $true
            TargetCount = $TargetCount
            Maximum     = $Maximum
            Message     = $null
        }
    }

    if ($AllowLargeBatch) {
        Write-OcpLog -Level Warning -Message "Bulk safety limit override in use. Targets=$TargetCount Maximum=$Maximum"
        return [pscustomobject]@{
            Allowed     = $true
            TargetCount = $TargetCount
            Maximum     = $Maximum
            Message     = "Override accepted for $TargetCount targets (limit $Maximum)."
        }
    }

    $message = @"
SAFETY LIMIT

Operation affects: $TargetCount projects
Maximum unattended mutations: $Maximum

Operation stopped.
"@
    throw [OcpSafetyException]::new($message.Trim())
}
