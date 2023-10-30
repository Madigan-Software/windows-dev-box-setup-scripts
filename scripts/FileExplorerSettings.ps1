$invocationName=if ($MyInvocation.MyCommand.Name -eq 'executeScript') { $MyInvocation.BoundParameters['script'] } else { $MyInvocation.MyCommand.Name }
$headerMessageWidth=120
$headerMessageCenteredPosition=(($headerMessageWidth - $invocationName.Length -4) / 2)
$headerMessage = "`n$('=' * $headerMessageWidth)`n=$(' ' * $headerMessageCenteredPosition) {0} $(' ' * $headerMessageCenteredPosition)=`n$('=' * $headerMessageWidth)"
Write-Host -Object ($headerMessage -f $invocationName) -ForegroundColor Magenta

if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

Invoke-ExternalCommand -Command { 
    #--- Configuring Windows properties ---
    #--- Windows Features ---
    # Show hidden files, Show protected OS files, Show file extensions
    Set-WindowsExplorerOptions -EnableShowHiddenFilesFoldersDrives -EnableShowProtectedOSFiles -EnableShowFileExtensions

    #--- File Explorer Settings ---
    # will expand explorer to the actual folder you're in
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name NavPaneExpandToCurrentFolder -Value 1
    #adds things back in your left pane like recycle bin
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name NavPaneShowAllFolders -Value 1
    #opens PC to This PC, not quick access
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name LaunchTo -Value 1
    #taskbar where window is open for multi-monitor
    Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name MMTaskbarMode -Value 2
}