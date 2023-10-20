# Description: Boxstarter Script
# Author: Microsoft
# Common dev settings for desktop app development

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
    
    #--- Tools ---
    #--- Installing VS and VS Code with Git
    # See this for install args: https://chocolatey.org/packages/visualstudio2022Community
    # https://docs.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-community
    # https://docs.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio#list-of-workload-ids-and-component-ids
    # visualstudio2022community
    # visualstudio2022professional
    # visualstudio2022enterprise
    $ProductName='visualstudio'
    $ProductVersion='2022'
    $PackageId="$($ProductName)$($ProductVersion)professional"
    $packageList=$(choco list "$($PackageId)" -y --accept-licence --limit-output --force)|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $packageList) { $packageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $onLinePackageList=choco search "$($PackageId)" --yes --limit-output --exact|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $onLinePackageList) { $onLinePackageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $result=Compare-Object -ReferenceObject $packageList -DifferenceObject $onLinePackageList -Property Id,Version -PassThru|Select-Object -Property * -ErrorAction SilentlyContinue
    if (!($result -and $($result.SideIndicator|Where-Object { $_ -match '^(\=\>|\<\=)$' }))) {
        _logMessage -Message "$($PackageId): $(if ($null -ne $onLinePackageList.Version) { "Already installed" } else { "Does not exist please check chocolatey https://community.chocolatey.org/packages?q=id%3A$($PackageId)" })" -ForegroundColor Yellow
    } else {
        choco install -y $PackageId --package-parameters="'--add Microsoft.VisualStudio.Component.Git' '--add Microsoft.Net.Component.4.7.1.TargetingPack' '-add Microsoft.Net.Component.4.7.1.SDK'"
    }

    Update-SessionEnvironment #refreshing env due to Git install
    
    #--- UWP Workload and installing Windows Template Studio ---
    $PackageId="$($ProductName)$($ProductVersion)-workload-azure"
    $packageList=$(choco list "$($PackageId)" -y --accept-licence --limit-output --force)|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $packageList) { $packageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $onLinePackageList=choco search "$($PackageId)" --yes --limit-output --exact|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $onLinePackageList) { $onLinePackageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $result=Compare-Object -ReferenceObject $packageList -DifferenceObject $onLinePackageList -Property Id,Version -PassThru|Select-Object -Property * -ErrorAction SilentlyContinue
    if (!($result -and $($result.SideIndicator|Where-Object { $_ -match '^(\=\>|\<\=)$' }))) {
        _logMessage -Message "$($PackageId): $(if ($null -ne $onLinePackageList.Version) { "Already installed" } else { "Does not exist please check chocolatey https://community.chocolatey.org/packages?q=id%3A$($PackageId)" })" -ForegroundColor Yellow
    } else {
        choco install -y $PackageId
    }

    $PackageId="$($ProductName)$($ProductVersion)-workload-netweb"
    $packageList=$(choco list "$($PackageId)" -y --accept-licence --limit-output --force)|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $packageList) { $packageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $onLinePackageList=choco search "$($PackageId)" --yes --limit-output --exact|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $onLinePackageList) { $onLinePackageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $result=Compare-Object -ReferenceObject $packageList -DifferenceObject $onLinePackageList -Property Id,Version -PassThru|Select-Object -Property * -ErrorAction SilentlyContinue
    if (!($result -and $($result.SideIndicator|Where-Object { $_ -match '^(\=\>|\<\=)$' }))) {
        _logMessage -Message "$($PackageId): $(if ($null -ne $onLinePackageList.Version) { "Already installed" } else { "Does not exist please check chocolatey https://community.chocolatey.org/packages?q=id%3A$($PackageId)" })" -ForegroundColor Yellow
    } else {
        choco install -y $PackageId
    }

    $PackageId="$($ProductName)$($ProductVersion)-workload-manageddesktop"
    $packageList=$(choco list "$($PackageId)" -y --accept-licence --limit-output --force)|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $packageList) { $packageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $onLinePackageList=choco search "$($PackageId)" --yes --limit-output --exact|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $onLinePackageList) { $onLinePackageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $result=Compare-Object -ReferenceObject $packageList -DifferenceObject $onLinePackageList -Property Id,Version -PassThru|Select-Object -Property * -ErrorAction SilentlyContinue
    if (!($result -and $($result.SideIndicator|Where-Object { $_ -match '^(\=\>|\<\=)$' }))) {
        _logMessage -Message "$($PackageId): $(if ($null -ne $onLinePackageList.Version) { "Already installed" } else { "Does not exist please check chocolatey https://community.chocolatey.org/packages?q=id%3A$($PackageId)" })" -ForegroundColor Yellow
    } else {
        choco install -y $PackageId
    }

    $PackageId="$($ProductName)$($ProductVersion)-workload-visualstudioextension"
    $packageList=$(choco list "$($PackageId)" -y --accept-licence --limit-output --force)|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $packageList) { $packageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $onLinePackageList=choco search "$($PackageId)" --yes --limit-output --exact|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $onLinePackageList) { $onLinePackageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $result=Compare-Object -ReferenceObject $packageList -DifferenceObject $onLinePackageList -Property Id,Version -PassThru|Select-Object -Property * -ErrorAction SilentlyContinue
    if (!($result -and $($result.SideIndicator|Where-Object { $_ -match '^(\=\>|\<\=)$' }))) {
        _logMessage -Message "$($PackageId): $(if ($null -ne $onLinePackageList.Version) { "Already installed" } else { "Does not exist please check chocolatey https://community.chocolatey.org/packages?q=id%3A$($PackageId)" })" -ForegroundColor Yellow
    } else {
        choco install -y $PackageId
    }

    $PackageId="$($ProductName)$($ProductVersion)-workload-data"
    $packageList=$(choco list "$($PackageId)" -y --accept-licence --limit-output --force)|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $packageList) { $packageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $onLinePackageList=choco search "$($PackageId)" --yes --limit-output --exact|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $onLinePackageList) { $onLinePackageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $result=Compare-Object -ReferenceObject $packageList -DifferenceObject $onLinePackageList -Property Id,Version -PassThru|Select-Object -Property * -ErrorAction SilentlyContinue
    if (!($result -and $($result.SideIndicator|Where-Object { $_ -match '^(\=\>|\<\=)$' }))) {
        _logMessage -Message "$($PackageId): $(if ($null -ne $onLinePackageList.Version) { "Already installed" } else { "Does not exist please check chocolatey https://community.chocolatey.org/packages?q=id%3A$($PackageId)" })" -ForegroundColor Yellow
    } else {
        choco install -y $PackageId
    }

    $PackageId="$($ProductName)$($ProductVersion)-workload-azurebuildtools"
    $packageList=$(choco list "$($PackageId)" -y --accept-licence --limit-output --force)|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $packageList) { $packageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $onLinePackageList=choco search "$($PackageId)" --yes --limit-output --exact|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $onLinePackageList) { $onLinePackageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $result=Compare-Object -ReferenceObject $packageList -DifferenceObject $onLinePackageList -Property Id,Version -PassThru|Select-Object -Property * -ErrorAction SilentlyContinue
    if (!($result -and $($result.SideIndicator|Where-Object { $_ -match '^(\=\>|\<\=)$' }))) {
        _logMessage -Message "$($PackageId): $(if ($null -ne $onLinePackageList.Version) { "Already installed" } else { "Does not exist please check chocolatey https://community.chocolatey.org/packages?q=id%3A$($PackageId)" })" -ForegroundColor Yellow
    } else {
        choco install -y $PackageId
    }
    
    #executeScript "WindowsTemplateStudio.ps1";
    #executeScript "GetUwpSamplesOffGithub.ps1";        
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
