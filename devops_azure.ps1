# Description: Boxstarter Script
# Author: Microsoft
# Common settings for azure devops

$invocationName=if ($MyInvocation.MyCommand.Name -eq 'executeScript') { $MyInvocation.BoundParameters['script'] } else { $MyInvocation.MyCommand.Name }
$headerMessageWidth=120
$headerMessageCenteredPosition=(($headerMessageWidth - $invocationName.Length -4) / 2)
$headerMessage = "`n$('=' * $headerMessageWidth)`n=$(' ' * $headerMessageCenteredPosition) {0} $(' ' * $headerMessageCenteredPosition)=`n$('=' * $headerMessageWidth)"
Write-Host -Object ($headerMessage -f $invocationName) -ForegroundColor Magenta

$debuggerAction = { if ( $boxstarterDebug ) { Break } } # kudos https://petri.com/conditional-breakpoints-in-powershell/
[void](Set-PSBreakpoint -Variable boxstarterDebug -Mode ReadWrite -Action $debuggerAction)
Set-PSBreakpoint -Variable boxstarterDebug -Mode ReadWrite -Action $debuggerAction

[bool]$boxstarterDebug=$env:boxstarterdebug -eq "true"
[void]($pp=if ((Get-Process -Id $pid).ProcessName -match 'choco') { Get-PackageParameters } else { ${ } })

if (<#$pp['debug']#> $boxstarterDebug) {
    $runspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunSpace
    Write-Host "Debug was passed in as a parameter"
    Write-Host "To enter debugging write: Enter-PSHostProcess -Id $pid"
    Write-Host "Debug-Runspace -Id $($runspace.id)"
    Wait-Debugger
}
 
if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }
$IsVirtual = ((Get-WmiObject Win32_ComputerSystem).model).Contains("Virtual")

try {
    Disable-MicrosoftUpdate
    Disable-UAC

    $ConfirmPreference = "None" #ensure installing powershell modules don't prompt on needed dependencies
    
    # Get the base URI path from the ScriptToCall value
    $bstrappackage = "-bootstrapPackage"
    if (![string]::IsNullOrEmpty($Boxstarter['ScriptToCall'])) {
        $helperUri = $Boxstarter['ScriptToCall']
        $strpos = $helperUri.IndexOf($bstrappackage)
        $helperUri = $helperUri.Substring($strpos + $bstrappackage.Length)
        $helperUri = $helperUri -replace ('(?:(\s+\-\w+)+)'), ''
        $helperUri = $helperUri.TrimStart("'", " ")
        $helperUri = $helperUri.TrimEnd("'", " ")

        Write-Verbose -Message "uri is $($helperUri|Out-String)"
        [void]([System.Uri]::TryCreate($helperUri, [System.UriKind]::RelativeOrAbsolute, [ref]$helperUri));
        Write-Verbose -Message "uri is $($helperUri|Out-String)"
        $helperUri
        $helperUri.AbsolutePath
    
        #$helperUri.Scheme -match '^file'; 
        $helperUri = $helperUri.AbsolutePath
        $helperUri = $helperUri.Substring(0, $helperUri.LastIndexOf("/"))
        $helperUri = $helperUri -replace '(\\|/)$',''
        $helperUri += "/scripts"
    } else {
        $helperUri = (Join-Path -Path $PSScriptRoot -ChildPath 'scripts')
    }
    $helperUri = $helperUri -replace '(\\|/)$',''
    write-host "helper script base URI is $helperUri"
    
    function executeScript {
        Param ([string]$script)
        write-host "executing $helperUri/$script ..."
        Invoke-Expression ((new-object net.webclient).DownloadString("$helperUri/$script"))
    }
    
    #--- Setting up Windows ---
    executeScript "FileExplorerSettings.ps1";
    executeScript "SystemConfiguration.ps1";
    executeScript "RemoveDefaultApps.ps1";
    executeScript "CommonDevTools.ps1";
    executeScript "Browsers.ps1";
    
    executeScript "HyperV.ps1";
    RefreshEnv
    executeScript "WSL.ps1";
    RefreshEnv
    executeScript "Docker.ps1";
    
    choco install -y powershell-core
    choco install -y azure-cli
    Install-Module -Force Az
    choco install -y microsoftazurestorageexplorer
    choco install -y terraform
    
    # Install tools in WSL instance
    write-host "Installing tools inside the WSL distro..."
    Ubuntu1804 run apt install ansible -y        
} catch {
    # Write-ChocolateyFailure $($MyInvocation.MyCommand.Name) $($_.Exception.ToString())
    $formatstring = "{0} : {1}`n{2}`n" +
                    "    + CategoryInfo          : {3}`n" +
                    "    + FullyQualifiedErrorId : {4}`n"
    $fields = $_.InvocationInfo.MyCommand.Name,$_.ErrorDetails.Message,$_.InvocationInfo.PositionMessage,$_.CategoryInfo.ToString(), $_.FullyQualifiedErrorId
    Write-Host -Object ($formatstring -f $fields) -ForegroundColor Red -BackgroundColor Black
    throw $_.Exception
} finally {
    #--- reenabling critial items ---
    Enable-UAC
    Enable-MicrosoftUpdate
}

Install-WindowsUpdate -acceptEula
