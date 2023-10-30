# Description: Boxstarter Script
# Author: FRFL - Cyril Madigan
# Common dev settings for baseline machine setup

[CmdletBinding()]
param()

if (<#$pp['debug']#> $env:boxstarterdebug -eq "true") {
    $runspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunSpace
    Write-Host "Debug was passed in as a parameter"
    Write-Host "To enter debugging write: Enter-PSHostProcess -Id $pid"
    Write-Host "Debug-Runspace -Id $($runspace.id)"
    Wait-Debugger
}
 
if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }
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

$_message = "*** [$($MyInvocation.MyCommand.Name)] Setting up developer workstation - Start ***"
try {
    _logMessage -Message $_message
    if (((choco --version) -as [System.Version]) -lt [System.Version]("2.2.2")) { 
        #_logMessage -Message "Chocolatey v$(choco --version) <= v2.2.2"
        #Invoke-ExternalCommand -Command { choco upgrade chocolatey }
        _chocolatey-InstallOrUpdate -PackageId Chocolatey
    }

    Disable-MicrosoftUpdate
    Disable-UAC

    if (!$IsVirtual) {
    Invoke-ExternalCommand -Command { 
        #region helper
        $_setFeatureState={
            [CmdletBinding()]
            param (
                [Parameter()]$Feature
               ,[Parameter()][ValidateSet('enable','disable')][string]$TargetState
            )
            if ($Feature.State -notmatch "^$($TargetState).*$") { 
                choco feature $TargetState.ToString().ToLower() --name="'$($Feature.Id.ToString().Trim())'"
            }
        }
        #endregion helper
        [array]$featureList=$(choco feature --limit-output|Select-Object @{ E={ ($_.Split('|')|Select-Object -First 1) -as [string] }; N='Id'; }, @{ E={ ($_.Split('|')|Select-Object -Skip 1 -First 1) -as [string] }; N='State'; }, @{ E={ ($_.Split('|')|Select-Object -Last 1) -as [string] }; N='Description'; })
        $enabledList = $featureList|Where-Object { $_.Id -match "^(allowEmptyChecksumsSecure|autoUninstaller|checksumFiles|ignoreInvalidOptionsSwitches|logValidationResultsOnWarnings|powershellHost|showDownloadProgress|showNonElevatedWarnings|usePackageExitCodes|usePackageRepositoryOptimizations)$" }
        $disabledList = $featureList|Where-Object { $_.Id -notin $enabledList.Id}
        $disabledList|Foreach-Object {
            &$_setFeatureState -Feature $_ -TargetState 'disable'
        }
        $enabledList|Foreach-Object {
            &$_setFeatureState -Feature $_ -TargetState 'enable'
        }
    }
    }
    # Get the base URI path from the ScriptToCall value
    <#$Boxstarter['ScriptToCall']=@"
Import-Module (Join-Path -Path "C:\ProgramData\Boxstarter" -ChildPath BoxStarter.Chocolatey\Boxstarter.Chocolatey.psd1) -global -DisableNameChecking; Invoke-ChocolateyBoxstarter -bootstrapPackage 'C:\data\tfs\git\Sandbox\windows-dev-box-setup-scripts\WORK_DeveloperMachineInstall.ps1' -DisableReboots -StopOnPackageFailure
"@#>
    $bstrappackage = "-bootstrapPackage"
    $helperUri = $Boxstarter['ScriptToCall']
    _logMessage -Message "*** [001] - helper boxstarter.ScriptToCall is $($Boxstarter['ScriptToCall'])" -ForegroundColor Gray

    if (![string]::IsNullOrEmpty($Boxstarter['ScriptToCall'])) {
        $strpos = $helperUri.IndexOf($bstrappackage)
        $helperUri = $helperUri.Substring($strpos + $bstrappackage.Length)
        $helperUri = $helperUri -replace ('(?:(\s+\-\w+)+)'), ''
        $helperUri = $helperUri.TrimStart("'", " ")
        $helperUri = $helperUri.TrimEnd("'", " ")
        [void]([System.Uri]::TryCreate($helperUri, [System.UriKind]::RelativeOrAbsolute, [ref]$helperUri));
        #_logMessage -Message "*** [002] - $($helperUri|Out-String)" -ForegroundColor Gray
        _logMessage -Message "*** [003] - $($helperUri.AbsolutePath)" -ForeGroundColor Magenta
        #$helperUri.Scheme -match '^file'; 
        $helperUri = $helperUri.AbsoluteUri
        $helperUri = $helperUri.Substring(0, $helperUri.LastIndexOf("/"))
        $helperUri += ""
    } else {
        $helperUri = (Join-Path -Path $PSScriptRoot -ChildPath '')
    }
    $helperUri = $helperUri -replace '(\\|/)$',''
    _logMessage -Message "*** [004] - helper script base URI is $($helperUri)" -ForegroundColor Gray
    
    function executeScript {
        Param ([string]$script)
        #$scriptInvovcation = (Get-Variable -Name MyInvocation -Scope Script).Value
        #$scriptFullPath = $scriptInvovcation.MyCommand.Path # full path of script
        #$scriptPath = Split-Path -Path $scriptFullPath      # pwth of script
        #$scriptName = $scriptInvovcation.MyCommand.Name     #scriptName
        #$invocationPath = $scriptInvovcation.InvocationName # invocation relative to `$PWD

        _logMessage -Message "executing $helperUri/$script ..."
        Invoke-Expression ((new-object net.webclient).DownloadString("$helperUri/$script"))
    }
    
    #--- Setting up Windows OS ---
    _logMessage -Message "*** [005] - Setting up Windows OS" -ForegroundColor Gray
    #executeScript "scripts/WinGetInstaller.ps1"
    #executeScript "scripts/WindowsOptionalFeatures.ps1"
    if (Test-PendingReboot) { Invoke-Reboot }

    #--- Setting up Common Folders ---
    _logMessage -Message "*** [006] - Creating common folder structure" -ForegroundColor Gray
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
    
    #--- Setting up SQL Server ---
    _logMessage -Message "*** [007] - Setting up SQL Server" -ForegroundColor Gray
    executeScript "scripts/SQLServerInstaller.ps1"
    if (Test-PendingReboot) { Invoke-Reboot }

    #--- Setting up base DevEnvironment ---
    _logMessage -Message "*** [008] - Developer Tools" -ForegroundColor Gray
    executeScript "dev_app.ps1";
    if (Test-PendingReboot) { Invoke-Reboot }
} catch {
    # Write-ChocolateyFailure $($MyInvocation.MyCommand.Name) $($_.Exception.ToString())
    $formatstring = "{0} : {1}`n{2}`n" +
                    "    + CategoryInfo          : {3}`n" +
                    "    + FullyQualifiedErrorId : {4}`n"
    $fields = $_.InvocationInfo.MyCommand.Name,$_.ErrorDetails.Message,$_.InvocationInfo.PositionMessage,$_.CategoryInfo.ToString(), $_.FullyQualifiedErrorId
    Write-Host -Object ($formatstring -f $fields) -ForegroundColor Red -BackgroundColor Black
    throw (New-Object System.Exception(($formatstring -f $fields), $_.Exception))
} finally {
    #--- reenabling critial items ---
    Enable-UAC
    Enable-MicrosoftUpdate

    $_message=$_message.Replace("- Start ","- End ")
    _logMessage -Message $_message -ForegroundColor Cyan

    $webLauncherUrl=https://dev.azure.com/FrFl-Development/Evolve
    Start-Process microsoft-edge:$webLauncherUrl
}
