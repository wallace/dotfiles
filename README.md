# dotfiles

Here lie my dotfiles. I'm using gnu-stow to manage installation of the dotfiles.
See http://brandon.invergo.net/news/2012-05-26-using-gnu-stow-to-manage-your-dotfiles.html for more information.

## Setup

### Prerequisites

#### macOS

    $ # Install Homebrew if not already installed
    $ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    $ brew bundle # installs all things listed in Brewfile

#### WSL2 Ubuntu / Linux

    $ # Install Homebrew (Linuxbrew)
    $ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    $ # Add brew to PATH (add to ~/.profile or ~/.bashrc for persistence)
    $ eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    $ brew bundle # installs all things listed in Brewfile
    $ # Note: reattach-to-user-namespace and ical-buddy are macOS-only and will be skipped

#### Windows (Native)

For native Windows usage (not WSL), you can use the git configuration directly.

Run these commands in PowerShell:

    # Install Git for Windows if not already installed
    winget install Git.Git

    # Install GitHub CLI for credential handling
    winget install GitHub.cli
    gh auth login

    # Navigate to the dotfiles directory
    cd path\to\dotfiles

    # Copy git config to user home directory
    # Remove existing files if they exist (handles symlinks/junctions)
    Remove-Item $env:USERPROFILE\.gitconfig -Force -ErrorAction SilentlyContinue
    Remove-Item $env:USERPROFILE\.gitconfig-windows -Force -ErrorAction SilentlyContinue
    Copy-Item .\git\.gitconfig $env:USERPROFILE\.gitconfig
    Copy-Item .\git\.gitconfig-windows $env:USERPROFILE\.gitconfig-windows

    # Create vim backup directory
    New-Item -ItemType Directory -Force -Path $env:USERPROFILE\.vim-tmp

Optional tools:

    winget install dandavison.delta  # Better diff viewer
    winget install junegunn.fzf      # Fuzzy finder for branch switching

PowerShell setup (zsh-like experience):

    # Install Oh-My-Posh for prompt theming
    winget install JanDeDobbeleer.OhMyPosh

    # Install PowerShell modules (no admin rights required with -Scope CurrentUser)
    Install-Module PSReadLine -Scope CurrentUser -Force
    Install-Module Terminal-Icons -Scope CurrentUser -Repository PSGallery -Force
    Install-Module PSFzf -Scope CurrentUser -Repository PSGallery -Force
    Install-Module posh-git -Scope CurrentUser -Force
    Install-Module z -Scope CurrentUser -Force

    # Install PowerShell profile using hardlink (from the dotfiles directory)
    # Note: Hardlinks work like symlinks but don't require admin privileges
    New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\Documents\PowerShell"
    New-Item -ItemType HardLink -Path "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" -Target "$PWD\powershell\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" -Force

#### All Platforms

    $ # set up oh-my-zsh
    $ sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    $ # remove default zshrc from oh-my-zsh
    $ rm ~/.zshrc

### Steps

    $ stow zsh
    $ stow ctags
    $ stow base16-shell
    $ stow git
    $ stow mutt
    $ stow notmuch
    $ stow offlineimap
    $ stow rbenv
    $ stow readline
    $ stow rspec
    $ stow ruby_debugger
    $ stow rubygems
    $ stow scripts
    $ stow tmux
    $ stow vim
    $ stow irb
    $ stow nvim
    $ stow obsidian
    $ # install latest node version and set to global in nodenv
    $ curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    $ # run PlugInstall from within vim
    $ mkdir ~/.vim-tmp # add vim backup directory to prevent errors like https://stackoverflow.com/questions/8428210/cannot-create-backup-fileadd-to-overwrite
    $ mkdir ~/.gitshots # add for git picture capture on git actions

## Platform Notes

### macOS-only packages
The following packages are only installed on macOS (no Linux bottles available):
- `reattach-to-user-namespace` - Required for tmux copy/paste integration on macOS
- `ical-buddy` - Calendar integration for Alfred workflow

### WSL2 / Linux considerations
- Ensure brew is in your PATH by adding `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"` to your shell profile
- tmux copy/paste works differently on Linux; `reattach-to-user-namespace` is not needed

### Windows (Native) considerations
- The git configuration uses conditional includes (`includeIf`) to load platform-specific settings
- On Windows, `.gitconfig-windows` is automatically included when working in paths starting with `C:/`
- Uses VS Code as the default editor and merge tool
- GitHub CLI (`gh`) handles credential management
- Some shell-based aliases (like `find-merge`, `show-merge`) require Git Bash or WSL
- Line endings are set to `autocrlf = true` for Windows compatibility

### GitHub Codespaces

This repo is configured as a [personal dotfiles repo for Codespaces](https://docs.github.com/en/codespaces/customizing-your-codespace/personalizing-codespaces-for-your-account).

1. Go to **Settings > Codespaces > Dotfiles** and select this repository
2. `install.sh` runs automatically when a Codespace is created

The install script will:
- Switch the default shell to zsh and install Oh-My-Zsh
- Install tools via Homebrew (fzf, ctags, delta, ripgrep, etc.)
- Stow dotfiles for vim, git, zsh, tmux, and more
- Install vim plugins and Ruby gems

To override the default git email, set the `CODESPACE_GIT_EMAIL` environment variable in your
[Codespaces secrets](https://github.com/settings/codespaces). Otherwise it defaults to `jonathan.wallace@gmail.com`.

To create a new Codespace from the CLI:

    $ scripts/bin/new-codespace.sh <branch>

## TODOs

 - [ ] switch to neovim??
 - [ ] add copilot vim integration
