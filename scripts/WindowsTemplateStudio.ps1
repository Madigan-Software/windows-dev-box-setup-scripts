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
    $wtsResults = $jsonResults.results[0].extensions | where {$_.extensionName -eq "WindowsTemplateStudio"} ;
    $wtsFileUrl = $wtsResults.versions[0].files | where {$_.assetType -eq "Microsoft.Templates.2022.vsix"};

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