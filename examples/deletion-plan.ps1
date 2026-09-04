#Requires -Version 7.0
# Preview a deletion plan and write Markdown next to the operator.

param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [string]$Cluster
)

Import-Module "$PSScriptRoot/../src/OpenShiftOps/OpenShiftOps.psd1"
$plan = Get-OcpProjectRemovalPlan -Name $Name -Cluster $Cluster
$plan.Markdown
$plan | ConvertTo-Json -Depth 6
