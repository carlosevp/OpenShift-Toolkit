BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
    Import-OpenShiftOpsForTest
}

Describe 'Connect-OcpCluster authentication' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        BeforeEach {
            Mock Invoke-OcpCli {
                param($ArgumentList)
                $joined = $ArgumentList -join ' '
                if ($joined -like 'login *') {
                    return New-CliResult
                }
                if ($joined -eq 'whoami --show-server') {
                    return New-CliResult -StandardOutput 'https://api.ocp-akron-prod.example.com:6443'
                }
                if ($joined -eq 'whoami') {
                    return New-CliResult -StandardOutput 'system:serviceaccount:openshiftops:runner'
                }
                if ($joined -eq 'version -o json') {
                    return New-CliResult -Json ([pscustomobject]@{
                        openshiftVersion = '4.16.0'
                        serverVersion    = [pscustomobject]@{ gitVersion = 'v1.29.0' }
                        clientVersion    = [pscustomobject]@{ gitVersion = 'v1.29.0' }
                    }) -StandardOutput '{}'
                }
                if ($joined -like 'auth can-i *') {
                    return New-CliResult -StandardOutput 'yes'
                }
                throw "Unexpected oc invocation: $joined"
            }
        }

        AfterEach {
            Disconnect-OcpCluster
        }

        It 'validates an existing oc context against the requested cluster' {
            $result = Connect-OcpCluster -Cluster Akron-Prod
            $result.Authenticated | Should -BeTrue
            $result.AuthenticationMethod | Should -Be 'ExistingContext'
            $result.FriendlyName | Should -Be 'Akron-Prod'
            $result.ClusterId | Should -Be 'ocp-akron-prod'
            $result.Username | Should -Be 'system:serviceaccount:openshiftops:runner'
            ($result | ConvertTo-Json -Depth 6) | Should -Not -Match '(?i)sha256~|bearer |--token'
            Should -Invoke Invoke-OcpCli -Times 0 -ParameterFilter { ($ArgumentList -join ' ') -like 'login *' }
        }

        It 'authenticates with a SecureString API / bearer token' {
            $secure = ConvertTo-SecureString 'unit-test-token-value' -AsPlainText -Force
            $result = Connect-OcpCluster -Cluster Akron-Prod -Token $secure
            $result.AuthenticationMethod | Should -Be 'Token'
            $result.Username | Should -Be 'system:serviceaccount:openshiftops:runner'
            ($result.PSObject.Properties.Name -join ',') | Should -Not -Match '(?i)token'
            ($result | ConvertTo-Json -Depth 6) | Should -Not -Match 'unit-test-token-value'
            Should -Invoke Invoke-OcpCli -Times 1 -ParameterFilter { $ArgumentList[0] -eq 'login' -and $ArgumentList[2] -eq '--token' }
        }

        It 'authenticates from a named environment variable without exposing the value' {
            $env:OCP_UNIT_TEST_TOKEN = 'env-token-secret-value'
            try {
                $result = Connect-OcpCluster -Cluster '  akron-prod  ' -TokenEnvironmentVariable OCP_UNIT_TEST_TOKEN
                $result.AuthenticationMethod | Should -Be 'Token'
                $result.FriendlyName | Should -Be 'Akron-Prod'
                ($result | ConvertTo-Json -Depth 6) | Should -Not -Match 'env-token-secret-value'
            }
            finally {
                Remove-Item Env:OCP_UNIT_TEST_TOKEN
            }
        }

        It 'fails when the token environment variable is missing' {
            { Connect-OcpCluster -Cluster Akron-Prod -TokenEnvironmentVariable OCP_TOKEN_DOES_NOT_EXIST } | Should -Throw
        }

        It 'fails when the token environment variable is empty' {
            $env:OCP_UNIT_EMPTY_TOKEN = ''
            try {
                { Connect-OcpCluster -Cluster Akron-Prod -TokenEnvironmentVariable OCP_UNIT_EMPTY_TOKEN } | Should -Throw
            }
            finally {
                Remove-Item Env:OCP_UNIT_EMPTY_TOKEN
            }
        }

        It 'does not consume OCP_TOKEN unless TokenEnvironmentVariable is specified' {
            $env:OCP_TOKEN = 'should-not-be-used'
            try {
                $result = Connect-OcpCluster -Cluster Akron-Prod
                $result.AuthenticationMethod | Should -Be 'ExistingContext'
                Should -Invoke Invoke-OcpCli -Times 0 -ParameterFilter { ($ArgumentList -join ' ') -like 'login *' }
            }
            finally {
                Remove-Item Env:OCP_TOKEN
            }
        }

        It 'rejects combining -Token and -TokenEnvironmentVariable' {
            $secure = ConvertTo-SecureString 'unit-test-token-value' -AsPlainText -Force
            { Connect-OcpCluster -Cluster Akron-Prod -Token $secure -TokenEnvironmentVariable OCP_TOKEN } | Should -Throw
        }

        It 'authenticates with oc login --web against the configured server' {
            $result = Connect-OcpCluster -Cluster Akron-Prod -Web
            $result.AuthenticationMethod | Should -Be 'Web'
            $result.FriendlyName | Should -Be 'Akron-Prod'
            $result.Authenticated | Should -BeTrue
            Should -Invoke Invoke-OcpCli -Times 1 -ParameterFilter {
                $ArgumentList[0] -eq 'login' -and $ArgumentList[1] -eq 'https://api.ocp-akron-prod.example.com:6443' -and $ArgumentList[2] -eq '--web'
            }
        }

        It 'rejects combining -Web and -Token' {
            $secure = ConvertTo-SecureString 'unit-test-token-value' -AsPlainText -Force
            { Connect-OcpCluster -Cluster Akron-Prod -Web -Token $secure } | Should -Throw
        }

        It 'refuses web login in Azure DevOps' {
            $previous = $env:TF_BUILD
            $env:TF_BUILD = 'True'
            try {
                { Connect-OcpCluster -Cluster Akron-Prod -Web } | Should -Throw
                Should -Invoke Invoke-OcpCli -Times 0 -ParameterFilter { ($ArgumentList -join ' ') -like 'login *--web' }
            }
            finally {
                if ($null -eq $previous) { Remove-Item Env:TF_BUILD -ErrorAction SilentlyContinue }
                else { $env:TF_BUILD = $previous }
            }
        }

        It 'continues when oc version JSON omits openshiftVersion' {
            Mock Invoke-OcpCli {
                param($ArgumentList)
                $joined = $ArgumentList -join ' '
                if ($joined -eq 'whoami --show-server') {
                    return New-CliResult -StandardOutput 'https://api.ocp-akron-prod.example.com:6443'
                }
                if ($joined -eq 'whoami') {
                    return New-CliResult -StandardOutput 'cvp@example.com'
                }
                if ($joined -eq 'version -o json') {
                    return New-CliResult -Json ([pscustomobject]@{
                        clientVersion = [pscustomobject]@{ gitVersion = 'v4.17.0' }
                    }) -StandardOutput '{}'
                }
                if ($joined -like 'auth can-i *') {
                    return New-CliResult -StandardOutput 'yes'
                }
                throw "Unexpected oc invocation: $joined"
            }

            $result = Connect-OcpCluster -Cluster Akron-Prod
            $result.Authenticated | Should -BeTrue
            $result.Username | Should -Be 'cvp@example.com'
            $result.ClientVersion | Should -Be 'v4.17.0'
            $result.OpenShiftVersion | Should -Be ''
        }

        It 'redacts the token from login exceptions' {
            Mock Invoke-OcpCli {
                param($ArgumentList)
                $joined = $ArgumentList -join ' '
                if ($joined -like 'login *') {
                    throw 'oc login failed: unauthorized token unit-test-token-value'
                }
                throw "Unexpected oc invocation: $joined"
            }
            $secure = ConvertTo-SecureString 'unit-test-token-value' -AsPlainText -Force
            try {
                Connect-OcpCluster -Cluster Akron-Prod -Token $secure
                throw 'expected token login to fail'
            }
            catch {
                $_.Exception.Message | Should -Not -Match 'unit-test-token-value'
                $_.Exception.ToString() | Should -Not -Match 'unit-test-token-value'
            }
        }

        It 'redacts --token values from command logs' {
            $redacted = Protect-OcpArgumentList -ArgumentList @('login', 'https://api.ocp-akron-prod.example.com:6443', '--token', 'unit-test-token-value')
            ($redacted -join ' ') | Should -Be 'login https://api.ocp-akron-prod.example.com:6443 --token ***REDACTED***'
            Protect-OcpSensitiveValue -Text 'oc login https://api.example.com:6443 --token=unit-test-token-value' | Should -Be 'oc login https://api.example.com:6443 --token=***REDACTED***'
        }

        It 'accepts a service account identity and checks oc auth can-i' {
            $result = Connect-OcpCluster -Cluster Akron-Prod
            $result.Username | Should -Be 'system:serviceaccount:openshiftops:runner'
            $result.CanGetProjects | Should -BeTrue
            Should -Invoke Invoke-OcpCli -ParameterFilter { ($ArgumentList -join ' ') -like 'auth can-i get projects' -or ($ArgumentList -join ' ') -like 'auth can-i get namespaces' }
        }

        It 'blocks when the authenticated server does not match the requested cluster' {
            Mock Invoke-OcpCli {
                param($ArgumentList)
                $joined = $ArgumentList -join ' '
                if ($joined -eq 'whoami --show-server') {
                    return New-CliResult -StandardOutput 'https://api.ocp-akron-prod.example.com:6443'
                }
                if ($joined -eq 'whoami') { return New-CliResult -StandardOutput 'tester' }
                if ($joined -eq 'version -o json') {
                    return New-CliResult -Json ([pscustomobject]@{
                        openshiftVersion = '4.16.0'
                        serverVersion    = [pscustomobject]@{ gitVersion = 'v1.29.0' }
                        clientVersion    = [pscustomobject]@{ gitVersion = 'v1.29.0' }
                    })
                }
                return New-CliResult -StandardOutput 'yes'
            }
            { Connect-OcpCluster -Cluster Akron-NonProd } | Should -Throw
        }

        It 'uses CLUSTER IDENTITY MISMATCH wording that includes both requested and live servers' {
            Mock Invoke-OcpCli {
                param($ArgumentList)
                $joined = $ArgumentList -join ' '
                if ($joined -eq 'whoami --show-server') {
                    return New-CliResult -StandardOutput 'https://api.ocp-akron-prod.example.com:6443'
                }
                if ($joined -eq 'whoami') { return New-CliResult -StandardOutput 'tester' }
                if ($joined -eq 'version -o json') {
                    return New-CliResult -Json ([pscustomobject]@{
                        openshiftVersion = '4.16.0'
                        serverVersion    = [pscustomobject]@{ gitVersion = 'v1.29.0' }
                        clientVersion    = [pscustomobject]@{ gitVersion = 'v1.29.0' }
                    })
                }
                return New-CliResult -StandardOutput 'yes'
            }
            try {
                Connect-OcpCluster -Cluster Akron-NonProd
                throw 'expected identity mismatch'
            }
            catch {
                $_.Exception.Message | Should -Match 'CLUSTER IDENTITY MISMATCH'
                $_.Exception.Message | Should -Match 'Akron-NonProd'
                $_.Exception.Message | Should -Match 'api.ocp-akron-nonprod'
                $_.Exception.Message | Should -Match 'api.ocp-akron-prod'
            }
        }
    }
}

