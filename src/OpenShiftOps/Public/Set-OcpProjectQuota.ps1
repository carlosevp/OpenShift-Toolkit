function Set-OcpProjectQuota {
    <#
    .SYNOPSIS
        Applies a ResourceQuota to a project after exporting the current quota/limitrange.
    .PARAMETER Name
        Project name.
    .PARAMETER Hard
        Hashtable of ResourceQuota hard limits, for example @{ 'pods' = '20'; 'requests.cpu' = '2' }.
    .EXAMPLE
        Set-OcpProjectQuota -Name claims-dev -Hard @{ pods = '10'; 'requests.memory' = '2Gi' } -WhatIf
    .OUTPUTS
        OpenShiftOps.QuotaChange
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Project')]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [hashtable]$Hard,

        [string]$QuotaName = 'project-quota',
        [string]$Cluster,
        [string]$ChangeReference
    )

    process {
        Assert-OcpProjectName -Name $Name
        $context = New-OcpOperationContext -Operation 'Set-OcpProjectQuota' -ClusterAlias $Cluster -Project $Name -ChangeReference $ChangeReference
        Assert-OcpPermission -Verb create -Resource resourcequotas -Namespace $Name | Out-Null

        $existingQuotas = @(Get-OcpJsonItems -ArgumentList @('get', 'resourcequotas', '-n', $Name, '-o', 'json'))
        $existingLimits = @(Get-OcpJsonItems -ArgumentList @('get', 'limitranges', '-n', $Name, '-o', 'json'))
        $recoveryDir = Join-Path (Get-OcpArtifactRoot) 'recovery' $context.OperationId
        New-Item -ItemType Directory -Path $recoveryDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $recoveryDir 'resourcequotas.json') -Value ($existingQuotas | ConvertTo-Json -Depth 12) -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $recoveryDir 'limitranges.json') -Value ($existingLimits | ConvertTo-Json -Depth 12) -Encoding UTF8

        $parts = @($Hard.Keys | ForEach-Object { "$_=$($Hard[$_])" })
        $hardArg = $parts -join ','
        $action = "Set ResourceQuota '$QuotaName' hard=$hardArg on $Name"
        if (-not $PSCmdlet.ShouldProcess($Name, $action)) {
            return [pscustomobject]@{
                PSTypeName      = 'OpenShiftOps.QuotaChange'
                Project         = $Name
                Cluster         = $context.FriendlyName
                ClusterId       = $context.ClusterId
                FriendlyName    = $context.FriendlyName
                QuotaName       = $QuotaName
                Hard            = $Hard
                Result          = 'WhatIf'
                RecoveryPath    = $recoveryDir
                OperationId     = $context.OperationId
            }
        }

        $create = Invoke-OcpCli -ArgumentList @('create', 'quota', $QuotaName, '-n', $Name, "--hard=$hardArg") -AllowNonZeroExit
        if (-not $create.Succeeded) {
            Invoke-OcpCli -ArgumentList @('delete', 'quota', $QuotaName, '-n', $Name, '--ignore-not-found=true') | Out-Null
            Invoke-OcpCli -ArgumentList @('create', 'quota', $QuotaName, '-n', $Name, "--hard=$hardArg") | Out-Null
        }

        $recovery = [pscustomobject]@{
            kind         = 'QuotaChange'
            recoveryPath = $recoveryDir
            reverse      = "oc apply -n $Name -f $recoveryDir/resourcequotas.json"
        }
        $audit = New-OcpAuditRecord -Context $context -Result 'Success' -Target $Name -Recovery $recovery -Message "Updated ResourceQuota $QuotaName"
        [pscustomobject]@{
            PSTypeName   = 'OpenShiftOps.QuotaChange'
            Project      = $Name
            Cluster      = $context.FriendlyName
            ClusterId    = $context.ClusterId
            FriendlyName = $context.FriendlyName
            QuotaName    = $QuotaName
            Hard         = $Hard
            Result       = 'Success'
            RecoveryPath = $recoveryDir
            AuditPath    = $audit.auditPath
            OperationId  = $context.OperationId
        }
    }
}
