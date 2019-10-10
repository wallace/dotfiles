# dotfiles

Here lie my dotfiles. I'm using gnu-stow to manage installation of the dotfiles.
See http://brandon.invergo.net/news/2012-05-26-using-gnu-stow-to-manage-your-dotfiles.html for more information.

## Setup

### Prerequisites

    $ brew install stow rbenv nodenv readline neovim/neovim/neovim vim git tmux reattach-to-user-namespace fzf hub ripgrep bash-completion
    $ brew install neomutt urlview notmuch offlineimap msmtp
    $ brew install --HEAD universal-ctags/universal-ctags/universal-ctags
    $ stow ctags
    $ sudo curl -L https://raw.githubusercontent.com/docker/compose/1.24.1/contrib/completion/bash/docker-compose -o /usr/local/etc/bash_completion.d/docker-compose
    $ stow base16-shell
    $ stow bash
    $ git clone --depth=1 https://github.com/Bash-it/bash-it.git ~/dotfiles/bash_it/.bash_it
    $ stow bash_it
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
    $ # install latest node version and set to global in nodenv
    $ curl -fLo ~/.local/share/nvim/site/autoload/plug.vim --create-dirs \
      https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    $ # run PlugInstall from within nvim
    $ mkdir ~/.vim-tmp # add vim backup directory to prevent errors like https://stackoverflow.com/questions/8428210/cannot-create-backup-fileadd-to-overwrite
