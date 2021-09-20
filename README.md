# dotfiles

Here lie my dotfiles. I'm using gnu-stow to manage installation of the dotfiles.
See http://brandon.invergo.net/news/2012-05-26-using-gnu-stow-to-manage-your-dotfiles.html for more information.

## Setup

### Prerequisites

    $ brew bundle # installs all things listed in Brewfile
    $ brew install --HEAD universal-ctags/universal-ctags/universal-ctags
    $ chsh -s /bin/zsh
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
    $ stow nvim
    $ stow irb
    $ # install latest node version and set to global in nodenv
    $ curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
      https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    $ # run PlugInstall from within nvim
    $ mkdir ~/.vim-tmp # add vim backup directory to prevent errors like https://stackoverflow.com/questions/8428210/cannot-create-backup-fileadd-to-overwrite
    $ mkdir ~/.gitshots # add for git picture capture on git actions
