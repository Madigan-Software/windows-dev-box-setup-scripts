if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

_chocolatey-InstallOrUpdate -PackageId "Microsoft-Hyper-V-All" -Source "'windowsFeatures'"
