Enable-WindowsOptionalFeature -Online -FeatureName containers -All
RefreshEnv
_chocolatey-InstallOrUpdate -PackageId docker-for-windows
_chocolatey-InstallOrUpdate -PackageId vscode-docker
