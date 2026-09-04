@{
    RootModule        = 'OpenShiftOps.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = '7c2e8a91-4d3f-4b6a-9e1c-2f8a0d6b5c47'
    Author            = 'Platform Operations'
    CompanyName       = 'Internal'
    Copyright         = '(c) Internal. All rights reserved.'
    Description       = 'Intent-based OpenShift operations toolkit with safety controls, audit, and Azure DevOps execution. Wraps oc; does not store credentials.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('OpenShift', 'Kubernetes', 'Operations', 'Safety', 'AzureDevOps')
            LicenseUri   = ''
            ProjectUri   = ''
            ReleaseNotes = 'Friendly cluster names, Connect-OcpCluster token/API/bearer authentication, isolated kubeconfig for token sessions.'
        }
    }
}
