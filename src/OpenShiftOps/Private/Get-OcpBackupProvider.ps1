function Get-OcpBackupProvider {
    [CmdletBinding()]
    param(
        [string]$Name
    )

    $config = Get-OcpConfiguration
    if (-not $Name) {
        $Name = [string]$config.safety.backups.defaultProvider
    }

    switch ($Name) {
        'ManifestExport' {
            return [pscustomobject]@{
                PSTypeName           = 'OpenShiftOps.BackupProvider'
                Name                 = 'ManifestExport'
                PersistentDataBackup = $false
                Description          = 'YAML/JSON manifest safety export. This is NOT a persistent volume backup.'
            }
        }
        'Velero' {
            return [pscustomobject]@{
                PSTypeName           = 'OpenShiftOps.BackupProvider'
                Name                 = 'Velero'
                PersistentDataBackup = $true
                Description          = 'Future Velero provider. Not implemented in this MVP.'
                Implemented          = $false
            }
        }
        default {
            throw [OcpValidationException]::new("Unknown backup provider '$Name'.")
        }
    }
}

function Test-OcpBackupProviderInternal {
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$Project
    )

    $provider = Get-OcpBackupProvider -Name $Name
    if ($provider.Name -eq 'ManifestExport') {
        return [pscustomobject]@{
            Provider                  = $provider.Name
            Available                 = $true
            PersistentDataBackupVerified = $false
            Message                   = 'ManifestExport is available. It does not back up PVC contents.'
        }
    }

    return [pscustomobject]@{
        Provider                     = $provider.Name
        Available                    = $false
        PersistentDataBackupVerified = $false
        Message                      = "Backup provider '$($provider.Name)' is not implemented."
    }
}

function New-OcpBackupManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$ExportStatus,

        [int]$ResourceTypesDiscovered,
        [int]$ResourceTypesExported,
        [int]$ResourceCount,
        [int]$PersistentVolumeCount,
        [string[]]$Warnings,
        [string]$OutputPath
    )

    $manifest = [ordered]@{
        operationId             = $Context.OperationId
        cluster                 = $(if (Test-OcpHasProperty -InputObject $Context -Name 'FriendlyName') { $Context.FriendlyName } else { $Context.ClusterAlias })
        clusterId               = $(if (Test-OcpHasProperty -InputObject $Context -Name 'ClusterId') { $Context.ClusterId } else { $Context.ClusterAlias })
        clusterFriendlyName     = $(if (Test-OcpHasProperty -InputObject $Context -Name 'FriendlyName') { $Context.FriendlyName } else { $null })
        authenticatedIdentity   = $Context.Username
        authenticationMethod    = $(if (Test-OcpHasProperty -InputObject $Context -Name 'AuthenticationMethod') { $Context.AuthenticationMethod } else { $null })
        project                 = $Project
        timestamp               = [DateTime]::UtcNow.ToString('o')
        exportStatus            = $ExportStatus
        resourceTypesDiscovered = $ResourceTypesDiscovered
        resourceTypesExported   = $ResourceTypesExported
        resourceCount           = $ResourceCount
        secretsExcluded         = $true
        persistentVolumeCount   = $PersistentVolumeCount
        provider                = 'ManifestExport'
        persistentDataBackup    = $false
        warnings                = @($Warnings)
    }

    $json = $manifest | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8
    return [pscustomobject]$manifest
}
