function Connect-OcpCluster {
    <#
    .SYNOPSIS
        Selects a configured OpenShift cluster and authenticates with oc.
    .DESCRIPTION
        Resolves a friendly name, alias, or canonical ID to the configured cluster
        record, then authenticates using one of:

        - ExistingContext: validate the current oc login against the selected cluster
        - Web: oc login <server> --web (browser / OAuth)
        - Token / API Token / Bearer Token: oc login --token (SecureString)
        - TokenEnvironmentVariable: read a named environment variable internally

        Token values are never logged, returned, audited, or written to artifacts.
        Token authentication uses an isolated temporary kubeconfig so the operator's
        default kubeconfig is not replaced. Web login updates the current kubeconfig
        (the same file oc login --web would use).

        Friendly names are lookup conveniences only. Mutations still require the
        authenticated API server to match the configured server URL.
    .PARAMETER Cluster
        Friendly name, alias, or canonical ID. Defaults to $env:OCP_CLUSTER when set.
    .PARAMETER Web
        Open a browser for OpenShift OAuth login (oc login --web). Interactive only.
    .PARAMETER Token
        OpenShift API / bearer token as a SecureString. Do not pass a plain string.
    .PARAMETER TokenEnvironmentVariable
        Name of an environment variable that contains the API / bearer token.
        The value is read internally and never returned.
    .EXAMPLE
        Connect-OcpCluster -Cluster Akron-NonProd -Web
    .EXAMPLE
        Connect-OcpCluster -Cluster Akron-Prod
    .EXAMPLE
        $token = Read-Host 'OpenShift API token' -AsSecureString
        Connect-OcpCluster -Cluster Akron-Prod -Token $token
    .EXAMPLE
        Connect-OcpCluster -Cluster Pitt-DR -TokenEnvironmentVariable OCP_TOKEN
    .OUTPUTS
        OpenShiftOps.Context
    #>
    [CmdletBinding(DefaultParameterSetName = 'ExistingContext')]
    param(
        [Parameter(ParameterSetName = 'ExistingContext')]
        [Parameter(ParameterSetName = 'Web')]
        [Parameter(ParameterSetName = 'Token')]
        [Parameter(ParameterSetName = 'TokenEnvironmentVariable')]
        [string]$Cluster = $env:OCP_CLUSTER,

        [Parameter(ParameterSetName = 'Web', Mandatory = $true)]
        [switch]$Web,

        [Parameter(ParameterSetName = 'Token', Mandatory = $true)]
        [SecureString]$Token,

        [Parameter(ParameterSetName = 'TokenEnvironmentVariable', Mandatory = $true)]
        [string]$TokenEnvironmentVariable
    )

    if ([string]::IsNullOrWhiteSpace($Cluster)) {
        throw [OcpValidationException]::new(
            'A cluster is required. Pass -Cluster or set OCP_CLUSTER to a configured friendly name, alias, or canonical ID.'
        )
    }

    $target = Resolve-OcpCluster -Cluster $Cluster
    $method = switch ($PSCmdlet.ParameterSetName) {
        'Web' { 'Web' }
        'Token' { 'Token' }
        'TokenEnvironmentVariable' { 'Token' }
        default { 'ExistingContext' }
    }

    $plainToken = $null
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Web') {
            Invoke-OcpWebLogin -Cluster $target
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Token') {
            $plainToken = ConvertFrom-OcpSecureString -SecureString $Token
            if ([string]::IsNullOrWhiteSpace($plainToken)) {
                throw [OcpAuthenticationException]::new('The supplied API / bearer token is empty.')
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'TokenEnvironmentVariable') {
            $plainToken = Get-OcpTokenFromEnvironment -VariableName $TokenEnvironmentVariable
        }

        if ($plainToken) {
            Switch-OcpIsolatedKubeconfig | Out-Null
            try {
                Invoke-OcpCli -ArgumentList @('login', $target.Server, '--token', $plainToken) | Out-Null
            }
            catch {
                Restore-OcpIsolatedKubeconfig -BestEffort
                $safe = Protect-OcpKnownSecret -Text $_.Exception.Message -Secret $plainToken
                throw [OcpAuthenticationException]::new(
                    "Token / API token / bearer token login to $($target.FriendlyName) failed. $safe"
                )
            }
        }

        $auth = Test-OcpAuthentication
        $identity = Test-OcpClusterIdentity -Cluster $target.Id -ThrowOnMismatch:$false
        if (-not $identity.Match) {
            if ($plainToken) {
                Restore-OcpIsolatedKubeconfig -BestEffort
            }
            throw [OcpClusterIdentityException]::new((New-OcpClusterIdentityMismatchMessage -Requested $target -ActualServer $identity.ActualServer))
        }

        Set-OcpSession -AuthenticationMethod $method -ClusterId $target.Id -FriendlyName $target.FriendlyName

        $canGetProjects = Test-OcpPermission -Verb get -Resource projects
        if (-not $canGetProjects.Allowed) {
            $canGetProjects = Test-OcpPermission -Verb get -Resource namespaces
        }

        $context = [pscustomobject]@{
            PSTypeName           = 'OpenShiftOps.Context'
            ClusterId            = $target.Id
            FriendlyName         = $target.FriendlyName
            ClusterAlias         = $target.Id
            Server               = $target.Server
            Username             = $auth.Username
            AuthenticationMethod = $method
            Classification       = $target.Classification
            Location             = $target.Location
            Purpose              = $target.Purpose
            Authenticated        = $true
            ExecutionMode        = Get-OcpExecutionMode
            RegisteredCluster    = $true
            DisplayName          = $target.FriendlyName
            RequestedBy          = Get-OcpRequestedBy
            OpenShiftVersion     = $auth.OpenShiftVersion
            KubernetesVersion    = $auth.KubernetesVersion
            ClientVersion        = $auth.ClientVersion
            CanGetProjects       = [bool]$canGetProjects.Allowed
        }

        Write-OcpLog -Level Information -Message "Connected to $($context.FriendlyName) ($($context.ClusterId)) using $method as $($context.Username)"
        Write-Information -MessageData @"
Connected successfully.

Cluster:        $($context.FriendlyName)
Cluster ID:     $($context.ClusterId)
Server:         $($context.Server)
User:           $($context.Username)
Auth:           $($context.AuthenticationMethod)
Classification: $($context.Classification)
"@ -InformationAction Continue

        return $context
    }
    finally {
        $plainToken = $null
    }
}

