#!/bin/bash

exec > >(tee -i $HOME/dotfiles_install.log)
exec 2>&1
set -x

fancy_echo() {
  local fmt="$1"; shift

  # shellcheck disable=SC2059
  printf "\\n$fmt\\n" "$@"
}

get() {
  curl -fLo $1 --create-dirs $2
}

if [ "$CODESPACES" == "true" ]; then
  fancy_echo "Installing apt-get packages"
  apt-get -y install fzf universal-ctags neovim zsh-autosuggestions stow

  fancy_echo "In codespaces! Installing dotfiles"
  mv $HOME/.zshrc $HOME/.zshrc.old         # let's use mine
  mv $HOME/.gitconfig $HOME/.gitconfig.old # let's use mine

  locals=( "nvim"  "vim" "zsh" "ruby_debugger" "git" "readline" "tmux" )
  for i in "${locals[@]}"
  do
    stow -t $HOME $i
  done

  #fancy_echo "Getting thoughtbot dotfiles"
  #get $HOME/.vimrc https://raw.githubusercontent.com/thoughtbot/dotfiles/master/vimrc
  #get $HOME/.vimrc.bundles https://raw.githubusercontent.com/thoughtbot/dotfiles/master/vimrc.bundles
  #get $HOME/.aliases https://raw.githubusercontent.com/thoughtbot/dotfiles/master/aliases
  #get $HOME/.gitconfig https://raw.githubusercontent.com/thoughtbot/dotfiles/master/gitconfig
  #get $HOME/.gitmessage https://raw.githubusercontent.com/thoughtbot/dotfiles/master/gitmessage
  #get $HOME/.gitignore https://raw.githubusercontent.com/thoughtbot/dotfiles/master/gitignore
  #get $HOME/.tmux.conf https://raw.githubusercontent.com/thoughtbot/dotfiles/master/tmux.conf

  fancy_echo "Installing vim plugins"
  if [ -e "$HOME"/.vim/autoload/plug.vim ]; then
    vim -E -s +PlugUpgrade +qa
  else
    curl -fLo "$HOME"/.vim/autoload/plug.vim --create-dirs \
      https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  fi
  mkdir ~/.vim-tmp # add vim backup directory to prevent errors like https://stackoverflow.com/questions/8428210/cannot-create-backup-fileadd-to-overwrite
  # vim +PlugUpdate +PlugClean! +qa

  #fancy_echo "Sourcing aliases"
  #[[ -f ~/.aliases ]] && source ~/.aliases
  #echo "alias g='git'" >> "$HOME"/.bashrc
  #echo "export EDITOR=vim" >> "$HOME"/.bashrc

  ##fancy_echo "Installing gems"
  ##gem install ripper-tags && ripper-tags -R

  fancy_echo "Switching to zsh"
  if ! grep -q "root.*/bin/zsh" /etc/passwd
  then
    chsh -s /bin/zsh root
  fi

  fancy_echo "All done"
else
  fancy_echo "Not running in a codespace"
fi
