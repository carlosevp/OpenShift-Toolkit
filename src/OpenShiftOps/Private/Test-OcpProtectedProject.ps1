function Test-OcpProtectedProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        $Labels
    )

    Assert-OcpProjectName -Name $Name
    $config = (Get-OcpConfiguration).protectedProjects
    $reasons = New-Object System.Collections.Generic.List[string]
    $systemProject = $false
    $cleanupProtected = $false

    $exact = @()
    if ($config.exact) { $exact += @($config.exact) }
    if ($config.additionalExact) { $exact += @($config.additionalExact) }

    $systemExact = @(
        'default', 'kube-system', 'kube-public', 'kube-node-lease', 'openshift'
    )

    if ($Name -in $exact) {
        $reasons.Add("exact:$Name")
        if ($Name -in $systemExact -or $Name.StartsWith('openshift-') -or $Name.StartsWith('kube-')) {
            $systemProject = $true
        }
    }

    $prefixes = @()
    if ($config.prefixes) { $prefixes += @($config.prefixes) }
    if ($config.additionalPrefixes) { $prefixes += @($config.additionalPrefixes) }

    foreach ($prefix in $prefixes) {
        if ([string]::IsNullOrWhiteSpace($prefix)) { continue }
        if ($Name.StartsWith([string]$prefix)) {
            $reasons.Add("prefix:$prefix")
            if ($prefix -in @('openshift-', 'kube-', 'redhat-')) {
                $systemProject = $true
            }
        }
    }

    $labelRules = $config.labels
    if ($labelRules) {
        foreach ($key in $labelRules.Keys) {
            $expected = [string]$labelRules[$key]
            $actual = [string](Get-OcpResourceLabel -Resource $Labels -Key $key)
            if ($actual -and $actual -eq $expected) {
                $reasons.Add("label:$key=$expected")
                $cleanupProtected = $true
            }
        }
    }

    # Always honor the configured cleanup-protection label even if omitted from protected-projects.yaml.
    $protectionKey = Get-OcpStandardLabelKey -Name 'cleanup-protection'
    $protectionValue = [string](Get-OcpResourceLabel -Resource $Labels -Key $protectionKey)
    if ($protectionValue -eq 'true' -and -not ($reasons | Where-Object { $_ -like "label:$protectionKey=*" })) {
        $reasons.Add("label:$protectionKey=true")
        $cleanupProtected = $true
    }

    $protected = $reasons.Count -gt 0
    return [pscustomobject]@{
        PSTypeName       = 'OpenShiftOps.ProtectedProject'
        Name             = $Name
        Protected        = $protected
        SystemProject    = $systemProject
        CleanupProtected = $cleanupProtected
        Reasons          = $reasons.ToArray()
    }
}

function Assert-OcpProjectNotProtected {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        $Labels
    )

    $result = Test-OcpProtectedProject -Name $Name -Labels $Labels
    if ($result.Protected) {
        $detail = $result.Reasons -join ', '
        throw [OcpProtectedProjectException]::new(
            "Project '$Name' is protected and cannot be deleted by OpenShiftOps. Reasons: $detail. There is no override for protected or platform namespaces."
        )
    }

    return $result
}
