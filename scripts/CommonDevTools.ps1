
# tools we expect devs across many scenarios will want
if ($Host.Name -ne 'Visual Studio Code Host') {
    _chocolatey-InstallOrUpdate -PackageId vscode
    _chocolatey-InstallOrUpdate -PackageId vscode-insiders
}
_chocolatey-InstallOrUpdate -PackageId git -PackageParameters "'/GitAndUnixToolsOnPath /WindowsTerminal'"
_chocolatey-InstallOrUpdate -PackageId 7zip.install
_chocolatey-InstallOrUpdate -PackageId sysinternals
