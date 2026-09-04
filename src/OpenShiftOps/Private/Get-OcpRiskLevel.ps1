function Get-OcpRiskLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation
    )

    $map = @{
        GetOcpContext                 = 'ReadOnly'
        GetOcpClusterInfo             = 'ReadOnly'
        ConnectOcpCluster             = 'Low'
        DisconnectOcpCluster          = 'Low'
        GetOcpProject                 = 'ReadOnly'
        GetOcpProjectDetails          = 'ReadOnly'
        FindOcpUnusedProject          = 'ReadOnly'
        TestOcpProjectStandards       = 'ReadOnly'
        GetOcpProjectRemovalPlan      = 'ReadOnly'
        ExportOcpProjectSafetySnapshot = 'Low'
        SetOcpProjectLabel            = 'Low'
        RemoveOcpProjectLabel         = 'Low'
        RepairOcpProjectMetadata      = 'Medium'
        NewOcpProject                 = 'Medium'
        SetOcpProjectQuota            = 'Medium'
        RemoveOcpProject              = 'Destructive'
        TestOcpBackupProvider         = 'ReadOnly'
        StartOcpBackup                = 'Medium'
        WaitOcpBackup                 = 'ReadOnly'
        TestOcpBackupCompleted        = 'ReadOnly'
        GetOcpBackupDetails           = 'ReadOnly'
    }

    $key = ($Operation -replace '[^A-Za-z]', '')
    if ($map.ContainsKey($key)) {
        return $map[$key]
    }

    Write-OcpLog -Level Warning -Message "Unknown operation '$Operation' treated as High risk (fail closed for mutations)."
    return 'High'
}

function Test-OcpRiskIsMutation {
    param([string]$Risk)
    return $Risk -in @('Low', 'Medium', 'High', 'Destructive')
}
