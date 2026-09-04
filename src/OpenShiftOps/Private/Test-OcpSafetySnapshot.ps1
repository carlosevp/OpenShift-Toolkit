function Test-OcpSafetySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw [OcpBackupException]::new("Safety snapshot manifest was not found: $ManifestPath")
    }

    $raw = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    $raw = Protect-OcpSensitiveValue -Text $raw
    try {
        $manifest = $raw | ConvertFrom-Json
    }
    catch {
        throw [OcpBackupException]::new("Safety snapshot manifest is not valid JSON: $ManifestPath")
    }

    $warnings = @()
    if ($manifest.warnings) { $warnings = @($manifest.warnings) }

    $ok = $manifest.exportStatus -eq 'Success'
    if ([int]$manifest.resourceTypesExported -lt 1) {
        $ok = $false
        $warnings += 'No resource types were exported.'
    }

    if ($manifest.secretsExcluded -ne $true) {
        throw [OcpSafetyException]::new(
            'Safety snapshot reported secretsExcluded=false. Secret values must never appear in normal artifacts. Fail closed.'
        )
    }

    $result = [pscustomobject]@{
        PSTypeName              = 'OpenShiftOps.SafetySnapshotVerification'
        Valid                   = $ok
        OperationId             = [string]$manifest.operationId
        Cluster                 = [string]$manifest.cluster
        Project                 = [string]$manifest.project
        ExportStatus            = [string]$manifest.exportStatus
        ResourceTypesDiscovered = [int]$manifest.resourceTypesDiscovered
        ResourceTypesExported   = [int]$manifest.resourceTypesExported
        ResourceCount           = [int]$manifest.resourceCount
        SecretsExcluded         = [bool]$manifest.secretsExcluded
        PersistentVolumeCount   = [int]$manifest.persistentVolumeCount
        Warnings                = $warnings
        ManifestPath            = $ManifestPath
        Manifest                = $manifest
    }

    if (-not $ok) {
        throw [OcpBackupException]::new(
            "Safety snapshot verification failed for project '$($result.Project)'. Status=$($result.ExportStatus)."
        )
    }

    return $result
}

function Compare-OcpRemovalPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ApprovedPlan,

        [Parameter(Mandatory = $true)]
        $CurrentPlan
    )

    $changes = New-Object System.Collections.Generic.List[string]

    if ($ApprovedPlan.Cluster -ne $CurrentPlan.Cluster) {
        $changes.Add("Cluster changed from $($ApprovedPlan.Cluster) to $($CurrentPlan.Cluster)")
    }
    if ($ApprovedPlan.Project -ne $CurrentPlan.Project) {
        $changes.Add("Project changed from $($ApprovedPlan.Project) to $($CurrentPlan.Project)")
    }
    if ([int]$ApprovedPlan.PVCCount -ne [int]$CurrentPlan.PVCCount) {
        $changes.Add("PVC count changed from $($ApprovedPlan.PVCCount) to $($CurrentPlan.PVCCount)")
    }
    if ([int]$CurrentPlan.RunningPodCount -gt [int]$ApprovedPlan.RunningPodCount) {
        $changes.Add("Running pods increased from $($ApprovedPlan.RunningPodCount) to $($CurrentPlan.RunningPodCount)")
    }
    if (-not $ApprovedPlan.CleanupProtected -and $CurrentPlan.CleanupProtected) {
        $changes.Add('Project became cleanup-protected after the plan was generated.')
    }
    if (-not $ApprovedPlan.ProtectedProject -and $CurrentPlan.ProtectedProject) {
        $changes.Add('Project became protected after the plan was generated.')
    }
    if ((Test-OcpHasProperty -InputObject $ApprovedPlan -Name 'Server') -and (Test-OcpHasProperty -InputObject $CurrentPlan -Name 'Server')) {
        if ($ApprovedPlan.Server -and $CurrentPlan.Server -and $ApprovedPlan.Server -ne $CurrentPlan.Server) {
            $changes.Add("Cluster server changed from $($ApprovedPlan.Server) to $($CurrentPlan.Server)")
        }
    }

    $material = $changes.Count -gt 0
    return [pscustomobject]@{
        PSTypeName        = 'OpenShiftOps.PlanComparison'
        MaterialChange    = $material
        Changes           = $changes.ToArray()
        ApprovedPlanId    = (Get-OcpProperty -InputObject $ApprovedPlan -Name 'OperationId')
        CurrentRisk       = (Get-OcpProperty -InputObject $CurrentPlan -Name 'Risk')
    }
}
