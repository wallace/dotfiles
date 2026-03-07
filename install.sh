#!/bin/bash
# https://docs.github.com/en/codespaces/customizing-your-codespace/personalizing-codespaces-for-your-account

# Configuration
GIT_EMAIL="${CODESPACE_GIT_EMAIL:-jonathan.wallace@gmail.com}"

# let's have our own log
exec > >(tee -i $HOME/dotfiles_install.log)
exec 2>&1
set -ex

fancy_echo() {
  local fmt="$1"; shift

  # shellcheck disable=SC2059
  printf "\\n$fmt\\n" "$@"
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
  echo -e "[user]\n  email = ${GIT_EMAIL}" >> "/home/$USER/.dotoverrides/gitconfig"

  fancy_echo "Installing packages via apt"
  sudo apt-get update -qq
  sudo apt-get install -y -q fzf stow ripgrep direnv tmux zsh universal-ctags zsh-autosuggestions

  if ! command -v delta &>/dev/null; then
    fancy_echo "Installing git-delta"
    DELTA_DEB_URL=$(curl -fsSL "https://api.github.com/repos/dandavison/delta/releases/latest" \
      | grep "browser_download_url.*amd64.deb" | cut -d '"' -f 4)
    curl -fsSL "$DELTA_DEB_URL" -o /tmp/git-delta.deb
    sudo dpkg -i /tmp/git-delta.deb && rm /tmp/git-delta.deb
  fi

  if [ ! -d "$HOME/.zsh/pure" ]; then
    fancy_echo "Installing pure prompt"
    git clone --quiet https://github.com/sindresorhus/pure.git "$HOME/.zsh/pure"
  fi

  fancy_echo "Installing Oh-My-Zsh"
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
    rm -f ~/.zshrc  # remove OMZ default before stow
  fi

  fancy_echo "Configuring rvm to auto-install Ruby versions"
  echo "rvm_autoinstall_on_use_flag=1" >> "$HOME/.rvmrc"

  fancy_echo "Installing dotfiles"
  mv $HOME/.gitconfig $HOME/.gitconfig.old 2>/dev/null || true
  mv $HOME/.zshrc $HOME/.zshrc.old 2>/dev/null || true

  locals=( "vim" "ruby_debugger" "git" "readline" "tmux" "zsh" "base16-shell" "scripts" "irb" "rspec" "rubygems" )
  for i in "${locals[@]}"
  do
    stow -q -t $HOME $i
  done

  fancy_echo "Installing vim plugins"
  if [ -e "$HOME"/.vim/autoload/plug.vim ]; then
    vim -E -s +PlugUpgrade +qa
  else
    curl -fLo "$HOME"/.vim/autoload/plug.vim --create-dirs \
      https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  fi
  mkdir -p ~/.vim-tmp # add vim backup directory to prevent errors like https://stackoverflow.com/questions/8428210/cannot-create-backup-fileadd-to-overwrite
  vim +PlugUpdate +PlugClean! +qa

  fancy_echo "Installing Claude Code and gems (parallel)"
  if ! command -v claude &>/dev/null; then
    curl -fsSL https://claude.ai/install.sh | bash &
  fi
  sudo gem install git_remote_branch ripper-tags &
  wait

  # Run pre-push git commit hook to check code owners
  if [ -d "/workspaces/github" ]; then
    echo "Setting up commit hook for codeowners"
    cd /workspaces/github && ln -s $(pwd)/script/git-hooks/pre-push .git/hooks/pre-push
  fi

  fancy_echo "All done"
else
  fancy_echo "Not running in a codespace"
fi
