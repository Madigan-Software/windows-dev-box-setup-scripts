<#
Install optional windows features
    .NET Framework 3.5 (includes .NET 2.0 and 3.0) - all features
    .NET Framework 4.8 Advanced Services - all features
    Internet Information Services
        Web Management Tools
            IIS 6 Management Compatibility
                IIS Metabase and IIS 6 configuration compatibility
            IIS Mangement Console
            IIS Management Scripts and Tools
            IIS Management Services
        World Wide Web Services - all features
    Microsoft Message Queue (MSMQ) Server - all features
    Windows Powershell 2.0 - all features
    Windows Process Activation Service - all features
#>
$_message = "*** [$($MyInvocation.MyCommand.Name)] Setting up Windows Features - Start ***"

try {
    _logMessage -Message $_message -ForegroundColor Gray

    #--- Windows Subsystems/Features ---
    $AutoUpdatePath="HKLM:SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    $DoSvcPath="HKLM:\SYSTEM\CurrentControlSet\Services\DoSvc"

    #region features

    $oldUseWUServer=(Get-ItemProperty $AutoUpdatePath -Name UseWUServer).UseWUServer
    $oldStart=(Get-ItemProperty -Path $DoSvcPath -Name Start).Start
    try {
        Set-ItemProperty -Path $AutoUpdatePath -Name UseWUServer -Value 0
        Set-ItemProperty -Path $DoSvcPath -Name Start -Type DWord -Value 3 -Force

        Get-Service -DisplayName 'Background Intelligent Transfer Service','Windows Update','Windows Update medic service','Delivery Optimization' -ErrorAction SilentlyContinue|Where-Object { $_.StartType -ne 'Deiabled' -and $_.Status -eq 'Running' }|Restart-Service -PassThru
        Get-Service -DisplayName 'Background Intelligent Transfer Service','Windows Update','Windows Update medic service','Delivery Optimization' -ErrorAction SilentlyContinue|Where-Object { $_.StartType -ne 'Deiabled' -and $_.Status -ne 'Running' }|Start-Service -PassThru

        $oldDoSvcStatus=(Get-Service -DisplayName "Delivery Optimization").Status
        $oldWuausrvStatus=(Get-Service -Name wuauserv).Status
        if ($oldWuausrvStatus -eq ([System.ServiceProcess.ServiceControllerStatus]::Running)) {
            Get-Service -Name wuauserv|Where-Object Status -eq ([System.ServiceProcess.ServiceControllerStatus]::Running)|
                Stop-Service -PassThru -Force
        }
        Get-Service -DisplayName 'Background Intelligent Transfer Service','Windows Update','Windows Update medic service','Delivery Optimization' -ErrorAction SilentlyContinue|Where-Object { $_.StartType -ne 'Deiabled' -and $_.Status -ne 'Running' }|Start-Service -PassThru

        $features=@()

        # IISFeatures
        $features+=@('IIS-ApplicationDevelopment','IIS-ApplicationInit','IIS-ASP','IIS-ASPNET','IIS-ASPNET45','IIS-BasicAuthentication','IIS-CertProvider','IIS-CGI','IIS-ClientCertificateMappingAuthentication','IIS-CommonHttpFeatures','IIS-CustomLogging','IIS-DefaultDocument','IIS-DigestAuthentication','IIS-DirectoryBrowsing','IIS-HealthAndDiagnostics','IIS-HttpCompressionDynamic','IIS-HttpCompressionStatic','IIS-HttpErrors','IIS-HttpLogging','IIS-HttpRedirect','IIS-HttpTracing','IIS-IIS6ManagementCompatibility','IIS-IISCertificateMappingAuthentication','IIS-IPSecurity','IIS-ISAPIExtensions','IIS-ISAPIFilter','IIS-LoggingLibraries','IIS-ManagementConsole','IIS-ManagementScriptingTools','IIS-ManagementService','IIS-Metabase','IIS-NetFxExtensibility','IIS-NetFxExtensibility45','IIS-ODBCLogging','IIS-Performance','IIS-RequestFiltering','IIS-RequestMonitor','IIS-Security','IIS-ServerSideIncludes','IIS-StaticContent','IIS-URLAuthorization','IIS-WebDAV','IIS-WebServer','IIS-WebServerManagementTools','IIS-WebServerRole','IIS-WebSockets','IIS-WindowsAuthentication')

        # MSMQFeatures
        $features+=@('MSMQ-Container','MSMQ-Server')

        # dotnet Framework 3.5
        $features+=@('WCF-HTTP-Activation','WCF-NonHTTP-Activation')

        # dotnet Framework 4.8
        $features+=@('WCF-Services45','WCF-HTTP-Activation45','WCF-MSMQ-Activation45','WCF-Pipe-Activation45','WCF-TCP-Activation45','WCF-TCP-PortSharing45')

        $features=$features|
            ForEach-Object { 
                Get-WindowsOptionalFeature -Online -FeatureName $_|Where-Object State -ne Enabled 
            }
        if ($features) {
            $message=("Adding  windows features $($features.DisplayName -join ", ")")
            if ($null -ne (get-command -name 'Write-BoxstarterMessage' -ErrorAction SilentlyContinue)) { Write-BoxstarterMessage -message $message -color Yellow } else { Write-Host -Object $message -ForegroundColor DarkYellow }
            $features|
                Enable-WindowsOptionalFeature -Online -NoRestart -All
        }
    
        # Enable RSAT
        $message=("Adding  windows features Rsat.ActiveDirectory.DS-LDS.Tools")
        if ($null -ne (get-command -name 'Write-BoxstarterMessage' -ErrorAction SilentlyContinue)) { Write-BoxstarterMessage -message $message -color Yellow } else { Write-Host -Object $message -ForegroundColor DarkYellow }
        Get-WindowsCapability -Name Rsat.ActiveDirectory.DS-LDS.Tools* -Online |
            Where-Object State -ne [Microsoft.Dism.Commands.PackageFeatureState]::Installed |
                Add-WindowsCapability -Online
    } finally {
        Set-ItemProperty -Path $AutoUpdatePath -Name UseWUServer -Value $oldUseWUServer
        if ($oldWuausrvStatus -ne ((Get-Service -Name wuauserv).Status)) { Get-Service -Name wuauserv|Start-Service -PassThru }

        Set-ItemProperty -Path $DoSvcPath -Name Start -Type DWord -Value $oldStart -Force
        if ($oldWuausrvStatus -ne ((Get-Service -DisplayName 'Delivery Optimization').Status)) { Get-Service -DisplayName 'Delivery Optimization'| Start-Service -PassThru }
    }

    #endregion features 
}
finally {
    $_message=$_message.Replace("- Start ","- End ")
    _logMessage -Message $_message -ForegroundColor Cyan
}
