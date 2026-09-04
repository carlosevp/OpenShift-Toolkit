# Integration tests are read-only unless OPENSHIFTOPS_INTEGRATION_MUTATIONS=1.
# They never delete a namespace.

Describe 'Optional live cluster integration' {
    BeforeAll {
        $script:Enabled = $env:OPENSHIFTOPS_INTEGRATION -eq '1'
        if ($script:Enabled) {
            $manifest = Join-Path $PSScriptRoot '..' '..' 'src' 'OpenShiftOps' 'OpenShiftOps.psd1'
            Import-Module -Name (Resolve-Path $manifest) -Force
        }
    }

    It 'returns a context from oc whoami' -Skip:(-not $script:Enabled) {
        $ctx = Get-OcpContext
        $ctx.Authenticated | Should -BeTrue
        $ctx.Server | Should -Match '^https://'
    }

    It 'lists projects without mutating' -Skip:(-not $script:Enabled) {
        $projects = @(Get-OcpProject)
        $projects.Count | Should -BeGreaterThan 0
    }

    It 'does not run mutations unless explicitly enabled' {
        $env:OPENSHIFTOPS_INTEGRATION_MUTATIONS | Should -Not -Be '1'
    }
}