function Invoke-OcpWebLogin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Cluster
    )

    if ((Get-OcpExecutionMode) -eq 'AzureDevOps') {
        throw [OcpAuthenticationException]::new(
            'Web / browser login is interactive and is not supported in Azure DevOps. Use a mapped service connection or Connect-OcpCluster -TokenEnvironmentVariable OCP_TOKEN.'
        )
    }

    Write-Information -MessageData @"
Opening a browser for OpenShift web login.

Cluster: $($Cluster.FriendlyName)
Server:  $($Cluster.Server)

Complete the login in the browser, then return here.
"@ -InformationAction Continue

    try {
        Invoke-OcpCli -ArgumentList @('login', $Cluster.Server, '--web') -Interactive -TimeoutSeconds 600 | Out-Null
    }
    catch {
        $safe = Protect-OcpSensitiveValue -Text $_.Exception.Message
        throw [OcpAuthenticationException]::new(
            "Web login to $($Cluster.FriendlyName) failed. Use 'oc login $($Cluster.Server) --web' if the browser did not open. $safe"
        )
    }
}

function Disconnect-OcpCluster {
    <#
    .SYNOPSIS
        Clears an OpenShiftOps token session and restores the previous kubeconfig.
    .DESCRIPTION
        Removes an isolated temporary kubeconfig created by token authentication.
        Never deletes the operator's existing kubeconfig. ExistingContext and Web
        sessions are cleared without changing KUBECONFIG.
    #>
    [CmdletBinding()]
    param()

    Restore-OcpIsolatedKubeconfig -BestEffort
    $script:OcpSession = New-OcpEmptySession
    Write-OcpLog -Level Information -Message 'OpenShiftOps session cleared.'
}
