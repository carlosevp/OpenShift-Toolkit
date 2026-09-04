BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
    Import-OpenShiftOpsForTest
}

Describe 'Cluster name resolution' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        It 'resolves a friendly name to the canonical cluster' {
            $r = Resolve-OcpCluster -Cluster 'Akron-Prod'
            $r.Id | Should -Be 'ocp-akron-prod'
            $r.FriendlyName | Should -Be 'Akron-Prod'
            $r.Server | Should -Match 'ocp-akron-prod'
            $r.Classification | Should -Be 'production'
        }

        It 'resolves a canonical ID' {
            (Resolve-OcpCluster -Cluster 'ocp-pitt-dr').FriendlyName | Should -Be 'Pitt-DR'
        }

        It 'resolves an alias' {
            $r = Resolve-OcpCluster -Cluster 'akr-prod'
            $r.Id | Should -Be 'ocp-akron-prod'
        }

        It 'is case-insensitive and trims whitespace' {
            $a = Resolve-OcpCluster -Cluster 'AKRON-PROD'
            $b = Resolve-OcpCluster -Cluster '  Akron-Prod  '
            $c = Resolve-OcpCluster -Cluster 'akron-prod'
            $a.Id | Should -Be $b.Id
            $b.Id | Should -Be $c.Id
            $a.Id | Should -Be 'ocp-akron-prod'
        }

        It 'does not fuzzy-match unknown names' {
            { Resolve-OcpCluster -Cluster 'akron-prd' } | Should -Throw
        }

        It 'fails on an unknown alias' {
            { Resolve-OcpCluster -Cluster 'no-such-cluster' } | Should -Throw
        }

        It 'resolves Pitt-DR independently from Akron-Prod' {
            $akron = Resolve-OcpCluster -Cluster 'Akron-Prod'
            $pitt = Resolve-OcpCluster -Cluster 'Pitt-DR'
            $akron.Id | Should -Not -Be $pitt.Id
            $akron.Server | Should -Not -Be $pitt.Server
            $pitt.Purpose | Should -Be 'disaster-recovery'
            $pitt.Location | Should -Be 'Pittsburgh'
        }

        It 'fails closed on alias collisions' {
            $clusters = [ordered]@{
                'ocp-a' = [ordered]@{
                    friendlyName   = 'A-Prod'
                    aliases        = @('prod')
                    server         = 'https://api.a.example.com:6443'
                    classification = 'production'
                }
                'ocp-b' = [ordered]@{
                    friendlyName   = 'B-Prod'
                    aliases        = @('prod')
                    server         = 'https://api.b.example.com:6443'
                    classification = 'production'
                }
            }
            { New-OcpClusterLookupIndex -Clusters $clusters } | Should -Throw
        }

        It 'fails closed on friendly-name collisions' {
            $clusters = [ordered]@{
                'ocp-a' = [ordered]@{ friendlyName = 'Shared'; aliases = @('a'); server = 'https://api.a.example.com:6443'; classification = 'nonprod' }
                'ocp-b' = [ordered]@{ friendlyName = 'shared'; aliases = @('b'); server = 'https://api.b.example.com:6443'; classification = 'nonprod' }
            }
            { New-OcpClusterLookupIndex -Clusters $clusters } | Should -Throw
        }

        It 'allows a friendly name and alias that normalize to the same key on one cluster' {
            $clusters = [ordered]@{
                'ocp-akron-prod' = [ordered]@{
                    friendlyName   = 'Akron-Prod'
                    aliases        = @('akron-prod', 'akr-prod')
                    server         = 'https://api.ocp-akron-prod.example.com:6443'
                    classification = 'production'
                }
            }
            $index = New-OcpClusterLookupIndex -Clusters $clusters
            $index['akron-prod'].ClusterId | Should -Be 'ocp-akron-prod'
            $index['akr-prod'].ClusterId | Should -Be 'ocp-akron-prod'
        }

        It 'fails closed on duplicate canonical IDs in YAML' {
            $yaml = @'
clusters:
  ocp-a:
    friendlyName: A
    server: https://api.a.example.com:6443
    classification: nonprod
  ocp-a:
    friendlyName: B
    server: https://api.b.example.com:6443
    classification: nonprod
'@
            { ConvertFrom-OcpYaml -Yaml $yaml } | Should -Throw
        }

        It 'fails closed when an alias collides with a canonical ID' {
            $clusters = [ordered]@{
                'ocp-a' = [ordered]@{ friendlyName = 'A'; aliases = @('ocp-b'); server = 'https://api.a.example.com:6443'; classification = 'nonprod' }
                'ocp-b' = [ordered]@{ friendlyName = 'B'; aliases = @('b'); server = 'https://api.b.example.com:6443'; classification = 'nonprod' }
            }
            { New-OcpClusterLookupIndex -Clusters $clusters } | Should -Throw
        }
    }
}

Describe 'Get-OcpClusterInfo catalog' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        It 'lists configured clusters without live authentication' {
            $list = @(Get-OcpClusterInfo)
            $list.FriendlyName | Should -Contain 'Akron-Prod'
            $list.FriendlyName | Should -Contain 'Pitt-DR'
            $list.Count | Should -Be 4
        }

        It 'returns details for a friendly name from the catalog' {
            Mock Test-OcpAuthentication { throw 'not connected' }
            $info = Get-OcpClusterInfo -Cluster Akron-Prod
            $info.Id | Should -Be 'ocp-akron-prod'
            $info.FriendlyName | Should -Be 'Akron-Prod'
            $info.AzureDevOps.ServiceConnection | Should -Be 'OCP-AKRON-PROD'
            $info.AzureDevOps.DestructiveServiceConnection | Should -Be 'OCP-AKRON-PROD-DESTRUCTIVE'
            ($info | ConvertTo-Json -Depth 6) | Should -Not -Match '(?i)token|password|kubeconfig'
        }
    }
}
