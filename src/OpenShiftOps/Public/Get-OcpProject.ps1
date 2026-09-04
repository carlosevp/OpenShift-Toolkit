function Get-OcpProject {
    <#
    .SYNOPSIS
        Lists OpenShift projects with lifecycle metadata and resource counts.
    .DESCRIPTION
        Returns structured objects suitable for pipeline filtering. Resource counts are
        included when the identity can list the relevant namespaced objects.
    .PARAMETER Name
        Optional project name. When omitted, all visible projects are returned.
    .PARAMETER Cluster
        Optional cluster alias used to verify the current oc context.
    .EXAMPLE
        Get-OcpProject
    .EXAMPLE
        Get-OcpProject | Where-Object Environment -eq 'dev' | Sort-Object AgeDays
    .OUTPUTS
        OpenShiftOps.Project
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('Project')]
        [string]$Name,

        [string]$Cluster
    )

    begin {
        $context = New-OcpOperationContext -Operation 'Get-OcpProject' -ClusterAlias $Cluster
        $listPermission = Test-OcpPermission -Verb get -Resource projects
        if (-not $listPermission.Allowed) {
            Assert-OcpPermission -Verb get -Resource namespaces | Out-Null
        }
    }

    process {
        $names = @()
        if ($Name) {
            Assert-OcpProjectName -Name $Name
            $names = @($Name)
        }
        else {
            $projects = @(Get-OcpJsonItems -ArgumentList @('get', 'projects', '-o', 'json'))
            if ($projects.Count -eq 0) {
                $projects = @(Get-OcpJsonItems -ArgumentList @('get', 'namespaces', '-o', 'json'))
            }
            $names = @($projects | ForEach-Object { [string]$_.metadata.name })
        }

        foreach ($projectName in $names) {
            try {
                $inventory = Get-OcpProjectInventory -Namespace $projectName
                $standards = $null
                try {
                    $standards = Test-OcpProjectStandards -Project $projectName -Cluster $context.ClusterAlias -Quiet
                }
                catch {
                    Write-OcpLog -Level Verbose -Message "Standards check skipped for $projectName : $($_.Exception.Message)"
                }
                ConvertTo-OcpProjectSummary -Inventory $inventory -ClusterAlias $context.ClusterId -FriendlyName $context.FriendlyName -Classification $context.Classification -Standards $standards
            }
            catch {
                Write-OcpLog -Level Warning -Message "Unable to inventory project '$projectName': $($_.Exception.Message)"
            }
        }
    }
}
