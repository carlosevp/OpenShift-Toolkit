function Get-OcpConfigRoot {
    [CmdletBinding()]
    param()

    if ($env:OPENSHIFTOPS_CONFIG_ROOT) {
        return [System.IO.Path]::GetFullPath($env:OPENSHIFTOPS_CONFIG_ROOT)
    }

    $fromModule = [System.IO.Path]::GetFullPath((Join-Path $script:OcpModuleRoot '..' '..' 'config'))
    if (Test-Path -LiteralPath $fromModule) {
        return $fromModule
    }

    throw [OcpConfigurationException]::new(
        "Unable to locate OpenShiftOps config directory. Set OPENSHIFTOPS_CONFIG_ROOT or keep config/ next to the repository root."
    )
}

function Get-OcpArtifactRoot {
    [CmdletBinding()]
    param()

    if ($env:BUILD_ARTIFACTSTAGINGDIRECTORY) {
        return Join-Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY 'openshiftops'
    }
    if ($env:OPENSHIFTOPS_ARTIFACT_ROOT) {
        return [System.IO.Path]::GetFullPath($env:OPENSHIFTOPS_ARTIFACT_ROOT)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) 'artifacts'))
}

function Get-OcpLogRoot {
    [CmdletBinding()]
    param()

    if ($env:OPENSHIFTOPS_LOG_ROOT) {
        return [System.IO.Path]::GetFullPath($env:OPENSHIFTOPS_LOG_ROOT)
    }
    if ((Get-OcpExecutionMode) -eq 'AzureDevOps' -and $env:BUILD_ARTIFACTSTAGINGDIRECTORY) {
        return Join-Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY 'openshiftops-logs'
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) 'logs'))
}

function Get-OcpConfiguration {
    [CmdletBinding()]
    param(
        [switch]$ForceReload
    )

    if ($script:OcpConfigLoaded -and -not $ForceReload) {
        return $script:OcpConfig
    }

    Initialize-OcpConfiguration -ForceReload:$ForceReload
    return $script:OcpConfig
}

function Initialize-OcpConfiguration {
    [CmdletBinding()]
    param(
        [switch]$ForceReload
    )

    if ($script:OcpConfigLoaded -and -not $ForceReload) {
        return
    }

    $root = Get-OcpConfigRoot
    $files = @{
        clusters           = Join-Path $root 'clusters.yaml'
        azureDevOps        = Join-Path $root 'azure-devops.yaml'
        protectedProjects  = Join-Path $root 'protected-projects.yaml'
        standards          = Join-Path $root 'project-standards.yaml'
        safety             = Join-Path $root 'safety-policy.yaml'
        projectBaseline    = Join-Path $root 'templates' 'project-baseline.yaml'
    }

    foreach ($path in $files.Values) {
        Assert-OcpConfigHasNoCredentials -Path $path
    }

    $clustersDoc = ConvertFrom-OcpYaml -Path $files.clusters
    $adoDoc = ConvertFrom-OcpYaml -Path $files.azureDevOps
    $protectedDoc = ConvertFrom-OcpYaml -Path $files.protectedProjects
    $standardsDoc = ConvertFrom-OcpYaml -Path $files.standards
    $safetyDoc = ConvertFrom-OcpYaml -Path $files.safety
    $baselineDoc = ConvertFrom-OcpYaml -Path $files.projectBaseline

    $config = [ordered]@{
        ConfigRoot        = $root
        clusters          = ConvertTo-OcpHashtable -InputObject $clustersDoc.clusters
        azureDevOps       = ConvertTo-OcpHashtable -InputObject $adoDoc.azureDevOps
        protectedProjects = ConvertTo-OcpHashtable -InputObject $protectedDoc.protectedProjects
        standards         = ConvertTo-OcpHashtable -InputObject $standardsDoc.standards
        safety            = ConvertTo-OcpHashtable -InputObject $safetyDoc.safety
        projectBaseline   = ConvertTo-OcpHashtable -InputObject $baselineDoc.projectBaseline
        clusterIndex      = [ordered]@{}
    }

    Assert-OcpConfigurationValid -Config $config
    $script:OcpConfig = $config
    $script:OcpConfigLoaded = $true
}

