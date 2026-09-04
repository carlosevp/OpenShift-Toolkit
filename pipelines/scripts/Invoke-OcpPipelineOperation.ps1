#Requires -Version 7.0
<#
.SYNOPSIS
    Thin Azure DevOps / local dispatcher. Business logic stays in OpenShiftOps.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'ProjectInventory',
        'FindUnusedProjects',
        'ValidateProjectStandards',
        'RepairProjectMetadata',
        'CreateProject',
        'DeleteProject',
        'ProjectDetails',
        'ClusterInfo'
    )]
    [string]$Operation,

    [Parameter(Mandatory = $true)]
    [string]$Cluster,

    [string]$Project,
    [string]$Environment,
    [string]$Application,
    [string]$Owner,
    [string]$CostCenter,
    [string]$ChangeReference,
    [string]$LabelJson,
    [string]$ApprovedPlanPath,
    [switch]$AllowDeleteWithPersistentVolumes,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleManifest = Join-Path $PSScriptRoot '..' '..' 'src' 'OpenShiftOps' 'OpenShiftOps.psd1'
Import-Module -Name (Resolve-Path -LiteralPath $moduleManifest) -Force

if ($OutputRoot) {
    $env:OPENSHIFTOPS_ARTIFACT_ROOT = $OutputRoot
}

$common = @{ ErrorAction = 'Stop' }
if ($Cluster) { $common.Cluster = $Cluster }
if ($ChangeReference) { $common.ChangeReference = $ChangeReference }
if ($env:TF_BUILD -eq 'True') {
    # Azure DevOps Environments provide the human approval. Do not hang on Confirm.
    $common.Confirm = $false
}

$result = $null
switch ($Operation) {
    'ClusterInfo' {
        $result = Get-OcpClusterInfo @common
    }
    'ProjectInventory' {
        if ($Project) {
            $result = Get-OcpProject -Name $Project @common
        }
        else {
            $result = Get-OcpProject @common
        }
    }
    'ProjectDetails' {
        if (-not $Project) { throw 'Project is required for ProjectDetails.' }
        $result = Get-OcpProjectDetails -Name $Project @common
    }
    'FindUnusedProjects' {
        $result = Find-OcpUnusedProject @common
    }
    'ValidateProjectStandards' {
        if ($Project) {
            $result = Test-OcpProjectStandards -Project $Project @common
        }
        else {
            $result = Test-OcpProjectStandards -All @common
        }
    }
    'RepairProjectMetadata' {
        if (-not $Project) { throw 'Project is required for RepairProjectMetadata.' }
        $label = $null
        if ($LabelJson) { $label = $LabelJson | ConvertFrom-Json -AsHashtable }
        $result = Repair-OcpProjectMetadata -Project $Project -Label $label @common
    }
    'CreateProject' {
        if (-not $Project) { throw 'Project is required for CreateProject.' }
        if (-not $Application -or -not $Environment -or -not $Owner) {
            throw 'Application, Environment, and Owner are required for CreateProject.'
        }
        $create = @{
            Name        = $Project
            Application = $Application
            Environment = $Environment
            Owner       = $Owner
        }
        if ($CostCenter) { $create.CostCenter = $CostCenter }
        $result = New-OcpProject @create @common
    }
    'DeleteProject' {
        if (-not $Project) { throw 'Project is required for DeleteProject.' }
        $delete = @{
            Name = $Project
        }
        if ($ApprovedPlanPath -and (Test-Path -LiteralPath $ApprovedPlanPath)) {
            $delete.ApprovedPlan = (Get-Content -LiteralPath $ApprovedPlanPath -Raw | ConvertFrom-Json)
        }
        if ($AllowDeleteWithPersistentVolumes -or $env:OCP_ALLOW_PVC_OVERRIDE -eq 'True') {
            $delete.AllowDeleteWithPersistentVolumes = $true
        }
        $result = Remove-OcpProject @delete @common
    }
}

$artifactRoot = if ($OutputRoot) { $OutputRoot } else { Join-Path (Get-Location) 'artifacts' }
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
$resultPath = Join-Path $artifactRoot 'result.json'
$summaryPath = Join-Path $artifactRoot 'summary.md'

($result | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $resultPath -Encoding UTF8

$context = Get-OcpContext
$summary = @"
# OpenShiftOps pipeline summary

| Field | Value |
| --- | --- |
| Operation | $Operation |
| Requested by | $($context.RequestedBy) |
| Cluster | $($context.FriendlyName) |
| Cluster ID | $($context.ClusterId) |
| Server | $($context.Server) |
| Authentication | $($context.AuthenticationMethod) |
| Project | $Project |
| Environment | $Environment |
| Execution mode | $($context.ExecutionMode) |
| Classification | $($context.Classification) |
| Change reference | $ChangeReference |
| Result file | result.json |
"@
Set-Content -LiteralPath $summaryPath -Value $summary -Encoding UTF8

if ($env:TF_BUILD -eq 'True') {
    Write-Host "##vso[task.uploadsummary]$summaryPath"
}

Write-Output $result
