[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

#region functions
#region helpers

$powershellCommandTemplate = (@'
<<FUNCTIONS>>

<<COMMANDS>>
'@)

function Clone-AzDevOpsRepository {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$Organisation
        , [Parameter(Mandatory)][string]$Project
        , [Parameter(Mandatory)][string]$RepositoryName
        , [Parameter(Mandatory)][string]$LocalRepositoryPath
    )

    $localGitPath = (Join-Path -Path (Join-Path -Path $LocalRepositoryPath -ChildPath $RepositoryName) -ChildPath '.git')
    $checkIfLocalRepositoryExists = (Test-Path -Path $localGitPath -PathType Container) # [Microsoft.PowerShell.Commands.TestPathType]::Container

    if (!$checkIfLocalRepositoryExists) {
        Invoke-CommandInPath -Path $LocalRepositoryPath -ScriptBlock { git clone "https://dev.azure.com/$($Organisation)/$($Project)/_git/$($RepositoryName)" }
        return
    }

    Write-Warning -Message "$RepositoryName already has already been cloned - Skipping"
} #end function

function ConvertFrom-Text {
    [cmdletbinding(DefaultParameterSetName = "File")]
    [alias("cft")]
    Param(
        [Parameter(Position = 0, Mandatory, HelpMessage = "Enter a regular expression pattern that uses named captures")]
        [ValidateScript( {
                if (($_.GetGroupNames() | Where-Object { $_ -notmatch "^\d{1}$" }).Count -ge 1) {
                    $True
                }
                else {
                    Throw "No group names found in your regular expression pattern."
                }
            })]
        [Alias("regex", "rx")]
        [regex]$Pattern,

        [Parameter(Position = 1, Mandatory, ParameterSetName = 'File')]
        [ValidateScript( { Test-Path $_ })]
        [alias("file")]
        [string]$Path,

        [Parameter(Position = 1, Mandatory, ValueFromPipeline, ParameterSetName = 'InputObject')]
        [ValidateNotNullOrEmpty()]
        [ValidateScript( {
                if ($_ -match "\S+") {
                    $true
                }
                else {
                    Throw "Cannot process an empty or null line of next."
                    $false
                }
            })]
        [string]$InputObject,

        [Parameter(HelpMessage = "Enter an optional typename for the object output.")]
        [ValidateNotNullOrEmpty()]
        [string]$TypeName,

        [Parameter(HelpMessage = "Do not use Write-Progress to report on processing. This can improve performance on large data sets.")]
        [switch]$NoProgress
    )

    Begin {
        $begin = Get-Date
        Write-Verbose "$((Get-Date).TimeOfDay) Starting $($MyInvocation.MyCommand)"
        Write-Verbose "$((Get-Date).TimeOfDay) Using pattern $($pattern.ToString())"

        if ($NoProgress) {
            Write-Verbose "$((Get-Date).TimeOfDay) Suppressing progress bar"
            $ProgressPreference = "SilentlyContinue"
        }
        #Get the defined capture names
        $names = $pattern.GetGroupNames() | Where-Object { $_ -notmatch "^\d+$" }
        Write-Verbose "$((Get-Date).TimeOfDay) Using names: $($names -join ',')"

        #define a hashtable of parameters to splat with Write-Progress
        $progParam = @{
            Activity = $MyInvocation.MyCommand
            Status   = "pre-processing"
        }
    } #begin

    Process {
        If ($PSCmdlet.ParameterSetName -eq 'File') {
            Write-Verbose "$((Get-Date).TimeOfDay) Processing $Path"
            Try {
                $progParam.CurrentOperation = "Getting content from $path"
                $progParam.Status = "Processing"
                Write-Progress @progParam
                $content = Get-Content -Path $path | Where-Object { $_ -match "\S+" }
                Write-Verbose "$((Get-Date).TimeOfDay) Will process $($content.count) entries"
            } #try
            Catch {
                Write-Warning "Could not get content from $path. $($_.Exception.Message)"
                Write-Verbose "$((Get-Date).TimeOfDay) Exiting function"
                #Bail out
                Return
            }
        } #if file parameter set
        else {
            Write-Verbose "$((Get-Date).TimeOfDay) processing input: $InputObject"
            $content = $InputObject
        }

        if ($content) {
            Write-Verbose "$((Get-Date).TimeOfDay) processing content"
            $content |  foreach-object -begin { $i = 0 } -process {
                #calculate percent complete
                $i++
                $pct = ($i / $content.count) * 100
                $progParam.PercentComplete = $pct
                $progParam.Status = "Processing matches"
                Write-Progress @progParam
                #process each line of the text file

                foreach ($match in $pattern.matches($_)) {
                    Write-Verbose "$((Get-Date).TimeOfDay) processing match"
                    $progParam.CurrentOperation = $match
                    Write-Progress @progParam

                    #get named matches and create a hash table for each one
                    $progParam.Status = "Creating objects"
                    Write-Verbose "$((Get-Date).TimeOfDay) creating objects"
                    $hash = [ordered]@{}
                    if ($TypeName) {
                        Write-Verbose "$((Get-Date).TimeOfDay) using a custom property name of $Typename"
                        $hash.Add("PSTypeName", $Typename)
                    }
                    foreach ($name in $names) {
                        $progParam.CurrentOperation = $name
                        Write-Progress @progParam
                        Write-Verbose "$((Get-Date).TimeOfDay) getting $name"
                        #initialize an ordered hash table
                        #add each name as a key to the hash table and the corresponding regex value
                        $hash.Add($name, $match.groups["$name"].value.Trim())
                    }
                    Write-Verbose "$((Get-Date).TimeOfDay) writing object to pipeline"
                    #write a custom object to the pipeline
                    [PSCustomObject]$hash
                }
            } #foreach line in the content
        } #if $content
    } #process

    End {
        Write-Verbose "$((Get-Date).TimeOfDay) Ending $($MyInvocation.MyCommand)"
        $end = Get-Date
        Write-Verbose "$((Get-Date).TimeOfDay) Total processing time $($end-$begin)"
    } #end

} #end function

function Create-SymbolicLink {
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter(Mandatory)][object[]]$SymbolicLinks
    )
    
    begin { }
    process {
        foreach ($symbolicLink in $SymbolicLinks) {
            [void](Remove-Item $symbolicLink.SymbolicLink -Force -ErrorAction SilentlyContinue)
            [void](New-Item -Force -ItemType SymbolicLink -Path $symbolicLink.SymbolicLink -Target $SymbolicLinks.SymbolicLinkTarget)
                
            if ($symbolicLink.Backup.IsPresent -and $symbolicLink.Backup.ToBool() -eq $true) {
                $backupTarget = "$($Target)-Backup-$($(New-Guid).Guid)"
                [void]($result = Copy-Item -Path $symbolicLink.SymbolicLinkTarget -Destination $backupTarget -Recurse -Force -PassThru)
                
                Write-Verbose -Message ($result | Out-String -Width 4095) -Verbose
            }
        }
}
    end { }
} #end function

