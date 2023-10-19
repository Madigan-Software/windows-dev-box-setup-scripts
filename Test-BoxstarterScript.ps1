
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
    $ScriptPath='Madigan-Software/windows-dev-box-setup-scripts/dev_app_desktop.NET.ps1'
)

#Import-Module Boxstarter
. { Invoke-Webrequest -useb https://boxstarter.org/bootstrapper.ps1 } | Invoke-Expression; Get-Boxstarter -Force
Install-BoxstarterPackage -PackageName $script -DisableReboots