function Assert-OcpConfigHasNoCredentials {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($raw -match '(?im)^\s*(password|token|secret|kubeconfig|client-key-data|client-certificate-data|bearer)\s*:') {
        throw [OcpConfigurationException]::new(
            "Credentials are not allowed in OpenShiftOps configuration files. Offending file: $Path"
        )
    }
}

function Assert-OcpConfigurationValid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Config
    )

    if (-not $Config.clusters -or $Config.clusters.Count -eq 0) {
        throw [OcpConfigurationException]::new('clusters.yaml must define at least one cluster.')
    }

    $allowedClassifications = @('nonprod', 'production')
    foreach ($id in @($Config.clusters.Keys)) {
        Assert-OcpClusterId -Id $id
        $cluster = $Config.clusters[$id]
        $friendly = [string](Get-OcpProperty -InputObject $cluster -Name 'friendlyName')
        if ([string]::IsNullOrWhiteSpace($friendly)) {
            $friendly = [string](Get-OcpProperty -InputObject $cluster -Name 'displayName')
        }
        if ([string]::IsNullOrWhiteSpace($friendly)) {
            throw [OcpConfigurationException]::new("Cluster '$id' is missing friendlyName.")
        }

        if (-not (Test-OcpHasProperty -InputObject $cluster -Name 'server') -or -not $cluster.server) {
            throw [OcpConfigurationException]::new("Cluster '$id' is missing server.")
        }
        $server = [string]$cluster.server
        if ($server -notmatch '^https://') {
            throw [OcpConfigurationException]::new("Cluster '$id' server must use https://. Fail closed.")
        }
        $classification = Normalize-OcpClassification -Value $cluster.classification
        if ($classification -notin $allowedClassifications) {
            throw [OcpConfigurationException]::new(
                "Cluster '$id' classification '$($cluster.classification)' is invalid. Use nonprod or production."
            )
        }

        $ado = Get-OcpProperty -InputObject $cluster -Name 'azureDevOps'
        if (-not $ado -or -not (Get-OcpProperty -InputObject $ado -Name 'serviceConnection')) {
            throw [OcpConfigurationException]::new(
                "Cluster '$id' is missing azureDevOps.serviceConnection. Pipeline mappings must come from the catalog."
            )
        }

        $aliases = @()
        if ((Test-OcpHasProperty -InputObject $cluster -Name 'aliases') -and $cluster.aliases) {
            $aliases = @($cluster.aliases | ForEach-Object { [string]$_ })
        }

        $cluster.classification = $classification
        $cluster.friendlyName = $friendly.Trim()
        $cluster.aliases = $aliases
        $cluster.id = $id
        $cluster.alias = $id
        $cluster.normalizedServer = ConvertTo-OcpNormalizedServer -Server $server
        $cluster.location = [string](Get-OcpProperty -InputObject $cluster -Name 'location')
        $cluster.purpose = [string](Get-OcpProperty -InputObject $cluster -Name 'purpose')
    }

    $Config.clusterIndex = New-OcpClusterLookupIndex -Clusters $Config.clusters

    $safety = $Config.safety
    if (-not $safety) {
        throw [OcpConfigurationException]::new('safety-policy.yaml is missing the safety document.')
    }

    if ($safety.secretExport.enabled -ne $false) {
        throw [OcpConfigurationException]::new(
            'security fail-closed: secretExport.enabled must be false. Secret value export is not implemented.'
        )
    }

    $bulk = [int]$safety.defaultMaximumBulkMutationCount
    if ($bulk -lt 1) {
        throw [OcpConfigurationException]::new('safety.defaultMaximumBulkMutationCount must be >= 1.')
    }

    $deletion = $safety.projectDeletion
    foreach ($flag in @('requireSafetyExport', 'blockProtectedProjects', 'blockSystemProjects', 'blockWhenPVCsExist', 'requireRevalidationAfterApproval')) {
        if ($deletion[$flag] -ne $true) {
            throw [OcpConfigurationException]::new("safety.projectDeletion.$flag must be true for this toolkit release.")
        }
    }

    if ($null -eq $deletion.allowPersistentVolumeOverride) {
        throw [OcpConfigurationException]::new('safety.projectDeletion.allowPersistentVolumeOverride must be set.')
    }

    if ($safety.backups.defaultProvider -ne 'ManifestExport') {
        throw [OcpConfigurationException]::new(
            "Unknown backup provider '$($safety.backups.defaultProvider)'. MVP supports ManifestExport only."
        )
    }

    if (-not $Config.standards.labelDomain) {
        throw [OcpConfigurationException]::new('standards.labelDomain is required.')
    }

    if (-not $Config.protectedProjects) {
        throw [OcpConfigurationException]::new('protected-projects.yaml is invalid.')
    }
}

