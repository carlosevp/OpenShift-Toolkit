function Get-OcpContext {
    <#
    .SYNOPSIS
        Returns the current authenticated OpenShift context.
    .DESCRIPTION
        Validates oc authentication (whoami, server, version) and maps the current
        API server to a configured cluster. Does not store or request credentials.
        Service account identities such as system:serviceaccount:ns:sa are valid.
    .EXAMPLE
        Get-OcpContext
    .OUTPUTS
        OpenShiftOps.Context
    #>
    [CmdletBinding()]
    param()

    $auth = Test-OcpAuthentication
    $cluster = Resolve-OcpCluster -Server $auth.Server -AllowUnknown
    $session = Get-OcpSession

    [pscustomobject]@{
        PSTypeName           = 'OpenShiftOps.Context'
        ClusterId            = $cluster.Id
        FriendlyName         = $cluster.FriendlyName
        ClusterAlias         = $cluster.Id
        Server               = $cluster.Server
        Username             = $auth.Username
        AuthenticationMethod = $session.AuthenticationMethod
        OpenShiftVersion     = [string](Get-OcpProperty -InputObject $auth -Name 'OpenShiftVersion' -Default '')
        KubernetesVersion    = [string](Get-OcpProperty -InputObject $auth -Name 'KubernetesVersion' -Default '')
        ClientVersion        = [string](Get-OcpProperty -InputObject $auth -Name 'ClientVersion' -Default '')
        Classification       = $cluster.Classification
        Location             = $cluster.Location
        Purpose              = $cluster.Purpose
        Authenticated        = $true
        ExecutionMode        = Get-OcpExecutionMode
        RegisteredCluster    = [bool]$cluster.Registered
        DisplayName          = $cluster.FriendlyName
        RequestedBy          = Get-OcpRequestedBy
    }
}
