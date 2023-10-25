if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

# tools we expect devs across many scenarios will want
_chocolatey-InstallOrUpdate -PackageId powershell-core
if ($Host.Name -ne 'Visual Studio Code Host') {
    _chocolatey-InstallOrUpdate -PackageId vscode
    _chocolatey-InstallOrUpdate -PackageId vscode-insiders
}
$githubParams=[ordered]@{
    GitAndUnixToolsOnPath=$null
    WindowsTerminal=$null
    WindowsTerminalProfile=$null
    NoAutoCrlf=$null
    DefaultBranchName='main'
    Editor='VisualStudioCode'
}
_chocolatey-InstallOrUpdate -PackageId git -PackageParameters "'$(($githubParams.Keys|ForEach-Object { "/$($_)$(if ($null -ne $githubParams[$_]) { ":$($githubParams[$_])" })" }) -join ' ')'" 
_chocolatey-InstallOrUpdate -PackageId 7zip.install
_chocolatey-InstallOrUpdate -PackageId sysinternals