function Get-Execution {
    $CallStack = Get-PSCallStack | Select-Object -Property *
    if (
         ($CallStack.Count -ne $null) -or
         (($CallStack.Command -ne '<ScriptBlock>') -and
         ($CallStack.Location -ne '<No file>') -and
         ($CallStack.ScriptName -ne $Null))
    ) {
        if ($CallStack.Count -eq 1) {
            $Output = $CallStack[0]
            $Output | Add-Member -MemberType NoteProperty -Name ScriptLocation -Value $((Split-Path $_.ScriptName)[0]) -PassThru
        }
        else {
            $Output = $CallStack[($CallStack.Count – 1)]
            $Output | Add-Member -MemberType NoteProperty -Name ScriptLocation -Value $((Split-Path $Output.ScriptName)[0]) -PassThru
        }
    }
    else {
        Write-Error -Message 'No callstack detected' -Category 'InvalidData'
    }
}

function Get-IndentationLevel {
    $level = 0
    $CallStack = Get-PSCallStack | Select-Object -Property *
    if (
         ($CallStack.Count -ne $null) -or
         (($CallStack.Command -ne '<ScriptBlock>') -and
         ($CallStack.Location -ne '<No file>') -and
         ($CallStack.ScriptName -ne $Null))
    ) {
        $level = $CallStack.Count – 1
    }
    else {
        Write-Error -Message 'No callstack detected' -Category 'InvalidData'
    }

    return $level
}

function Invoke-CommandInPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
        , [Parameter(Mandatory)][string]$Path
    )

    try {
        if (!(Test-Path -Path $Path)) {
            Write-Host -Object ("Creating folder '$($Path)'")
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction SilentlyContinue
        }

        Push-Location $Path
        & $ScriptBlock
    }
    finally {
        Pop-Location
    }
} #end function

