$invocationName=if ($MyInvocation.MyCommand.Name -eq 'executeScript') { $MyInvocation.BoundParameters['script'] } else { $MyInvocation.MyCommand.Name }
$headerMessageWidth=120
$headerMessageCenteredPosition=(($headerMessageWidth - $invocationName.Length -4) / 2)
$headerMessage = "`n$('=' * $headerMessageWidth)`n=$(' ' * $headerMessageCenteredPosition) {0} $(' ' * $headerMessageCenteredPosition)=`n$('=' * $headerMessageWidth)"
Write-Host -Object ($headerMessage -f $invocationName) -ForegroundColor Magenta

if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

Invoke-ExternalCommand -Command { 
    $_message = "*** [$($MyInvocation.MyCommand.Name)] Setting up WinGet - Start ***"

    try {
        _logMessage -Message $_message -ForegroundColor Gray

        $progressPreference = 'silentlyContinue'
        Write-Information "Downloading WinGet and its dependencies..."
        Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle
        Invoke-WebRequest -Uri https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx -OutFile Microsoft.VCLibs.x64.14.00.Desktop.appx
        Invoke-WebRequest -Uri https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.7.3/Microsoft.UI.Xaml.2.7.x64.appx -OutFile Microsoft.UI.Xaml.2.7.x64.appx
        Add-AppxPackage Microsoft.VCLibs.x64.14.00.Desktop.appx
        Add-AppxPackage Microsoft.UI.Xaml.2.7.x64.appx
        Add-AppxPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle
    } finally {
        Remove-Item -Path '.\Microsoft.VCLibs.x64.14.00.Desktop.appx','.\Microsoft.UI.Xaml.2.7.x64.appx','Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -Force -ErrorAction SilentlyContinue

        $_message=$_message.Replace("- Start ","- End ")
        _logMessage -Message $_message -ForegroundColor Cyan
    }
}