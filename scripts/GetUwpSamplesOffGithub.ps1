if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

Invoke-ExternalCommand -Command { 
    Update-SessionEnvironment
    Set-Location $env:USERPROFILE\desktop
    mkdir UwpSamples
    Set-Location UwpSamples
    git clone https://github.com/Microsoft/Windows-universal-samples/
}