BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
    Import-OpenShiftOpsForTest
}

Describe 'Label mutation recovery and ShouldProcess' {
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
                if ($joined -eq 'auth can-i patch namespaces -n claims-dev claims-dev' -or $joined -like 'auth can-i patch namespaces*') {
                    return New-CliResult -StandardOutput 'yes'
                }
                if ($joined -like 'get project claims-dev -o json' -or $joined -like 'get namespace claims-dev -o json') {
                    $proj = New-FakeProject -Name 'claims-dev' -Labels @{
                        'company.com/environment' = 'develop'
                        'company.com/application' = 'claims'
                        'company.com/owner'       = 'claims-team'
                        'company.com/cost-center' = '12345'
                        'company.com/managed-by'  = 'openshiftops'
                    }
                    return New-CliResult -Json $proj -StandardOutput ($proj | ConvertTo-Json -Depth 6)
                }
                if ($joined -like 'label namespace claims-dev *') {
                    throw 'oc label must not run during WhatIf'
                }
                return New-CliResult -StandardOutput 'yes'
            }
        }

        It 'returns old and new label values and does not mutate during -WhatIf' {
            $result = Set-OcpProjectLabel -Name claims-dev -Key 'company.com/environment' -Value 'dev' -Cluster Akron-NonProd -WhatIf -Confirm:$false
            $result.OldValue | Should -Be 'develop'
            $result.NewValue | Should -Be 'dev'
            $result.Result | Should -Be 'WhatIf'
            $result.Recovery | Should -Match 'develop'
        }

        It 'Repair-OcpProjectMetadata -WhatIf maps develop to dev' {
            $result = Repair-OcpProjectMetadata -Project claims-dev -Cluster Akron-NonProd -WhatIf -Confirm:$false
            $result.Result | Should -Be 'WhatIf'
            $change = $result.Changes | Where-Object Key -eq 'company.com/environment'
            $change.OldValue | Should -Be 'develop'
            $change.NewValue | Should -Be 'dev'
        }
    }
}

Describe 'Permission failures' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        It 'throws when can-i returns no' {
            Mock Invoke-OcpCli {
                New-CliResult -StandardOutput 'no' -ExitCode 1
            }
            { Assert-OcpPermission -Verb delete -Resource projects } | Should -Throw
        }
    }
}
