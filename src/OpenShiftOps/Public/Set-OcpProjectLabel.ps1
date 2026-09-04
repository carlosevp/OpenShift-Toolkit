function Set-OcpProjectLabel {
    <#
    .SYNOPSIS
        Sets a label on an OpenShift project and records before/after values for recovery.
    .PARAMETER Name
        Project name.
    .PARAMETER Key
        Kubernetes label key.
    .PARAMETER Value
        Kubernetes label value.
    .PARAMETER Cluster
        Cluster alias that must match the current oc context.
    .PARAMETER ChangeReference
        Optional change record. Required for production when policy demands it.
    .EXAMPLE
        Set-OcpProjectLabel -Name claims-dev -Key company.com/environment -Value dev -WhatIf
    .OUTPUTS
        OpenShiftOps.LabelChange
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Project')]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [string]$Cluster,
        [string]$ChangeReference
    )

    process {
        Assert-OcpProjectName -Name $Name
        Assert-OcpLabelKey -Key $Key
        Assert-OcpLabelValue -Value $Value

        $context = New-OcpOperationContext -Operation 'Set-OcpProjectLabel' -ClusterAlias $Cluster -Project $Name -ChangeReference $ChangeReference
        Assert-OcpPermission -Verb patch -Resource namespaces -Name $Name | Out-Null

        $project = Get-OcpProjectObject -Name $Name
        if (-not $project) {
            throw [OcpValidationException]::new("Project '$Name' was not found.")
        }

        $oldValue = [string](Get-OcpResourceLabel -Resource $project -Key $Key)
        $target = "$Name label $Key"
        $action = "Set '$Key' from '$oldValue' to '$Value' on cluster $($context.FriendlyName) [$($context.ClusterId)]"

        if (-not $PSCmdlet.ShouldProcess($target, $action)) {
            return [pscustomobject]@{
                PSTypeName   = 'OpenShiftOps.LabelChange'
                Project      = $Name
                Cluster      = $context.FriendlyName
                ClusterId    = $context.ClusterId
                FriendlyName = $context.FriendlyName
                Key          = $Key
                OldValue     = $oldValue
                NewValue     = $Value
                Result       = 'WhatIf'
                Recovery     = "Set-OcpProjectLabel -Name $Name -Key $Key -Value '$oldValue'"
                OperationId  = $context.OperationId
            }
        }

        Invoke-OcpCli -ArgumentList @('label', 'namespace', $Name, "$Key=$Value", '--overwrite') | Out-Null

        $recovery = [pscustomobject]@{
            kind      = 'LabelChange'
            key       = $Key
            oldValue  = $oldValue
            newValue  = $Value
            reverse   = $(
                if ([string]::IsNullOrEmpty($oldValue)) {
                    "Remove-OcpProjectLabel -Name '$Name' -Key '$Key'"
                }
                else {
                    "Set-OcpProjectLabel -Name '$Name' -Key '$Key' -Value '$oldValue'"
                }
            )
        }

        $audit = New-OcpAuditRecord -Context $context -Result 'Success' -Target $Name -Recovery $recovery -Message "Set label $Key"
        [pscustomobject]@{
            PSTypeName   = 'OpenShiftOps.LabelChange'
            Project      = $Name
            Cluster      = $context.FriendlyName
                ClusterId    = $context.ClusterId
                FriendlyName = $context.FriendlyName
            Key          = $Key
            OldValue     = $oldValue
            NewValue     = $Value
            Result       = 'Success'
            Recovery     = $recovery
            AuditPath    = $audit.auditPath
            OperationId  = $context.OperationId
        }
    }
}