function Log-Action {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
        , [Parameter()][string]$Title
        , [Parameter()][System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::Cyan
        , [Parameter()][switch]$NoHeader
    )
    
    begin {
        $maxMessageLength = 120
        
        [string[]]$message = @()
        $message = $title
        $writeHostMessage = { Write-Host -Object "$($message)" -ForegroundColor $ForegroundColor }

        [int]$level = if ((($level = ($(Get-IndentationLevel) - 3)) -le 0)) { 0 } else { 
            # Write-Host ($level) -ForegroundColor Cyan
            # Write-Host ($level - 1) -ForegroundColor Cyan
            $level - $(if ($level -le 2) { 1 } else { $level - 1 }) 
        }
        $padding = ' ' * $level
        $writeHostMessage = { Write-Host -Object "$(if($padding.Length -gt 0) { " -$($padding)" })$($message)" -ForegroundColor $ForegroundColor }

        if (!$NoHeader.IsPresent -or $NoHeader.ToBool() -eq $false) {
            $message += "`n$("*" * $maxMessageLength)"
            if (![string]::IsNullOrWhiteSpace($Title)) {
                $messageSpacingLength = ($maxMessageLength - 4 - $Title.Length) / 2
                $spacing = ' ' * $messageSpacingLength
                $message += "`n* $($spacing)$($Title)$($spacing) *"
                $message += "`n$("*" * $maxMessageLength)"
                Write-Host -Object $message -ForegroundColor $ForegroundColor
            }
            else {
                &$writeHostMessage
            }
        }
        else {
            &$writeHostMessage
        }
    }
    
    process {
        & $ScriptBlock
    }
    
    end {
        if (!$NoHeader.IsPresent -or $NoHeader.ToBool() -eq $false) {
            $message = "$("*" * $maxMessageLength)"
            Write-Host -Object $message -ForegroundColor $ForegroundColor
        }
    }
} #end function

#region Proxy Functions
<#
$WriteHostAutoIndent = $true
$WriteHostIndentSize = 1
function Write-Host {
    #.Synopsis
    #  Wraps Write-Host with support for indenting based on stack depth.
    #.Description
    #  This Write-Host cmdlet customizes output. You can indent the text using PadIndent, or indent based on stack depth using AutoIndent or by setting the global variable $WriteHostAutoIndent = $true.
    #
    #  You can specify the color of text by using the ForegroundColor parameter, and you can specify the background color by using the BackgroundColor parameter. The Separator parameter lets you specify a string to use to separate displayed objects. The particular result depends on the program that is hosting Windows PowerShell.
    #.Example
    #  write-host "no newline test >" -nonewline
    #  no newline test >C:\PS>
    #
    #  This command displays the input to the console, but because of the NoNewline parameter, the output is followed directly by the prompt.
    #.Example
    #  C:\PS> write-host (2,4,6,8,10,12) -Separator ", -> " -foregroundcolor DarkGreen -backgroundcolor white
    #  2, -> 4, -> 6, -> 8, -> 10, -> 12
    #
    #  This command displays the even numbers from 2 through 12. The Separator parameter is used to add the string , -> (comma, space, -, >, space).
    #.Example
    #  write-host "Red on white text." -ForegroundColor red -BackgroundColor white
    #  Red on white text.
    #
    #  This command displays the string "Red on white text." The text is red, as defined by the ForegroundColor parameter. The background is white, as defined by the BackgroundColor parameter.
    #.Example
    #  $WriteHostAutoIndent = $true
    #  C:\PS>&{
    #  >> Write-Host "Level 1"
    #  >> &{ Write-Host "Level 2" 
    #  >> &{ Write-Host "Level 3" } 
    #  >> Write-Host "Level 2"
    #  >> } }
    #    Level 1
    #      Level 2
    #        Level 3
    #      Level 2
    #
    #  This command displays how you can set WriteHostAutoIndent to control the output of a series of nested functions that use Write-Host for logging...
    #.Inputs
    #  System.Object
    #  You can pipe objects to be written to the host
    #.Outputs
    #  None
    #  Write-Host sends objects to the host. It does not return any objects. However, the host might display the objects that Write-Host sends to it.
    [CmdletBinding(HelpUri = 'http://go.microsoft.com/fwlink/?LinkID=113426', RemotingCapability = 'None')]
    param(
        # Objects to display in the console.
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [System.Object[]]
        ${Object},
    
        # Specifies that the content displayed in the console does not end with a newline character.
        [switch]
        ${NoNewline},
    
        # String to the output between objects displayed on the console.
        [System.Object]
        ${Separator},
    
        # Specifies the text color. There is no default.
        [System.ConsoleColor]
        ${ForegroundColor},
    
        # Specifies the background color. There is no default
        [System.ConsoleColor]
        ${BackgroundColor},
    
        # If set, Write-Host will indent based on the stack depth.  Defaults to the global preference variable $WriteHostAutoIndent (False).
        [Switch]
        $AutoIndent = $(if ($Global:WriteHostAutoIndent) { $Global:WriteHostAutoIndent } else { $False }),
       
        # Amount to indent (before auto indent).  Defaults to the global preference variable $WriteHostPadIndent (0).
        [Int]
        $PadIndent = $(if ($Global:WriteHostPadIndent) { $Global:WriteHostPadIndent } else { 0 }),
    
        # Number of spaces in each indent. Defaults to the global preference variable WriteHostIndentSize (2).
        [Int]
        $IndentSize = $(if ($Global:WriteHostIndentSize) { $Global:WriteHostIndentSize } else { 2 })
    )
    begin {
        function Get-ScopeDepth { 
            $depth = 0
            trap { continue } # trap outside the do-while scope
            do { $null = Get-Variable PID -Scope (++$depth) } while ($?)
            return $depth - 3
        }
       
        if ($PSBoundParameters.ContainsKey("AutoIndent")) { $null = $PSBoundParameters.Remove("AutoIndent") }
        if ($PSBoundParameters.ContainsKey("PadIndent")) { $null = $PSBoundParameters.Remove("PadIndent") }
        if ($PSBoundParameters.ContainsKey("IndentSize")) { $null = $PSBoundParameters.Remove("IndentSize") }
       
        $Indent = $PadIndent
       
        if ($AutoIndent) { $Indent += (Get-ScopeDepth) * $IndentSize }
        $Width = $Host.Ui.RawUI.BufferSize.Width - $Indent
    
        if ($PSBoundParameters.ContainsKey("Object")) {
            $OFS = $Separator
            $PSBoundParameters["Object"] = $(
                foreach ($line in $Object) {
                    $line = "$line".Trim("`n").Trim("`r")
                    for ($start = 0; $start -lt $line.Length; $start += $Width - 1) {
                        $Count = if ($Width -gt ($Line.Length - $start)) { $Line.Length - $start } else { $Width - 1 }
                   (" " * $Indent) + $line.SubString($start, $Count).Trim()
                    }
                }
            ) -join ${Separator}
        }
       
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer)) {
                $PSBoundParameters['OutBuffer'] = 1
            }
            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Write-Host', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = { & $wrappedCmd @PSBoundParameters }
            $steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
            $steppablePipeline.Begin($PSCmdlet)
        }
        catch {
            throw
        }
    }
    
    process {
        try {
            $OFS = $Separator
            $_ = $(
                foreach ($line in $_) {
                    $line = "$line".Trim("`n").Trim("`r")
                    for ($start = 0; $start -lt $line.Length; $start += $Width - 1) {
                        $Count = if ($Width -gt ($Line.Length - $start)) { $Line.Length - $start } else { $Width - 1 }
                   (" " * $Indent) + $line.SubString($start, $Count).Trim()
                    }
                }
            ) -join ${Separator}
            $steppablePipeline.Process($_)
        }
        catch {
            throw
        }
    }
    
    end {
        try {
            $steppablePipeline.End()
        }
        catch {
            throw
        }
    }
} #end function    
    
