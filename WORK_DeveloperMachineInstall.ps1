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

    if ($useBoxstarterMessage) { Write-BoxstarterMessage @commandParams } else { Write-Host @commandParams }
    if ($useBoxstarterMessage) { Write-BoxstarterMessage @commandParams } else { Write-Host @commandParams }
}

function Invoke-ExternalCommand([scriptblock]$Command) {
    $Command | Out-String | Write-Verbose
    & $Command
    $rC, $lEC = $?, $LASTEXITCODE
    _logMessage -Message "RC: $($rC) - LEC: $($lEC)" -ForegroundColor Gray    

    # Need to check both of these cases for errors as they represent different items
    # - $?: did the powershell script block throw an error
    # - $lastexitcode: did a windows command executed by the script block end in error
    if ((!$rC) -or ($lEC -ne 0)) {
        if ($error -ne $null) {
            Write-Warning $error[0]
        }
        throw "Command failed to execute: $Command"
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
            if ($null -ne $PackageParameters) { $chocoParameters += $('--package-parameters="{0}"' -f $PackageParameters) }
            if ($null -ne $Source) { $chocoParameters += $('--source="{0}"' -f $Source) }
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

    Invoke-ExternalCommand -Command { 
        choco feature disable --name="'allowEmptyChecksums'"                     # Allow packages to have empty/missing checksums for downloaded resources from non-secure locations (HTTP, FTP). Enabling is not recommended if using sources that download resources from the internet.
        choco feature disable --name="'allowGlobalConfirmation'"                 # Prompt for confirmation in scripts or bypass.
        choco feature disable --name="'disableCompatibilityChecks'"              # Disable Compatibility Checks - Should a warning we shown, before and after command execution, when a runtime compatibility check determines that there is an incompatibility between Chocolatey and Chocolatey Licensed Extension. Available in 1.1.0+
        choco feature disable --name="'exitOnRebootDetected'"                    # Exit On Reboot Detected - Stop running install, upgrade, or uninstall when a reboot request is detected. Requires 'usePackageExitCodes' feature to be turned on. Will exit with either 350 or 1604. When it exits with 350, it means pending reboot discovered prior to running operation. When it exits with 1604, it means some work completed prior to reboot request being detected.
        choco feature disable --name="'failOnAutoUninstaller'"                   # Fail if automatic uninstaller fails.
        choco feature disable --name="'failOnInvalidOrMissingLicense'"           # Fail On Invalid Or Missing License - allows knowing when a license is expired or not applied to a machine.
        choco feature disable --name="'failOnStandardError'"                     # Fail if install provider writes to stderr. Not recommended for use.
        choco feature disable --name="'ignoreUnfoundPackagesOnUpgradeOutdated'"  # Ignore Unfound Packages On Upgrade Outdated - When checking outdated or upgrades, if a package is not found against sources specified, don't report the package at all.
        choco feature disable --name="'logEnvironmentValues'"                    # Log Environment Values - will log values of environment before and after install (could disclose sensitive data).
        choco feature disable --name="'logWithoutColor'"                         # Log without color - Do not show colorization in logging output.
        choco feature disable --name="'removePackageInformationOnUninstall'"     # Remove Stored Package Information On Uninstall - When a package is uninstalled, should the stored package information also be removed?
        choco feature disable --name="'skipPackageUpgradesWhenNotInstalled'"     # Skip Packages Not Installed During Upgrade - if a package is not installed, do not install it during the upgrade process.
        choco feature disable --name="'stopOnFirstPackageFailure'"               # Stop On First Package Failure - Stop running install, upgrade or uninstall on first package failure instead of continuing with others. As this will affect upgrade all, it is normally recommended to leave this off.
        choco feature disable --name="'useEnhancedExitCodes'"                    # Use Enhanced Exit Codes - Chocolatey is able to provide enhanced exit codes surrounding list, search, info, outdated and other commands that don't deal directly with package operations. To see enhanced exit codes and their meanings, please run `choco [cmdname] -?`. With this feature off, choco will exit with 0, 1, or -1  (matching previous behavior).
        choco feature disable --name="'useFipsCompliantChecksums'"               # Use FIPS Compliant Checksums - Ensure checksumming done by choco uses FIPS compliant algorithms. Not recommended unless required by FIPS Mode. Enabling on an existing installation could have unintended consequences related to upgrades/uninstalls.
        choco feature disable --name="'useRememberedArgumentsForUpgrades'"       # Use Remembered Arguments For Upgrades - When running upgrades, use arguments for upgrade that were used for installation ('remembered'). This is helpful when running upgrade for all packages. This is considered in preview and will be flipped to on by default in a future release.
        choco feature disable --name="'virusCheck'"                              # Virus Check - perform virus checking on downloaded files. Licensed versions only.
        choco feature enable  --name="'allowEmptyChecksumsSecure'"               # Allow packages to have empty/missing checksums for downloaded resources from secure locations (HTTPS).
        choco feature enable  --name="'autoUninstaller'"                         # Uninstall from programs and features without requiring an explicit uninstall script.
        choco feature enable  --name="'checksumFiles'"                           # Checksum files when pulled in from internet (based on package).
        choco feature enable  --name="'ignoreInvalidOptionsSwitches'"            # Ignore Invalid Options/Switches - If a switch or option is passed that is not recognized, should choco fail?
        choco feature enable  --name="'logValidationResultsOnWarnings'"          # Log validation results on warnings - Should the validation results be logged if there are warnings?
        choco feature enable  --name="'powershellHost'"                          # Use Chocolatey's built-in PowerShell host.
        choco feature enable  --name="'showDownloadProgress'"                    # Show Download Progress - Show download progress percentages in the CLI.
        choco feature enable  --name="'showNonElevatedWarnings'"                 # Show Non-Elevated Warnings - Display non-elevated warnings.
        choco feature enable  --name="'usePackageExitCodes'"                     # Use Package Exit Codes - Package scripts can provide exit codes. With this on, package exit codes will be what choco uses for exit when non-zero (this value can come from a dependency package). Chocolatey defines valid exit codes as 0, 1605, 1614, 1641, 3010. With this feature off, choco will exit with 0, 1, or -1 (matching previous behavior).
        choco feature enable  --name="'usePackageRepositoryOptimizations'"       # Use Package Repository Optimizations - Turn on optimizations for reducing bandwidth with repository queries during package install/upgrade/outdated operations. Should generally be left enabled, unless a repository needs to support older methods of query. When disabled, this makes queries similar to the way they were done in earlier versions of Chocolatey.
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
    #executeScript "dev_app.ps1";
    if (Test-PendingReboot) { Invoke-Reboot }
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

    $_message=$_message.Replace("- Start ","- End ")
    _logMessage -Message $_message -ForegroundColor Cyan
}
