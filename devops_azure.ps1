# Description: Boxstarter Script
# Author: Microsoft
# Common settings for azure devops

try {
    Disable-MicrosoftUpdate
    Disable-UAC

    $ConfirmPreference = "None" #ensure installing powershell modules don't prompt on needed dependencies
    
    # Get the base URI path from the ScriptToCall value
    $bstrappackage = "-bootstrapPackage"
    $helperUri = $Boxstarter['ScriptToCall']
    $strpos = $helperUri.IndexOf($bstrappackage)
    $helperUri = $helperUri.Substring($strpos + $bstrappackage.Length)
    $helperUri = $helperUri.TrimStart("'", " ")
    $helperUri = $helperUri.TrimEnd("'", " ")
    $helperUri = $helperUri.Substring(0, $helperUri.LastIndexOf("/"))
    $helperUri += "/scripts"
    write-host "helper script base URI is $helperUri"
    
    function executeScript {
        Param ([string]$script)
        write-host "executing $helperUri/$script ..."
        iex ((new-object net.webclient).DownloadString("$helperUri/$script"))
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