function Normalize-OcpClassification {
    param($Value)
    $text = [string]$Value
    switch ($text.ToLowerInvariant()) {
        'prod' { return 'production' }
        'production' { return 'production' }
        'nonprod' { return 'nonprod' }
        'non-prod' { return 'nonprod' }
        'development' { return 'nonprod' }
        default { return $text.ToLowerInvariant() }
    }
}

function ConvertTo-OcpHashtable {
    [CmdletBinding()]
    param(
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [hashtable] -or $InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = ConvertTo-OcpHashtable -InputObject $InputObject[$key]
        }
        return $result
    }

    if ($InputObject -is [string] -or $InputObject -is [ValueType]) {
        return $InputObject
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $InputObject) {
            $list.Add((ConvertTo-OcpHashtable -InputObject $item))
        }
        return $list.ToArray()
    }

    if ($InputObject -is [psobject]) {
        $result = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-OcpHashtable -InputObject $property.Value
        }
        return $result
    }

    return $InputObject
}

function Get-OcpStandardLabelKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Name -match '/') {
        return $Name
    }

    $domain = [string](Get-OcpConfiguration).standards.labelDomain
    return "$domain/$Name"
}

function Test-OcpHasProperty {
    [CmdletBinding()]
    param(
        $InputObject,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $false
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        return $InputObject.Contains([string]$Name)
    }

    # Never use $object.Name — StrictMode throws on missing JSON fields such as openshiftVersion.
    $names = @($InputObject.PSObject.Properties.Name)
    return ($names -contains $Name)
}

function Get-OcpProperty {
    [CmdletBinding()]
    param(
        $InputObject,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        $Default = $null
    )

    if (-not (Test-OcpHasProperty -InputObject $InputObject -Name $Name)) {
        return $Default
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        return $InputObject[$Name]
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }
    return $property.Value
}

function Get-OcpResourceLabel {
    [CmdletBinding()]
    param(
        $Resource,
        [string]$Key
    )

    if ($null -eq $Resource) { return $null }
    $labels = $null
    $metadata = Get-OcpProperty -InputObject $Resource -Name 'metadata'
    if ($null -ne $metadata) {
        $labels = Get-OcpProperty -InputObject $metadata -Name 'labels'
    }
    if ($null -eq $labels) {
        $labels = Get-OcpProperty -InputObject $Resource -Name 'labels'
    }
    if ($null -eq $labels) {
        $labels = $Resource
    }

    return Get-OcpMapValue -Map $labels -Key $Key
}

function Get-OcpMapValue {
    [CmdletBinding()]
    param(
        $Map,
        [string]$Key
    )

    if ($null -eq $Map) { return $null }
    if ($Map -is [hashtable] -or $Map -is [System.Collections.IDictionary]) {
        if ($Map.Contains($Key)) { return $Map[$Key] }
        return $null
    }

    $property = $Map.PSObject.Properties[$Key]
    if ($property) { return $property.Value }
    return $null
}
