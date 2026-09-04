#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:OcpModuleRoot = $PSScriptRoot
$script:OcpConfig = $null
$script:OcpConfigLoaded = $false
$script:OcpSession = $null

$classFile = Join-Path $PSScriptRoot 'OpenShiftOps.Classes.ps1'
. $classFile

$privateRoot = Join-Path $PSScriptRoot 'Private'
$publicRoot = Join-Path $PSScriptRoot 'Public'

Get-ChildItem -LiteralPath $privateRoot -Filter '*.ps1' | Sort-Object Name | ForEach-Object {
    . $_.FullName
}

Get-ChildItem -LiteralPath $publicRoot -Filter '*.ps1' | Sort-Object Name | ForEach-Object {
    . $_.FullName
}

try {
    Initialize-OcpConfiguration
    $script:OcpSession = New-OcpEmptySession
}
catch {
    throw [OcpConfigurationException]::new(
        "OpenShiftOps configuration failed to load. The module fails closed until config/ is valid. $($_.Exception.Message)"
    )
}

$ExecutionContext.SessionState.Module.OnRemove = {
    Restore-OcpIsolatedKubeconfig -BestEffort
}

$exported = @(
    'Connect-OcpCluster'
    'Disconnect-OcpCluster'
    'Get-OcpContext'
    'Get-OcpClusterInfo'
    'Get-OcpProject'
    'Get-OcpProjectDetails'
    'Find-OcpUnusedProject'
    'Test-OcpProjectStandards'
    'Set-OcpProjectLabel'
    'Remove-OcpProjectLabel'
    'Repair-OcpProjectMetadata'
    'New-OcpProject'
    'Set-OcpProjectQuota'
    'Get-OcpProjectRemovalPlan'
    'Export-OcpProjectSafetySnapshot'
    'Remove-OcpProject'
    'Test-OcpBackupProvider'
    'Start-OcpBackup'
    'Wait-OcpBackup'
    'Test-OcpBackupCompleted'
    'Get-OcpBackupDetails'
)

Update-TypeData -TypeName OpenShiftOps.ClusterInfo -DefaultDisplayPropertySet FriendlyName, Classification, Location, Purpose -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName OpenShiftOps.Context -DefaultDisplayPropertySet FriendlyName, ClusterId, Server, Username, AuthenticationMethod, Classification -Force -ErrorAction SilentlyContinue

Export-ModuleMember -Function $exported
