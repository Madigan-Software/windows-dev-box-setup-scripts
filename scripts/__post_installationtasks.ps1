[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

function Log-Action {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
       ,[Parameter()][string]$Title
       ,[Parameter()][System.ConsoleColor]$ForegroundColor=[System.ConsoleColor]::Cyan
    )
    
    begin {
        $maxMessageLength = 120
        [string[]]$message= @()
        $message += "`n$("*" * $maxMessageLength)"
        if (![string]::IsNullOrWhiteSpace($Title)) {
            $messageSpacingLength=($maxMessageLength - 4 -$Title.Length) / 2
            $spacing = ' ' * $messageSpacingLength
            $message += "`n* $($spacing)$($Title)$($spacing) *"
            $message += "`n$("*" * $maxMessageLength)"
        }
        Write-Host -Object $message -ForegroundColor $ForegroundColor
    }
    
    process {
        & $ScriptBlock
    }
    
    end {
        $message = "$("*" * $maxMessageLength)"
        Write-Host -Object $message -ForegroundColor $ForegroundColor
    }
}

function Invoke-CommandInPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
       ,[Parameter(Mandatory)][string]$Path
    )

    try{
        if (!(Test-Path -Path $Path)) {
            Write-Host -Object ("Creating folder '$($Path)'")
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction SilentlyContinue
        }

        Push-Location $Path
        & $ScriptBlock
    } finally {
        Pop-Location
    }
}

function Clone-AzDevOpsRepository {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Organisation
       ,[Parameter(Mandatory)][string]$Project
       ,[Parameter(Mandatory)][string]$RepositoryName
       ,[Parameter(Mandatory)][string]$LocalRepositoryPath
    )

    $localGitPath = (Join-Path -Path (Join-Path -Path $LocalRepositoryPath -ChildPath $RepositoryName) -ChildPath '.git')
    $checkIfLocalRepositoryExists=(Test-Path -Path $localGitPath -PathType Container) # [Microsoft.PowerShell.Commands.TestPathType]::Container

    if (!$checkIfLocalRepositoryExists) {
        Invoke-CommandInPath -Path $LocalRepositoryPath -ScriptBlock { git clone "https://dev.azure.com/$($Organisation)/$($Project)/_git/$($RepositoryName)" }
        return
    }

    Write-Warning -Message "$RepositoryName already has already been cloned - Skipping"
}

# (optional) SQL Developer Bundle (https://www.red-gate.com/account )
choco install --yes dotnetdeveloperbundle # ANTS Performance Profiler Pro,ANTS Memory Profiler,.NET Reflector VSPro
choco install --yes sqltoolbelt --params "/products:'SQL Compare, SQL Data Compare, SQL Prompt, SQL Search, SQL Data Generator, SSMS Integration Pack '"

# UrlRewrite (https://www.iis.net/downloads/microsoft/url-rewrite )
choco install --yes urlrewrite

# IIS hosting bundle for .net (https://www.microsoft.com/net/permalink/dotnetcore-current-windows-runtime-bundle-installer )
# Run a separate PowerShell process because the script calls exit, so it will end the current PowerShell session.
#&powershell -NoProfile -ExecutionPolicy unrestricted -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; &([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing 'https://dot.net/v1/dotnet-install.ps1'))) <additional install-script args>"
Log-Action -Title 'IIS hosting bundle' -ForegroundColor Magenta -ScriptBlock { 
    $dotnetInstallerPath=(Join-Path -Path $env:TEMP -ChildPath 'dotnet-install.ps1')
    try {
        #Invoke-WebRequest 'https://dot.net/v1/dotnet-install.ps1' -Proxy $env:HTTP_PROXY -ProxyUseDefaultCredentials -OutFile $dotnetInstallerPath;
        Invoke-WebRequest 'https://dot.net/v1/dotnet-install.ps1' -OutFile $dotnetInstallerPath;

        #& ./$dotnetInstallerPath -InstallDir '~/.dotnet' -Version 'latest' -Runtime 'dotnet' -Channel LTS -ProxyAddress $env:HTTP_PROXY -ProxyUseDefaultCredentials;
        & $dotnetInstallerPath -Version 'latest' -Channel LTS;
    }
    finally {
        Remove-item -Path $dotnetInstallerPath -Force -ErrorAction SilentlyContinue
    }
}

