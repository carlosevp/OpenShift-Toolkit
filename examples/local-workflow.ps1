#Requires -Version 7.0
# Local operator workflow. This script is documentation-as-code; it does not delete projects.

Import-Module "$PSScriptRoot/../src/OpenShiftOps/OpenShiftOps.psd1"

Get-OcpClusterInfo
Connect-OcpCluster -Cluster Akron-NonProd
Get-OcpContext
Get-OcpClusterInfo
Get-OcpProject | Sort-Object AgeDays | Select-Object -First 20
Find-OcpUnusedProject |
    Where-Object Candidate -eq $true |
    Select-Object Project, AgeDays, Confidence, PVCCount, Reasons

# Preview-only mutations:
# Repair-OcpProjectMetadata -Project claims-dev -WhatIf
# Get-OcpProjectRemovalPlan -Name old-claims-dev | Select-Object -ExpandProperty Markdown
# Remove-OcpProject -Name old-claims-dev -WhatIf
