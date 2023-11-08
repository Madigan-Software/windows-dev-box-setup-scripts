$invocationName=if ($MyInvocation.MyCommand.Name -eq 'executeScript') { $MyInvocation.BoundParameters['script'] } else { $MyInvocation.MyCommand.Name }
$headerMessageWidth=120
$headerMessageCenteredPosition=(($headerMessageWidth - $invocationName.Length -4) / 2)
$headerMessage = "`n$('=' * $headerMessageWidth)`n=$(' ' * $headerMessageCenteredPosition) {0} $(' ' * $headerMessageCenteredPosition)=`n$('=' * $headerMessageWidth)"
Write-Host -Object ($headerMessage -f $invocationName) -ForegroundColor Magenta

#[Diagnostics.CodeAnalysis.SuppressMessage("PSUseApprovedVerbs", Scope="function", Target="Using-Object", Justification="Wrapping dispose pattern")]

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

$script:vs2022RootPath = 'C:\Program Files\Microsoft Visual Studio\2022\Professional'
$script:vs2022ExePath = "$($vs2022RootPath)\Common7\IDE\devenv.exe"

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
            if ($symbolicLink.Backup.IsPresent -and $symbolicLink.Backup.ToBool() -eq $true) {
                $backupTarget = "$($Target)-Backup-$($(New-Guid).Guid)"
                [void]($result = Copy-Item -Path $symbolicLink.SymbolicLinkTarget -Destination $backupTarget -Recurse -Confirm:$false -Force -PassThru)
                
                Write-Verbose -Message ($result | Out-String -Width 4095) -Verbose
            }

            [void](Remove-Item $symbolicLink.SymbolicLink -Force -Confirm:$false -Recurse -ErrorAction SilentlyContinue)
            [void](New-Item -Force -ItemType SymbolicLink -Path $symbolicLink.SymbolicLink -Target $SymbolicLinks.SymbolicLinkTarget)
                
        }
    }
    end { }
} #end function

function Get-Execution {
    $CallStack = Get-PSCallStack | Select-Object -Property *
    if (
         ($null -ne $CallStack.Count) -or
         (($CallStack.Command -ne '<ScriptBlock>') -and
         ($CallStack.Location -ne '<No file>') -and
         ($null -ne $CallStack.ScriptName))
    ) {
        if ($CallStack.Count -eq 1) {
            $Output = $CallStack[0]
            $Output | Add-Member -MemberType NoteProperty -Name ScriptLocation -Value $((Split-Path $_.ScriptName)[0]) -PassThru
        }
        else {
            $Output = $CallStack[($CallStack.Count - 1)]
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
         ($null -ne $CallStack.Count) -or
         (($CallStack.Command -ne '<ScriptBlock>') -and
         ($CallStack.Location -ne '<No file>') -and
         ($null -ne $CallStack.ScriptName))
    ) {
        $level = $CallStack.Count - 1
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
        , [Parameter()][switch]$Skip
    )

    try {
        if (!(Test-Path -Path $Path)) {
            Write-Host -Object ("Creating folder '$($Path)'")
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction SilentlyContinue
        }

        Push-Location $Path
        if (!$Skip.IsPresent -or $Skip.ToBool() -eq $false) {
            & $ScriptBlock
        } else {
            Write-Warning -Message "Skipping - Executing Command in $($Path)"
        }
    }
    finally {
        Pop-Location
    }
} #end function

function Invoke-VSIXInstaller {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$PackageName,
        [Parameter(Mandatory)][string]$VsixFileName,
        [Parameter(Mandatory)][string]$VsixUrl,
        [Parameter(Mandatory)][string]$Checksum
    )
    
    begin {
        #Install-ChocolateyVsixPackage currently broke it cannot determine the installed locarion of the VSIXInstaller.exe
        #if (!(Get-Module -Name Choco*)) { Import-Module $env:ChocolateyInstall\helpers\chocolateyInstaller.psm1 }

        $installer = "$($script:vs2022RootPath)\Common7\IDE\VSIXInstaller.exe"
    }
    process {}
    end {
        try {
            #Install-ChocolateyVsixPackage currently broke it cannot determine the installed locarion of the VSIXInstaller.exe
            #Install-ChocolateyVsixPackage -packageName $PackageName -vsixUrl $VsixUrl -vsVersion 17 -checksum $Checksum 
            $vsixPath = "$($env:USERPROFILE)\$($vsixFileName)"
    
            (New-Object Net.WebClient).DownloadFile($VsixUrl, $vsixPath)
            if (($downloadFileHash = (Get-FileHash -Path $vsixPath -Algorithm MD5).Hash) -eq $Checksum) {
                try {
                    Write-Host "Installing $($PackageName) ($($vsixPath)) using $($installer)"
                    $psi = New-Object System.Diagnostics.ProcessStartInfo
                    $psi.FileName = $installer
                    $psi.Arguments = "/q $vsixPath" # /admin /prerequisitesRequired
                    $s = [System.Diagnostics.Process]::Start($psi)
                    $s.WaitForExit()
        
                    if ($s.ExitCode -gt 0) {
                        switch ($s.ExitCode) {
                            1001 { Write-Warning -Message "$($PackageName) is already installed" }
                            2004 { Write-Warning -Message "***** => $($PackageName) may not be installed, check and install manually if it is missing <= *****" }
                            Default { throw "There was an error installing '$($PackageName)'. The exit code returned was $($s.ExitCode)." }
                        }
                    }
                }
                catch {
                    if ($? -or $LASTEXITCODE -ne 0) {
                        throw "Failed to install WSIX for VS2022 extension"
                    }
                    throw
                }
    
            }
            else {
                throw "Checksum for $($PackageName) ($($downloadFileHash) != $($Checksum))"
            }
        }
        finally {
            Remove-Item $vsixPath -Force -ErrorAction SilentlyContinue
        }    
    }
}

function Log-Action {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
        , [Parameter()][string]$Title
        , [Parameter()][System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::Cyan
        , [Parameter()][switch]$NoHeader
        , [Parameter()][switch]$Skip
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
        if (!$Skip.IsPresent -or $Skip.ToBool() -eq $false) {
            &$ScriptBlock
        } else {
            Write-Warning -Message "Skipping - $($Title)"
        }
    }
    
    end {
        if (!$NoHeader.IsPresent -or $NoHeader.ToBool() -eq $false) {
            $message = "$("*" * $maxMessageLength)"
            Write-Host -Object $message -ForegroundColor $ForegroundColor
        }
    }
} #end function

