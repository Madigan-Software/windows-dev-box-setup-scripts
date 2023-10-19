[CmdletBinding()]
param(
    [Parameter()][ValidateSet('2019')][string]$Version='2022'
   ,[Parameter()][ValidateSet('dev')][string]$Sku='dev'
)

$_message = "*** [$($MyInvocation.MyCommand.Name)] Installing SQL Server $($Sku) $($Version) - Start ***"

try {
    _logMessage -Message $_message -ForegroundColor Cyan

    $sqlSAPwd=if (([Environment]::GetEnvironmentVariable("choco:sqlserver$($Version):SAPWD"))) { ([Environment]::GetEnvironmentVariable("choco:sqlserver$($Version):SAPWD","User")) } else { ([Net.NetworkCredential]::new('', (Read-Host -Prompt 'Enter SQL Servwr SA password' -AsSecureString)).Password) }
    @('User','Process')|ForEach-Object {
        [Environment]::SetEnvironmentVariable("choco:sqlserver$($Version):SAPWD",$sqlSAPwd,"$($_)")
    }

    &$RefreshEnvironment
    
    # SQL Server 2019 Developer (https://my.visualstudio.com/downloads ) (install collation SQL_Latin1_General_CP1_CI_AS)
    # SQL Management Studio 18.2 (https://docs.microsoft.com/en-gb/sql/ssms/download-sql-server-management-studio-ssms )
    Get-Service -Name MSSQLSERVER* -ErrorAction SilentlyContinue|Stop-Service -Force -PassThru
    $commandArgs =@()
    #$commandArgs += '/IACCEPTSQLSERVERLICENCETERMS'
    #$commandArgs += '/IsoPath="C:\Users\cyrilm\AppData\Local\Temp\chocolatey\chocolatey\sql-server-2019\15.0.2000.20210324\SQLServer{0}-x64-ENU-{1}.iso"' -f $Version,$Sku
    $commandArgs += '/ACTION=Install'
    $commandArgs += '/ENU'
    #$commandArgs += '/UpdateEnabled'
    #$commandArgs += '/UpdateSource=MU'
    # $commandArgs += '/NPEnabled=1'
    # $commandArgs += '/TCPEnabled=1'
    $commandArgs += '/SQLSYSADMINACCOUNTS="{0}" "{1}"' -f "$($env:USERDOMAIN)\$($env:USERNAME)","BUILTIN\Administrators"
    $commandArgs += '/SQLMINMEMORY=0'
    $commandArgs += '/SQLMAXMEMORY=2048'
    $commandArgs += '/SQLCOLLATION=SQL_Latin1_General_CP1_CI_AS'
    $commandArgs += '/SECURITYMODE=SQL'
    $commandArgs += '/SAPWD="{0}"' -f $sqlSAPwd
    $commandArgs += '/FEATURES=SQL,Tools'  # SQL (Sql Server DB engine, Replication, FullText, Data Quality Server) - Options: (SQLEngine,Replication,FullText,DQ,PolyBase,PolyBaseCore,PolyBaseJava,AdvancedAnalytics,SQL_INST_MR,SQL_INST_MPY,SQL_INST_JAVA); AS; RS; RS_SHP; RS_SHPWFE; DQC; IS (IS_Master,IS_Worker); MDS; SQL_SHARED_MPY; SQL_SHARED_MR; Tools (BC,Conn,DREPLAY_CTLR,DREPLAY_CLT,SNAC_SDK,LocalDB**)
    $commandArgs += '/INSTANCENAME=MSSQLSERVER' # or $env:choco:sqlserver$Version:INSTANCENAME=MSSQLSERVER
    # $commandArgs += '/SQLSVCACCOUNT={0}' -f "NT Service\MSSQL`$MSSQLSERVER"
    # $commandArgs += '/AGTSVCACCOUNT={0}' -f "NT Service\SQLAgent`$MSSQLSERVER"
    $commandArgs += '/AGTSVCSTARTUPTYPE=Manual'
    $commandArgs += '/BROWSERSVCSTARTUPTYPE=Automatic'
    
    $commandArgs += '/SQLBACKUPDIR="C:\data\sql\Backup"'

    $commandArgs += '/INSTALLSHAREDDIR="C:\data\sql\Data"'
    $commandArgs += '/INSTALLSQLDATADIR="C:\data\sql\Data"'
    
    $commandArgs += '/SQLTEMPDBDIR="C:\data\sql\Data"'
    $commandArgs += '/SQLTEMPDBLOGDIR="C:\data\sql\Log"'

    $commandArgs += '/SQLUSERDBDIR="C:\data\sql\Data"'
    $commandArgs += '/SQLUSERDBLOGDIR="C:\data\sql\Log"'

    choco install "sql-server-$($Version)" $chocoDefaultArgs --package-parameters ('"{0}"' -f ($commandArgs -join ' '))

    Get-Service -Name sql* -ErrorAction SilentlyContinue|Start-Service -PassThru

    if ((Get-Command -CommandType Function -Name executeChocolateyInstall* -ErrorAction SilentlyContinue)) { executeChocolateyInstall -Package 'sql-server-management-studio' } 

    _logMessage -Message @'
[TODO]:    Set SQL Server full text mode to rebuild'
           Rename sa => default user
           Enable the Named Pipes protocol in SQL Server Configuration Manager -> SQL Server Network Configuration -> Protocols for MSSQLSERVER
'@ -ForegroundColor Yellow
} finally {
    #if (Test-PendingReboot) { Invoke-Reboot }

    #[Environment]::SetEnvironmentVariable("choco:sqlserver$($Version):SAPWD",$null,"User")
    #[Environment]::GetEnvironmentVariable("choco:sqlserver$($Version):SAPWD","User")

    $_message=$_message.Replace("- Start ","- End ")
    _logMessage -Message $_message -ForegroundColor Cyan
}