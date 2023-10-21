
# tools we expect devs across many scenarios will want
if ($Host.Name -ne 'Visual Studio Code Host') {
    Invoke-ExternalCommand -Command { choco install -y vscode }
    Invoke-ExternalCommand -Command { choco install -y vscode-insiders }
}
Invoke-ExternalCommand -Command { choco install -y git --package-parameters="'/GitAndUnixToolsOnPath /WindowsTerminal'" }
Invoke-ExternalCommand -Command { choco install -y 7zip.install }
Invoke-ExternalCommand -Command { choco install -y sysinternals }
