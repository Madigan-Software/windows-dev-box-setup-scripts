if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

# Using vscode as a default IDE
_chocolatey-InstallOrUpdate -PackageId vscode
_chocolatey-InstallOrUpdate -PackageId git -PackageParameters "'/GitAndUnixToolsOnPath /WindowsTerminal'"
