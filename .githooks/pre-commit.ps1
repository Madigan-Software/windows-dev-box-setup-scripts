## https://www.youtube.com/watch?v=ig5E8CcdM9g
## https://stackoverflow.com/questions/5629261/running-powershell-scripts-as-git-hooks
## https://git-scm.com/docs/githooks#_post_checkout


# Verify user's Git config has appropriate email address
if ($env:GIT_AUTHOR_EMAIL -notmatch '@(users\.)(noreply\.)?github\.com$') {
    Write-Warning "Your Git email address '$env:GIT_AUTHOR_EMAIL' is not configured correctly."
    Write-Warning "It should end with '@github.com' or '@users.noreply.github.com'."
    Write-Warning "Use the command: 'git config --global user.email <name@github.com>' to set it correctly."
    exit 1
}

Get-ChildItem env:GIT*

exit 0