BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
    Import-OpenShiftOpsForTest
}

Describe 'Pipeline cluster map matches the catalog' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        It 'keeps pipelines/cluster-map.yml aligned with config/clusters.yaml' {
            $mapPath = Join-Path $script:OcpModuleRoot '..' '..' 'pipelines' 'cluster-map.yml'
            $map = ConvertFrom-OcpYaml -Path (Resolve-Path $mapPath)
            $config = Get-OcpConfiguration
            $entries = @($map.clusters)
            $entries.Count | Should -Be $config.clusters.Count

            foreach ($entry in $entries) {
                $id = [string]$entry.clusterId
                $config.clusters.Contains($id) | Should -BeTrue
                $cluster = $config.clusters[$id]
                [string]$cluster.friendlyName | Should -Be ([string]$entry.friendlyName)
                [string]$cluster.azureDevOps.serviceConnection | Should -Be ([string]$entry.serviceConnection)
                [string]$cluster.azureDevOps.destructiveServiceConnection | Should -Be ([string]$entry.destructiveServiceConnection)
                [string]$cluster.classification | Should -Be ([string]$entry.classification)
            }
        }

        It 'maps every friendly name in authenticate.yml to the catalog connection' {
            $authPath = Join-Path $script:OcpModuleRoot '..' '..' 'pipelines' 'templates' 'authenticate.yml'
            $auth = Get-Content -LiteralPath (Resolve-Path $authPath) -Raw
            $config = Get-OcpConfiguration
            foreach ($id in $config.clusters.Keys) {
                $cluster = $config.clusters[$id]
                $friendly = [string]$cluster.friendlyName
                $auth | Should -Match ([regex]::Escape("eq(parameters.cluster, '$friendly')"))
                $auth | Should -Match ([regex]::Escape("serviceConnection: $($cluster.azureDevOps.serviceConnection)"))
                $auth | Should -Match ([regex]::Escape("serviceConnection: $($cluster.azureDevOps.destructiveServiceConnection)"))
            }
        }
    }
}