# WIX (https://github.com/wixtoolset/wix3/releases/tag/wix3111rtm )
choco install --yes wixtoolset
#choco install --yes wix35
# WIX Extension(https://marketplace.visualstudio.com/items?itemName=WixToolset.WixToolsetVisualStudio2022Extension )
#  https://wixtoolset.gallerycdn.vsassets.io/extensions/wixtoolset/wixtoolsetvisualstudio2022extension/1.0.0.22/1668223914320/Votive2022.vsix

# MVC 4 (https://www.microsoft.com/en-gb/download/details.aspx?id=30683 )
choco install --yes aspnetmvc4.install

<#
# GIT (https://git-scm.com/download/win )
/GitOnlyOnPath - Puts gitinstall\cmd on path. This is also done by default if no package parameters are set.
/GitAndUnixToolsOnPath - Puts gitinstall\bin on path. This setting will override /GitOnlyOnPath.
/NoAutoCrlf - Ensure 'Checkout as is, commit as is'. This setting only affects new installs, it will not override an existing .gitconfig.
/WindowsTerminal - Makes vim use the regular Windows terminal instead of MinTTY terminal.
/NoShellIntegration - Disables open GUI and open shell integration ( "Git GUI Here" and "Git Bash Here" entries in context menus).
/NoGuiHereIntegration - Disables open GUI shell integration ( "Git GUI Here" entry in context menus).
/NoShellHereIntegration - Disables open git bash shell integration ( "Git Bash Here" entry in context menus).
/NoCredentialManager - Disable Git Credential Manager by adding $Env:GCM_VALIDATE='false' user environment variable.
/NoGitLfs - Disable Git LFS installation.
/SChannel - Configure Git to use the Windows native SSL/TLS implementation (SChannel) instead of OpenSSL. This aligns Git HTTPS behavior with other Windows applications and system components and increases manageability in enterprise environments.
/NoOpenSSH - Git will not install its own OpenSSH (and related) binaries but use them as found on the PATH.
/WindowsTerminalProfile - Add a Git Bash Profile to Windows Terminal.
/Symlinks - Enable symbolic links (requires the SeCreateSymbolicLink permission). Existing repositories are unaffected by this setting.
/DefaultBranchName:default_branch_name - Define the default branch name.
/Editor:Nano|VIM|Notepad++|VisualStudioCode|VisualStudioCodeInsiders|SublimeText|Atom|VSCodium|Notepad|Wordpad|Custom editor path - Default editor used by Git. The selected editor needs to be available on the machine (unless it is part of git for windows) for this to work.

/PseudoConsoleSupport - Enable experimental support for pseudo consoles. Allows running native console programs like Node or Python in a Git Bash window without using winpty, but it still has known bugs.
/FSMonitor - Enable experimental built-in file system monitor. Automatically run a built-in file system watcher, to speed up common operations such as git status, git add, git commit, etc in worktrees containing many files.
#>
$githubParams=[ordered]@{
    GitAndUnixToolsOnPath=$null
    WindowsTerminal=$null
    WindowsTerminalProfile=$null
    NoAutoCrlf=$null
    DefaultBranchName='main'
    Editor='VisualStudioCode'
}
choco install --yes git --params "'$(($githubParams.Keys|ForEach-Object { "/$($_)$(if ($null -ne $githubParams[$_]) { ":$($githubParams[$_])" })" }) -join ' ')'" 

# Node (https://nodejs.org/en )
#choco install --yes nodejs
choco install --yes nodejs-lts

# Postman (https://www.postman.com/downloads )
choco install --yes postman
#choco install --yes postman-cli

# (optional screen capture tool) Share X (https://getsharex.com )
choco install --yes sharex

