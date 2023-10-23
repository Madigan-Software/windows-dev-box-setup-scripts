if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

Enable-WindowsOptionalFeature -Online -FeatureName containers -All
RefreshEnv
_chocolatey-InstallOrUpdate -PackageId docker-for-windows
_chocolatey-InstallOrUpdate -PackageId vscode-docker