function Build-SolutionOrProject {
    [CmdletBinding()]
    param (
        [Parameter()][string]$SolutionPath
       ,[Parameter()][string]$ProjectName
       ,[Parameter()][switch]$Rebuild
       ,[Parameter()][int]$Timeout = 180
    )

    $path = (Get-Item -Path $SolutionPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DirectoryName)
    if ($null -eq $path) { Write-Warning -Message "Solution '$($SolutionPath)' not found"; return; }

    Invoke-CommandInPath -Path $path -ScriptBlock {
        $projectPath=(Get-ChildItem -Path . -file -Recurse -Filter "$($ProjectName).*proj"|Select-Object -First 1)
        $devEnvParams = [ordered]@{
            "Build"                                 = "`"Release`|AnyCPU`""
            # "p:SkipInvalidConfigurations"           = 'true'
            # "p:GenerateProjectSpecificOutputFolder" = 'true'
            # "p:DeployOnBuild"                       = 'true'
            # "p:WebPublishMethod"                    = 'Package'
            # #"p:OutDir"                             = "$(Build.BinariesDirectory)\"
            # "nodeReuse:false"                       = $null
            "Out"                                     = "`"$(Join-Path $env:TEMP -ChildPath "$((New-Guid).Guid).BuildLog.log")`""
        }
        if ($null -ne $projectPath) { $devEnvParams['Project'] = "`"$($projectPath|Select-Object -ExpandProperty FullName|Resolve-Path -Relative)`"" }
        if ($Rebuild.IsPresent -and $Rebuild.ToBool() -eq $true) { $devEnvParams['Rebuild'] = "`"Release`|AnyCPU`""; $devEnvParams.Remove('Build') }

        git fetch --prune --all --quiet
        git pull --all --quiet

        $buildCommands=@(
            'Build'
            'Clean'
            'Deploy'
            'Out'
            'Project'
            'ProjectConfig'
            'Rebuild'
            'Upgrade'
        )
        $devEnvParamsToString = "$(($devEnvParams.Keys|ForEach-Object { 
            "-$($_)$(if ($null -ne $devEnvParams[$_]) { "$(if ($_ -notin $buildCommands) {"="} else { " "})$($devEnvParams[$_])" })" 
        }) -join ' ')" 
        [void](Remove-Item -Path "$($devEnvParams['Out'])" -Force -ErrorAction SilentlyContinue)

        Start-Sleep -Seconds 2
        try {
            $command = ". '$($script:vs2022ExePath)' $(Resolve-Path -Relative $SolutionPath) $($devEnvParamsToString)"
            Log-Action -Title "Building $($command)" -NoHeader -ScriptBlock {
                Invoke-Expression $command
            }
            Start-Sleep -Seconds 2
            Get-Process -name MSBuild*,devenv*|Wait-Process -TimeoutSec $Timeout
    
            $succeeded = '(?<succeeded>\b(?:(\d+))\b)\s+succeeded'
            $failed = '(?<failed>\b(?:(\d+))\b)\s+failed'
            $skipped = '(?<skipped>\b(?:(\d+))\b)\s+skipped'
            $result=ConvertFrom-Text -Path $devEnvParams['Out'].Replace('"','') -Pattern "=+.*build.*$($succeeded),\s+$($failed),\s+$($skipped)\s+=+" -NoProgress
            if ($result -and $result.failed -gt 0) {
                Write-Error -Message ("Building project $(if ($null -ne $devEnvParams['Project']) { "$($devEnvParams['Project']) in " })$($SolutionPath), or one of its dependencies failed  for details check log $($devEnvParams['Out'])")
            } 
            
            return $result
        }
        finally {
        }
    }
}

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
choco install --yes dotnetdeveloperbundle --limit-output # ANTS Performance Profiler Pro,ANTS Memory Profiler,.NET Reflector VSPro
choco install --yes sqltoolbelt --limit-output --params "/products:'SQL Compare, SQL Data Compare, SQL Prompt, SQL Search, SQL Data Generator, SSMS Integration Pack '"

# UrlRewrite (https://www.iis.net/downloads/microsoft/url-rewrite )
choco install --yes urlrewrite --limit-output

