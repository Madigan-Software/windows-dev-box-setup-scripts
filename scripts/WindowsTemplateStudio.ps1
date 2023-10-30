$invocationName=if ($MyInvocation.MyCommand.Name -eq 'executeScript') { $MyInvocation.BoundParameters['script'] } else { $MyInvocation.MyCommand.Name }
$headerMessageWidth=120
$headerMessageCenteredPosition=(($headerMessageWidth - $invocationName.Length -4) / 2)
$headerMessage = "`n$('=' * $headerMessageWidth)`n=$(' ' * $headerMessageCenteredPosition) {0} $(' ' * $headerMessageCenteredPosition)=`n$('=' * $headerMessageWidth)"
Write-Host -Object ($headerMessage -f $invocationName) -ForegroundColor Magenta

if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

Invoke-ExternalCommand -Command { 
    # installing Windows Template Studio VSIX
    Write-Host "Installing Windows Template Studio" -ForegroundColor "Yellow"

    $requestUri = "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery";
    $requestBody = '{"flags":"262","filters":[{"criteria":[{"filterType":"10","value":"windows template studio"}],"sortBy":"0","sortOrder":"2","pageSize":"25","pageNumber":"1"}]}';
    $requestHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]";
    $requestHeaders.Add('Accept','application/json; api-version=3.2-preview.1');
    $requestHeaders.Add('Content-Type','application/json; charset=utf-8');

    $results = Invoke-WebRequest -Uri $requestUri -Method POST -Headers $requestHeaders -Body $requestBody -UseBasicParsing;

    $jsonResults = $results.Content | ConvertFrom-Json;
    $wtsResults = $jsonResults.results[0].extensions | Where-Object {$_.extensionName -eq "WindowsTemplateStudio"} ;
    $wtsFileUrl = $wtsResults.versions[0].files | Where-Object {$_.assetType -eq "Microsoft.Templates.2022.vsix"};

    $wtsVsix = [System.IO.Path]::GetFileName($wtsFileUrl.source);
    $wtsFullPath = [System.IO.Path]::Combine((Resolve-Path $env:USERPROFILE).path, $wtsVsix);

    try {
        Invoke-WebRequest -Uri $wtsFileUrl.source -OutFile $wtsFullPath;
        
        $vsixInstallerFile = Get-Childitem -Include vsixinstaller.exe -Recurse -Path "C:\Program Files\Microsoft Visual Studio\2022\";
        $wtsArgList = "/quiet `"$wtsFullPath`"";
        
        $vsixInstallerResult = Start-Process -FilePath $vsixInstallerFile.FullName -ArgumentList $wtsArgList -Wait -PassThru;
    }
    finally {
        <#Do this after the try block regardless of whether an exception occurred or not#>
        Remove-Item $wtsFullPath
    }
}