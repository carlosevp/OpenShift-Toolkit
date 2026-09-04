BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
    Import-OpenShiftOpsForTest
}

Describe 'Recovery manifests and secret redaction' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        It 'strips server-generated fields' {
            $resource = [pscustomobject]@{
                apiVersion = 'v1'
                kind       = 'ConfigMap'
                metadata   = [pscustomobject]@{
                    name              = 'app'
                    uid               = '123'
                    resourceVersion   = '9'
                    generation        = 2
                    creationTimestamp = '2024-01-01T00:00:00Z'
                    managedFields     = @('x')
                }
                status = [pscustomobject]@{ phase = 'ignored' }
                data   = [pscustomobject]@{ k = 'v' }
            }
            $clean = ConvertTo-OcpRecoveryManifest -Resource $resource
            $clean.metadata.PSObject.Properties['uid'] | Should -BeNullOrEmpty
            $clean.metadata.PSObject.Properties['resourceVersion'] | Should -BeNullOrEmpty
            $clean.PSObject.Properties['status'] | Should -BeNullOrEmpty
            $clean.data.k | Should -Be 'v'
        }

        It 'strips secret data when excluded' {
            $secret = [pscustomobject]@{
                apiVersion = 'v1'
                kind       = 'Secret'
                metadata   = [pscustomobject]@{ name = 's1'; annotations = [pscustomobject]@{} }
                data       = [pscustomobject]@{ password = 'dGVzdA==' }
                stringData = [pscustomobject]@{ extra = 'nope' }
            }
            $clean = ConvertTo-OcpRecoveryManifest -Resource $secret -ExcludeSecretData
            $clean.PSObject.Properties['data'] | Should -BeNullOrEmpty
            $clean.PSObject.Properties['stringData'] | Should -BeNullOrEmpty
            $clean.metadata.annotations.'openshiftops/secret-data-excluded' | Should -Be 'true'
        }
    }
}

Describe 'Safety snapshot verification' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ocp-tests-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:TempRoot | Out-Null
    }

    AfterAll {
        if (Test-Path $script:TempRoot) { Remove-Item $script:TempRoot -Recurse -Force }
    }

    InModuleScope OpenShiftOps {
        It 'accepts a successful export manifest' {
            $path = Join-Path $TestDrive 'backup-manifest.json'
            @{
                operationId             = 'id'
                cluster                 = 'ocp-dev'
                project                 = 'old-app'
                timestamp               = '2026-09-04T00:00:00Z'
                exportStatus            = 'Success'
                resourceTypesDiscovered = 41
                resourceTypesExported   = 29
                resourceCount           = 183
                secretsExcluded         = $true
                persistentVolumeCount   = 0
                warnings                = @()
            } | ConvertTo-Json | Set-Content -LiteralPath $path
            $r = Test-OcpSafetySnapshot -ManifestPath $path
            $r.Valid | Should -BeTrue
        }

        It 'fails closed when exportStatus is not Success' {
            $path = Join-Path $TestDrive 'backup-failed.json'
            @{
                operationId             = 'id'
                cluster                 = 'ocp-dev'
                project                 = 'old-app'
                exportStatus            = 'Failed'
                resourceTypesDiscovered = 0
                resourceTypesExported   = 0
                resourceCount           = 0
                secretsExcluded         = $true
                persistentVolumeCount   = 0
                warnings                = @('boom')
            } | ConvertTo-Json | Set-Content -LiteralPath $path
            { Test-OcpSafetySnapshot -ManifestPath $path } | Should -Throw
        }

        It 'fails closed if secrets were exported' {
            $path = Join-Path $TestDrive 'backup-secrets.json'
            @{
                operationId             = 'id'
                cluster                 = 'ocp-dev'
                project                 = 'old-app'
                exportStatus            = 'Success'
                resourceTypesDiscovered = 1
                resourceTypesExported   = 1
                resourceCount           = 1
                secretsExcluded         = $false
                persistentVolumeCount   = 0
                warnings                = @()
            } | ConvertTo-Json | Set-Content -LiteralPath $path
            { Test-OcpSafetySnapshot -ManifestPath $path } | Should -Throw
        }
    }
}

Describe 'Stale plan detection' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        It 'detects PVC count increase' {
            $approved = [pscustomobject]@{ Cluster = 'ocp-dev'; Project = 'app'; PVCCount = 0; RunningPodCount = 0; CleanupProtected = $false; ProtectedProject = $false; Server = 'https://api.ocp-dev.example.com:6443' }
            $current = [pscustomobject]@{ Cluster = 'ocp-dev'; Project = 'app'; PVCCount = 2; RunningPodCount = 0; CleanupProtected = $false; ProtectedProject = $false; Server = 'https://api.ocp-dev.example.com:6443' }
            $r = Compare-OcpRemovalPlan -ApprovedPlan $approved -CurrentPlan $current
            $r.MaterialChange | Should -BeTrue
            $r.Changes -join ' ' | Should -Match 'PVC'
        }

        It 'detects running pod increase' {
            $approved = [pscustomobject]@{ Cluster = 'ocp-dev'; Project = 'app'; PVCCount = 0; RunningPodCount = 0; CleanupProtected = $false; ProtectedProject = $false }
            $current = [pscustomobject]@{ Cluster = 'ocp-dev'; Project = 'app'; PVCCount = 0; RunningPodCount = 4; CleanupProtected = $false; ProtectedProject = $false }
            (Compare-OcpRemovalPlan -ApprovedPlan $approved -CurrentPlan $current).MaterialChange | Should -BeTrue
        }

        It 'detects cleanup-protection appearing after plan' {
            $approved = [pscustomobject]@{ Cluster = 'ocp-dev'; Project = 'app'; PVCCount = 0; RunningPodCount = 0; CleanupProtected = $false; ProtectedProject = $false }
            $current = [pscustomobject]@{ Cluster = 'ocp-dev'; Project = 'app'; PVCCount = 0; RunningPodCount = 0; CleanupProtected = $true; ProtectedProject = $true }
            (Compare-OcpRemovalPlan -ApprovedPlan $approved -CurrentPlan $current).MaterialChange | Should -BeTrue
        }
    }
}

Describe 'Bulk safety limits' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        It 'allows batches at or below the default limit' {
            $r = Test-OcpBulkSafetyLimit -TargetCount 10
            $r.Allowed | Should -BeTrue
        }

        It 'stops when the unattended mutation count is exceeded' {
            { Test-OcpBulkSafetyLimit -TargetCount 47 } | Should -Throw
        }
    }
}
