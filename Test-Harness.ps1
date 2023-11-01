using namespace System.Management.Automation

# $script:publicToExport.function += @('Add-ConsoleEnvVarPath')
# $script:publicToExport.alias += @('Add-EnvVar')

# Description: Boxstarter Script
# Author: Cyril Madigan
# Common TestHarness for debugging scripts
# Last Updated: 2023-10-19
#
# Install boxstarter:
# 	. { iwr -useb http://boxstarter.org/bootstrapper.ps1 } | iex; get-boxstarter -Force
#
# You might need to set: Set-ExecutionPolicy RemoteSigned
#
# Run this boxstarter by calling the following from an **elevated** command-prompt:
# 	start http://boxstarter.org/package/nr/url?<URL-TO-RAW-GIST>
# OR
# 	Install-BoxstarterPackage -PackageName <URL-TO-RAW-GIST> -DisableReboots
#
# Learn more: http://boxstarter.org/Learn/WebLauncher
[CmdletBinding()]
param (
    [Parameter()][ValidateScript({
        Test-Path -Path $_ 
    })][string]$ScriptPath='Madigan-Software/windows-dev-box-setup-scripts/WORK_DeveloperMachineInstall.ps1'
    ,[Parameter()][switch]$DebugEnabled
    ,[Parameter()][switch]$Force
    )
        
function PSCommandPath() { return $PSCommandPath }
function ScriptName() { return $MyInvocation.ScriptName }
function MyCommandName() { return $MyInvocation.MyCommand.Name }
function MyCommandDefinition() {
    # Begin of MyCommandDefinition()
    # Note: ouput of this script shows the contents of this function, not the execution result
    return $MyInvocation.MyCommand.Definition
    # End of MyCommandDefinition()
}
function MyInvocationPSCommandPath() { return $MyInvocation.PSCommandPath }

Write-Host ""
Write-Host "PSVersion: $($PSVersionTable.PSVersion)"
Write-Host ""
Write-Host "`$PSCommandPath:"
Write-Host " *   Direct: $PSCommandPath"
Write-Host " * Function: $(PSCommandPath)"
Write-Host ""
<#
Write-Host "`$MyInvocation.ScriptName:"
Write-Host " *   Direct: $($MyInvocation.ScriptName)"
Write-Host " * Function: $(ScriptName)"
Write-Host ""
Write-Host "`$MyInvocation.MyCommand.Name:"
Write-Host " *   Direct: $($MyInvocation.MyCommand.Name)"
Write-Host " * Function: $(MyCommandName)"
Write-Host ""
Write-Host "`$MyInvocation.MyCommand.Definition:"
Write-Host " *   Direct: $($MyInvocation.MyCommand.Definition)"
Write-Host " * Function: $(MyCommandDefinition)"
Write-Host ""
Write-Host "`$MyInvocation.PSCommandPath:"
Write-Host " *   Direct: $($MyInvocation.PSCommandPath)"
Write-Host " * Function: $(MyInvocationPSCommandPath)"
Write-Host ""
#>

Import-Module Boxstarter.Common
#C:\ProgramData\Boxstarter\BoxstarterShell.ps1
#$Boxstarter
$Boxstarter.RebootOk=$true
#Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://boxstarter.org/bootstrapper.ps1')); Get-Boxstarter -Force;
#. { Invoke-Webrequest -useb https://boxstarter.org/bootstrapper.ps1 } | Invoke-Expression; Get-Boxstarter -Force
# Start-Process http://boxstarter.org/package/url?https://raw.githubusercontent.com/Madigan-Software/windows-dev-box-setup-scripts/FRFL/WORK_DeveloperMachineInstall.ps1
#[void]($result=Install-BoxstarterPackage -PackageName $ScriptPath -KeepWindowOpen -StopOnPackageFailure -Credential $(Get-Credential -Message "Credential for boxstarter" -UserName $env:USERNAME))
try {
    if ($DebugEnabled.IsPresent -and $DebugEnabled.ToBool()) { [System.Environment]::SetEnvironmentVariable('BoxstarterDebug', $DebugEnabled.ToBool().ToString(), [System.EnvironmentVariableTarget]::Process); }
    $env:BoxstarterDebug = [System.Environment]::GetEnvironmentVariable('BoxstarterDebug', [System.EnvironmentVariableTarget]::Process);

    try {
        <##>
        if (!(Test-Path $ScriptPath)) {
            Write-Warning "Invalid Path: $ScriptPath"
            if (! $Force ) {
                $exception = [IO.FileNotFoundException]::new(
                    <# message : #> "Filepath: ['$($ScriptPath)'] - does not exist",
                    <# fileName: #> $ScriptPath
                )
                $errorRecord = [ErrorRecord]::new(
                    <# exception    : #> $exception,
                    <# errorId      : #> 'MissingTarget',
                    <# errorCategory: #> [ErrorCategory]::InvalidArgument,
                    <# targetObject : #> $null)
        
                $PSCmdlet.WriteError( <# errorRecord: #> $errorRecord )
                # $PSCmdlet.ThrowTerminatingError($errorRecord)
                throw $exception
            }
        }
        <##>
        [void]($result=Install-BoxstarterPackage -PackageName $ScriptPath -DisableReboots -KeepWindowOpen -DisableRestart -StopOnPackageFailure)
    } catch [System.IO.FileNotFoundException] {
        $ScriptPath=Join-Path -Path "$($PSScriptRoot)" -ChildPath "WORK_DeveloperMachineInstall.ps1"
        [void]($result=Install-BoxstarterPackage -PackageName $ScriptPath -DisableReboots -KeepWindowOpen -DisableRestart -StopOnPackageFailure)
    }
}
finally {
    [System.Environment]::SetEnvironmentVariable('BoxstarterDebug', $null, [System.EnvironmentVariableTarget]::Process);
    [void](Remove-Item -Path env:boxstarterdebug -Force -ErrorAction SilentlyContinue)
}
#"Result: $($result|Out-String)" 
Exit $result

#Import-Module (Join-Path -Path "C:\ProgramData\Boxstarter" -ChildPath BoxStarter.Chocolatey\Boxstarter.Chocolatey.psd1) -global -DisableNameChecking; Invoke-ChocolateyBoxstarter -bootstrapPackage '$PSScriptRoot\WORK_DeveloperMachineInstall.ps1' -StopOnPackageFailure