function New-OcpProject {
    <#
    .SYNOPSIS
        Creates an OpenShift project with the configured baseline labels and optional quota.
    .PARAMETER Name
        New project name.
    .PARAMETER Application
        Application label value.
    .PARAMETER Environment
        Environment label value. Must be one of the configured allowed values.
    .PARAMETER Owner
        Owning team or distribution list.
    .PARAMETER CostCenter
        Cost center label value.
    .PARAMETER Description
        Optional display description.
    .PARAMETER Lifecycle
        Optional lifecycle label. Defaults from configuration when set.
    .EXAMPLE
        New-OcpProject -Name claims-api-dev -Application claims-api -Environment dev -Owner claims-team -CostCenter 12345
    .OUTPUTS
        OpenShiftOps.ProjectCreate
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('Project')]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Application,

        [Parameter(Mandatory = $true)]
        [string]$Environment,

        [Parameter(Mandatory = $true)]
        [string]$Owner,

        [string]$CostCenter,
        [string]$Team,
        [string]$Description,
        [string]$Lifecycle,
        [string]$Cluster,
        [string]$ChangeReference
    )

    Assert-OcpProjectName -Name $Name
    $context = New-OcpOperationContext -Operation 'New-OcpProject' -ClusterAlias $Cluster -Project $Name -ChangeReference $ChangeReference
    Assert-OcpPermission -Verb create -Resource projects | Out-Null

    $existing = Get-OcpProjectObject -Name $Name
    if ($existing) {
        throw [OcpValidationException]::new("Project '$Name' already exists.")
    }

    $config = Get-OcpConfiguration
    $standards = $config.standards
    $envKey = Get-OcpStandardLabelKey -Name 'environment'
    $envDef = $standards.labels.environment
    if ($envDef.aliases -and $envDef.aliases.Contains($Environment)) {
        $Environment = [string]$envDef.aliases[$Environment]
    }
    $allowedEnv = @($envDef.allowedValues | ForEach-Object { [string]$_ })
    if ($Environment -notin $allowedEnv) {
        throw [OcpValidationException]::new("Environment '$Environment' is not allowed. Allowed: $($allowedEnv -join ', ')")
    }

    if (-not $Lifecycle -and $standards.labels.lifecycle.default) {
        $Lifecycle = [string]$standards.labels.lifecycle.default
    }
    $managedBy = [string]$standards.labels.'managed-by'.default
    if (-not $managedBy) { $managedBy = 'openshiftops' }

    $labels = [ordered]@{
        (Get-OcpStandardLabelKey -Name 'application')        = $Application
        (Get-OcpStandardLabelKey -Name 'environment')        = $Environment
        (Get-OcpStandardLabelKey -Name 'owner')              = $Owner
        (Get-OcpStandardLabelKey -Name 'managed-by')         = $managedBy
        (Get-OcpStandardLabelKey -Name 'created-by')         = (ConvertTo-OcpLabelSafeValue -Value $context.RequestedBy)
        (Get-OcpStandardLabelKey -Name 'created-date')       = [DateTime]::UtcNow.ToString('yyyyMMdd')
        (Get-OcpStandardLabelKey -Name 'cleanup-protection') = 'false'
    }
    if ($CostCenter) { $labels[(Get-OcpStandardLabelKey -Name 'cost-center')] = $CostCenter }
    if ($Team) { $labels[(Get-OcpStandardLabelKey -Name 'team')] = $Team }
    if ($Lifecycle) { $labels[(Get-OcpStandardLabelKey -Name 'lifecycle')] = $Lifecycle }

    foreach ($key in @($labels.Keys)) {
        Assert-OcpLabelKey -Key $key
        Assert-OcpLabelValue -Value $labels[$key]
    }

    $action = "Create project '$Name' on $($context.FriendlyName) [$($context.ClusterId)] with baseline labels and optional quota/limitrange"
    if (-not $PSCmdlet.ShouldProcess($Name, $action)) {
        return [pscustomobject]@{
            PSTypeName  = 'OpenShiftOps.ProjectCreate'
            Project      = $Name
            Cluster      = $context.FriendlyName
            ClusterId    = $context.ClusterId
            FriendlyName = $context.FriendlyName
            Labels       = $labels
            Result      = 'WhatIf'
            OperationId = $context.OperationId
        }
    }

    $createArgs = @('new-project', $Name)
    if ($Description) {
        $createArgs += @('--description', $Description)
        $createArgs += @('--display-name', $Description)
    }
    $created = Invoke-OcpCli -ArgumentList $createArgs -AllowNonZeroExit
    if (-not $created.Succeeded) {
        Invoke-OcpCli -ArgumentList @('create', 'namespace', $Name) | Out-Null
    }

    foreach ($key in $labels.Keys) {
        Invoke-OcpCli -ArgumentList @('label', 'namespace', $Name, "$key=$($labels[$key])", '--overwrite') | Out-Null
    }

    $appliedQuota = $false
    $appliedLimitRange = $false
    $baseline = $config.projectBaseline
    if ($baseline.resourceQuota.enabled -eq $true) {
        Apply-OcpProjectQuotaFromBaseline -Namespace $Name -Baseline $baseline.resourceQuota
        $appliedQuota = $true
    }
    if ($baseline.limitRange.enabled -eq $true) {
        Apply-OcpProjectLimitRangeFromBaseline -Namespace $Name -Baseline $baseline.limitRange
        $appliedLimitRange = $true
    }

    $audit = New-OcpAuditRecord -Context $context -Result 'Success' -Target $Name -Recovery ([pscustomobject]@{
        kind    = 'ProjectCreate'
        reverse = "Get-OcpProjectRemovalPlan -Name '$Name'  # then Remove-OcpProject after plan/approval"
        labels  = $labels
    }) -Message "Created project $Name"

    [pscustomobject]@{
        PSTypeName         = 'OpenShiftOps.ProjectCreate'
        Project            = $Name
        Cluster            = $context.FriendlyName
        ClusterId          = $context.ClusterId
        FriendlyName       = $context.FriendlyName
        Classification     = $context.Classification
        Labels             = $labels
        ResourceQuotaApplied = $appliedQuota
        LimitRangeApplied  = $appliedLimitRange
        Result             = 'Success'
        AuditPath          = $audit.auditPath
        OperationId        = $context.OperationId
    }
}
