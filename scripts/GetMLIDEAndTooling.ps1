# Using vscode as a default IDE
Invoke-ExternalCommand -Command { choco install -y vscode }
Invoke-ExternalCommand -Command { choco install -y git --package-parameters="'/GitAndUnixToolsOnPath /WindowsTerminal'" }
