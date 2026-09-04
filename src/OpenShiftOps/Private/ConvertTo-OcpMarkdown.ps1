function ConvertTo-OcpProjectRemovalPlanMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Plan
    )

    $blockerText = if ($Plan.BlockingConditions -and $Plan.BlockingConditions.Count -gt 0) {
        ($Plan.BlockingConditions | ForEach-Object { "BLOCKER:`n$_" }) -join "`n`n"
    }
    else {
        'No blockers.'
    }

    $warningText = if ($Plan.Warnings -and $Plan.Warnings.Count -gt 0) {
        ($Plan.Warnings | ForEach-Object { "- $_" }) -join "`n"
    }
    else {
        '- None'
    }

    $proceed = if ($Plan.CanProceed) { 'YES (still requires ShouldProcess / pipeline approval)' } else { 'NO' }

    @"
# PROJECT DELETION PLAN

Cluster:         $(if ($Plan.FriendlyName) { $Plan.FriendlyName } else { $Plan.Cluster })
Cluster ID:      $(if ($Plan.ClusterId) { $Plan.ClusterId } else { $Plan.Cluster })
Server:          $($Plan.Server)
Project:         $($Plan.Project)
Classification:  $($Plan.Classification)

Age:             $($Plan.AgeDays) days
Owner:           $($Plan.Owner)
Environment:     $($Plan.Environment)
Application:     $($Plan.Application)

Resources:
  Deployments:     $($Plan.DeploymentCount)
  StatefulSets:    $($Plan.StatefulSetCount)
  Running Pods:    $($Plan.RunningPodCount)
  Routes:          $($Plan.RouteCount)
  PVCs:            $($Plan.PVCCount)
  Secrets:         $($Plan.SecretCount)
  ConfigMaps:      $($Plan.ConfigMapCount)
  CronJobs:        $($Plan.CronJobCount)

Persistent storage detected: $($Plan.PersistentStorageDetected)
Protected project:           $($Plan.ProtectedProject)
Cleanup protected:           $($Plan.CleanupProtected)

$blockerText

Warnings:
$warningText

Can proceed:  $proceed
Risk:         $($Plan.Risk)

IMPORTANT:
A YAML safety export is a Safety Export, not a Persistent Data Backup.
Manifest exports do not back up PVC contents or secret values.
"@
}

function ConvertTo-OcpStandardsMarkdown {
    [CmdletBinding()]
    param($Result)

    $missing = if ($Result.MissingLabels) { $Result.MissingLabels -join ', ' } else { 'None' }
    $invalid = if ($Result.InvalidLabels) { ($Result.InvalidLabels | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ' } else { 'None' }
    @"
Project: $($Result.Project)
Cluster: $(if ($Result.FriendlyName) { $Result.FriendlyName } else { $Result.Cluster })
Cluster ID: $(if ($Result.ClusterId) { $Result.ClusterId } else { $Result.Cluster })
Compliant: $($Result.Compliant)
Missing labels: $missing
Invalid labels: $invalid
"@
}