function Write-Verbose {
    #.Synopsis
    #  Wraps Write-Verbose with support for indenting based on stack depth. Writes text to the verbose message stream. 
    #.Description
    #  This Write-Verbose customizes output. You can indent the text using PadIndent, or indent based on stack depth using AutoIndent or by setting the global variable $WriteHostAutoIndent = $true.
    #.Example
    #  $VerbosePreference = "Continue"
    #  C:\PS>write-verbose "Testing Verbose"
    #  VERBOSE: Testing Verbose
    #
    #  Setting the VerbosePreference causes Write-Verbose output to be displayed in the console
    #.Example
    #  C:\PS> write-Verbose (2,4,6,8,10,12) -Separator ", -> "
    #  VERBOSE: 2, -> 4, -> 6, -> 8, -> 10, -> 12
    #
    #  This command displays the even numbers from 2 through 12. The Separator parameter is used to add the string , -> (comma, space, -, >, space).
    #.Example
    #  $WriteVerboseAutoIndent = $true
    #  C:\PS>&{
    #  >> Write-Verbose "Level 1"
    #  >> &{ Write-Verbose "Level 2" 
    #  >> &{ Write-Verbose "Level 3" } 
    #  >> Write-Verbose "Level 2"
    #  >> } }
    #  VERBOSE:   Level 1
    #  VERBOSE:     Level 2
    #  VERBOSE:       Level 3
    #  VERBOSE:     Level 2
    #
    #  This command displays how you can set WriteHostAutoIndent to control the output of a series of nested functions that use Write-Verbose for logging...
    #.Inputs
    #  System.Object
    #  You can pipe objects to be written to the verbose message stream. 
    #.Outputs
    #  None
    #  Write-Verbose sends objects to the verbose message stream. It does not return any objects. However, the host might display the objects if the $VerbosePreference
    [CmdletBinding(HelpUri = 'http://go.microsoft.com/fwlink/?LinkID=113429', RemotingCapability = 'None')]
    param(
        # Objects to display in the console.
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [System.Object[]]
        ${Message},
    
        # String to the output between objects displayed on the console.
        [System.Object]
        ${Separator},
    
        # If set, Write-Verbose will indent based on the stack depth.  Defaults to the global preference variable $WriteVerboseAutoIndent (False).
        [Switch]
        $AutoIndent = $(if ($Global:WriteVerboseAutoIndent) { $Global:WriteVerboseAutoIndent }else { $False }),
       
        # Amount to indent (before auto indent).  Defaults to the global preference variable $WriteVerbosePadIndent (0).
        [Int]
        $PadIndent = $(if ($Global:WriteVerbosePadIndent) { $Global:WriteVerbosePadIndent }else { 0 }),
    
        # Number of spaces in each indent. Defaults to the global preference variable WriteVerboseIndentSize (2).
        [Int]
        $IndentSize = $(if ($Global:WriteVerboseIndentSize) { $Global:WriteVerboseIndentSize }else { 2 })
    )
    begin {
        function Get-ScopeDepth { 
            $depth = 0
            trap { continue } # trap outside the do-while scope
            do { $null = Get-Variable PID -Scope (++$depth) } while ($?)
            return $depth - 3
        }
       
        if ($PSBoundParameters.ContainsKey("AutoIndent")) { $null = $PSBoundParameters.Remove("AutoIndent") }
        if ($PSBoundParameters.ContainsKey("PadIndent")) { $null = $PSBoundParameters.Remove("PadIndent") }
        if ($PSBoundParameters.ContainsKey("IndentSize")) { $null = $PSBoundParameters.Remove("IndentSize") }
        if ($PSBoundParameters.ContainsKey("Separator")) { $null = $PSBoundParameters.Remove("Separator") }
       
        $Indent = $PadIndent
       
        if ($AutoIndent) { $Indent += (Get-ScopeDepth) * $IndentSize }
        $Prefix = "VERBOSE: ".Length
        $Width = $Host.Ui.RawUI.BufferSize.Width - $Indent - $Prefix
    
       
        if ($PSBoundParameters.ContainsKey("Message")) {
            $OFS = $Separator
            $PSBoundParameters["Message"] = $(
                foreach ($line in $Message) {
                    $line = "$line".Trim("`n").Trim("`r")
                    for ($start = 0; $start -lt $line.Length; $start += $Width - 1) {
                        $Count = if ($Width -gt ($Line.Length - $start)) { $Line.Length - $start } else { $Width - 1 }
                        if ($start) { 
                      (" " * ($Indent + $Prefix)) + $line.SubString($start, $Count).Trim()
                        }
                        else {
                      (" " * $Indent) + $line.SubString($start, $Count).Trim()
                        }
                    }
                }
            ) -join "`n"
        }
       
        try {
            $outBuffer = $null
            if ($PSBoundParameters.TryGetValue('OutBuffer', [ref]$outBuffer)) {
                $PSBoundParameters['OutBuffer'] = 1
            }
            $wrappedCmd = $ExecutionContext.InvokeCommand.GetCommand('Write-Verbose', [System.Management.Automation.CommandTypes]::Cmdlet)
            $scriptCmd = { & $wrappedCmd @PSBoundParameters }
            $steppablePipeline = $scriptCmd.GetSteppablePipeline($myInvocation.CommandOrigin)
            $steppablePipeline.Begin($PSCmdlet)
        }
        catch {
            throw
        }
    }
    
    process {
        try {
            $OFS = $Separator
            $_ = $(
                foreach ($line in $_) {
                    $line = "$line".Trim("`n").Trim("`r")
                    for ($start = 0; $start -lt $line.Length; $start += $Width - 1) {
                        $Count = if ($Width -gt ($Line.Length - $start)) { $Line.Length - $start } else { $Width - 1 }
                        if ($start) { 
                      (" " * ($Indent + $Prefix)) + $line.SubString($start, $Count).Trim()
                        }
                        else {
                      (" " * $Indent) + $line.SubString($start, $Count).Trim()
                        }
                   
                    }
                }
            ) -join "`n"
            $steppablePipeline.Process($_)
        }
        catch {
            throw
        }
    }
    
    end {
        try {
            $steppablePipeline.End()
        }
        catch {
            throw
        }
    }
} #end  function
#>
#endregion Proxy Functions
#endregion Helpers
#endregion functions

