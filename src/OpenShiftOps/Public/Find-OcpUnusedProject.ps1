function Find-OcpUnusedProject {
    <#
    .SYNOPSIS
        Finds cleanup candidate projects. Never deletes anything.
    .DESCRIPTION
        Scores visible projects using conservative signals such as age, running
        workloads, PVCs, lifecycle labels, and cleanup protection. LastKnownActivity
        is Unknown unless a reliable timestamp is available.
    .PARAMETER Cluster
        Optional cluster alias used to verify the current oc context.
    .PARAMETER MinimumAgeDays
        Overrides the configured minimum age.
    .EXAMPLE
        Find-OcpUnusedProject | Export-Csv cleanup.csv
    .OUTPUTS
        OpenShiftOps.UnusedProject
    #>
    [CmdletBinding()]
    param(
        [string]$Cluster,
        [int]$MinimumAgeDays
    )

    $context = New-OcpOperationContext -Operation 'Find-OcpUnusedProject' -ClusterAlias $Cluster
    $config = (Get-OcpConfiguration).standards.unusedProject
    if (-not $MinimumAgeDays) {
        $MinimumAgeDays = if ($config.minimumAgeDays) { [int]$config.minimumAgeDays } else { 30 }
    }
    $highAge = if ($config.highConfidenceAgeDays) { [int]$config.highConfidenceAgeDays } else { 90 }

    $projects = @(Get-OcpProject -Cluster $context.ClusterAlias)
    foreach ($project in $projects) {
        $reasons = New-Object System.Collections.Generic.List[string]
        $score = 0

        if ($project.ProtectedProject -or $project.CleanupProtected) {
            [pscustomobject]@{
                PSTypeName         = 'OpenShiftOps.UnusedProject'
                Project            = $project.Name
                Cluster            = $context.FriendlyName
                ClusterId          = $context.ClusterId
                FriendlyName       = $context.FriendlyName
                Classification     = $context.Classification
                AgeDays            = $project.AgeDays
                RunningWorkloads   = $project.RunningPodCount
                PVCCount           = $project.PVCCount
                Owner              = $project.Owner
                Environment        = $project.Environment
                LastKnownActivity  = 'Unknown'
                CleanupProtected   = $true
                Confidence         = 'Excluded'
                Reasons            = @('Project is protected or cleanup-protected and must not be treated as a deletion candidate.')
                Candidate          = $false
            }
            continue
        }

        $age = 0
        if ($project.AgeDays) { $age = [int]$project.AgeDays }
        if ($age -lt $MinimumAgeDays) {
            continue
        }

        $reasons.Add("Age is $age days (minimum $MinimumAgeDays).")
        $score += 1
        if ($age -ge $highAge) {
            $reasons.Add("Age is at least $highAge days.")
            $score += 2
        }

        $running = 0
        if ($project.RunningPodCount) { $running = [int]$project.RunningPodCount }
        if ($running -eq 0) {
            $reasons.Add('No running pods.')
            $score += 2
        }
        else {
            $reasons.Add("Running pods: $running")
            $score -= 3
        }

        if ([int]$project.DeploymentCount -eq 0 -and [int]$project.StatefulSetCount -eq 0) {
            $reasons.Add('No Deployments or StatefulSets.')
            $score += 1
        }

        if ([int]$project.PVCCount -gt 0) {
            $reasons.Add("PVC count is $($project.PVCCount). Persistent data may exist.")
            $score -= 2
        }
        else {
            $reasons.Add('No PersistentVolumeClaims.')
            $score += 1
        }

        if ($project.Lifecycle -eq 'temporary' -and $config.considerTemporaryLifecycle -eq $true) {
            $reasons.Add('Lifecycle label is temporary.')
            $score += 2
        }

        if ($project.Environment -eq 'prod') {
            $reasons.Add('Environment is prod. Treat with extra caution.')
            $score -= 2
        }

        $confidence = 'Low'
        $candidate = $false
        if ($score -ge 6 -and $running -eq 0) {
            $confidence = 'High'
            $candidate = $true
        }
        elseif ($score -ge 3 -and $running -eq 0) {
            $confidence = 'Medium'
            $candidate = $true
        }
        elseif ($score -ge 1) {
            $confidence = 'Low'
            $candidate = $true
        }

        [pscustomobject]@{
            PSTypeName         = 'OpenShiftOps.UnusedProject'
            Project            = $project.Name
            Cluster            = $context.FriendlyName
            ClusterId          = $context.ClusterId
            FriendlyName       = $context.FriendlyName
            Classification     = $context.Classification
            AgeDays            = $project.AgeDays
            RunningWorkloads   = $running
            DeploymentCount    = $project.DeploymentCount
            StatefulSetCount   = $project.StatefulSetCount
            RouteCount         = $project.RouteCount
            PVCCount           = $project.PVCCount
            Owner              = $project.Owner
            Environment        = $project.Environment
            Lifecycle          = $project.Lifecycle
            LastKnownActivity  = 'Unknown'
            CleanupProtected   = [bool]$project.CleanupProtected
            Confidence         = $confidence
            Reasons            = $reasons.ToArray()
            Candidate          = $candidate
            Score              = $score
        }
    }
}
