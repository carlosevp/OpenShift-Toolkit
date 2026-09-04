function Get-OcpJsonItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $result = Invoke-OcpCli -ArgumentList $ArgumentList -Json -AllowNonZeroExit
    if (-not $result.Succeeded) {
        Write-OcpLog -Level Verbose -Message "oc returned non-zero for $($result.Arguments -join ' ')"
        return @()
    }

    if ($null -eq $result.Json) {
        return @()
    }

    if (Test-OcpHasProperty -InputObject $result.Json -Name 'items') {
        $items = Get-OcpProperty -InputObject $result.Json -Name 'items'
        if ($null -eq $items) {
            return @()
        }
        return @($items)
    }

    $kind = [string](Get-OcpProperty -InputObject $result.Json -Name 'kind')
    if ($kind -eq 'List') {
        return @()
    }

    return @($result.Json)
}

function Get-OcpProjectObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-OcpProjectName -Name $Name
    $project = Invoke-OcpCli -ArgumentList @('get', 'project', $Name, '-o', 'json') -Json -AllowNonZeroExit
    if ($project.Succeeded) {
        return $project.Json
    }

    $namespace = Invoke-OcpCli -ArgumentList @('get', 'namespace', $Name, '-o', 'json') -Json -AllowNonZeroExit
    if ($namespace.Succeeded) {
        return $namespace.Json
    }

    return $null
}

function Get-OcpProjectInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Namespace,

        [switch]$IncludeTransient,
        [switch]$IncludePvcDetails
    )

    Assert-OcpProjectName -Name $Namespace
    $project = Get-OcpProjectObject -Name $Namespace
    if (-not $project) {
        throw [OcpValidationException]::new("Project '$Namespace' was not found.")
    }

    $created = $null
    $ageDays = $null
    if ($project.metadata.creationTimestamp) {
        $created = [DateTime]$project.metadata.creationTimestamp
        $ageDays = [int][Math]::Floor(([DateTime]::UtcNow - $created.ToUniversalTime()).TotalDays)
    }

    $resourceQueries = @(
        @{ Name = 'pods'; Arguments = @('get', 'pods', '-n', $Namespace, '-o', 'json') }
        @{ Name = 'deployments'; Arguments = @('get', 'deployments.apps', '-n', $Namespace, '-o', 'json') }
        @{ Name = 'statefulsets'; Arguments = @('get', 'statefulsets.apps', '-n', $Namespace, '-o', 'json') }
        @{ Name = 'daemonsets'; Arguments = @('get', 'daemonsets.apps', '-n', $Namespace, '-o', 'json') }
        @{ Name = 'services'; Arguments = @('get', 'services', '-n', $Namespace, '-o', 'json') }
        @{ Name = 'routes'; Arguments = @('get', 'routes.route.openshift.io', '-n', $Namespace, '-o', 'json') }
        @{ Name = 'persistentvolumeclaims'; Arguments = @('get', 'persistentvolumeclaims', '-n', $Namespace, '-o', 'json') }
        @{ Name = 'secrets'; Arguments = @('get', 'secrets', '-n', $Namespace, '-o', 'json') }
        @{ Name = 'configmaps'; Arguments = @('get', 'configmaps', '-n', $Namespace, '-o', 'json') }
        @{ Name = 'cronjobs'; Arguments = @('get', 'cronjobs.batch', '-n', $Namespace, '-o', 'json') }
        @{ Name = 'jobs'; Arguments = @('get', 'jobs.batch', '-n', $Namespace, '-o', 'json') }
        @{ Name = 'buildconfigs'; Arguments = @('get', 'buildconfigs.build.openshift.io', '-n', $Namespace, '-o', 'json') }
        @{ Name = 'imagestreams'; Arguments = @('get', 'imagestreams.image.openshift.io', '-n', $Namespace, '-o', 'json') }
        @{ Name = 'replicationcontrollers'; Arguments = @('get', 'replicationcontrollers', '-n', $Namespace, '-o', 'json') }
    )

    $collections = @{}
    foreach ($query in $resourceQueries) {
        $collections[$query.Name] = @(Get-OcpJsonItems -ArgumentList $query.Arguments)
    }

    $runningPods = @($collections.pods | Where-Object {
            $status = Get-OcpProperty -InputObject $_ -Name 'status'
            (Get-OcpProperty -InputObject $status -Name 'phase') -eq 'Running'
        })
    $deploymentsWithReplicas = @($collections.deployments | Where-Object {
            $spec = Get-OcpProperty -InputObject $_ -Name 'spec'
            [int](Get-OcpProperty -InputObject $spec -Name 'replicas' -Default 0) -gt 0
        })
    $statefulSetsWithReplicas = @($collections.statefulsets | Where-Object {
            $spec = Get-OcpProperty -InputObject $_ -Name 'spec'
            [int](Get-OcpProperty -InputObject $spec -Name 'replicas' -Default 0) -gt 0
        })

    $pvcDetails = @()
    if ($IncludePvcDetails -or $collections.persistentvolumeclaims.Count -gt 0) {
        foreach ($pvc in $collections.persistentvolumeclaims) {
            $spec = Get-OcpProperty -InputObject $pvc -Name 'spec'
            $status = Get-OcpProperty -InputObject $pvc -Name 'status'
            $resources = Get-OcpProperty -InputObject $spec -Name 'resources'
            $requests = Get-OcpProperty -InputObject $resources -Name 'requests'
            $metadata = Get-OcpProperty -InputObject $pvc -Name 'metadata'
            $pvcDetails += [pscustomobject]@{
                Name          = [string](Get-OcpProperty -InputObject $metadata -Name 'name')
                StorageClass  = [string](Get-OcpProperty -InputObject $spec -Name 'storageClassName')
                Capacity      = [string](Get-OcpMapValue -Map $requests -Key 'storage')
                VolumeName    = [string](Get-OcpProperty -InputObject $spec -Name 'volumeName')
                VolumeMode    = [string](Get-OcpProperty -InputObject $spec -Name 'volumeMode')
                AccessModes   = @((Get-OcpProperty -InputObject $spec -Name 'accessModes'))
                Phase         = [string](Get-OcpProperty -InputObject $status -Name 'phase')
            }
        }
    }

    $protection = Test-OcpProtectedProject -Name $Namespace -Labels $project.metadata.labels
    $labelDomain = [string](Get-OcpConfiguration).standards.labelDomain

    return [pscustomobject]@{
        PSTypeName              = 'OpenShiftOps.ProjectInventory'
        Name                    = $Namespace
        Project                 = $project
        Created                 = $created
        AgeDays                 = $ageDays
        Labels                  = $project.metadata.labels
        Annotations             = $project.metadata.annotations
        Environment             = [string](Get-OcpResourceLabel -Resource $project -Key "$labelDomain/environment")
        Owner                   = [string](Get-OcpResourceLabel -Resource $project -Key "$labelDomain/owner")
        Application             = [string](Get-OcpResourceLabel -Resource $project -Key "$labelDomain/application")
        Lifecycle               = [string](Get-OcpResourceLabel -Resource $project -Key "$labelDomain/lifecycle")
        PodCount                = $collections.pods.Count
        RunningPodCount         = $runningPods.Count
        DeploymentCount         = $collections.deployments.Count
        ActiveDeploymentCount   = $deploymentsWithReplicas.Count
        StatefulSetCount        = $collections.statefulsets.Count
        ActiveStatefulSetCount  = $statefulSetsWithReplicas.Count
        DaemonSetCount          = $collections.daemonsets.Count
        ServiceCount            = $collections.services.Count
        RouteCount              = $collections.routes.Count
        PVCCount                = $collections.persistentvolumeclaims.Count
        SecretCount             = $collections.secrets.Count
        ConfigMapCount          = $collections.configmaps.Count
        CronJobCount            = $collections.cronjobs.Count
        JobCount                = $collections.jobs.Count
        BuildConfigCount        = $collections.buildconfigs.Count
        ImageStreamCount        = $collections.imagestreams.Count
        PersistentStorageDetected = ($collections.persistentvolumeclaims.Count -gt 0)
        PersistentVolumeClaims  = $pvcDetails
        ProtectedProject        = [bool]$protection.Protected
        CleanupProtected        = [bool]$protection.CleanupProtected
        SystemProject           = [bool]$protection.SystemProject
        ProtectionReasons       = $protection.Reasons
        Collections             = $collections
        IncludeTransient        = [bool]$IncludeTransient
    }
}

