$invocationName=if ($MyInvocation.MyCommand.Name -eq 'executeScript') { $MyInvocation.BoundParameters['script'] } else { $MyInvocation.MyCommand.Name }
$headerMessageWidth=120
$headerMessageCenteredPosition=(($headerMessageWidth - $invocationName.Length -4) / 2)
$headerMessage = "`n$('=' * $headerMessageWidth)`n=$(' ' * $headerMessageCenteredPosition) {0} $(' ' * $headerMessageCenteredPosition)=`n$('=' * $headerMessageWidth)"
Write-Host -Object ($headerMessage -f $invocationName) -ForegroundColor Magenta

if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

_chocolatey-InstallOrUpdate -PackageId "Microsoft-Windows-Subsystem-Linux" -PackageParameters $packageParameters -Source "'windowsfeatures'"
Invoke-ExternalCommand -Command { 
    try {
        #--- Ubuntu ---
        # TODO: Move this to choco install once --root is included in that package
        Invoke-WebRequest -Uri https://aka.ms/wsl-ubuntu-1804 -OutFile ~/Ubuntu.appx -UseBasicParsing
        Add-AppxPackage -Path ~/Ubuntu.appx
        # run the distro once and have it install locally with root user, unset password

        RefreshEnv
        Ubuntu1804 install --root
        Ubuntu1804 run apt update
        Ubuntu1804 run apt upgrade -y

        <#
        NOTE: Other distros can be scripted the same way for example:

        #--- SLES ---
        # Install SLES Store app
        Invoke-WebRequest -Uri https://aka.ms/wsl-sles-12 -OutFile ~/SLES.appx -UseBasicParsing
        Add-AppxPackage -Path ~/SLES.appx
        # Launch SLES
        sles-12.exe

        # --- openSUSE ---
        Invoke-WebRequest -Uri https://aka.ms/wsl-opensuse-42 -OutFile ~/openSUSE.appx -UseBasicParsing
        Add-AppxPackage -Path ~/openSUSE.appx
        # Launch openSUSE
        opensuse-42.exe
        #>
    } finally {
        Remove-Item ~/Ubuntu.appx -Force -ErrorAction silentlyContinue
    }
}