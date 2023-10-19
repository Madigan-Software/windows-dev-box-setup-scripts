# Description: Boxstarter Script
# Author: FRFL - Cyril Madigan
# Common dev settings for baseline machine setup

[CmdletBinding()]
param()

function _logMessage {
    param(
        [Parameter()][string]$Message
        ,[Parameter()][ConsoleColor]$ForegroundColor
        ,[Parameter()][ConsoleColor]$BackgroundColor
        )

    [bool]$useBoxstarterMessage = $($null -ne (Get-Command -name 'Write-BoxstarterMessage' -ErrorAction SilentlyContinue))
    $ForegroundColor=if (!$ForegroundColor) { [ConsoleColor]::Yellow } else { $ForegroundColor }
    $ForegroundColor=if ($useBoxstarterMessage) { $ForegroundColor } else { [System.Enum]::GetNames($ForegroundColor.GetType()) -match "$($ForegroundColor.ToString())"|Select-Object -Last 1 }
    $BackgroundColor=if (!$BackgroundColor) { [ConsoleColor]::Yellow } else { $BackgroundColor }
    $BackgroundColor=if ($useBoxstarterMessage) { $BackgroundColor } else { [System.Enum]::GetNames($BackgroundColor.GetType()) -match "$($BackgroundColor.ToString())"|Select-Object -Last 1 }

    $commandParams=@{
        "$(if ($useBoxstarterMessage) { 'message' } else { 'Object' })"=$Message;
        "$(if ($useBoxstarterMessage) { 'color' } else { 'ForegroundColor' })"=$ForegroundColor;
    }

    if ($useBoxstarterMessage) { Write-BoxstarterMessage @$commandParams } else { Write-Host @$commandParams }
}

$RefreshEnvironment={
    $message = "*** Refresh Environment ***"
    if ((Get-Command -Name 'Update-SessionEnvironment')) {
        $message = $message -replace '\*\*\*$', '- Update-SessionEnvironment ***'
        _logMessage -Message $message -ForegroundColor Yellow
        Update-SessionEnvironment 
    }
    else { 
        $message = $message -replace '\*\*\*$', '- RefreshEnv.cmd ***'
        _logMessage -Message $message -ForegroundColor Yellow
        RefreshEnv.cmd 
    }
    #&$LogSeperator
}

try {
    _logMessage -Message "*** Trace Start - Setting up developer workstation ***"

    Disable-MicrosoftUpdate
    Disable-UAC

    # Get the base URI path from the ScriptToCall value
    $bstrappackage = "-bootstrapPackage"
    $helperUri = $Boxstarter['ScriptToCall']
    _logMessage -Message "helper boxstarter.ScriptToCall is $($Boxstarter['ScriptToCall'])" -ForegroundColor Gray

    $strpos = $helperUri.IndexOf($bstrappackage)
    $helperUri = $helperUri.Substring($strpos + $bstrappackage.Length)
    $helperUri = $helperUri.TrimStart("'", " ")
    $helperUri = $helperUri.TrimEnd("'", " ")
    $helperUri = $helperUri.Substring(0, $helperUri.LastIndexOf("/"))
    $helperUri += ""
    _logMessage -Message "helper script base URI is $helperUri" -ForegroundColor Gray
    
    function executeScript {
        Param ([string]$script)
        $scriptInvovcation = (Get-Variable -Name MyInvocation -Scope Script).Value
        $scriptFullPath = $scriptInvovcation.MyCommand.Path # full path of script
        $scriptPath = Split-Path -Path $scriptFullPath      # pwth of script
        $scriptName = $scriptInvovcation.MyCommand.Name     #scriptName
        $invocationPath = $scriptInvovcation.InvocationName # invocation relative to `$PWD

        _logMessage -Message "executing $helperUri/$script ..."
        Invoke-Expression ((new-object net.webclient).DownloadString("$helperUri/$script"))
    }
    
    #--- Setting up Windows OS ---
    executeScript "/scripts/WinGetInstaller.ps1"
    executeScript "/scripts/WindowsOptionalFeatures.ps1"

    #--- Setting up base DevEnvironment ---
    _logMessage -Message "*** Creating common folder structure ***"
    $rootPath="C:\data\"
    @(
        "\sql\Backup\"
        ,"\sql\Data\"
        ,"\sql\Log\"
        ,"\sql\Snapshots\"
        ,"\tfs\git\"
        ,"\tfs\git\Sandbox"
    ) | Foreach-Object {
        [void](New-Item -Path "$($rootPath)$($_)" -Type Directory -Force -ErrorAction SilentlyContinue)
    }
    executeScript "dev_app.ps1";

    #--- Setting up SQL Server ---
    executeScript "/scripts/SQLServerInstaller.ps1"

    _logMessage -Message "*** Setting up developer workstation - End ***"
} catch {
    Write-ChocolateyFailure $($MyInvocation.MyCommand.Name) $($_.Exception.ToString())
} finally {
    #--- reenabling critial items ---
    Enable-UAC
    Enable-MicrosoftUpdate
}