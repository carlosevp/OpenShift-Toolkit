function New-OcpAuditRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        [Parameter(Mandatory = $true)]
        [string]$Result,

        [string]$Target,
        [string]$SafetyExportStatus,
        [bool]$PersistentVolumesDetected,
        [object]$Recovery,
        [string[]]$Warnings,
        [string]$Message,
        [string]$OutputPath
    )

    $record = [ordered]@{
        operationId                 = $Context.OperationId
        timestamp                   = [DateTime]::UtcNow.ToString('o')
        cluster                     = $(if ((Test-OcpHasProperty -InputObject $Context -Name 'FriendlyName') -and $Context.FriendlyName) { $Context.FriendlyName } else { $Context.ClusterAlias })
        clusterId                   = $(if (Test-OcpHasProperty -InputObject $Context -Name 'ClusterId') { $Context.ClusterId } else { $Context.ClusterAlias })
        clusterFriendlyName         = $(if (Test-OcpHasProperty -InputObject $Context -Name 'FriendlyName') { $Context.FriendlyName } else { $null })
        server                      = $Context.Server
        classification              = $Context.Classification
        authenticatedIdentity       = $Context.Username
        authenticationMethod        = $(if (Test-OcpHasProperty -InputObject $Context -Name 'AuthenticationMethod') { $Context.AuthenticationMethod } else { Get-OcpAuthenticationMethod })
        executionMode               = $Context.ExecutionMode
        requestedBy                 = $Context.RequestedBy
        username                    = $Context.Username
        operation                   = $Context.Operation
        target                      = $(if ($Target) { $Target } else { $Context.Project })
        risk                        = $Context.Risk
        changeReference             = $Context.ChangeReference
        safetyExportStatus          = $SafetyExportStatus
        persistentVolumesDetected   = [bool]$PersistentVolumesDetected
        result                      = $Result
        message                     = Protect-OcpSensitiveValue -Text $Message
        warnings                    = @($Warnings)
        recovery                    = $Recovery
        pipeline                    = $Context.Pipeline
    }

    $json = ($record | ConvertTo-Json -Depth 8)
    $json = Protect-OcpSensitiveValue -Text $json

    Write-OcpLog -Level Audit -Message "$($Context.Operation) $($record.target) -> $Result" -OperationId $Context.OperationId

    $artifactRoot = Get-OcpArtifactRoot
    $auditDir = Join-Path $artifactRoot 'audit'
    if (-not (Test-Path -LiteralPath $auditDir)) {
        New-Item -ItemType Directory -Path $auditDir -Force -WhatIf:$false | Out-Null
    }

    if (-not $OutputPath) {
        $safeTarget = if ($record.target) { $record.target } else { 'cluster' }
        $OutputPath = Join-Path $auditDir "$($Context.OperationId)-$safeTarget.json"
    }

    Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8 -WhatIf:$false
    $record.auditPath = $OutputPath
    return [pscustomobject]$record
}
