#!/bin/bash
# https://docs.github.com/en/codespaces/customizing-your-codespace/personalizing-codespaces-for-your-account

# let's have our own log
exec > >(tee -i $HOME/dotfiles_install.log)
exec 2>&1
set -ex

fancy_echo() {
  local fmt="$1"; shift

  # shellcheck disable=SC2059
  printf "\\n$fmt\\n" "$@"
}

get() {
  curl -fLo $1 --create-dirs $2
}

# default to codespace user
if [ -z "${USER}" ]; then
  USER=vscode
fi

if [ "$CODESPACES" == "true" ]; then
  fancy_echo "Switching to zsh"
  if ! grep -q "${USER}.*/bin/zsh" /etc/passwd
  then
    sudo chsh -s /bin/zsh ${USER}
  fi

  # set up org specific overrides
  fancy_echo "Installing GitHub codespace related dotoverrides configs..."
  mkdir -p "/home/$USER/.dotoverrides"
  echo -e "[user]\n  email = wallace@github.com" >> "/home/$USER/.dotoverrides/gitconfig"

  fancy_echo "In codespaces! Installing apt-get packages"
  sudo apt-get -y install fzf universal-ctags zsh-autosuggestions stow

  fancy_echo "Installing git-delta"
  wget https://github.com/dandavison/delta/releases/download/0.8.3/git-delta_0.8.3_amd64.deb
  sudo dpkg -i git-delta_0.8.3_amd64.deb

  fancy_echo "Installing dotfiles"
  mv $HOME/.gitconfig $HOME/.gitconfig.old # let's use mine
  mv $HOME/.zshrc $HOME/.zshrc.old         # let's use mine

  locals=( "vim" "ruby_debugger" "git" "readline" "tmux" "zsh" "base16-shell" )
  for i in "${locals[@]}"
  do
    stow -t $HOME $i
  done

  fancy_echo "Installing vim plugins"
  if [ -e "$HOME"/.vim/autoload/plug.vim ]; then
    vim -E -s +PlugUpgrade +qa
  else
    curl -fLo "$HOME"/.vim/autoload/plug.vim --create-dirs \
      https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  fi
  mkdir ~/.vim-tmp # add vim backup directory to prevent errors like https://stackoverflow.com/questions/8428210/cannot-create-backup-fileadd-to-overwrite
  vim +PlugUpdate +PlugClean! +qa

  #fancy_echo "Sourcing aliases"
  #[[ -f ~/.aliases ]] && source ~/.aliases
  #echo "alias g='git'" >> "$HOME"/.bashrc
  #echo "export EDITOR=vim" >> "$HOME"/.bashrc

  fancy_echo "Installing gems"
  sudo gem install git_remote_branch ripper-tags && ripper-tags -R --exclude=vendor

  # Run pre-push git commit hook to check code owners
  echo "Setting up commit hook for codeowners"
  cd /workspaces/github && ln -s $(pwd)/script/git-hooks/pre-push .git/hooks/pre-push

  fancy_echo "All done"
else
  fancy_echo "Not running in a codespace"
fi
