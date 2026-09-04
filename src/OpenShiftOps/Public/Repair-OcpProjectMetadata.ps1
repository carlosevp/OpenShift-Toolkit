function Repair-OcpProjectMetadata {
    <#
    .SYNOPSIS
        Remediates project labels to match configured standards.
    .DESCRIPTION
        Applies missing required defaults and maps known alias values (for example
        develop -> dev). Additional values can be supplied for required labels that
        have no default. Captures before/after values for recovery.
    .PARAMETER Project
        Project name to repair.
    .PARAMETER Label
        Hashtable of additional label values keyed by short name or full key.
    .PARAMETER Cluster
        Cluster alias that must match the current oc context.
    .EXAMPLE
        Repair-OcpProjectMetadata -Project claims-dev -WhatIf
    .EXAMPLE
        Repair-OcpProjectMetadata -Project claims-dev -Label @{ 'cost-center' = '12345' }
    .OUTPUTS
        OpenShiftOps.MetadataRepair
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Name')]
        [string]$Project,

        [hashtable]$Label,
        [string]$Cluster,
        [string]$ChangeReference
    )

    process {
        Assert-OcpProjectName -Name $Project
        $context = New-OcpOperationContext -Operation 'Repair-OcpProjectMetadata' -ClusterAlias $Cluster -Project $Project -ChangeReference $ChangeReference
        Assert-OcpPermission -Verb patch -Resource namespaces -Name $Project | Out-Null

        $object = Get-OcpProjectObject -Name $Project
        if (-not $object) {
            throw [OcpValidationException]::new("Project '$Project' was not found.")
        }

        $standards = (Get-OcpConfiguration).standards
        $changes = New-Object System.Collections.Generic.List[object]

        foreach ($shortName in $standards.labels.Keys) {
            $definition = $standards.labels[$shortName]
            $key = Get-OcpStandardLabelKey -Name $shortName
            $current = [string](Get-OcpResourceLabel -Resource $object -Key $key)
            $desired = $null

            if ($Label) {
                if ($Label.ContainsKey($shortName)) { $desired = [string]$Label[$shortName] }
                if ($Label.ContainsKey($key)) { $desired = [string]$Label[$key] }
            }

            if ([string]::IsNullOrWhiteSpace($desired) -and $current -and (Test-OcpHasProperty -InputObject $definition -Name 'aliases')) {
                $aliasMap = $definition.aliases
                if ($aliasMap -and ($aliasMap.Contains($current))) {
                    $desired = [string]$aliasMap[$current]
                }
            }

            if ([string]::IsNullOrWhiteSpace($desired) -and [string]::IsNullOrWhiteSpace($current) -and (Test-OcpHasProperty -InputObject $definition -Name 'default')) {
                $desired = [string]$definition.default
            }

            if ([string]::IsNullOrWhiteSpace($desired)) {
                continue
            }

            Assert-OcpLabelValue -Value $desired
            if ((Test-OcpHasProperty -InputObject $definition -Name 'allowedValues') -and $definition.allowedValues) {
                $allowed = @($definition.allowedValues | ForEach-Object { [string]$_ })
                if ($desired -notin $allowed) {
                    throw [OcpValidationException]::new("Value '$desired' is not allowed for label $key.")
                }
            }

            if ($desired -ne $current) {
                $changes.Add([pscustomobject]@{
                    Key      = $key
                    OldValue = $current
                    NewValue = $desired
                })
            }
        }

        $summary = ($changes | ForEach-Object {
            $oldDisplay = if ($_.OldValue) { $_.OldValue } else { '<missing>' }
            "$($_.Key)`n    $oldDisplay`n    ->`n    $($_.NewValue)"
        }) -join "`n`n"

        if ($changes.Count -eq 0) {
            Write-OcpLog -Level Information -Message "No metadata repairs required for $Project" -OperationId $context.OperationId
            return [pscustomobject]@{
                PSTypeName  = 'OpenShiftOps.MetadataRepair'
                Project     = $Project
                Cluster      = $context.FriendlyName
                ClusterId    = $context.ClusterId
                FriendlyName = $context.FriendlyName
                Changes     = @()
                Result      = 'NoChange'
                OperationId = $context.OperationId
            }
        }

        $target = $Project
        $action = "Repair $($changes.Count) label(s) on $($context.FriendlyName) [$($context.ClusterId)]:`n$summary"
        if (-not $PSCmdlet.ShouldProcess($target, $action)) {
            return [pscustomobject]@{
                PSTypeName  = 'OpenShiftOps.MetadataRepair'
                Project     = $Project
                Cluster      = $context.FriendlyName
                ClusterId    = $context.ClusterId
                FriendlyName = $context.FriendlyName
                Changes     = $changes.ToArray()
                Result      = 'WhatIf'
                Summary     = $summary
                OperationId = $context.OperationId
            }
        }

        foreach ($change in $changes) {
            Invoke-OcpCli -ArgumentList @('label', 'namespace', $Project, "$($change.Key)=$($change.NewValue)", '--overwrite') | Out-Null
        }

        $recovery = [pscustomobject]@{
            kind    = 'MetadataRepair'
            changes = $changes.ToArray()
            reverse = @($changes | ForEach-Object {
                if ([string]::IsNullOrWhiteSpace($_.OldValue)) {
                    "Remove-OcpProjectLabel -Name '$Project' -Key '$($_.Key)'"
                }
                else {
                    "Set-OcpProjectLabel -Name '$Project' -Key '$($_.Key)' -Value '$($_.OldValue)'"
                }
            })
        }

        $audit = New-OcpAuditRecord -Context $context -Result 'Success' -Target $Project -Recovery $recovery -Message $summary
        [pscustomobject]@{
            PSTypeName   = 'OpenShiftOps.MetadataRepair'
            Project      = $Project
            Cluster      = $context.FriendlyName
            ClusterId    = $context.ClusterId
            FriendlyName = $context.FriendlyName
            Changes      = $changes.ToArray()
            Result       = 'Success'
            Summary      = $summary
            Recovery    = $recovery
            AuditPath   = $audit.auditPath
            OperationId = $context.OperationId
        }
    }
}
