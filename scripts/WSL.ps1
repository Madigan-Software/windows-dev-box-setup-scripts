$headerMessageWidth=120
$headerMessage="$('=' * $headerMessageWidth)`n=$(' ' * (($headerMessageWidth - $("{0}".Length))/2)) {0} $(' ' * (($headerMessageWidth - $("{0}".Length))/2))=`n$('=' * $headerMessageWidth)`n"
Write-Host -Object ($headerMessage -f $MyInvocation.MyCommand.Name) -ForegroundColor Magenta

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