# IIS hosting bundle for .net (https://www.microsoft.com/net/permalink/dotnetcore-current-windows-runtime-bundle-installer )
# Run a separate PowerShell process because the script calls exit, so it will end the current PowerShell session.
#&powershell -NoProfile -ExecutionPolicy unrestricted -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; &([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing 'https://dot.net/v1/dotnet-install.ps1'))) <additional install-script args>"
Log-Action -Title 'IIS hosting bundle' -ScriptBlock { 
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
choco install --yes wixtoolset --limit-output
#choco install --yes wix35 --limit-output

Log-Action -Title 'WIX Extension' -NoHeader -ForegroundColor Cyan -ScriptBlock {
    # WIX Extension(https://marketplace.visualstudio.com/items?itemName=WixToolset.WixToolsetVisualStudio2022Extension )
    #   Install-ChocolateyVsixPackage -packageName "wixtoolsetvisualstudio2019extension" -vsixUrl "https://wixtoolset.gallerycdn.vsassets.io/extensions/wixtoolset/wixtoolsetvisualstudio2019extension/1.0.0.18/1640535816037/Votive2019.vsix" -vsVersion 17.1.0
    #  https://wixtoolset.gallerycdn.vsassets.io/extensions/wixtoolset/wixtoolsetvisualstudio2022extension/1.0.0.22/1668223914320/Votive2022.vsix
    
    $vsixFileName = "Votive2022.vsix"
    $checksumMD5 = '1AC0C61B7FB1D88C2193CFB8E8E38519' # $checkSumSha256="C8B3E77EF18B8F5190B4B9BB6BA6996CB528B8F2D6BC34B373BB2242D71F3F43"
    $params = @{
        PackageName  = "wixtoolsetvisualstudio2022extension"
        VsixFileName = "$($vsixFileName)";
        VsixUrl      = "https://wixtoolset.gallerycdn.vsassets.io/extensions/wixtoolset/wixtoolsetvisualstudio2022extension/1.0.0.22/1668223914320/$($vsixFileName)";
        Checksum     = $checksumMD5;
    }

    Invoke-VSIXInstaller @params
}


# MVC 4 (https://www.microsoft.com/en-gb/download/details.aspx?id=30683 )
choco install --yes aspnetmvc4.install --limit-output

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
$gitParams = [ordered]@{
    GitAndUnixToolsOnPath  = $null
    WindowsTerminal        = $null
    WindowsTerminalProfile = $null
    NoAutoCrlf             = $null
    DefaultBranchName      = 'main'
    Editor                 = 'VisualStudioCode'
}
choco install --yes git --limit-output --params "'$(($gitParams.Keys|ForEach-Object { "/$($_)$(if ($null -ne $gitParams[$_]) { ":$($gitParams[$_])" })" }) -join ' ')'" 

# Node (https://nodejs.org/en )
#choco install --yes nodejs --limit-output
choco install --yes nodejs-lts --limit-output

# Postman (https://www.postman.com/downloads )
choco install --yes postman --limit-output
#choco install --yes postman-cli --limit-output

# (optional screen capture tool) Share X (https://getsharex.com )
choco install --yes sharex --limit-output

# Azure CLI (https://aka.ms/installazurecliwindows )
choco install --yes azure-cli --limit-output
$extensions = @('azure-devops', 'bicep')
Log-Action -Title $("Install Azure Addons/Extensions ('$("$($extensions -join '", "')")')") -ScriptBlock {
    $componentNamePattern = [regex]::new('(?<name>\b(?:\w+)(?:\-*)(?:\w+)\s*\b)')
    $versionPattern = '(?<version>\b(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)\b)'
    $updateAvailablePattern = '((?<updateAvailable>\b((\s+\*+)))|(?<updateAvailable>\b(?:(\s+\*+)?))\b)'

    #region get available extensions matching extension list 
    $functions = ''
    $commands = @(
        "az extension list-available --output jsonc;"
    )
    $powershellCommand = $powershellCommandTemplate.Replace('<<FUNCTIONS>>', $functions).Replace('<<COMMANDS>>', $commands).Trim()
    $scriptBlock = ([scriptblock]::Create(("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"{0}`"" -f $powershellCommand)))

    [array]$azureExtensions = Invoke-CommandInPath -Path (Get-Location) -ScriptBlock $scriptBlock | ConvertFrom-Json | Select-Object -unique name, summary, version, installed, experimental, preview
    if (($extensions -contains 'bicep')) {
        $bicepVersion = try {
            $functions = ''
            $commands = @(
                "az bicep version;"
            )
            $powershellCommand = $powershellCommandTemplate.Replace('<<FUNCTIONS>>', $functions).Replace('<<COMMANDS>>', $commands).Trim()
            $scriptBlock = ([scriptblock]::Create(("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"{0}`"" -f $powershellCommand)))
            $result = Invoke-CommandInPath -Path (Get-Location) -ScriptBlock $scriptBlock
            $result | Where-Object { $_ } | ConvertFrom-Text -Pattern "$($versionPattern)" -NoProgress | Select-Object -ExpandProperty version
        }
        catch { '0.0.0' }

        if (!($azureExtensions | Where-Object name -match 'bicep')) { $azureExtensions += @{ name = "bicep"; summary = $null; version = $bicepVersion; installed = $null -ne $bicep -and $bicepVersion -ne '0.0.0'; experimental = $false; preview = $false; } | Select-Object name, summary, version, installed, experimental, preview }
    }
    #endregion get available extensions matching extension list 
    $azureExtensions = $azureExtensions | Where-Object { $_.name -match ('({0})' -f $($extensions -join '|')) -and !$_.installed }

    #region install missing extensions
    $azCliInstallCommands = (($($extensions | Where-Object { $_ -match ('({0})' -f $($azureExtensions.name -join '|')) } | ForEach-Object { @{ name = $_; summary = $null; version = '0.0.0'; installed = $false; experimental = $false; preview = $false; } })) | Where-Object { 
        !$_.installed 
    }) | ForEach-Object {
        $azComponent = $_
        switch ($azComponent.name) {
            'bicep' { "az $($azComponent.name) install" }
            Default { "az extension add --name $($azComponent.name)" }
        }
    }
    $azCliInstall = [scriptblock]::Create(($azCliInstallCommands -join "`n"))
    if ($azCliInstall) {
        #         $functions = 
        #         @'
        # function ConvertFrom-Text {
        # <<DEFINITION>>
        # } #end function
        # '@.Replace('<<DEFINITION>>', $((Get-Command -Name 'ConvertFrom-Text')).Definition)
        $functions = ''
        $powershellCommand = $powershellCommandTemplate.Replace('<<FUNCTIONS>>', $functions).Replace('<<COMMANDS>>', $azCliInstall).Trim()
        $scriptBlock = ([scriptblock]::Create(("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"{0}`"" -f $powershellCommand)))
        $result = Invoke-CommandInPath -Path (Get-Location) -ScriptBlock $scriptBlock
    }
    #endregion install missing extensions

    #region upgrade az
    $functions = ''
    $commands = @(
        @'
az --version;
'@
    )
    $powershellCommand = $powershellCommandTemplate.Replace('<<FUNCTIONS>>', $functions).Replace('<<COMMANDS>>', $commands).Trim()
    $scriptBlock = ([scriptblock]::Create(("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"{0}`"" -f $powershellCommand)))
    $result = Invoke-CommandInPath -Path (Get-Location) -ScriptBlock $scriptBlock | Where-Object { $_ -match '(?:(\d+)\.)?(?:(\d+)\.)?(?:(\d+)\.\d+)' }

    $doCliUpgrade = (($updatesAvailable = ($result | Where-Object { $_ } | ConvertFrom-Text -Pattern "$($componentNamePattern)$($versionPattern)$($updateAvailablePattern)" -NoProgress | Where-Object { ![string]::IsNullOrWhiteSpace($_.updateAvailable) })).Count -gt 0)
    if ($doCliUpgrade) {
        Log-Action -Title 'The following Az Updates are afailable, and will be updated' -NoHeader -ScriptBlock { $updatesAvailable | ForEach-Object { "   $($_.name), v$($_.version)" } }

        $functions = ''
        $commands = @(
            'az upgrade --yes;'
        )
        $powershellCommand = $powershellCommandTemplate.Replace('<<FUNCTIONS>>', $functions).Replace('<<COMMANDS>>', $commands).Trim()
        $scriptBlock = ([scriptblock]::Create(("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"{0}`"" -f $powershellCommand)))
        $result = Invoke-CommandInPath -Path (Get-Location) -ScriptBlock $scriptBlock
    }
    #endregion upgrade az
}

# Azure Artifacts Credential Provider (https://github.com/microsoft/artifacts-credprovider#setup )
Log-Action -Title 'Azure Artifacts Credential' -ScriptBlock { Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-artifacts-credprovider.ps1) } -AddNetfx" }

# Clone Evolve Repos
$organisation = 'FrFl-Development'
$project = 'Evolve'

Log-Action -Title 'Clone Repos' -ScriptBlock { 
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
        , 'Evolve'
        , 'FRFL'
        # Optional
        , 'TfsBuildExtensions'
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
            $functions = ''
            $commands = @(
                "$($utilityPath)\CloneAllRepos.ps1 -RepositoryNameStartsWith '$($repositoryName)';"
            )
            $powershellCommand = $powershellCommandTemplate.Replace('<<FUNCTIONS>>', $functions).Replace('<<COMMANDS>>', $commands).Trim()
            #$scriptBlock = ([scriptblock]::Create(("powershell -NoLogo -ExecutionPolicy RemoteSigned -Command `"{0}`"" -f $powershellCommand)))
            $scriptBlock = ([scriptblock]::Create(("{0}" -f $powershellCommand)))
            Invoke-CommandInPath -Path $utilityPath -ScriptBlock $scriptBlock
        }
    }
}

Log-Action -Title 'TODO: Visual Studio Configuration' -ForegroundColor Green -ScriptBlock {
    "
    Run as admin
    Run Visual studio as administrator. Follow the answer linked to run as administrator, even when using the taskbar context menu MRU list -> https://stackoverflow.com/questions/42723232/vs2017-vs-2019-run-as-admin-from-taskbar 
    "
}

Log-Action -Title 'Nuget Config' -ScriptBlock {
    "
    Manual Instructions
    In Tools->Nuget Package Manager->Package Manager Settings
    General -> Change the Default package management format to PackageReference
    Package Sources -> Add a source 'Evolve' directed to https://pkgs.dev.azure.com/FrFl-Development/_packaging/EvolvePackage/nuget/v3/index.json 
    Package Sources -> Add a source 'DevExpress' directed to the DevExpress NuGet feed URL from https://www.devexpress.com/ClientCenter/DownloadManager/  once you are logged into your DevExpress account
    "
    $sequencePattern = '(\s+)?(?<sequence>\b\d+\b)\.\s+'
    $namePattern = '(?<name>\b\w.+\b)\s+'
    $statusPattern = '\[(?<enabled>Enabled|Disabled)\]'

    $nugetSources = @{
        'nuget.org' = @{ Source = 'https://api.nuget.org/v3/index.json'; Enabled = $true; };
        'Evolve'    = @{ Source = 'https://pkgs.dev.azure.com/FrFl-Development/_packaging/EvolvePackage/nuget/v3/index.json'; Enabled = $true; };
        #'DevExpress'=@{ Source='https://nuget.devexpress.com/<<your unique api key>>/api'; Enabled=$true; }
        # Optional
        # 'Evolve.old'=@{ Source='\\prd-tfs-bld01\Packages\Nuget'; Enabled=$false; }
        # 'Devexpress 20.1 Local'=@{ Source='C:\Program Files (x86)\Devexpress 20.1\Components\System\Components\Packages'; Enabled=$false; }
        # 'Microsoft Visual Studio Offline Packages'=@{ Source='C:\Program Files (x86)\Microsoft SDKs\NuGetPackages\'; Enabled=$false; }
    }
    $nugetList = @()

    $nugetList += (dotnet nuget list source --format Detailed) -match ("$($sequencePattern)({0})\s+$($statusPattern)" -f ($nugetSources.Keys -join '|'))

    [array]$nugetList = ($nugetlist | ForEach-Object {
            $result = $_ | ConvertFrom-Text -Pattern "$($sequencePattern)$($namePattern)$($statusPattern)" -NoProgress
            $result.enabled = ([regex]::Replace($result.enabled, '(?<status>Enabled)', $true.ToString())) # Back reference ${status} could be used for replacement
            $result.enabled = ([regex]::Replace($result.enabled, '(?<status>Disabled)', $false.ToString())) # Back reference ${status} could be used for replacement

            $result
        })
    [array]$nugetSourcesToAdd = $nugetSources.GetEnumerator() | Where-Object { 
        $_.Key -notmatch ("^($($nugetList.name -join '|'))$")
    }
    [array]$nugetSourcesToUpdate = $nugetSources.GetEnumerator() | Where-Object { 
        $nugetSourceKey = $_.Key
        $_.Key -in $nugetList.name -and ($nugetList | Where-Object { $_.name -eq $nugetSourceKey } | Select-Object -ExpandProperty enabled) -ne $_.Value.Enabled 
    }

    if (($nugetList | Where-Object { $_ }) -and ((($nugetSourcesToAdd.Count) -gt 0) -or (($nugetSourcesToUpdate.Count) -gt 0))) {
        #$nugetSourcesToAdd.Keys|ForEach-Object { dotnet nuget remove source "$($_)" }
        if ($null -ne $nugetSourcesToAdd) {
            $nugetSourcesToAdd.GetEnumerator() | ForEach-Object {
                Write-Host "Adding" $_.Key -ForegroundColor DarkBlue
                "dotnet nuget add source '$($_.Value.Source)' --name '$($_.Key)'" | Invoke-Expression
            }
        }

        if ($null -ne $nugetSourcesToUpdate) {
            $nugetSourcesToUpdate.GetEnumerator() | ForEach-Object {
                Write-Host "Updating" $_.Key -ForegroundColor DarkBlue
                "dotnet nuget $($(if ($_.Value.Enabled) {'enable'} else {'disable'})) source '$($_.Key)'" | Invoke-Expression
            }
        }
    }
}

Log-Action -Title 'TODO: Password Manager' -ForegroundColor Green -ScriptBlock {
    "
    Speak with service desk about access to password manager (currently '1Password')
    "
}

Log-Action -Title 'TODO: SQL Server' -ForegroundColor Green -ScriptBlock {
    "
    Ensure that Full-Text Index is installed, and the server collation MUST be set to SQL_Latin1_General_CP1_CI_AS as we have scripts that are collation sensitive that create temporary stored procs etc. (If SQL is already installed with the wrong server collationfollow these instructions https://docs.microsoft.com/en-us/sql/relational-databases/collations/set-or-change-the-server-collation  )
    "
    Log-Action -Title 'Restore seed databases' -ForegroundColor DarkYellow -NoHeader -ScriptBlock {
        "
        Restore seed databases to your SQL instance from T:\Projects\Secure\Evolve\DatabaseSeeds.
        "
    }

    Log-Action -Title "Give $($env:USERDOMAIN)\$($env:USERNAME) dbo access to Evolve* and DataRetention DB's, Add Linked Server" -ForegroundColor DarkYellow -NoHeader -Skip -ScriptBlock {
        "
        Add $($env:USERDOMAIN)\$($env:USERNAME) user with dbo access to the Evolve....... DBs and DataRetention DB
        Add a linked server object for DEV-SQL-APP01 called DEV-SQL-APP01 and configure Server Options->RPC Out to 'true'. Set Security to `"Be made with the login's current security context`"
        "
        function Using-Object {
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
                [void]($commandList.Add('
                USE [master]
                DECLARE @_WindowsUser sysname = ''{0}\{1}''
                DECLARE @_sql NVARCHAR(MAX)
                
                --SELECT name FROM sys.sql_logins
                IF NOT EXISTS (SELECT name FROM sys.server_principals WHERE name = @_WindowsUser) BEGIN SET @_sql = N''CREATE LOGIN ['' + @_WindowsUser + ''] FROM WINDOWS WITH DEFAULT_DATABASE=[master]''; EXEC sys.sp_executesql @stmt=@_sql; END
                
                BEGIN
                    USE [DataRetention]
                    if NOT EXISTS(SELECT * FROM sys.database_principals WHERE name = @_WindowsUser) BEGIN SET @_sql = N''CREATE USER ['' + @_WindowsUser + ''] FOR LOGIN ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql; END
                    BEGIN SET @_sql = ''ALTER ROLE [db_owner] ADD MEMBER ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql END;
                END
                
                BEGIN 
                    USE [EvolveApplication]
                    if NOT EXISTS(SELECT * FROM sys.database_principals WHERE name = @_WindowsUser) BEGIN SET @_sql = N''CREATE USER ['' + @_WindowsUser + ''] FOR LOGIN ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql; END
                    BEGIN SET @_sql = ''ALTER ROLE [db_owner] ADD MEMBER ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql END;
                END
                
                BEGIN
                    USE [EvolveDealer]
                    if NOT EXISTS(SELECT * FROM sys.database_principals WHERE name = @_WindowsUser) BEGIN SET @_sql = N''CREATE USER ['' + @_WindowsUser + ''] FOR LOGIN ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql; END
                    BEGIN SET @_sql = ''ALTER ROLE [db_owner] ADD MEMBER ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql END;
                END
                
                BEGIN
                    USE [EvolveDecision]
                    if NOT EXISTS(SELECT * FROM sys.database_principals WHERE name = @_WindowsUser) BEGIN SET @_sql = N''CREATE USER ['' + @_WindowsUser + ''] FOR LOGIN ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql; END
                    BEGIN SET @_sql = ''ALTER ROLE [db_owner] ADD MEMBER ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql END;
                END
                
                BEGIN
                    USE [EvolvePayment]
                    if NOT EXISTS(SELECT * FROM sys.database_principals WHERE name = @_WindowsUser) BEGIN SET @_sql = N''CREATE USER ['' + @_WindowsUser + ''] FOR LOGIN ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql; END
                    BEGIN SET @_sql = ''ALTER ROLE [db_owner] ADD MEMBER ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql END;
                END
                
                BEGIN 
                    USE [EvolveProjection]
                    if NOT EXISTS(SELECT * FROM sys.database_principals WHERE name = @_WindowsUser) BEGIN SET @_sql = N''CREATE USER ['' + @_WindowsUser + ''] FOR LOGIN ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql; END
                    BEGIN SET @_sql = ''ALTER ROLE [db_owner] ADD MEMBER ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql END;
                END
                
                BEGIN
                    USE [EvolveSecurity]
                    if NOT EXISTS(SELECT * FROM sys.database_principals WHERE name = @_WindowsUser) BEGIN SET @_sql = N''CREATE USER ['' + @_WindowsUser + ''] FOR LOGIN ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql; END
                    BEGIN SET @_sql = ''ALTER ROLE [db_owner] ADD MEMBER ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql END;
                END
                
                BEGIN 
                    USE [EvolveServices]
                    if NOT EXISTS(SELECT * FROM sys.database_principals WHERE name = @_WindowsUser) BEGIN SET @_sql = N''CREATE USER ['' + @_WindowsUser + ''] FOR LOGIN ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql; END
                    BEGIN SET @_sql = ''ALTER ROLE [db_owner] ADD MEMBER ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql END;
                END
                
                BEGIN
                    USE [EvolveShared]
                    if NOT EXISTS(SELECT * FROM sys.database_principals WHERE name = @_WindowsUser) BEGIN SET @_sql = N''CREATE USER ['' + @_WindowsUser + ''] FOR LOGIN ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql; END
                    BEGIN SET @_sql = ''ALTER ROLE [db_owner] ADD MEMBER ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql END;
                END
                
                BEGIN
                    USE [EvolveShared]
                    if NOT EXISTS(SELECT * FROM sys.database_principals WHERE name = @_WindowsUser) BEGIN SET @_sql = N''CREATE USER ['' + @_WindowsUser + ''] FOR LOGIN ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql; END
                    BEGIN SET @_sql = ''ALTER ROLE [db_owner] ADD MEMBER ['' + @_WindowsUser + '']''; EXEC sys.sp_executesql @stmt=@_sql END;
                END
                ' -f 'TEAM','Evolve'))
                [void]($commandList.Add('
                USE [master]
                BEGIN
                    EXEC master.dbo.sp_addlinkedserver @server = N''{0}'', @srvproduct=N''SQL Server''
                    EXEC master.dbo.sp_serveroption @server=N''{0}'', @optname=N''collation compatible'', @optvalue=N''false''
                    EXEC master.dbo.sp_serveroption @server=N''{0}'', @optname=N''data access'', @optvalue=N''true''
                    EXEC master.dbo.sp_serveroption @server=N''{0}'', @optname=N''dist'', @optvalue=N''false''
                    EXEC master.dbo.sp_serveroption @server=N''{0}'', @optname=N''pub'', @optvalue=N''false''
                    EXEC master.dbo.sp_serveroption @server=N''{0}'', @optname=N''rpc'', @optvalue=N''false'' -- true in uat
                    EXEC master.dbo.sp_serveroption @server=N''{0}'', @optname=N''rpc out'', @optvalue=N''true''
                    EXEC master.dbo.sp_serveroption @server=N''{0}'', @optname=N''sub'', @optvalue=N''false''
                    EXEC master.dbo.sp_serveroption @server=N''{0}'', @optname=N''connect timeout'', @optvalue=N''0''
                    EXEC master.dbo.sp_serveroption @server=N''{0}'', @optname=N''collation name'', @optvalue=null
                    EXEC master.dbo.sp_serveroption @server=N''{0}'', @optname=N''lazy schema validation'', @optvalue=N''false''
                    EXEC master.dbo.sp_serveroption @server=N''{0}'', @optname=N''query timeout'', @optvalue=N''0''
                    EXEC master.dbo.sp_serveroption @server=N''{0}'', @optname=N''use remote collation'', @optvalue=N''true''
                    EXEC master.dbo.sp_serveroption @server=N''{0}'', @optname=N''remote proc transaction promotion'', @optvalue=N''true''
                    EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = N''{0}'', @locallogin = NULL , @useself = N''True''
                END
                ' -f 'DEV-SQL-APP01'))
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
    
    }

    Log-Action -Title "Update your seeds to current" -ForegroundColor DarkYellow -NoHeader -ScriptBlock {
        "
        Update your seeds to current by:-
        Legacy DB - Running publish on all databases from the database project, or if too far out of date, run project to database compares for all the projects and manually update from the models.
        "
    }
}

Log-Action -Title 'TODO: Microservices' -ForegroundColor Green -ScriptBlock {
    "
    Run 'update-database' for each from Nuget Package Manager console.
    This may not be needed
    "
}

Log-Action -Title 'TODO: More SQL Server' -ForegroundColor Green -ScriptBlock {
    "
    Once the databases are up-to-date, execute the spCreateFullTextIndex stored procedure as follows to ensure that the Search full-text index is created:
    "

    Log-Action -Title "Give $($env:USERDOMAIN)\$($env:USERNAME) dbo access to Evolve* and DataRetention DB's" -ForegroundColor DarkYellow -NoHeader -ScriptBlock {
        "
        EXEC EvolveApplication.SearchImport.spCreateFullTextIndex

        Create your user in the aspnet_users table and related tables to grant the correct permissions.
        SQL Prompt (optional)
        Get snippets from https://frfl.sharepoint.com/sites/ITTeam/Developement/Forms/AllItems.aspx?viewid=e84320c5-033b-4a12-a5eb-971adf5b1171&id=%2Fsites%2FITTeam%2FDevelopement%2FTools%2FSQL Prompt%2FSnippets 
        Get Styles from https://frfl.sharepoint.com/sites/ITTeam/Developement/Forms/AllItems.aspx?viewid=e84320c5-033b-4a12-a5eb-971adf5b1171&id=%2Fsites%2FITTeam%2FDevelopement%2FTools%2FSQL Prompt%2FStyles 
        "
        #Start-Process "odopen://sync/?siteId=SiteID_HERE&amp;webId=WebID_HERE&amp;listId=ListID_HERE&amp;userEmail=UserEmail_HERE&amp;webUrl=WebURL_HERE"
        <#
        Start-Process "odopen://sync?siteId=%7Bf66eaa35%2Dbd5c%2D4954%2D9739%2D2d96aa4f9155%7D&webId=%7B14e4b14b%2De21b%2D410b%2D895e%2D2ee04ae2841d%7D&listId=1a39d371%2D212e%2D4f8a%2Da861%2Db24bdae04e78&webUrl=https%3A%2F%2Ffrfl%2Esharepoint%2Ecom%2Fsites%2FITTeam&webTitle=IT%20Team&listTitle=Development&scope=OPENLIST&isSiteAdmin=0
        
        &userEmail=cyril%2Emadigan%40frfl%2Eco%2Euk
        &userId=e501559d%2Daa6f%2D4860%2Da65d%2D008cf90c5bb2
        &webTemplate=64
        &webLogoUrl=%2Fsites%2FITTeam%2F%5Fapi%2FGroupService%2FGetGroupImage%3Fid%3D%27f1f4d0ec%2Dc839%2D4243%2Db3b8%2D371250982cfd%27%26hash%3D637674028206291066
        &onPrem=0
        &libraryType=3
        "#>
        # Give Windows some time to load before getting the email address
        function Test-ADAuthentication {
            [CmdletBinding(DefaultParametersetName="default", SupportsShouldProcess = $true)]
            Param(
               [Parameter(ParameterSetName="default",Mandatory)]
               [ValidateNotNull()]
               [System.Management.Automation.PSCredential]  #Type
               [System.Management.Automation.Credential()]  #TypeConverter
               $Credential = [System.Management.Automation.PSCredential]::Empty
            )

            [bool]$result = $false
          
            Add-Type -AssemblyName System.DirectoryServices.AccountManagement
            
            $contextType = [System.DirectoryServices.AccountManagement.ContextType]::Domain

            $domain = if ($credential -ne [System.Management.Automation.PSCredential]::Empty) {
                if ($Credential.GetNetworkCredential().Domain) { 
                    $Credential.GetNetworkCredential().Domain 
                } elseif ($credential.UserName.Split('@')[1]) {
                    $env:USERDOMAIN
                } else {
                    $credential.UserName.Split('\')[0]
                }
            } else {
                $env:USERDOMAIN
            }
            
            $argumentList = New-Object -TypeName "System.Collections.ArrayList"
            $null = $argumentList.Add($contextType)
            $null = $argumentList.Add($domain)
        
            #if($null -ne $Server){ $argumentList.Add($Server) }            
            $principalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext -ArgumentList $argumentList -ErrorAction SilentlyContinue
        
            if ($null -eq $principalContext) { Write-Warning "$Domain\$User - AD Authentication failed" }
            if ($principalContext.ValidateCredentials($Credential.GetNetworkCredential().UserName, $Credential.GetNetworkCredential().Password)) {
                Write-Host -ForegroundColor green "$Domain\$User - AD Authentication OK"
                $result = $true
            }
            else {
                Write-Warning "$Domain\$userName - AD Authentication failed"
            }
        
            return $result
        }
        
        $UserName = $env:USERNAME
        $Domain = "@frfl.co.uk"
        [void]($userEmail = (az account show|ConvertFrom-Json|Select-Object @{ E={ $_.user.name }; N='Email'}|Select-Object -ExpandProperty Email))
        if (!$userEmail) { $userEmail=$UserName + $Domain }
        Do {
            $credentials = $(Get-Credential -Message "Please supply your credentials" -UserName $userEmail)
        
        } Until ((Test-ADAuthentication -Credential $credentials))
        
        $synchroniseSharepointLibraries = @{
            Web = @{
                Id    = "14e4b14b%2De21b%2D410b%2D895e%2D2ee04ae2841d"
                Name  = "ITTeam"
                Title = "IT Team"
                Url   = "https://frfl.sharepoint.com/sites/ITTeam"
                Site  = @{ Name = "ITTeam"; Id = "f66eaa35%2Dbd5c%2D4954%2D9739%2D2d96aa4f9155"; }
                List  = @{ 
                    #Documents            = @{ Id = "d01eb810%2D86d9%2D439b%2D86c7%2Dc6e9ceb317ec"; Title = "Documents"; }
                    #BusinessIntelligence = @{ Id = "becc8b61%2D17ee%2D4c80%2Db666%2Da5dde99a24c9"; Title = "Business Intelligence"; }
                    #ChangeManagement     = @{ Id = "fefee048%2D0645%2D42c3%2D9f34%2D2d85fe71f397"; Title = "Change Management"; }
                    Development          = @{ Id = "1a39d371%2D212e%2D4f8a%2Da861%2Db24bdae04e78"; Title = "Development"; }
                    #Infrastructure       = @{ Id = "2cd12d31%2D6555%2D43f4%2Da16f%2Dcf59c7d4a51e"; Title = "Infrastructure"; }
                    #ServiceDesk          = @{ Id = "483078e1%2D60c5%2D4c86%2D92eb%2Deca9b2c9cc63"; Title = "ServiceDesk"; }
                    TeamManagement       = @{ Id = "93e4bb97%2D8f6c%2D4907%2D9d37%2Df847b00f6840"; Title = "Team Management"; }
                    #TestTeam             = @{ Id = "0f666079%2D5539%2D4bbf%2Daaf9%2D9a96b1acdd03"; Title = "Test Team"; }
                    #Contracts            = @{ Id = "4cb602d5%2Df481%2D484b%2D882b%2D0d610c26ef91"; Title = "Contracts"; }
                    #Analytics            = @{ Id = "4b96fbb8%2D1bb6%2D4696%2D9c61%2D12ae555502e6"; Title = "Analytics"; }
                }
                Scope = "OPENLIST"
            }
        }
        $synchroniseSharepointLibraries.Keys | ForEach-Object {
            $web = $synchroniseSharepointLibraries[$_]
            $web.List.Keys | ForEach-Object {
                $list = $web.List[$_]
        
                $webUrl = $web.Url
                $webId = $web.Id
                $siteId = $web.Site.Id
                $listId = $list.Id
                $listTitle = $list.Title
                $webTitle = $web.Title
        
                if (!(Test-Path -Path "$($env:USERPROFILE)\First Response Finance Ltd\$($webTitle) - $($list.Title)\" -PathType Container -ErrorAction SilentlyContinue)) {
                    # Use a "Do" loop to check to see if OneDrive process has started and continue to check until it does
                    Do{
                        # Check to see if OneDrive is running
                        $ODStatus = Get-Process onedrive -ErrorAction SilentlyContinue
                        
                        # If it is start the sync. If not, loopback and check again
                        If ($ODStatus) 
                        {
                            # Give OneDrive some time to start and authenticate before syncing library
                            Start-Sleep -s 30
            
                            # set the path for odopen
                            $odopen = "odopen://sync/?siteId=" + $siteId + "&webId=" + $webId + "&webUrl=" + $webUrl +             "&webTitle=" + $webTitle + "&listId=" + $listId + "&listTitle=" + $listTitle + "&userEmail=" + $userEmail + "&scope=OPENLIST"
        
                            #Start the sync
                            Start-Process $odopen -Credential $credentials
                            #Start-Process $odopen
                        }
                    }
                    Until ($ODStatus)
                } else {
                    Write-Host -Object ("   $($webTitle) - $($list.Title) already synchronised") -ForegroundColor Cyan
                }
            }
        }
        
        $copySQLPromptSnippetsPath= "$($env:USERPROFILE)\First Response Finance Ltd\IT Team - Development\Tools\SQL Prompt\Snippets\CopySqlPromptSnippets.bat"
        if ((Test-Path -Path $copySQLPromptSnippetsPath -PathType Leaf)) {
            Invoke-Expression -Command "& `"$($copySQLPromptSnippetsPath)`" -AddScheduledTask"
        }
    }
}

Log-Action -Title 'Logging Distribution' -ScriptBlock {
    "
    Building FrFl.Service.LoggingDistributor If this fails follow the manual instructions

    Manual Instructions
    In the main Evolve solution, build the FrFl.Service.LoggingDistributor project
    Manually copy the Build output to a suitable location (suggested C:\Program Files (x86)\First Response Finance Ltd\Evolve Logging Distributor )
    From a command prompt run FrFl.Service.LoggingDistributor.exe /i /user TEAM\Evolve /password ****** to install as a service
    "
    $solutionPath='Evolve'|ForEach-Object { Get-ChildItem -Path "C:\data\tfs\git\$($_)" -file -Recurse -Filter *.sln } | Select-Object -First 1
    $projectName='FrFl.Service.LoggingDistributor'
    $result = Build-SolutionOrProject -SolutionPath $solutionPath.FullName -ProjectName $projectName -Timeout 180
    if (!($result -and $result.failed -gt 0)) {
        $loggingDistributorPath = Get-ChildItem -Path "$($solutionPath.DirectoryName)" -file -Recurse -Filter "$($projectName).*proj" | Select-Object -First 1
        Log-Action -Title "Create logging distribution folder" -NoHeader -ScriptBlock {
            $source="$(Resolve-Path -Relative -Path (Join-Path $loggingDistributorPath.DirectoryName -ChildPath "bin\Release"))\*"
            $destination="C:\Program Files (x86)\First Response Finance Ltd\Evolve Logging Distributor"
            [void](New-Item -ItemType Directory -Path $destination -Force -ErrorAction SilentlyContinue)
            
            #TODO: Stop service
            Get-Service -Name FrFl.Service.LoggingDistributor -ErrorAction SilentlyContinue | Stop-Service -Passthru -Force -ErrorAction SilentlyContinue
            [void]($result=Copy-Item -Path $source -Destination $destination -Recurse -Force -PassThru)
            Write-Host -Object ("   logging distributer has been set up in $($destination) copyied $($result.Count) files") -ForegroundColor Cyan
            Log-Action -Title 'TODO: Setting up Logging Distributer as a Service' -NoHeader -ForegroundColor Green -ScriptBlock {
                Invoke-CommandInPath -Path $destination -ScriptBlock {
                    "         FrFl.Service.LoggingDistributor.exe /i /user TEAM\Evolve /password ******"
                    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($(Read-host -Prompt "Enter password for Evolve user" -AsSecureString))
                    $PlainText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                    .\FrFl.Service.LoggingDistributor.exe /i /user TEAM\Evolve /password [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
                    Get-Service -Name FrFl.Service.LoggingDistributor -ErrorAction SilentlyContinue | Start-Service -Passthru -Force
                }
            }
        }
    }
}

Log-Action -Title 'Register Zecom Server' -ScriptBlock {
    "
    Manual Instructions 
    Open an administrator command prompt
    Execute C:\Program Files (x86)\Telephony\CTI\Bin\ZCom.exe /regserver
    "
    $path = Get-ChildItem -Path "C:\Program Files*\Telephony\CTI\Bin\*" -Recurse -File -Include zcom.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty DirectoryName
    Invoke-CommandInPath -Path $path -ScriptBlock {
        if (!(Test-Path -Path "$(Join-Path -Path $path -ChildPath 'ZCom.exe')")) {
            Write-Warning -Message "ZCom.exe not found at '$($path)\ZCom.exe'"
            return
        }

        & ".\ZCom.exe" /regserver
    }
}

Log-Action -Title 'TODO: Solution Build & Run' -ForegroundColor Green -ScriptBlock {
    "
    Connect to the VPN if you arn't already
    In a admin PowerShell prompt execute set-executionpolicy Unrestricted
    In a admin command prompt execute C:\Data\TFS\Git\Evolve.Scripts\DevEnvConfig>DevEnvMigration.bat
    In a admin command prompt execute C:\Data\TFS\Git\Evolve.Scripts>CreateEventSources.bat
    In a admin command prompt execute C:\Data\TFS\Git\Evolve.Scripts>CreateEvolveMSMQ.cmd
    In a admin command prompt execute C:\Data\TFS\Git\Evolve.Scripts\Utility>BuildMicroservices.bat
    Open and run the legacy Evolve.sln solution
    Access https://l-evolve/admin 
    You are good to go
    "
    Invoke-CommandInPath -Path . -ScriptBlock {
        Log-Action -Title 'Relax Powershell execution restrictions' -NoHeader -ScriptBlock {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        }
    }

    Invoke-CommandInPath -Path "C:\Data\TFS\Git\Evolve.Scripts\DevEnvConfig" -ScriptBlock {
        Log-Action -Title 'DevEnvMigration' -NoHeader -ScriptBlock {
            & ".\DevEnvMigration.bat" -InstallVSTemplate -DoMicroserviceDatabaseUpdate
        }
    }

    Invoke-CommandInPath -Path "C:\Data\TFS\Git\Evolve.Scripts" -ScriptBlock {
        Log-Action -Title 'CreateEventSources' -NoHeader -ScriptBlock {
            & ".\CreateEventSources.bat"
        }
        Log-Action -Title 'CreateEvolveMSMQ' -NoHeader -ScriptBlock {
            & ".\CreateEvolveMSMQ.cmd"
        }
    }
        
    Invoke-CommandInPath -Path "C:\Data\TFS\Git\Evolve.Scripts\Utility" -ScriptBlock {
        Log-Action -Title 'BuildMicroservices' -NoHeader -ScriptBlock {
            & ".\BuildMicroservices.bat"
        }
    }

    Invoke-CommandInPath -Path "C:\Data\TFS\Git\Evolve" -ScriptBlock {
        Log-Action -Title 'Open and run the legacy Evolve.sln solution' -NoHeader -ScriptBlock {
            Start-Process -FilePath ".\FrFl.Evolve.sln"
            Start-Sleep -Seconds 2
            try { Get-Process -name devenv*|Wait-Process -TimeoutSec 180 } catch { }
            Get-Process -name devenv*|Wait-Process -TimeoutSec 180
        }
        Log-Action -Title 'Access https://l-evolve/admin' -NoHeader -ScriptBlock {

            $webLauncherUrl="https://l-evolve/admin"
            Start-Process -FilePath microsoft-edge:$webLauncherUrl
        }
    }
}

Log-Action -Title 'TODO: Website setup' -ForegroundColor Green -ScriptBlock {
    "
    Setting up and running the website has a few additional steps. They are,
    Build the Evolve solution that hosts the public service api (Setting up portal api and vendor api)
    Build the Evolve.PublicWebsite.CMS solution

    [Obsolete]
    Open a command prompt at the following directory: C:\Data\Tfs\Git\Evolve.PublicWebsite.CMS\Evolve.PublicWebsite.CMS
    Run `"npm i`" to restore the javascript packages for the project
    Run `"npm run build-prod`" to build the angular portion of the site (this may take a few mins to run)
    Build the Evolve.PublicWebsite.Spa solution
    Open a command prompt at the following directory: C:\Data\Tfs\Git\Evolve.PublicWebsite.SPA\Evolve.PublicWebsite.SPA
    Run `"npm i`" to restore the javascript packages for the project
    Run `"npm run build-prod`" to build the angular portion of the site (this may take a few mins to run)

    Manual instructions
    New Website Manial setup https://dev.azure.com/FrFl-Development/Evolve/_wiki/wikis/Evolve.wiki/368/Project-Setup
    In a admin command prompt execute C:\Data\TFS\Git\Evolve\Scripts\DevEnvConfig>DevEnvMigration.bat
    Go to l-web  and you're done
    "
    $solutionPath='Evolve'|ForEach-Object { Get-ChildItem -Path "C:\data\tfs\git\$($_)" -file -Recurse -Filter *.sln } | Select-Object -First 1
    $result = Build-SolutionOrProject -SolutionPath $solutionPath -ProjectName 'FrFl.PublicService.PortalApi.ServiceHost' -Timeout 180
    #$result
    if (!($result -and $result.failed -gt 0)) {
        $result = Build-SolutionOrProject -SolutionPath $solutionPath -ProjectName 'FrFl.PublicService.VendorApi.ServiceHost' -Timeout 180
        #$result
        <#
        if (!($result -and $result.failed -gt 0)) {
            foreach ($projectName in @('Evolve.PublicWebsite.CMS', 'Evolve.PublicWebsite.SPA')) {
                $path=$projectName|ForEach-Object { Get-ChildItem -Path "C:\data\tfs\git\$($_)" -file -Recurse -Filter *.sln|Select-Object -First 1 -ExpandProperty FullName }
                Invoke-CommandInPath -Path $path -ScriptBlock {
                    Log-Action -Title 'npm i' -NoHeader -ScriptBlock {
                        & "npm i"
                    }
                    Log-Action -Title 'npm run build-prod' -NoHeader -ScriptBlock {
                        & "npm run build-prod"
                    }
                }
            }
        }
        #>

        Log-Action -Title 'Access l-web' -NoHeader -ScriptBlock {
            $webLauncherUrl="https://l-web"
            Start-Process -FilePath microsoft-edge:$webLauncherUrl
        }
    }
}

Log-Action -Title 'Optional VS2022 Extensions' -NoHeader -ForegroundColor Cyan -ScriptBlock {
    $extensions = @{
        VSColorOutput   = @{
            PackageName = "vscoloroutputvisualstudio2022extension"
            FileName    = "VSColorOutput.vsix"
            ChecksumMD5 = '1AC0C61B7FB1D88C2193CFB8E8E38519' # $checkSumSha256="C8B3E77EF18B8F5190B4B9BB6BA6996CB528B8F2D6BC34B373BB2242D71F3F43"
            Url         = "https://mikeward-annarbor.gallerycdn.vsassets.io/extensions/mikeward-annarbor/vscoloroutput/2.74/1692882607561/$($this.FileName)"; <# https://marketplace.visualstudio.com/items?itemName=MikeWard-AnnArbor.VSColorOutput64 #>
            Checksum    = $this.ChecksumMD5;
        }
        GitHubCodePilot = @{
            <#
            https://learn.microsoft.com/en-us/visualstudio/ide/work-with-github-accounts
            #>
            PackageName = "githubcodepilotvisualstudio2022extension"
            FileName    = "GitHub.Copilot.Vsix.1.133.0.0.vsix"
            ChecksumMD5 = '1AC0C61B7FB1D88C2193CFB8E8E38519' # $checkSumSha256="C8B3E77EF18B8F5190B4B9BB6BA6996CB528B8F2D6BC34B373BB2242D71F3F43"
            Url         = "https://github.gallerycdn.vsassets.io/extensions/github/copilotvs/1.133.0.0/1699306328409/$($this.FileName)"; <# https://marketplace.visualstudio.com/items?itemName=MikeWard-AnnArbor.VSColorOutput64 #>
            Checksum    = $this.ChecksumMD5;
        }
    }
    
    $extensions.Keys | ForEach-Object {
        
        $extension = $extensions[$_]
        if ($extension.Url -notmatch "$($extension.FileName)$") { $extension.Url = "$($extension.Url)$($extension.FileName)" }
        if ($extension.Checksum -notmatch "$($extension.ChecksumMD5)$") { $extension.Checksum = "$($extension.ChecksumMD5)" }

        do {
            $promptResult = Read-Host -Prompt "Install $($extension.PackageName) (Y/N)"
        } until (
            <# Condition that stops the loop if it returns true #>
            $promptResult -match '^[yn]$'
        )

        if ($promptResult -match '^[n]$') {
            Write-Host -Object "Skipping $($extension.PackageName)" -ForegroundColor Cyan
        } else {
            # $vsixFileName = $extension.FileName
            # $checksumMD5 = $extension.ChecksumMD5
            # $vsixUrl = $extension.Url
            # $checksum = $extension.Checksum
            # $packageName = $extension.PackageName
            # if (!(Get-InstalledVsixPackage -Name $packageName)) {
            #     Install-ChocolateyVsixPackage -packageName extension.PackageName -vsixUrl $extension.Url -vsVersion 17.1.0
            #     Install-VsixPackage -VsixFileName $vsixFileName -ChecksumMD5 $checksumMD5 -VsixUrl $vsixUrl -Checksum $checksum -PackageName $packageName
            # }
            
            $params = @{
                PackageName  = $extension.PackageName
                VsixFileName = $extension.FileName;
                VsixUrl      = $extension.Url;
                Checksum     = $extension.Checksum;
            }
        
            Invoke-VSIXInstaller @params
        }
    }
}

Log-Action -Title "Update Outdated packages" -ScriptBlock {
    $outdated = choco outdated --limit-output | Select-Object @{E = { $_.Split('|') | Select-Object -First 1 }; N = "Id" }, @{E = { $_.Split('|') | Select-Object -Skip 1 -First 1 }; N = "CurrentVersion" }, @{E = { $_.Split('|') | Select-Object -Skip 2 -First 1 }; N = "NewVersion" }, @{E = { $_.Split('|') | Select-Object -Skip 3 -First 1 }; N = "Pinned" }
    $outdated | Where-Object { !("$($_.Pinned)" -as [bool]) } | ForEach-Object { choco upgrade --yes $_.Id --limit-output }
}

Log-Action -Title "Set Up SymbolicLinks to folders" -NoHeader -ScriptBlock {
    $symbolicLinks = @{ 
        'Editor Config' = @{ SymbolicLink = [string]"C:\Data\TFS\Git\.editorconfig"; SymbolicLinkTarget = [string]"C:\data\tfs\git\EditorConfig\.editorconfig"; Backup = [switch]$false; } 
        'Projects'      = @{ SymbolicLink = [string]"C:\Projects"; SymbolicLinkTarget = [string]"C:\data\tfs\git"; Backup = [switch]$false; } 
    }
    Get-ChildItem -Path "$($env:USERPROFILE)\First Response Finance Ltd\IT Team - Development\Tools\SQL Prompt\Styles\" -Filter *.sqlpromptstyle* | ForEach-Object {
        $symbolicLinks.Add("SqlPrompt$($_.Name)", @{ SymbolicLink = [string]"$($env:LOCALAPPDATA)\Red Gate\SQL Prompt 10\Styles\$($_.Name)"; SymbolicLinkTarget = [string]"$($_.FullName)"; Backup = [switch]$false; })
    }

    $symbolicLinks.Keys | ForEach-Object { 
        $symbolicLink = $symbolicLinks["$($_)"] 
        Log-Action -Title "$($_)" -NoHeader -ScriptBlock {
            Create-SymbolicLink -SymbolicLinks $symbolicLink
        }        
    }
}

Log-Action -Title "Enable GodMode" -ScriptBlock {
    $godModePath = "$($env:USERPROFILE)\Desktop\GodMode.{ED7BA470-8E54-465E-825C-99712043E01C}"
    if (!(Test-Path -Path $godModePath)) {
        [void](New-Item -ItemType Directory -Path $godModePath -Force -ErrorAction SilentlyContinue)
    }
}

exit 0

#endregion Main Logic
