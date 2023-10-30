$invocationName=if ($MyInvocation.MyCommand.Name -eq 'executeScript') { $MyInvocation.BoundParameters['script'] } else { $MyInvocation.MyCommand.Name }
$headerMessageWidth=120
$headerMessageCenteredPosition=(($headerMessageWidth - $invocationName.Length -4) / 2)
$headerMessage = "`n$('=' * $headerMessageWidth)`n=$(' ' * $headerMessageCenteredPosition) {0} $(' ' * $headerMessageCenteredPosition)=`n$('=' * $headerMessageWidth)"
Write-Host -Object ($headerMessage -f $invocationName) -ForegroundColor Magenta

if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

Invoke-ExternalCommand -Command { 
    Update-SessionEnvironment
    Set-Location $env:USERPROFILE\desktop
    mkdir UwpSamples
    Set-Location UwpSamples
    git clone https://github.com/Microsoft/Windows-universal-samples/
}