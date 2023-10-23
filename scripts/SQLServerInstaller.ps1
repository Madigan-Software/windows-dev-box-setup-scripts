[CmdletBinding()]
param(
    [Parameter()][ValidateSet('2019','2022')][string]$Version='2022'
   ,[Parameter()][ValidateSet('dev')][string]$Sku='dev'
)

if (!$PSScriptRoot) {Set-Variable -Name PSScriptRoot -Value $MyInvocation.PSScriptRoot -Force }

[ValidateSet("sql-server")][string]$ProductName="sql-server"
[ValidateSet("sql-server-2019","sql-server-2022")][string]$PackageId="$($ProductName)-$($Version)"

function _IsMsSQLServerInstalled($serverInstance) {
    If(Test-Path 'HKLM:\Software\Microsoft\Microsoft SQL Server\Instance Names\SQL') { return $true }
    try {
        $server = New-Object Microsoft.SqlServer.Management.Smo.Server $serverInstance
        $ver = $server.Version.Major
        Write-Host " MsSQL Server version detected :" $ver
        return ($null -ne $ver)
    }
    Catch {return $false}
    
    return $false
}

$_message = "*** [$($MyInvocation.MyCommand.Name)] Installing SQL Server $($Sku) $($Version) - Start ***"

try {
    _logMessage -Message $_message -ForegroundColor Cyan

    $packageList=$(choco list "$($PackageId)" -y --accept-licence --limit-output --force)|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } }
    if ($null -eq $packageList) { $packageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $onLinePackageList=$(choco search "$($PackageId)" --yes --limit-output --exact|Where-Object { $_ -match ("$($PackageId)") }|ForEach-Object { [PSCustomObject]@{ Version=$($_ -split '\|'|Select-Object -Last 1) -as [System.Version];Id=$($_ -split '\|'|Select-Object -First 1) -as [string]; } })
    if ($null -eq $onLinePackageList) { $onLinePackageList = [PSCustomObject]@{ Version = -1 -as [System.Version];Id=$PackageId; } }
    $result=$(Compare-Object -ReferenceObject $packageList -DifferenceObject $onLinePackageList -Property Id,Version -PassThru|Select-Object -Property * -ErrorAction SilentlyContinue|Where-Object { $_.SideIndicator -match '^(\=\>)$' })
    $result
    # if (!($result -and $($result.SideIndicator|Where-Object { $_.SideIndicator -match '^(\=\>|\<\=)$' }))) {
    #     _logMessage -Message "$($PackageId): $(if ($null -ne $onLinePackageList.Version) { "Already installed" } else { "Does not exist please check chocolatey https://community.chocolatey.org/packages?q=id%3A$($PackageId)" })" -ForegroundColor Yellow
    #     return
    # }

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
    $commandArgs += '/NPEnabled=1'
    $commandArgs += '/TCPEnabled=1'
    $commandArgs += '/SQLSYSADMINACCOUNTS=""{0}"" ""{1}""' -f "$($env:USERDOMAIN)\$($env:USERNAME)","BUILTIN\Administrators"
    $commandArgs += '/SQLMINMEMORY=0'
    $commandArgs += '/SQLMAXMEMORY={0}' -f $((Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property capacity -Sum).sum /1mb /$((Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfCores -Sum).sum))
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

    $commandArgs += '/IGNOREPENDINGREBOOT'
    
    _logMessage -Message @"

========================================================================================================================
*                                      I n s t a l l i n g   S Q L   S e r v e r                                      *
========================================================================================================================
"@ -ForegroundColor Magenta
    if (!(_IsMsSQLServerInstalled '.')) {
        $packageParameters = $("'{0}'" -f $($commandArgs -join ' '))
        _logMessage -Message "PP: $($packageParameters)" -ForegroundColor DarkMagenta
    
        _chocolatey-InstallOrUpdate -PackageId "$($PackageId)" -PackageParameters $packageParameters
    }

    _logMessage -Message "Starting SQL Server services" -ForegroundColor Gray
    Get-Service -Name sql* -ErrorAction SilentlyContinue|Start-Service -PassThru

    _logMessage -Message @"

========================================================================================================================
*                  I n s t a l l i n g   S Q L   S e r v e r   -   M a n a g e m e n t   S t u d i o                  *
========================================================================================================================
"@ -ForegroundColor Magenta
    _chocolatey-InstallOrUpdate -PackageId "$($ProductName)-management-studio" -PackageParameters $packageParameters
    
    _logMessage -Message @"

========================================================================================================================
*                                               P o s t   I n s t a l l                                               *
========================================================================================================================
"@ -ForegroundColor Magenta
    function Using-Object
    {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)][AllowEmptyString()][AllowEmptyCollection()][AllowNull()][Object]$InputObject
           ,[Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
        )
    
        try {
            & $ScriptBlock
        } finally {
            if ($null -ne $InputObject -and $InputObject -is [System.IDisposable]) {
                $InputObject.Dispose()
            }
        }
    }

    $commandList = [System.Collections.ArrayList]::new()
    try {
        Using-Object ($sqlConnection = [System.Data.SqlClient.SqlConnection]::new("Data Source=$($env:COMPUTERNAME);Initial Catalog=master; Integrated Security=True;")) {
            $sqlConnection.Open()
            $content = $null #Get-Content $scriptFileNameGoesHere
            [void]($commandList.Add('SELECT [Server]=@@ServerName'))
            [void]($commandList.Add('
            USE [master]; 
            IF NOT EXISTS (SELECT 1 FROM master.sys.server_principals WHERE [name] = N''defaultuser'' and [type] IN (''C'',''E'', ''G'', ''K'', ''S'', ''U'')) AND EXISTS (SELECT 1 FROM master.sys.server_principals WHERE [name] = N''sa'' and [type] IN (''C'',''E'', ''G'', ''K'', ''S'', ''U'')) BEGIN 
                DECLARE @sql NVARCHAR(MAX) =''ALTER LOGIN [sa] WITH NAME = [defaultuser]; ''
                EXEC sp_executesql @sql
            END'))
            $content|Where-Object {$null -ne $_} | Foreach-Object {
                Write-Verbose -Message "[002.2]" -Verbose
                $command=$_
                if ($command.Trim() -eq "GO") { $commandList.Add($command); $command = "" } 
                else { $command =  $command + $_ +"`r`n" }
            }
            $commandList | ForEach-Object {
                $command=$_
                Using-Object ($sqlCommand = [System.Data.SqlClient.SqlCommand]::new($command, $sqlConnection)) {
                    $DataSet = [System.Data.DataSet]::new()
                    try {
                        if ($sqlCommand.CommandText -match 'SELECT ') {
                            $SqlAdapter = [System.Data.SqlClient.SqlDataAdapter]::new()
                            $SqlAdapter.SelectCommand = $sqlCommand
                            $result=$SqlAdapter.Fill($DataSet)
                            Write-Host -Object ("Result For $($command): $($result)") -ForegroundColor Cyan
                        } else {
                            $sqlCommand.ExecuteNonQuery()
                        }
                    } catch {
                        <#Do this if a terminating exception happens#>
                        Throw [Exception]::new("Error occurred executing Command: $(if ($sqlCommand.CommandText -match 'SELECT ') { 'ExecuteReader' } else { 'ExecuteNonQuery' })`n$($command|Out-String)", $_.Exception)
                    } finally{
                    }
                    $DataSet.Tables[0]
                }
            }
        }
    }
    catch {
        <#Do this if a terminating exception happens#>
        Throw [Exception]::new("Error occurred executing post database install commands`n$($commandList|Out-String)", $_.Exception)
    }

    _logMessage -Message @'
[TODO]:    Set SQL Server full text mode to rebuild'
'@ -ForegroundColor Yellow
} finally {
    #if (Test-PendingReboot) { Invoke-Reboot }

    #[Environment]::SetEnvironmentVariable("choco:sqlserver$($Version):SAPWD",$null,"User")
    #[Environment]::GetEnvironmentVariable("choco:sqlserver$($Version):SAPWD","User")

    $_message=$_message.Replace("- Start ","- End ")
    _logMessage -Message $_message -ForegroundColor Cyan
}
