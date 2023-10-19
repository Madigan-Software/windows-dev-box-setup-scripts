# Description: Boxstarter Script
# Author: Microsoft
# Common dev settings for machine learning using only Windows native tools

try {
    Disable-MicrosoftUpdate
    Disable-UAC

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
    executeScript "SystemConfiguration.ps1";
    executeScript "FileExplorerSettings.ps1";
    executeScript "RemoveDefaultApps.ps1";
    executeScript "GetMLIDEAndTooling.ps1";
    executeScript "PythonMLTools.ps1";        
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
