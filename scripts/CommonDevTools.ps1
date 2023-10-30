$headerMessageWidth=120
$headerMessage="$('=' * $headerMessageWidth)`n=$(' ' * (($headerMessageWidth - $("{0}".Length))/2)) {0} $(' ' * (($headerMessageWidth - $("{0}".Length))/2))=`n$('=' * $headerMessageWidth)`n"
Write-Host -Object ($headerMessage -f $MyInvocation.MyCommand.Name) -ForegroundColor Magenta

if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

# tools we expect devs across many scenarios will want
_chocolatey-InstallOrUpdate -PackageId powershell-core
if ($Host.Name -ne 'Visual Studio Code Host') {
    _chocolatey-InstallOrUpdate -PackageId vscode
    _chocolatey-InstallOrUpdate -PackageId vscode-insiders
}
$gitParams=[ordered]@{
    GitAndUnixToolsOnPath=$null
    WindowsTerminal=$null
    WindowsTerminalProfile=$null
    NoAutoCrlf=$null
    DefaultBranchName='main'
    Editor='VisualStudioCode'
}
_chocolatey-InstallOrUpdate -PackageId git -PackageParameters "'$(($gitParams.Keys|ForEach-Object { "/$($_)$(if ($null -ne $gitParams[$_]) { ":$($gitParams[$_])" })" }) -join ' ')'" 
_chocolatey-InstallOrUpdate -PackageId 7zip.install
_chocolatey-InstallOrUpdate -PackageId sysinternals
