# Description: Boxstarter Script
# Author: FRFL - Cyril Madigan
# Common dev settings for baseline machine setup

[CmdletBinding()]
param()

$invocation=$MyInvocation.PSObject.Copy()
$invocationName=if ($invocation.MyCommand.Name -eq 'executeScript') { $invocation.BoundParameters['script'] } else { $invocation.MyCommand.Name }

$headerMessageWidth=120
$headerMessageCenteredPosition=(($headerMessageWidth - $invocationName.Length -4) / 2)
$headerMessage = "`n$('=' * $headerMessageWidth)`n=$(' ' * $headerMessageCenteredPosition) {0} $(' ' * $headerMessageCenteredPosition)=`n$('=' * $headerMessageWidth)"
Write-Host -Object ($headerMessage -f $invocationName) -ForegroundColor Magenta

$debuggerAction = { if ( $boxstarterDebug ) { Break } } # kudos https://petri.com/conditional-breakpoints-in-powershell/
[void](Set-PSBreakpoint -Variable boxstarterDebug -Mode ReadWrite -Action $debuggerAction)

[bool]$boxstarterDebug=$env:boxstarterdebug -eq "true"

$IsDebuggerAttached = ((Test-Path Variable:PSDebugContext -ErrorAction SilentlyContinue) -eq $true)  # [System.Diagnostics.Debugger]::IsAttached
if (<#$pp['debug']#> $boxstarterDebug -and !$IsDebuggerAttached) {
    $runspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunSpace
    Write-Host "Debug was passed in as a parameter"
    Write-Host "To enter debugging write: Enter-PSHostProcess -Id $pid"
    Write-Host "Debug-Runspace -Id $($runspace.id)"
    Wait-Debugger
}
 
if ($boxstarterDebug -and $IsDebuggerAttached) {
    $params = @{ }
    if ($invocation.MyCommand.CommandType -eq 'ExternalScript' -and $null -ne $invocation.MyCommand.Source) {$params.Add('Script',  $invocation.MyCommand.Source)}
    foreach ($command in @(
        #"Invoke-Expression",
        "executeScript",
        "_chocolatey-InstallOrUpdate"
    )) {
        $params.Command = $command
        [void](Set-PSBreakpoint @params)
    }

    $params = @{ }
    foreach ($command in @(
        "choco",
        "Call-Chocolatey",
        #"Invoke-Expression",
        # "executeScript",
        # "_chocolatey-InstallOrUpdate",
        "Invoke-ExternalCommand",
        "Install-Prerequisite",
        "ExitWithDelay"
    )) {
        $params.Command = $command
        [void](Set-PSBreakpoint @params)
    }

    [void](Set-PSBreakpoint -Command "Invoke-ExternalCommand")
}
[void]($pp=if ((Get-Process -Id $pid).ProcessName -match 'choco') { Get-PackageParameters } else { ${ } })

if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

$IsVirtual = ((Get-WmiObject Win32_ComputerSystem).model).Contains("Virtual")
$IsWindowsSandbox = {
    return (
        $env:UserName -eq 'WDAGUtilityAccount' -and
        (Get-Service -Name cexecsvc).Status -eq 'Running' -and 
        $(&$IsVirtual)
    )
}

Function Set-PowerShellExitCode {
    <#
.SYNOPSIS
Sets the exit code for the PowerShell scripts.

.DESCRIPTION
Sets the exit code as an environment variable that is checked and used
as the exit code for the package at the end of the package script.

.NOTES
This tells PowerShell that it should prepare to shut down.

.INPUTS
None

.OUTPUTS
None

.PARAMETER ExitCode
The exit code to set.

.PARAMETER IgnoredArguments
Allows splatting with arguments that do not apply. Do not use directly.

.EXAMPLE
Set-PowerShellExitCode 3010
    #>
    param (
        [parameter(Mandatory = $false, Position = 0)][int] $exitCode,
        [parameter(ValueFromRemainingArguments = $true)][Object[]] $ignoredArguments
    )

    # Do not log function call - can mess things up

    if ($exitCode -eq $null -or $exitCode -eq '') {
        Write-Debug '$exitCode was passed null'
        return
    }

    try {
        $host.SetShouldExit($exitCode);
    }
    catch {
        Write-Warning "Unable to set host exit code"
    }

    $LASTEXITCODE = $exitCode
    $env:ChocolateyExitCode = $exitCode;
}

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

    if ($null -eq $(Get-Command -Name choco)) {
        throw "Chocolatey is not installed, unable to continue"
        Exit 1
    }

    [array]$remotePackageList=$(choco search $PackageId --limit-output --exact|Select-Object @{ E={ ($_.Split('|')|Select-Object -First 1) -as [string] }; N='Id'; }, @{ E={ ($_.Split('|')|Select-Object -Last 1) -as [System.Version] }; N='Version'; })
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
            if (!($? -or $LASTEXITCODE -eq 0)) { throw "Error occurred upgrading $($packageId) - $($LASTEXITCODE)" }
        }
    }; 
    Write-Host -Object ("$($packageId) v$($packageList|Select-Object -ExpandProperty Version)") -ForegroundColor Cyan;
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

