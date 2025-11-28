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

## TODOs

 - [ ] only run rubocop pre-commit hook when rb files are being committed
 - [ ] switch to neovim??
 - [ ] add copilot vim integration
 - [x] update for linux
