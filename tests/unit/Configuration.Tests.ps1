BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
    Import-OpenShiftOpsForTest
}

Describe 'ConvertTo-OcpNormalizedServer' {

    InModuleScope OpenShiftOps {
        It 'normalizes trailing slashes and case' {
            $a = ConvertTo-OcpNormalizedServer -Server 'HTTPS://API.OCP-DEV.EXAMPLE.COM:6443/'
            $b = ConvertTo-OcpNormalizedServer -Server 'https://api.ocp-dev.example.com:6443'
            $a | Should -Be $b
        }

        It 'treats default https port 443 as explicit' {
            $a = ConvertTo-OcpNormalizedServer -Server 'https://api.example.com'
            $b = ConvertTo-OcpNormalizedServer -Server 'https://api.example.com:443'
            $a | Should -Be $b
        }

        It 'does not collapse 6443 to 443' {
            $a = ConvertTo-OcpNormalizedServer -Server 'https://api.example.com:6443'
            $b = ConvertTo-OcpNormalizedServer -Server 'https://api.example.com'
            $a | Should -Not -Be $b
        }
    }
}

Describe 'Protect-OcpSensitiveValue' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        It 'redacts bearer tokens' {
            Protect-OcpSensitiveValue -Text 'Authorization: Bearer abc.def.ghi' | Should -Match '\*\*\*REDACTED\*\*\*'
            Protect-OcpSensitiveValue -Text 'Authorization: Bearer abc.def.ghi' | Should -Not -Match 'abc.def.ghi'
        }

        It 'redacts --token arguments' {
            $redacted = Protect-OcpArgumentList -ArgumentList @('login', '--token=super-secret-token')
            ($redacted -join ' ') | Should -Match 'REDACTED'
            ($redacted -join ' ') | Should -Not -Match 'super-secret-token'
        }

        It 'redacts a separate --token value argument' {
            $redacted = Protect-OcpArgumentList -ArgumentList @('login', 'https://api.example.com:6443', '--token', 'super-secret-token')
            ($redacted -join ' ') | Should -Be 'login https://api.example.com:6443 --token ***REDACTED***'
        }

        It 'redacts JWT-shaped values' {
            $jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc'
            Protect-OcpSensitiveValue -Text "token $jwt" | Should -Match 'REDACTED-JWT'
        }
    }
}

Describe 'Get-OcpVersionInfo' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        It 'reads classic oc version JSON' {
            $json = [pscustomobject]@{
                openshiftVersion = '4.16.0'
                serverVersion    = [pscustomobject]@{ gitVersion = 'v1.29.0' }
                clientVersion    = [pscustomobject]@{ gitVersion = 'v1.29.0' }
            }
            $info = Get-OcpVersionInfo -Json $json
            $info.OpenShiftVersion | Should -Be '4.16.0'
            $info.KubernetesVersion | Should -Be 'v1.29.0'
            $info.ClientVersion | Should -Be 'v1.29.0'
        }

        It 'does not throw when openshiftVersion and serverVersion are missing' {
            $json = [pscustomobject]@{
                clientVersion = [pscustomobject]@{ gitVersion = 'v4.17.0' }
            }
            $info = Get-OcpVersionInfo -Json $json
            $info.OpenShiftVersion | Should -Be ''
            $info.KubernetesVersion | Should -Be ''
            $info.ClientVersion | Should -Be 'v4.17.0'
        }

        It 'reads ConvertFrom-Json output that omits openshiftVersion under StrictMode' {
            $json = '{"clientVersion":{"gitVersion":"v4.17.0"},"kustomizeVersion":"v5.4.2"}' | ConvertFrom-Json
            { $null = $json.openshiftVersion } | Should -Throw
            $info = Get-OcpVersionInfo -Json $json
            $info.OpenShiftVersion | Should -Be ''
            $info.ClientVersion | Should -Be 'v4.17.0'
            Get-OcpProperty -InputObject $json -Name 'openshiftVersion' -Default '' | Should -Be ''
        }

        It 'accepts kubernetesVersion and releaseClientVersion fields' {
            $json = [pscustomobject]@{
                kubernetesVersion    = 'v1.31.0'
                releaseClientVersion = '4.17.14'
            }
            $info = Get-OcpVersionInfo -Json $json
            $info.KubernetesVersion | Should -Be 'v1.31.0'
            $info.ClientVersion | Should -Be '4.17.14'
        }
    }
}

Describe 'YAML configuration loading' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        It 'loads clusters, safety policy, and standards' {
            $config = Get-OcpConfiguration
            $config.clusters.Contains('ocp-akron-prod') | Should -BeTrue
            $config.clusters['ocp-akron-prod'].classification | Should -Be 'production'
            $config.clusters['ocp-akron-prod'].friendlyName | Should -Be 'Akron-Prod'
            $config.safety.secretExport.enabled | Should -BeFalse
            $config.safety.projectDeletion.blockWhenPVCsExist | Should -BeTrue
            $config.standards.labelDomain | Should -Be 'company.com'
        }
    }
}