# Azure CLI (https://aka.ms/installazurecliwindows )
choco install --yes azure-cli
$extensions=@('azure-devops','bicep')
$azureExtensions=Invoke-CommandInPath -Path (Get-Location) -ScriptBlock ([scriptblock]::Create("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"az extension list-available --output jsonc`""))|ConvertFrom-Json|Select-Object -unique name,summary,version,installed,experimental,preview
$azureExtensions=$azureExtensions|Where-Object { $_.name -match ('({0})' -f $extensions -join '|') -and !$_.installed}

$azCliInstallCommands = ($azureExtensions, $($extensions|Where-Object{ $_ -notmatch ('({0})' -f $($azureExtensions.name -join '|'))}|ForEach-Object { @{ name=$_; summary=$null; version='0.0.0'; installed=$false; experimental=$false;preview=$false; } }))|Where-Object {!$_.installed}|Select-Object -ExpandProperty name|ForEach-Object {
    switch ($_) {
        'bicep' { "az $($_) install" }
        Default { "az extension add --name $($_)"}
    }
}
Invoke-CommandInPath -Path (Get-Location) -ScriptBlock ([scriptblock]::Create(($azCliInstallCommands -join "`n")))

#az upgrade

# Azure Artifacts Credential Provider (https://github.com/microsoft/artifacts-credprovider#setup )
Log-Action -Title 'Azure Artifacts Credential' -ForegroundColor Magenta -ScriptBlock { Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-artifacts-credprovider.ps1) } -AddNetfx" }

# Clone Evolve Repos
$organisation='FrFl-Development'
$project='Evolve'

Log-Action -Title 'Clone Repos' -ForegroundColor Magenta -ScriptBlock { 
    $developmentPaths = @{RepositoryRoot='C:\data\tfs\git';SQLRoot='C:\data\sql';}
    $developmentPaths.Keys|ForEach-Object { 
        if (!(Test-Path -Path $developmentPaths[$_])) {
            Write-Host -Object ("Creating folder '$($developmentPaths[$_])'")
            New-Item -ItemType Directory -Path $developmentPaths[$_] -Force -ErrorAction SilentlyContinue
        }
    }

    #[System.Management.Automation.CommandTypes]::Application
    if (!(Get-Command -Name 'git' -CommandType Application)) { Write-Warning -Message "'Git' is not currently installed, opening browser https://git-scm.com/download/win"; Start-Process 'https://git-scm.com/download/win'; return; }

    $repositoryName = 'Evolve.Scripts'
    Clone-AzDevOpsRepository -Organisation $organisation -Project $project -RepositoryName $repositoryName -LocalRepositoryPath $developmentPaths['RepositoryRoot']

    $utilityPath = (Join-Path -Path (Join-Path -Path $developmentPaths['RepositoryRoot'] -ChildPath $repositoryName) -ChildPath 'Utility' -Resolve)
    $repositoryNames = @(
        # Core
         'EditorConfig'
        ,'Evolve'
        ,'FRFL'
        # Optional
        ,'TfsBuildExtensions'
        # ,'Assist'
        # ,'Callisto'
        # ,'CallRouting'
        # ,'Convex'
        # ,'Database'
        # ,'Eclipse'
        # ,'Lazarus'
        # ,'Observability'
        # ,'Playground'
        # ,'Polaris'
        # ,'ReHeat'
        # ,'Root'
        # ,'TFS.Settings'    
    ) | ForEach-Object {
        $repositoryName = $_
        Log-Action -Title "Cloning $($repositoryName)" -ScriptBlock { 
            $scriptBlock = [scriptblock]::Create("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"$($utilityPath)\CloneAllRepos.ps1 -RepositoryNameStartsWith '$($repositoryName)'`"")
            Invoke-CommandInPath -Path $utilityPath -ScriptBlock $scriptBlock
        }
    }
}
<#
Visual Studio Configuration
Run as admin
Run Visual studio as administrator. Follow the answer linked to run as administrator, even when using the taskbar context menu MRU list -> https://stackoverflow.com/questions/42723232/vs2017-vs-2019-run-as-admin-from-taskbar 

Nuget Config

In Tools->Nuget Package Manager->Package Manager Settings
General -> Change the Default package management format to PackageReference
Package Sources -> Add a source 'Evolve' directed to https://pkgs.dev.azure.com/FrFl-Development/_packaging/EvolvePackage/nuget/v3/index.json 
Package Sources -> Add a source 'DevExpress' directed to the DevExpress NuGet feed URL from https://www.devexpress.com/ClientCenter/DownloadManager/  once you are logged into your DevExpress account
Password Manager
Speak with service desk about access to password manager (currently '1Password')

SQL Server
Ensure that Full-Text Index is installed, and the server collation MUST be set to SQL_Latin1_General_CP1_CI_AS as we have scripts that are collation sensitive that create temporary stored procs etc. (If SQL is already installed with the wrong server collationfollow these instructions https://docs.microsoft.com/en-us/sql/relational-databases/collations/set-or-change-the-server-collation  )

Restore seed databases to your SQL instance from T:\Projects\Secure\Evolve\DatabaseSeeds.
Add TEAM\Evolve user with dbo access to the Evolve....... DBs and DataRetention DB
Add a linked server object for DEV-SQL-APP01 called DEV-SQL-APP01 and configure Server Options->RPC Out to 'true'. Set Security to "Be made with the login's current security context"
Update your seeds to current by:-
Legacy DB - Running publish on all databases from the database project, or if too far out of date, run project to database compares for all the projects and manually update from the models.
Microservices - Run 'update-database' for each from Nuget Package Manager console.
Once the databases are up-to-date, execute the spCreateFullTextIndex stored procedure as follows to ensure that the Search full-text index is created:
EXEC EvolveApplication.SearchImport.spCreateFullTextIndex
Create your user in the aspnet_users table and related tables to grant the correct permissions.
SQL Prompt (optional)
Get snippets from https://frfl.sharepoint.com/sites/ITTeam/Developement/Forms/AllItems.aspx?viewid=e84320c5-033b-4a12-a5eb-971adf5b1171&id=%2Fsites%2FITTeam%2FDevelopement%2FTools%2FSQL Prompt%2FSnippets 
Get Styles from https://frfl.sharepoint.com/sites/ITTeam/Developement/Forms/AllItems.aspx?viewid=e84320c5-033b-4a12-a5eb-971adf5b1171&id=%2Fsites%2FITTeam%2FDevelopement%2FTools%2FSQL Prompt%2FStyles 
Logging Distribution
In the main Evolve solution, build the FrFl.Service.LoggingDistributor project
Manually copy the Build output to a suitable location (suggested C:\Program Files (x86)\First Response Finance Ltd\Evolve Logging Distributor )
From a command prompt run FrFl.Service.LoggingDistributor.exe /i /user TEAM\Evolve /password ****** to install as a service
Zeacom
Open an administrator command prompt
Execute C:\Program Files (x86)\Telephony\CTI\Bin\ZCom.exe /regserver
Solution Build & Run
Connect to the VPN if you arn't already
In a admin command prompt execute C:\Data\TFS\Git\Evolve.Scripts\DevEnvConfig>DevEnvMigration.bat
In a admin command prompt execute C:\Data\TFS\Git\Evolve.Scripts>CreateEventSources.bat
In a admin command prompt execute C:\Data\TFS\Git\Evolve.Scripts>CreateEvolveMSMQ.cmd
In a admin command prompt execute C:\Data\TFS\Git\Evolve.Scripts\Utility>BuildMicroservices.bat
In a admin PowerShell prompt execute set-executionpolicy Unrestricted
Open and run the legacy Evolve.sln solution
Access https://l-evolve/admin 
You are good to go
Website setup
Setting up and running the website has a few additional steps. They are,

Build the Evolve solution that hosts the public service api (Setting up portal api and vendor api)
Build the Evolve.PublicWebsite.CMS solution
Open a command prompt at the following directory: C:\Data\Tfs\Git\Evolve.PublicWebsite.CMS\Evolve.PublicWebsite.CMS
Run "npm i" to restore the javascript packages for the project
Run "npm run build-prod" to build the angular portion of the site (this may take a few mins to run)
Build the Evolve.PublicWebsite.Spa solution
Open a command prompt at the following directory: C:\Data\Tfs\Git\Evolve.PublicWebsite.SPA\Evolve.PublicWebsite.SPA
Run "npm i" to restore the javascript packages for the project
Run "npm run build-prod" to build the angular portion of the site (this may take a few mins to run)
In a admin command prompt execute C:\Data\TFS\Git\Evolve\Scripts\DevEnvConfig>DevEnvMigration.bat
Go to l-web  and you're done
#>