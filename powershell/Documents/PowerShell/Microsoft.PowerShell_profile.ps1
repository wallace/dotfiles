# PowerShell Profile - zsh-like configuration
# Install required modules first:
#   Install-Module PSReadLine -Force
#   Install-Module Terminal-Icons -Repository PSGallery
#   Install-Module PSFzf -Repository PSGallery
#   Install-Module posh-git -Scope CurrentUser
#   Install-Module z -Scope CurrentUser
# Install Oh-My-Posh:
#   winget install JanDeDobbeleer.OhMyPosh

# PSReadLine - fish-like autosuggestions and history
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
}

# Oh-My-Posh - prompt theming (similar to oh-my-zsh)
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json" | Invoke-Expression
}

# Terminal-Icons - colorful file/folder icons
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
}

# PSFzf - fuzzy finder integration
if (Get-Module -ListAvailable -Name PSFzf) {
    Import-Module PSFzf
    # Ctrl+f for file/folder search, Ctrl+r for history search
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+f' -PSReadlineChordReverseHistory 'Ctrl+r'
}

# posh-git - git integration in prompt
if (Get-Module -ListAvailable -Name posh-git) {
    Import-Module posh-git
}

# z - directory jumping (tracks frequently used directories)
if (Get-Module -ListAvailable -Name z) {
    Import-Module z
}

# Aliases similar to common zsh/bash aliases
Set-Alias -Name ll -Value Get-ChildItem
Set-Alias -Name la -Value Get-ChildItem

# Function for ls -la equivalent
function lsa { Get-ChildItem -Force }

# Function for quick directory navigation
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

# Git aliases (similar to oh-my-zsh git plugin)
function gs { git status }
function ga { git add $args }
function gc { git commit -v $args }
function gp { git push $args }
function gl { git pull $args }
function gd { git diff $args }
function gco { git checkout $args }
function gb { git branch $args }
function glog { git log --oneline --decorate --graph $args }

# Function to quickly edit this profile
function Edit-Profile { code $PROFILE }
Set-Alias -Name ep -Value Edit-Profile

# Function to reload profile
function Reload-Profile {
    . $PROFILE
    Write-Host "PowerShell profile reloaded!" -ForegroundColor Green
}
Set-Alias -Name reload -Value Reload-Profile

# Set default encoding to UTF-8
$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# Welcome message
Write-Host "PowerShell Profile Loaded!" -ForegroundColor Cyan
