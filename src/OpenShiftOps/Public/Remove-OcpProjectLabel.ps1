function Remove-OcpProjectLabel {
    <#
    .SYNOPSIS
        Removes a label from an OpenShift project and records the previous value.
    .EXAMPLE
        Remove-OcpProjectLabel -Name claims-dev -Key company.com/temporary -WhatIf
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

        [string]$Cluster,
        [string]$ChangeReference
    )

    process {
        Assert-OcpProjectName -Name $Name
        Assert-OcpLabelKey -Key $Key

        $context = New-OcpOperationContext -Operation 'Remove-OcpProjectLabel' -ClusterAlias $Cluster -Project $Name -ChangeReference $ChangeReference
        Assert-OcpPermission -Verb patch -Resource namespaces -Name $Name | Out-Null

        $project = Get-OcpProjectObject -Name $Name
        if (-not $project) {
            throw [OcpValidationException]::new("Project '$Name' was not found.")
        }

        $oldValue = [string](Get-OcpResourceLabel -Resource $project -Key $Key)
        $target = "$Name label $Key"
        $action = "Remove label '$Key' (current value '$oldValue') on cluster $($context.FriendlyName) [$($context.ClusterId)]"

        if (-not $PSCmdlet.ShouldProcess($target, $action)) {
            return [pscustomobject]@{
                PSTypeName   = 'OpenShiftOps.LabelChange'
                Project      = $Name
                Cluster      = $context.FriendlyName
                ClusterId    = $context.ClusterId
                FriendlyName = $context.FriendlyName
                Key          = $Key
                OldValue     = $oldValue
                NewValue     = $null
                Result       = 'WhatIf'
                Recovery     = "Set-OcpProjectLabel -Name $Name -Key $Key -Value '$oldValue'"
                OperationId  = $context.OperationId
            }
        }

        Invoke-OcpCli -ArgumentList @('label', 'namespace', $Name, "$Key-") | Out-Null
        $recovery = [pscustomobject]@{
            kind     = 'LabelChange'
            key      = $Key
            oldValue = $oldValue
            newValue = $null
            reverse  = $(if ($oldValue) { "Set-OcpProjectLabel -Name '$Name' -Key '$Key' -Value '$oldValue'" } else { 'No previous value.' })
        }

        $audit = New-OcpAuditRecord -Context $context -Result 'Success' -Target $Name -Recovery $recovery -Message "Removed label $Key"
        [pscustomobject]@{
            PSTypeName   = 'OpenShiftOps.LabelChange'
            Project      = $Name
            Cluster      = $context.FriendlyName
                ClusterId    = $context.ClusterId
                FriendlyName = $context.FriendlyName
            Key          = $Key
            OldValue     = $oldValue
            NewValue     = $null
            Result       = 'Success'
            Recovery     = $recovery
            AuditPath    = $audit.auditPath
            OperationId  = $context.OperationId
        }
    }
}
