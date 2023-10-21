Enable-WindowsOptionalFeature -Online -FeatureName containers -All
RefreshEnv
Invoke-ExternalCommand -Command { choco install -y docker-for-windows }
Invoke-ExternalCommand -Command { choco install -y vscode-docker }
