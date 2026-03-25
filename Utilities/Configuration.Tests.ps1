Describe 'Test-NetworkConnectivity' {
    It 'returns dictionary keyed by host' {
        . "$PSScriptRoot/Configuration.ps1"
        $hosts = @('host1.example', 'host2.example')
        Mock -CommandName Invoke-WebRequest -MockWith { [pscustomobject]@{ StatusCode = 200 } }
        $result = Test-NetworkConnectivity -TestHosts $hosts
        $result.Keys | Should -Be $hosts
    }
}