#region Main Logic

# (optional) SQL Developer Bundle (https://www.red-gate.com/account )
choco install --yes dotnetdeveloperbundle # ANTS Performance Profiler Pro,ANTS Memory Profiler,.NET Reflector VSPro
choco install --yes sqltoolbelt --params "/products:'SQL Compare, SQL Data Compare, SQL Prompt, SQL Search, SQL Data Generator, SSMS Integration Pack '"

# UrlRewrite (https://www.iis.net/downloads/microsoft/url-rewrite )
choco install --yes urlrewrite

# IIS hosting bundle for .net (https://www.microsoft.com/net/permalink/dotnetcore-current-windows-runtime-bundle-installer )
# Run a separate PowerShell process because the script calls exit, so it will end the current PowerShell session.
#&powershell -NoProfile -ExecutionPolicy unrestricted -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; &([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing 'https://dot.net/v1/dotnet-install.ps1'))) <additional install-script args>"
Log-Action -Title 'IIS hosting bundle' -ForegroundColor Magenta -ScriptBlock { 
    $dotnetInstallerPath = (Join-Path -Path $env:TEMP -ChildPath 'dotnet-install.ps1')
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
$githubParams = [ordered]@{
    GitAndUnixToolsOnPath  = $null
    WindowsTerminal        = $null
    WindowsTerminalProfile = $null
    NoAutoCrlf             = $null
    DefaultBranchName      = 'main'
    Editor                 = 'VisualStudioCode'
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
$extensions = @('azure-devops', 'bicep')
Log-Action -Title $("Install Azure Addons/Extensions ('$("$($extensions -join '", "')")')") -ScriptBlock {
    $componentNamePattern = [regex]::new('(?<name>\b(?:\w+)(?:\-*)(?:\w+)\s*\b)')
    $versionPattern = '(?<version>\b(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)\b)'
    $updateAvailablePattern = '((?<updateAvailable>\b((\s+\*+)))|(?<updateAvailable>\b(?:(\s+\*+)?))\b)'

    #region get available extensions matching extension list 
    $functions=''
    $commands=@(
        "az extension list-available --output jsonc;"
    )
    $powershellCommand = $powershellCommandTemplate.Replace('<<FUNCTIONS>>', $functions).Replace('<<COMMANDS>>', $commands).Trim()
    $scriptBlock = ([scriptblock]::Create(("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"{0}`"" -f $powershellCommand)))

    $azureExtensions = Invoke-CommandInPath -Path (Get-Location) -ScriptBlock $scriptBlock | ConvertFrom-Json | Select-Object -unique name, summary, version, installed, experimental, preview
    if (($extensions -contains 'bicep')) {
        $bicepVersion=try {
            $functions=''
            $commands=@(
                "az bicep version;"
            )
            $powershellCommand = $powershellCommandTemplate.Replace('<<FUNCTIONS>>', $functions).Replace('<<COMMANDS>>', $commands).Trim()
            $scriptBlock = ([scriptblock]::Create(("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"{0}`"" -f $powershellCommand)))
            $result=Invoke-CommandInPath -Path (Get-Location) -ScriptBlock $scriptBlock
            $result | Where-Object { $_ } | ConvertFrom-Text -Pattern "$($versionPattern)" | Select-Object -ExpandProperty version
        } catch { '0.0.0' }

        if (!($azureExtensions|Where-Object name -match 'bicep')) { $azureExtensions += @{ name="bicep"; summary=$null; version=$bicepVersion; installed=$null -ne $bicep -and $bicepVersion -ne '0.0.0'; experimental=$false; preview=$false; } | Select-Object name, summary, version, installed, experimental, preview }
    }
    #endregion get available extensions matching extension list 
    $azureExtensions = $azureExtensions | Where-Object { $_.name -match ('({0})' -f $($extensions -join '|')) -and !$_.installed }

    #region install missing extensions
    $azCliInstallCommands = ($($extensions | Where-Object { $_ -match ('({0})' -f $($azureExtensions.name -join '|')) } | ForEach-Object { @{ name = $_; summary = $null; version = '0.0.0'; installed = $false; experimental = $false; preview = $false; } })) | Where-Object { !$_.installed } | Select-Object -ExpandProperty name | ForEach-Object {
        switch ($_) {
            'bicep' { "az $($_) install" }
            Default { "az extension add --name $($_)" }
        }
    }
    $azCliInstall=[scriptblock]::Create(($azCliInstallCommands -join "`n"))
    if ($azCliInstall) {
#         $functions = 
#         @'
# function ConvertFrom-Text {
# <<DEFINITION>>
# } #end function
# '@.Replace('<<DEFINITION>>', $((Get-Command -Name 'ConvertFrom-Text')).Definition)
        $functions=''
        $powershellCommand = $powershellCommandTemplate.Replace('<<FUNCTIONS>>', $functions).Replace('<<COMMANDS>>', $azCliInstall).Trim()
        $scriptBlock = ([scriptblock]::Create(("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"{0}`"" -f $powershellCommand)))
        $result=Invoke-CommandInPath -Path (Get-Location) -ScriptBlock $scriptBlock
    }
    #endregion install missing extensions

    #region upgrade az
    $functions=''
    $commands=@(
        @'
az --version;
'@
    )
    $powershellCommand = $powershellCommandTemplate.Replace('<<FUNCTIONS>>', $functions).Replace('<<COMMANDS>>', $commands).Trim()
    $scriptBlock = ([scriptblock]::Create(("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"{0}`"" -f $powershellCommand)))
    $result = Invoke-CommandInPath -Path (Get-Location) -ScriptBlock $scriptBlock | Where-Object { $_ -match '(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)' }

    $doCliUpgrade=(($updatesAvailable = ($result | Where-Object { $_ } | ConvertFrom-Text -Pattern "$($componentNamePattern)$($versionPattern)$($updateAvailablePattern)" | Where-Object { ![string]::IsNullOrWhiteSpace($_.updateAvailable) })).Count -gt 0)
    if ($doCliUpgrade) {
        Log-Action -Title 'The following Az Updates are afailable, and will be updated' -NoHeader -ScriptBlock { $updatesAvailable|ForEach-Object { "   $($_.name), v$($_.version)" } }

        $functions=''
        $commands=@(
            'az upgrade --yes;'
        )
        $powershellCommand = $powershellCommandTemplate.Replace('<<FUNCTIONS>>', $functions).Replace('<<COMMANDS>>', $commands).Trim()
        $scriptBlock = ([scriptblock]::Create(("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"{0}`"" -f $powershellCommand)))
        $result = Invoke-CommandInPath -Path (Get-Location) -ScriptBlock $scriptBlock
    }
    #endregion upgrade az
}

# Azure Artifacts Credential Provider (https://github.com/microsoft/artifacts-credprovider#setup )
Log-Action -Title 'Azure Artifacts Credential' -ForegroundColor Magenta -ScriptBlock { Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-artifacts-credprovider.ps1) } -AddNetfx" }

# Clone Evolve Repos
$organisation = 'FrFl-Development'
$project = 'Evolve'

Log-Action -Title 'Clone Repos' -ForegroundColor Magenta -ScriptBlock { 
    $developmentPaths = @{RepositoryRoot = 'C:\data\tfs\git'; SQLRoot = 'C:\data\sql'; }
    $developmentPaths.Keys | ForEach-Object { 
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
        Log-Action -Title "Cloning $($repositoryName)" -NoHeader -ScriptBlock { 
            $functions=''
            $commands=@(
                "$($utilityPath)\CloneAllRepos.ps1 -RepositoryNameStartsWith '$($repositoryName)';"
            )
            $powershellCommand = $powershellCommandTemplate.Replace('<<FUNCTIONS>>', $functions).Replace('<<COMMANDS>>', $commands).Trim()
            #$scriptBlock = ([scriptblock]::Create(("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"{0}`"" -f $powershellCommand)))
            $scriptBlock = ([scriptblock]::Create(("{0}" -f $powershellCommand)))
            Invoke-CommandInPath -Path $utilityPath -ScriptBlock $scriptBlock
        }
    }
}

