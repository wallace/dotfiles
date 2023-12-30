# dotfiles

Here lie my dotfiles. I'm using gnu-stow to manage installation of the dotfiles.
See http://brandon.invergo.net/news/2012-05-26-using-gnu-stow-to-manage-your-dotfiles.html for more information.

## Setup

### Prerequisites

    $ brew bundle # installs all things listed in Brewfile
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
    $ # install latest node version and set to global in nodenv
    $ curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    $ # run PlugInstall from within vim
    $ mkdir ~/.vim-tmp # add vim backup directory to prevent errors like https://stackoverflow.com/questions/8428210/cannot-create-backup-fileadd-to-overwrite
    $ mkdir ~/.gitshots # add for git picture capture on git actions

## TODOs

 - [ ] only run rubocop pre-commit hook when rb files are being committed
 - [ ] switch to neovim??
 - [ ] add copilot vim integration