$_message = "*** [$($invocation.MyCommand.Name)] Setting up developer workstation - Start ***"
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
    # Get the base URI path from the ScriptToCall value
    <#$Boxstarter['ScriptToCall']=@"
Import-Module (Join-Path -Path "C:\ProgramData\Boxstarter" -ChildPath BoxStarter.Chocolatey\Boxstarter.Chocolatey.psd1) -global -DisableNameChecking; Invoke-ChocolateyBoxstarter -bootstrapPackage 'C:\data\tfs\git\Sandbox\windows-dev-box-setup-scripts\WORK_DeveloperMachineInstall.ps1' -DisableReboots -StopOnPackageFailure
"@#>
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

        #$helperUri.Scheme -match '^file'; 
        $helperUri = $helperUri.AbsolutePath
        $helperUri = $helperUri.Substring(0, $helperUri.LastIndexOf("/"))
        $helperUri = $helperUri -replace '(\\|/)$',''
        $helperUri += ""
    } else {
        $helperUri = (Join-Path -Path $PSScriptRoot -ChildPath '')
    }
    $helperUri = $helperUri -replace '(\\|/)$',''
    
    function executeScript {
        Param ([string]$script)
        #$scriptInvovcation = (Get-Variable -Name MyInvocation -Scope Script).Value
        #$scriptFullPath = $scriptInvovcation.MyCommand.Path # full path of script
        #$scriptPath = Split-Path -Path $scriptFullPath      # pwth of script
        #$scriptName = $scriptInvovcation.MyCommand.Name     #scriptName
        #$invocationPath = $scriptInvovcation.InvocationName # invocation relative to `$PWD

        _logMessage -Message "executing $helperUri/$script ..."
        $expression=((new-object net.webclient).DownloadString("$helperUri/$script"))
        Invoke-Expression $expression
        if (Test-PendingReboot) { Invoke-Reboot }
    }
    
    #--- Setting up Windows OS ---
    executeScript "scripts/WinGetInstaller.ps1"
    if (!$IsWindowsSandbox) {
        executeScript "scripts/WindowsOptionalFeatures.ps1"
    }

    #--- Setting up Common Folders ---
    $rootPath="C:\data\"
    @(
        "\sql\Backup\"
        ,"\sql\Data\"
        ,"\sql\Log\"
        ,"\sql\Snapshots\"
        ,"\tfs\git\"
        ,"\tfs\git\Sandbox"
    ) | Foreach-Object {
        _logMessage -Message "Creating folder $($rootPath)$($_) ..."
        [void](New-Item -Path "$($rootPath)$($_)" -Type Directory -Force -ErrorAction SilentlyContinue)
    }
    
    #--- Setting up SQL Server ---
    executeScript "scripts/SQLServerInstaller.ps1"

    #--- Setting up base DevEnvironment ---
    executeScript "dev_app.ps1";

    executeScript "__post_installationtasks.ps1";            
} catch {
    # Write-ChocolateyFailure $($invocation.MyCommand.Name) $($_.Exception.ToString())
    $formatstring = "{0} : {1}`n{2}`n" +
                    "    + CategoryInfo          : {3}`n" +
                    "    + FullyQualifiedErrorId : {4}`n"
    $fields = $_.InvocationInfo.MyCommand.Name,$_.ErrorDetails.Message,$_.InvocationInfo.PositionMessage,$_.CategoryInfo.ToString(), $_.FullyQualifiedErrorId
    Write-Host -Object ($formatstring -f $fields) -ForegroundColor Red -BackgroundColor Black
    
    Set-PowerShellExitCode -exitCode -1
    throw (New-Object System.Exception(($formatstring -f $fields), $_.Exception))
} finally {
    #--- reenabling critial items ---
    Enable-UAC
    Enable-MicrosoftUpdate

    $_message=$_message.Replace("- Start ","- End ")
    _logMessage -Message $_message -ForegroundColor Cyan
}

# Install-WindowsUpdate -AcceptEula #-GetUpdatesFromMS
$webLauncherUrl="https://dev.azure.com/FrFl-Development/Evolve"
Start-Process microsoft-edge:$webLauncherUrl
