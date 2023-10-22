# Description: Boxstarter Script
# Author: Microsoft
# Common dev settings for machine learning using Windows and Linux native tools

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

    # Need to check both of these cases for errors as they represent different items
    # - $?: did the powershell script block throw an error
    # - $lastexitcode: did a windows command executed by the script block end in error
    if ((-not $?) -or ($lastexitcode -ne 0)) {
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

try {
    Disable-MicrosoftUpdate
    Disable-UAC

    # Get the base URI path from the ScriptToCall value
    $bstrappackage = "-bootstrapPackage"
    if (![string]::IsNullOrEmpty($Boxstarter['ScriptToCall'])) {
        $helperUri = $Boxstarter['ScriptToCall']
        $strpos = $helperUri.IndexOf($bstrappackage)
        $helperUri = $helperUri.Substring($strpos + $bstrappackage.Length)
        $helperUri = $helperUri.TrimStart("'", " ")
        $helperUri = $helperUri.TrimEnd("'", " ")

        _logMessage -Message "uri is $($helperUri|Out-String)" -ForegroundColor Gray
        [void]([System.Uri]::TryCreate($helperUri, [System.UriKind]::RelativeOrAbsolute, [ref]$helperUri));
        _logMessage -Message "uri is $($helperUri|Out-String)" -ForegroundColor Gray
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
    executeScript "SystemConfiguration.ps1";
    executeScript "FileExplorerSettings.ps1";
    executeScript "RemoveDefaultApps.ps1";
    executeScript "CommonDevTools.ps1";
    executeScript "HyperV.ps1";
    executeScript "WSL.ps1";
    
    write-host "Installing tools inside the WSL distro..."
    Ubuntu1804 run apt install python2.7 python-pip -y 
    Ubuntu1804 run apt install python-numpy python-scipy -y
    Ubuntu1804 run pip install pandas
    write-host "Finished installing tools inside the WSL distro"        
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
