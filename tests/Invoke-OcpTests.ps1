#Requires -Version 7.0
param(
    [switch]$Integration
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src' 'OpenShiftOps' 'OpenShiftOps.psd1') -Force
$unit = Join-Path $PSScriptRoot 'unit'
$config = New-PesterConfiguration
$config.Run.Path = $unit
$config.Run.ExcludePath = @(Join-Path $unit 'OpenShiftOps.Helpers.ps1')
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $root 'TestResults' 'unit.xml'

New-Item -ItemType Directory -Path (Join-Path $root 'TestResults') -Force | Out-Null

$unitResult = Invoke-Pester -Configuration $config
$failed = 0
$resultObject = $unitResult
if ($resultObject -is [System.Array]) {
    $failed = @($resultObject | Where-Object { $_.Result -eq 'Failed' }).Count
}
else {
    if ($resultObject.PSObject.Properties['FailedCount']) {
        $failed = [int]$resultObject.FailedCount
    }
    if ($resultObject.PSObject.Properties['Result'] -and $resultObject.Result -eq 'Failed') {
        $failed = [Math]::Max($failed, 1)
    }
    if ($resultObject.PSObject.Properties['Containers']) {
        $failedContainers = @($resultObject.Containers | Where-Object { $_.Result -eq 'Failed' }).Count
        $failed += $failedContainers
    }
}

if ($failed -gt 0) {
    throw "Unit tests failed: $failed"
}

if ($Integration) {
    $env:OPENSHIFTOPS_INTEGRATION = '1'
    $intConfig = New-PesterConfiguration
    $intConfig.Run.Path = Join-Path $PSScriptRoot 'integration'
    $intConfig.Output.Verbosity = 'Detailed'
    $intResult = Invoke-Pester -Configuration $intConfig
    if ($intResult.PSObject.Properties['FailedCount'] -and $intResult.FailedCount -gt 0) {
        throw "Integration tests failed: $($intResult.FailedCount)"
    }
}

Write-Host 'OpenShiftOps tests passed.'