Log-Action -Title 'Visual Studio Configuration' -ForegroundColor Green -ScriptBlock {
    "
    Run as admin
    Run Visual studio as administrator. Follow the answer linked to run as administrator, even when using the taskbar context menu MRU list -> https://stackoverflow.com/questions/42723232/vs2017-vs-2019-run-as-admin-from-taskbar 
    "
}

Log-Action -Title 'Nuget Config' -ForegroundColor Green -ScriptBlock {
    "
    In Tools->Nuget Package Manager->Package Manager Settings
    General -> Change the Default package management format to PackageReference
    Package Sources -> Add a source 'Evolve' directed to https://pkgs.dev.azure.com/FrFl-Development/_packaging/EvolvePackage/nuget/v3/index.json 
    Package Sources -> Add a source 'DevExpress' directed to the DevExpress NuGet feed URL from https://www.devexpress.com/ClientCenter/DownloadManager/  once you are logged into your DevExpress account
    "
}

Log-Action -Title 'Password Manager' -ForegroundColor Green -ScriptBlock {
    "
    Speak with service desk about access to password manager (currently '1Password')
    "
}

Log-Action -Title 'SQL Server' -ForegroundColor Green -ScriptBlock {
    "
    Ensure that Full-Text Index is installed, and the server collation MUST be set to SQL_Latin1_General_CP1_CI_AS as we have scripts that are collation sensitive that create temporary stored procs etc. (If SQL is already installed with the wrong server collationfollow these instructions https://docs.microsoft.com/en-us/sql/relational-databases/collations/set-or-change-the-server-collation  )
    
    Restore seed databases to your SQL instance from T:\Projects\Secure\Evolve\DatabaseSeeds.
    Add TEAM\Evolve user with dbo access to the Evolve....... DBs and DataRetention DB
    Add a linked server object for DEV-SQL-APP01 called DEV-SQL-APP01 and configure Server Options->RPC Out to 'true'. Set Security to `"Be made with the login's current security context`"
    Update your seeds to current by:-
    Legacy DB - Running publish on all databases from the database project, or if too far out of date, run project to database compares for all the projects and manually update from the models.
    "
}

Log-Action -Title 'Microservices' -ForegroundColor Green -ScriptBlock {
    "
    Run 'update-database' for each from Nuget Package Manager console.
    "
}

Log-Action -Title 'SQL Server' -ForegroundColor Green -ScriptBlock {
    "
    Once the databases are up-to-date, execute the spCreateFullTextIndex stored procedure as follows to ensure that the Search full-text index is created:
    EXEC EvolveApplication.SearchImport.spCreateFullTextIndex
    Create your user in the aspnet_users table and related tables to grant the correct permissions.
    SQL Prompt (optional)
    Get snippets from https://frfl.sharepoint.com/sites/ITTeam/Developement/Forms/AllItems.aspx?viewid=e84320c5-033b-4a12-a5eb-971adf5b1171&id=%2Fsites%2FITTeam%2FDevelopement%2FTools%2FSQL Prompt%2FSnippets 
    Get Styles from https://frfl.sharepoint.com/sites/ITTeam/Developement/Forms/AllItems.aspx?viewid=e84320c5-033b-4a12-a5eb-971adf5b1171&id=%2Fsites%2FITTeam%2FDevelopement%2FTools%2FSQL Prompt%2FStyles 
    "
}

Log-Action -Title 'Logging Distribution' -ForegroundColor Green -ScriptBlock {
    "
    In the main Evolve solution, build the FrFl.Service.LoggingDistributor project
    Manually copy the Build output to a suitable location (suggested C:\Program Files (x86)\First Response Finance Ltd\Evolve Logging Distributor )
    From a command prompt run FrFl.Service.LoggingDistributor.exe /i /user TEAM\Evolve /password ****** to install as a service
    "
}

Log-Action -Title 'Zeacom' -ForegroundColor Green -ScriptBlock {
    "
    Open an administrator command prompt
    Execute C:\Program Files (x86)\Telephony\CTI\Bin\ZCom.exe /regserver
    "
}

Log-Action -Title 'Solution Build & Run' -ForegroundColor Green -ScriptBlock {
    "
    Connect to the VPN if you arn't already
    In a admin command prompt execute C:\Data\TFS\Git\Evolve.Scripts\DevEnvConfig>DevEnvMigration.bat
    In a admin command prompt execute C:\Data\TFS\Git\Evolve.Scripts>CreateEventSources.bat
    In a admin command prompt execute C:\Data\TFS\Git\Evolve.Scripts>CreateEvolveMSMQ.cmd
    In a admin command prompt execute C:\Data\TFS\Git\Evolve.Scripts\Utility>BuildMicroservices.bat
    In a admin PowerShell prompt execute set-executionpolicy Unrestricted
    Open and run the legacy Evolve.sln solution
    Access https://l-evolve/admin 
    You are good to go
    "
}

Log-Action -Title 'Website setup' -ForegroundColor Green -ScriptBlock {
    "
    Setting up and running the website has a few additional steps. They are,

    Build the Evolve solution that hosts the public service api (Setting up portal api and vendor api)
    Build the Evolve.PublicWebsite.CMS solution
    Open a command prompt at the following directory: C:\Data\Tfs\Git\Evolve.PublicWebsite.CMS\Evolve.PublicWebsite.CMS
    Run `"npm i`" to restore the javascript packages for the project
    Run `"npm run build-prod`" to build the angular portion of the site (this may take a few mins to run)
    Build the Evolve.PublicWebsite.Spa solution
    Open a command prompt at the following directory: C:\Data\Tfs\Git\Evolve.PublicWebsite.SPA\Evolve.PublicWebsite.SPA
    Run `"npm i`" to restore the javascript packages for the project
    Run `"npm run build-prod`" to build the angular portion of the site (this may take a few mins to run)
    In a admin command prompt execute C:\Data\TFS\Git\Evolve\Scripts\DevEnvConfig>DevEnvMigration.bat
    Go to l-web  and you're done
    "
}

Log-Action -Title "Set Up SymbolicLinks to folders" -NoHeader -ScriptBlock {
    $symbolicLinks=@{ 
        'Editor Config' = @{ SymbolicLink=[string]"C:\Data\TFS\Git\.editorconfig"; SymbolicLinkTarget = [string]"C:\data\tfs\git\EditorConfig\.editorconfig"; Backup = [switch]$false; } 
        'Projects' = @{ SymbolicLink=[string]"C:\Projects"; SymbolicLinkTarget = [string]"C:\data\tfs\git"; Backup = [switch]$false; } 
    }

    $symbolicLinks.Keys|ForEach-Object { 
        $symbolicLink=$symbolicLinks["$($_)"] 
        Log-Action -Title "$($_)" -NoHeader -ScriptBlock {
            Create-SymbolicLink -SymbolicLinks $symbolicLink
        }        
    }
}

exit 0

#endregion Main Logic