function ConvertTo-OcpProjectSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Inventory,

        [string]$ClusterAlias,
        [string]$FriendlyName,
        [string]$Classification,
        $Standards
    )

    process {
        $display = if ($FriendlyName) { $FriendlyName } else { $ClusterAlias }
        [pscustomobject]@{
            PSTypeName         = 'OpenShiftOps.Project'
            Name               = $Inventory.Name
            Cluster            = $display
            ClusterId          = $ClusterAlias
            FriendlyName       = $display
            Classification     = $Classification
            Environment        = $Inventory.Environment
            Owner              = $Inventory.Owner
            Application        = $Inventory.Application
            Lifecycle          = $Inventory.Lifecycle
            Created            = $Inventory.Created
            AgeDays            = $Inventory.AgeDays
            PodCount           = $Inventory.PodCount
            RunningPodCount    = $Inventory.RunningPodCount
            DeploymentCount    = $Inventory.DeploymentCount
            StatefulSetCount   = $Inventory.StatefulSetCount
            PVCCount           = $Inventory.PVCCount
            RouteCount         = $Inventory.RouteCount
            SecretCount        = $Inventory.SecretCount
            ConfigMapCount     = $Inventory.ConfigMapCount
            CronJobCount       = $Inventory.CronJobCount
            StandardsCompliant = if ($null -ne $Standards) { [bool]$Standards.Compliant } else { $null }
            CleanupProtected   = $Inventory.CleanupProtected
            ProtectedProject   = $Inventory.ProtectedProject
        }
    }
}
