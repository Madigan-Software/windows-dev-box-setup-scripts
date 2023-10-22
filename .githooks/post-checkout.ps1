[CmdletBinding()]
param (
    $PreviousHead,
    $NewHead,
    $BranchCheckout
)

function Convert-BranchToFileName() {
    param(
        $branch
    )

    $filename = $branch
    if ($branch.StartsWith('*')) {
        $filename = $branch.Substring(2)
    }

    $filename = $filename.Split([IO.Path]::GetInvalidPathChars()) -join ''
    return $filename.Trim()
}

if (!(Test-Path '.vscode\launch')) {
    New-Item '.vscode\launch' -ItemType Directory | Out-Null
}

$branches = git branch --points-at $PreviousHead
foreach ($branch in $branches) {
    if (Test-Path '.vscode\launch.json') {
        $filename = Convert-BranchToFileName $branch
        Copy-Item '.vscode\launch.json' ".vscode\launch\$filename.json" -Force
    }
}

if ($BranchCheckout -eq 1) {
    $newBranch = git branch --show-current
    if (Test-Path ".vscode\launch\$(Convert-BranchToFileName $newBranch).json") {
        Copy-Item ".vscode\launch\$(Convert-BranchToFileName $newBranch).json" '.vscode\launch.json' -Force
    }
}