Describe 'Destructive revalidation uses resolved server identity' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'OpenShiftOps.Helpers.ps1')
        Import-OpenShiftOpsForTest
    }

    InModuleScope OpenShiftOps {
        It 'revalidates the live server immediately before deletion' {
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
            Mock Get-OcpProjectRemovalPlan { New-OcpTestPlan -CanProceed }
            Mock Get-OcpProjectObject { New-FakeProject -Name 'old-app' }
            Mock Export-OcpProjectSafetySnapshot {
                [pscustomobject]@{ ExportStatus = 'Success'; Valid = $true }
            }
            Mock Invoke-OcpCli {
                param($ArgumentList)
                $joined = $ArgumentList -join ' '
                if ($joined -eq 'whoami --show-server') {
                    return New-CliResult -StandardOutput 'https://api.ocp-akron-prod.example.com:6443'
                }
                if ($joined -like 'auth can-i *') { return New-CliResult -StandardOutput 'yes' }
                if ($joined -eq 'delete project old-app') { throw 'delete must not run after identity mismatch' }
                return New-CliResult
            }

            { Remove-OcpProject -Name old-app -Cluster Akron-NonProd -Confirm:$false } | Should -Throw
            Should -Invoke Invoke-OcpCli -Times 0 -ParameterFilter { ($ArgumentList -join ' ') -eq 'delete project old-app' }
        }
    }
}
