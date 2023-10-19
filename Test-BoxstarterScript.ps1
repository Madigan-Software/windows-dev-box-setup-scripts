
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
    })]
    [string]
    $ScriptPath='Madigan-Software/windows-dev-box-setup-scripts/WORK_DeveloperMachineInstall.ps1'
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

Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://boxstarter.org/bootstrapper.ps1')); Get-Boxstarter -Force;
#. { Invoke-Webrequest -useb https://boxstarter.org/bootstrapper.ps1 } | Invoke-Expression; Get-Boxstarter -Force
Install-BoxstarterPackage -PackageName $script -DisableReboots