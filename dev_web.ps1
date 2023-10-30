# Description: Boxstarter Script
# Author: Microsoft
# Common settings for web dev

$boxstarterDebug=$env:boxstarterdebug -eq "true"
$debuggerAction = { if ( $boxstarterDebug ) {Break} }

[void]($pp=if ((Get-Process -Id $pid).ProcessName -match 'choco') { Get-PackageParameters } else { $null })

if (<#$pp['debug']#> $boxstarterDebug) {
    $runspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunSpace
    Write-Host "Debug was passed in as a parameter"
    Write-Host "To enter debugging write: Enter-PSHostProcess -Id $pid"
    Write-Host "Debug-Runspace -Id $($runspace.id)"
    Wait-Debugger
}
 
if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }
Set-PSBreakpoint -variable boxstarterDebug -Action $debuggerAction
$IsVirtual = ((Get-WmiObject Win32_ComputerSystem).model).Contains("Virtual")

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

    if ($useBoxstarterMessage) { Write-BoxstarterMessage @commandParams } else { Write-Host @commandParams }
    if ($useBoxstarterMessage) { Write-BoxstarterMessage @commandParams } else { Write-Host @commandParams }
}

function Invoke-ExternalCommand([scriptblock]$Command) {
    # Workaround: Prevents 2> redirections applied to calls to this function
    #             from accidentally triggering a terminating error.
    #             See bug report at https://github.com/PowerShell/PowerShell/issues/4002
    $ErrorActionPreference = 'Continue'
    
    $Command | Out-String | Write-Verbose
    try { & $Command } catch { throw } # catch is triggered ONLY if $exe can't be found, never for errors reported by $exe itself
    $rC, $lEC = $?, $(if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 })
    _logMessage -Message "RC: $($rC) - LEC: $($lEC)" -ForegroundColor Gray    

    # Need to check both of these cases for errors as they represent different items
    # - $?: did the powershell script block throw an error
    # - $lastexitcode: did a windows command executed by the script block end in error
    if ((!$rC) -or (!$leC -and $lEC -ne 0)) {
        if ($error -ne $null) {
            Write-Warning $error[0]
        }
        throw "Command failed to execute (exit code $lEC): $Command" # "$exe indicated failure (exit code $LASTEXITCODE; full command: $Args)."
    }
}

function _chocolatey-InstallOrUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageId
       ,[Parameter()][string]$PackageParameters=""
       ,[Parameter()][string]$Source=""
    )

    [array]$remotePackageList=$(choco search $PackageId --limit-output --exact|Select-Object @{ E={ ($_.Split('|')|Select-Object -First 1) -as [string] }; N='Id'; }, @{ E={ ($_.Split('|')|Select-Object -Last 1) -as [System.Version] }; N='Version'; })
    if ($null -eq $(Get-Command -Name choco)) {
        throw "Chocolatey is not installed, unable to continue"
        Exit 1
    }

    $remotePackageListVersion = ($remotePackageList.Version|Measure-Object -Maximum).Maximum
    [array]$packageList=$(choco list $PackageId --local-only --limit-output --exact|Select-Object @{ E={ ($_.Split('|')|Select-Object -First 1) -as [string] }; N='Id'; }, @{ E={ ($_.Split('|')|Select-Object -Last 1) -as [System.Version] }; N='Version'; })
    $packageInstalledVersion=if ($PackageId -eq 'chocolatey') { $(@(($(choco --version) -as [Version]), $packageList.Version)|Measure-Object -Maximum).Maximum } else { $($packageList.Version|Measure-Object -Maximum).Maximum }

    if ($remotePackageListVersion -gt $packageInstalledVersion) { 
        Invoke-ExternalCommand { 
            $chocoParameters=@()
            $chocoParameters += 'upgrade'
            $chocoParameters += $packageId
            $chocoParameters += '--yes'
            $chocoParameters += '--accept-licence'
            $chocoParameters += '--force'
            if (![string]::IsNullOrWhiteSpace($PackageParameters)) { $chocoParameters += $('--package-parameters="{0}"' -f $PackageParameters) }
            if (![string]::IsNullOrWhiteSpace($Source)) { $chocoParameters += $('--source="{0}"' -f $Source) }
            choco @chocoParameters
            _logMessage -Message "RC: $($?) - LEC: $($LASTEXITCODE)" -ForegroundColor Gray    
        }
    }; 
    Write-Host -Object ("$($packageId) v$(choco --version)") -ForegroundColor Cyan;
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
    Disable-MicrosoftUpdate
    Disable-UAC

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
    executeScript "CommonDevTools.ps1";
    executeScript "RemoveDefaultApps.ps1";
    executeScript "HyperV.ps1";
    executeScript "Docker.ps1";
    executeScript "WSL.ps1";
    executeScript "Browsers.ps1";
    
    #--- Tools ---
    code --install-extension msjsdiag.debugger-for-chrome
    code --install-extension msjsdiag.debugger-for-edge
    
    #--- Microsoft WebDriver ---
    choco install -y microsoftwebdriver        
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
