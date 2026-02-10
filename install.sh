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

  fancy_echo "Installing Homebrew"
  if ! command -v brew &> /dev/null; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi

  fancy_echo "Installing packages via Homebrew"
  brew install fzf universal-ctags zsh-autosuggestions stow git-delta ripgrep pure direnv tmux

  fancy_echo "Installing Oh-My-Zsh"
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
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
    stow -t $HOME $i
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

  fancy_echo "Installing Claude Code"
  npm install -g @anthropic-ai/claude-code

  fancy_echo "Installing gems"
  sudo gem install git_remote_branch ripper-tags && ripper-tags -R --exclude=vendor

  # Run pre-push git commit hook to check code owners
  if [ -d "/workspaces/github" ]; then
    echo "Setting up commit hook for codeowners"
    cd /workspaces/github && ln -s $(pwd)/script/git-hooks/pre-push .git/hooks/pre-push
  fi

  fancy_echo "All done"
else
  fancy_echo "Not running in a codespace"
fi
