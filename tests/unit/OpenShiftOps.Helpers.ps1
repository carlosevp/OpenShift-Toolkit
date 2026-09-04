# Shared Pester helpers. Dot-source from unit tests.

function global:Import-OpenShiftOpsForTest {
    $manifest = Join-Path $PSScriptRoot '..' '..' 'src' 'OpenShiftOps' 'OpenShiftOps.psd1'
    Import-Module -Name (Resolve-Path $manifest) -Force
}

function global:New-CliResult {
    param(
        [int]$ExitCode = 0,
        [string]$StandardOutput = '',
        [string]$StandardError = '',
        $Json = $null,
        [string[]]$Arguments = @()
    )

    [pscustomobject]@{
        PSTypeName     = 'OpenShiftOps.CliResult'
        ExitCode       = $ExitCode
        Succeeded      = ($ExitCode -eq 0)
        StandardOutput = $StandardOutput
        StandardError  = $StandardError
        Json           = $Json
        Arguments      = $Arguments
    }
}

function global:New-FakeProject {
    param(
        [string]$Name = 'claims-dev',
        [hashtable]$Labels = @{
            'company.com/application'        = 'claims'
            'company.com/environment'        = 'dev'
            'company.com/owner'              = 'claims-team'
            'company.com/cost-center'        = '12345'
            'company.com/managed-by'         = 'openshiftops'
            'company.com/cleanup-protection' = 'false'
        },
        [string]$Created = '2024-01-01T00:00:00Z'
    )

    [pscustomobject]@{
        apiVersion = 'project.openshift.io/v1'
        kind       = 'Project'
        metadata   = [pscustomobject]@{
            name              = $Name
            labels            = [pscustomobject]$Labels
            annotations       = [pscustomobject]@{}
            creationTimestamp = $Created
        }
        spec   = [pscustomobject]@{}
        status = [pscustomobject]@{ phase = 'Active' }
    }
}

function global:New-FakeList {
    param([object[]]$Items = @())
    [pscustomobject]@{
        apiVersion = 'v1'
        kind       = 'List'
        items      = $Items
    }
}

function global:New-FakePvc {
    param(
        [string]$Name = 'data',
        [string]$StorageClass = 'gp3',
        [string]$Capacity = '10Gi'
    )
    [pscustomobject]@{
        apiVersion = 'v1'
        kind       = 'PersistentVolumeClaim'
        metadata   = [pscustomobject]@{ name = $Name }
        spec       = [pscustomobject]@{
            storageClassName = $StorageClass
            volumeName       = 'pv-1'
            volumeMode       = 'Filesystem'
            accessModes      = @('ReadWriteOnce')
            resources        = [pscustomobject]@{
                requests = [pscustomobject]@{ storage = $Capacity }
            }
        }
        status = [pscustomobject]@{ phase = 'Bound' }
    }
}

function global:New-OcpTestPlan {
    param(
        [int]$Pvc = 0,
        [int]$Running = 0,
        [switch]$Protected,
        [switch]$CanProceed
    )

    [pscustomobject]@{
        PSTypeName                = 'OpenShiftOps.ProjectRemovalPlan'
        OperationId               = 'plan-1'
        Cluster                   = 'Akron-NonProd'
        ClusterId                 = 'ocp-akron-nonprod'
        FriendlyName              = 'Akron-NonProd'
        Server                    = 'https://api.ocp-akron-nonprod.example.com:6443'
        Project                   = 'old-app'
        Environment               = 'dev'
        Owner                     = 'team'
        Application               = 'app'
        Classification            = 'nonprod'
        CreatedDate               = [DateTime]::UtcNow.AddDays(-400)
        AgeDays                   = 400
        PodCount                  = $Running
        RunningPodCount           = $Running
        DeploymentCount           = 0
        StatefulSetCount          = 0
        RouteCount                = 0
        PVCCount                  = $Pvc
        SecretCount               = 1
        ConfigMapCount            = 1
        CronJobCount              = 0
        PersistentStorageDetected = ($Pvc -gt 0)
        PersistentVolumeClaims    = @()
        ProtectedProject          = [bool]$Protected
        CleanupProtected          = [bool]$Protected
        SystemProject             = $false
        Warnings                  = @()
        BlockingConditions        = $(if ($Pvc -gt 0) { @('PVC') } elseif ($Protected) { @('protected') } else { @() })
        Risk                      = 'Destructive'
        CanProceed                = [bool]$CanProceed
        ChangeReference           = $null
        GeneratedAt               = [DateTime]::UtcNow
    }
}

