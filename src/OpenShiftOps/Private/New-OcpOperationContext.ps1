function New-OcpOperationId {
    [CmdletBinding()]
    param()
    return [guid]::NewGuid().ToString()
}

function New-OcpOperationContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [string]$ClusterAlias,
        [string]$Project,
        [string]$ChangeReference,
        [string]$Risk
    )

    if ($Project) {
        Assert-OcpProjectName -Name $Project
    }

    $null = Get-OcpConfiguration
    $auth = Test-OcpAuthentication
    $executionMode = Get-OcpExecutionMode

    $cluster = $null
    if ($ClusterAlias) {
        Assert-OcpClusterIdentity -Cluster $ClusterAlias
        $cluster = Resolve-OcpCluster -Cluster $ClusterAlias
    }
    else {
        $cluster = Resolve-OcpCluster -Server $auth.Server -AllowUnknown
        if (-not $cluster.Registered) {
            Write-OcpLog -Level Warning -Message "Current oc server is not in clusters.yaml. Mutations will be refused."
        }
    }

    if (-not $Risk) {
        $Risk = Get-OcpRiskLevel -Operation $Operation
    }

    if ((Test-OcpRiskIsMutation -Risk $Risk) -and -not $cluster.Registered) {
        throw [OcpClusterIdentityException]::new(
            "Refusing mutation '$Operation' because the current oc server is not a registered cluster alias."
        )
    }

    if ((Test-OcpRiskIsMutation -Risk $Risk) -and $cluster.Registered) {
        Assert-OcpClusterIdentity -Cluster $cluster.Id
    }

    Assert-OcpChangeReference -ChangeReference $ChangeReference -Classification $cluster.Classification -Risk $Risk

    $operationId = New-OcpOperationId
    $context = [pscustomobject]@{
        PSTypeName       = 'OpenShiftOps.OperationContext'
        OperationId      = $operationId
        Operation        = $Operation
        Risk             = $Risk
        ClusterAlias     = $cluster.Id
        ClusterId        = $cluster.Id
        FriendlyName     = $cluster.FriendlyName
        Server           = $cluster.Server
        Classification   = $cluster.Classification
        Location         = $cluster.Location
        Purpose          = $cluster.Purpose
        AuthenticationMethod = (Get-OcpAuthenticationMethod)
        RegisteredCluster = [bool]$cluster.Registered
        Project          = $Project
        Username         = $auth.Username
        OpenShiftVersion = $auth.OpenShiftVersion
        ExecutionMode    = $executionMode
        RequestedBy      = Get-OcpRequestedBy
        ChangeReference  = $ChangeReference
        StartedAt        = [DateTime]::UtcNow
        Pipeline         = Get-OcpPipelineMetadata
    }

    Write-OcpLog -Level Information -Message "Operation context created for $Operation" -OperationId $operationId -Data @{
        cluster = $context.FriendlyName
        clusterId = $context.ClusterId
        risk    = $Risk
        project = $Project
        mode    = $executionMode
    }

    return $context
}

function Get-OcpPipelineMetadata {
    [CmdletBinding()]
    param()

    if ((Get-OcpExecutionMode) -ne 'AzureDevOps') {
        return $null
    }

    return [pscustomobject]@{
        BuildId        = $env:BUILD_BUILDID
        BuildNumber    = $env:BUILD_BUILDNUMBER
        PipelineName   = $env:BUILD_DEFINITIONNAME
        RequestedFor   = $env:BUILD_REQUESTEDFOR
        Repository     = $env:BUILD_REPOSITORY_NAME
        Commit         = $env:BUILD_SOURCEVERSION
        TeamProject    = $env:SYSTEM_TEAMPROJECT
        CollectionUri  = $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI
        JobId          = $env:SYSTEM_JOBID
    }
}
