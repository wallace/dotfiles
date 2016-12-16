# dotfiles

Here lie my dotfiles. I'm using gnu-stow to manage installation of the dotfiles.
See http://brandon.invergo.net/news/2012-05-26-using-gnu-stow-to-manage-your-dotfiles.html for more information.

## Setup

### Prerequisites

    $ brew install stow rbenv readline neovim/neovim/neovim vim git tmux reattach-to-user-namespace fzf
    $ stow base16-shell
    $ stow bash
    $ git clone --depth=1 https://github.com/Bash-it/bash-it.git ~/dotfiles/bash_it/.bash_it
    $ stow bash_it
    $ stow git
    $ stow rbenv
    $ stow readline
    $ stow rspec
    $ stow ruby_debugger
    $ stow rubygems
    $ stow scripts
    $ stow tmux
    $ stow vim

### sd

    # clone to Documents/projects/sd
    $ git clone git@github.com:rylnd/sd ~/Documents/projects/sd
