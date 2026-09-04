BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
    Import-OpenShiftOpsForTest
}

Describe 'Project deletion safety' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        BeforeEach {
            Mock Test-OcpAuthentication {
                [pscustomobject]@{
                    Username          = 'tester'
                    Server            = 'https://api.ocp-akron-nonprod.example.com:6443'
                    OpenShiftVersion  = '4.16.0'
                    KubernetesVersion = 'v1.29.0'
                    ClientVersion     = 'v1.29.0'
                    Authenticated     = $true
                }
            }
            Mock Invoke-OcpCli {
                param($ArgumentList)
                $joined = $ArgumentList -join ' '
                if ($joined -eq 'whoami --show-server') {
                    return New-CliResult -StandardOutput 'https://api.ocp-akron-nonprod.example.com:6443'
                }
                if ($joined -like 'auth can-i *') {
                    return New-CliResult -StandardOutput 'yes'
                }
                if ($joined -like 'get project old-app -o json' -or $joined -like 'get namespace old-app -o json') {
                    $proj = New-FakeProject -Name 'old-app'
                    return New-CliResult -Json $proj
                }
                if ($joined -eq 'delete project old-app') {
                    throw 'delete must not run in this test unless explicitly mocked'
                }
                return New-CliResult
            }
        }

        It 'refuses deletion when PVCs exist' {
            Mock Get-OcpProjectRemovalPlan { New-OcpTestPlan -Pvc 4 }
            Mock Get-OcpProjectObject { New-FakeProject -Name 'old-app' }
            { Remove-OcpProject -Name old-app -Cluster Akron-NonProd -Confirm:$false } | Should -Throw
        }

        It 'refuses deletion of protected projects' {
            Mock Get-OcpProjectRemovalPlan { New-OcpTestPlan -Protected }
            Mock Get-OcpProjectObject {
                New-FakeProject -Name 'old-app' -Labels @{ 'company.com/cleanup-protection' = 'true' }
            }
            { Remove-OcpProject -Name old-app -Cluster Akron-NonProd -Confirm:$false } | Should -Throw
        }

        It 'does not delete during -WhatIf when the plan is otherwise clear' {
            Mock Get-OcpProjectRemovalPlan { New-OcpTestPlan -CanProceed }
            Mock Get-OcpProjectObject { New-FakeProject -Name 'old-app' }
            Mock Export-OcpProjectSafetySnapshot {
                [pscustomobject]@{
                    ExportStatus  = 'Success'
                    Valid         = $true
                    Path          = 'unused'
                    ManifestPath  = 'unused'
                }
            }
            Mock Test-OcpSafetySnapshot { [pscustomobject]@{ Valid = $true; ExportStatus = 'Success' } }
            $result = Remove-OcpProject -Name old-app -Cluster Akron-NonProd -WhatIf -Confirm:$false
            $result.Result | Should -Be 'WhatIf'
        }

        It 'fails closed when the safety export fails' {
            Mock Get-OcpProjectRemovalPlan { New-OcpTestPlan -CanProceed }
            Mock Get-OcpProjectObject { New-FakeProject -Name 'old-app' }
            Mock Export-OcpProjectSafetySnapshot { throw [OcpBackupException]::new('export failed') }
            { Remove-OcpProject -Name old-app -Cluster Akron-NonProd -Confirm:$false } | Should -Throw
        }

        It 'detects a stale approved plan' {
            Mock Get-OcpProjectRemovalPlan { New-OcpTestPlan -Pvc 2 }
            Mock Get-OcpProjectObject { New-FakeProject -Name 'old-app' }
            $approved = New-OcpTestPlan -Pvc 0 -CanProceed
            { Remove-OcpProject -Name old-app -Cluster Akron-NonProd -ApprovedPlan $approved -Confirm:$false } | Should -Throw
        }
    }
}

Describe 'PVC inventory details' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        It 'records PVC storage class, capacity, and bound volume' {
            Mock Invoke-OcpCli {
                param($ArgumentList)
                $joined = $ArgumentList -join ' '
                if ($joined -like 'get project claims-dev -o json') {
                    return New-CliResult -Json (New-FakeProject)
                }
                if ($joined -like 'get persistentvolumeclaims -n claims-dev -o json') {
                    $list = New-FakeList -Items @(New-FakePvc)
                    return New-CliResult -Json $list
                }
                if ($joined -like 'get * -n claims-dev -o json') {
                    return New-CliResult -Json (New-FakeList)
                }
                return New-CliResult -Json (New-FakeList)
            }

            $inv = Get-OcpProjectInventory -Namespace claims-dev -IncludePvcDetails
            $inv.PVCCount | Should -Be 1
            $inv.PersistentStorageDetected | Should -BeTrue
            $inv.PersistentVolumeClaims[0].StorageClass | Should -Be 'gp3'
            $inv.PersistentVolumeClaims[0].Capacity | Should -Be '10Gi'
            $inv.PersistentVolumeClaims[0].VolumeName | Should -Be 'pv-1'
        }
    }
}
