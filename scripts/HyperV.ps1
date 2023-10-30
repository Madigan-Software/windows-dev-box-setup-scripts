$headerMessageWidth=120
$headerMessage="$('=' * $headerMessageWidth)`n=$(' ' * (($headerMessageWidth - $("{0}".Length))/2)) {0} $(' ' * (($headerMessageWidth - $("{0}".Length))/2))=`n$('=' * $headerMessageWidth)`n"
Write-Host -Object ($headerMessage -f $MyInvocation.MyCommand.Name) -ForegroundColor Magenta

if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

_chocolatey-InstallOrUpdate -PackageId "Microsoft-Hyper-V-All" -Source "'windowsFeatures'"
