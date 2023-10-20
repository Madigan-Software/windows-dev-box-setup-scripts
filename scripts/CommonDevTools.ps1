
# tools we expect devs across many scenarios will want
if ($Host.Name -ne 'Visual Studio Code Host') {
    choco install -y vscode
    choco install -y vscode-insiders
}
choco install -y git --package-parameters="'/GitAndUnixToolsOnPath /WindowsTerminal'"
choco install -y python
choco install -y 7zip.install
choco install -y sysinternals
