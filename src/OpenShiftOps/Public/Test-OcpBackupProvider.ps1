function Test-OcpBackupProvider {
    <#
    .SYNOPSIS
        Tests whether a backup provider is available.
    .DESCRIPTION
        MVP implements ManifestExport only. Velero and CSI snapshot providers are
        extension points and are not required.
    .PARAMETER Name
        Provider name. Defaults to the configured default provider.
    .EXAMPLE
        Test-OcpBackupProvider
    .OUTPUTS
        OpenShiftOps.BackupProviderStatus
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('ManifestExport', 'Velero')]
        [string]$Name,

        [string]$Project
    )

    Test-OcpBackupProviderInternal -Name $Name -Project $Project
}

function Start-OcpBackup {
    <#
    .SYNOPSIS
        Starts a backup using the selected provider. ManifestExport creates a safety snapshot.
    .NOTES
        Persistent data backup is not provided by ManifestExport.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Project,

        [ValidateSet('ManifestExport')]
        [string]$Provider = 'ManifestExport',

        [string]$Cluster
    )

    if ($PSCmdlet.ShouldProcess($Project, "Start $Provider safety export")) {
        if ($Provider -eq 'ManifestExport') {
            return Export-OcpProjectSafetySnapshot -Name $Project -Cluster $Cluster
        }
    }
}

function Wait-OcpBackup {
    <#
    .SYNOPSIS
        Waits for a backup provider operation. ManifestExport is synchronous and returns immediately.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Backup
    )

    return $Backup
}

function Test-OcpBackupCompleted {
    <#
    .SYNOPSIS
        Returns true when a backup/export object completed successfully.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Backup
    )

    return [bool]($Backup.ExportStatus -eq 'Success' -or $Backup.exportStatus -eq 'Success')
}

function Get-OcpBackupDetails {
    <#
    .SYNOPSIS
        Returns details from a backup or safety-export object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Backup
    )

    return $Backup
}
