BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
    Import-OpenShiftOpsForTest
}

Describe 'Cluster identity' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        BeforeEach {
            Mock Invoke-OcpCli {
                param($ArgumentList)
                $joined = $ArgumentList -join ' '
                if ($joined -eq 'whoami --show-server') {
                    return New-CliResult -StandardOutput "https://api.ocp-akron-prod.example.com:6443`n"
                }
                if ($joined -eq 'whoami') {
                    return New-CliResult -StandardOutput "tester`n"
                }
                if ($joined -eq 'version -o json') {
                    return New-CliResult -Json ([pscustomobject]@{
                        openshiftVersion = '4.16.0'
                        serverVersion    = [pscustomobject]@{ gitVersion = 'v1.29.0' }
                        clientVersion    = [pscustomobject]@{ gitVersion = 'v1.29.0' }
                    }) -StandardOutput '{}'
                }
                throw "Unexpected oc invocation: $joined"
            }
        }

        It 'fails closed when the selected alias does not match oc whoami --show-server' {
            { Test-OcpClusterIdentity -Cluster 'Akron-NonProd' -ThrowOnMismatch } | Should -Throw
        }

        It 'matches production when the server is the registered prod API' {
            $result = Test-OcpClusterIdentity -Cluster 'Akron-Prod' -ThrowOnMismatch:$false
            $result.Match | Should -BeTrue
            $result.Classification | Should -Be 'production'
        }

        It 'classifies Akron-NonProd as nonprod and Akron-Prod as production' {
            (Resolve-OcpCluster -Cluster 'Akron-NonProd').Classification | Should -Be 'nonprod'
            (Resolve-OcpCluster -Cluster 'Akron-Prod').Classification | Should -Be 'production'
        }
    }
}

Describe 'Protected projects' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        It 'detects exact default namespace' {
            $r = Test-OcpProtectedProject -Name 'default'
            $r.Protected | Should -BeTrue
        }

        It 'detects openshift- prefix as system' {
            $r = Test-OcpProtectedProject -Name 'openshift-monitoring'
            $r.Protected | Should -BeTrue
            $r.SystemProject | Should -BeTrue
        }

        It 'detects kube- prefix' {
            $r = Test-OcpProtectedProject -Name 'kube-system'
            $r.Protected | Should -BeTrue
        }

        It 'detects cleanup-protection label' {
            $labels = [pscustomobject]@{ 'company.com/cleanup-protection' = 'true' }
            $r = Test-OcpProtectedProject -Name 'claims-dev' -Labels $labels
            $r.Protected | Should -BeTrue
            $r.CleanupProtected | Should -BeTrue
        }

        It 'does not treat a normal app project as protected' {
            $labels = [pscustomobject]@{ 'company.com/cleanup-protection' = 'false' }
            $r = Test-OcpProtectedProject -Name 'claims-dev' -Labels $labels
            $r.Protected | Should -BeFalse
        }
    }
}
