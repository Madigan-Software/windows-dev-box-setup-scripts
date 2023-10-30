$invocationName=if ($MyInvocation.MyCommand.Name -eq 'executeScript') { $MyInvocation.BoundParameters['script'] } else { $MyInvocation.MyCommand.Name }
$headerMessageWidth=120
$headerMessageCenteredPosition=(($headerMessageWidth - $invocationName.Length -4) / 2)
$headerMessage = "`n$('=' * $headerMessageWidth)`n=$(' ' * $headerMessageCenteredPosition) {0} $(' ' * $headerMessageCenteredPosition)=`n$('=' * $headerMessageWidth)"
Write-Host -Object ($headerMessage -f $invocationName) -ForegroundColor Magenta

if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

Invoke-ExternalCommand -Command { 
    #--- Enable developer mode on the system ---
    Set-ItemProperty -Path HKLM:\Software\Microsoft\Windows\CurrentVersion\AppModelUnlock -Name AllowDevelopmentWithoutDevLicense -Value 1
}