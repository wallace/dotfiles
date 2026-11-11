#!/bin/bash
# https://docs.github.com/en/codespaces/customizing-your-codespace/personalizing-codespaces-for-your-account

# Configuration
GIT_EMAIL="${CODESPACE_GIT_EMAIL:-jonathan.wallace@gmail.com}"
# Where this repo actually lives. Codespaces clones it somewhere under
# /workspaces rather than ~/dotfiles, so resolve it from the script instead of
# hardcoding a path.
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  sudo apt-get install -y -q fzf stow ripgrep direnv tmux zsh universal-ctags zsh-autosuggestions jq

  # Claude Code memory, one private repo per project (claude/bin/claude-memory-sync
  # explains the layout and the per-project token). Early, straight after the
  # packages it needs (jq), so a failure further down cannot skip it. The claude package is not
  # stowed here, since its settings carry desktop-only hooks, so link the script
  # and add only its two hooks.
  fancy_echo "Setting up Claude memory sync"
  mkdir -p "$HOME/bin" "$HOME/.claude"
  ln -sf "$DOTFILES_DIR/claude/bin/claude-memory-sync" "$HOME/bin/claude-memory-sync"
  claude_settings="$HOME/.claude/settings.json"
  [ -s "$claude_settings" ] || echo '{}' > "$claude_settings"
  if ! grep -q claude-memory-sync "$claude_settings"; then
    jq '.hooks.SessionStart += [{"hooks":[{"type":"command","command":"$HOME/bin/claude-memory-sync pull","timeout":60}]}]
      | .hooks.SessionEnd += [{"hooks":[{"type":"command","command":"$HOME/bin/claude-memory-sync push","timeout":60}]}]' \
      "$claude_settings" > "$claude_settings.tmp" && mv "$claude_settings.tmp" "$claude_settings"
  fi
  # Fetch now if the token is already in this environment; if not, the first
  # Claude session's SessionStart hook does it.
  project_dir="/workspaces/${GITHUB_REPOSITORY#*/}"
  if [ -d "$project_dir" ]; then
    (cd "$project_dir" && "$HOME/bin/claude-memory-sync" pull </dev/null) || true
  fi

  if ! command -v delta &>/dev/null; then
    fancy_echo "Installing git-delta"
    # Pin a known-good version rather than auto-resolving "latest" so a
    # compromised or malformed release can't pull in an arbitrary .deb.
    DELTA_VERSION="${DELTA_VERSION:-0.18.2}"
    DELTA_SHA256="${DELTA_SHA256:-}"   # optional pin; set in CI/automation
    DELTA_DEB_URL="https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_amd64.deb"
    curl -fsSL "$DELTA_DEB_URL" -o /tmp/git-delta.deb
    if [ -n "$DELTA_SHA256" ]; then
      echo "$DELTA_SHA256  /tmp/git-delta.deb" | sha256sum -c -
    fi
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

  locals=( "vim" "ruby_debugger" "git" "readline" "tmux" "zsh" "base16-shell" "scripts" "copilot-cli" "irb" "rspec" "rubygems" "kitty" )
  for i in "${locals[@]}"
  do
    # No -q: stow 2.4 (Debian 13, today's codespace images) rejects it as an
    # unknown option, and under set -e that ended the whole install here.
    stow -t $HOME $i
  done

  # ~/.gitconfig is deliberately not stowed -- see git/.stow-local-ignore for
  # why. Nothing else creates it, so write the per-machine shim that pulls in
  # the tracked config. Without this the git package has no entry point and
  # none of its settings apply.
  if [ ! -e "$HOME/.gitconfig" ]; then
    fancy_echo "Writing ~/.gitconfig shim"
    printf '[include]\n\tpath = %s/git/.gitconfig\n' "$DOTFILES_DIR" > "$HOME/.gitconfig"
  fi

  fancy_echo "Installing vim plugins"
  # Some codespace images ship without vim; under set -e the plugin step
  # then ended the install before Claude Code and the gems.
  if command -v vim &>/dev/null; then
    if [ -e "$HOME"/.vim/autoload/plug.vim ]; then
      vim -E -s +PlugUpgrade +qa
    else
      curl -fLo "$HOME"/.vim/autoload/plug.vim --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    fi
    mkdir -p ~/.vim-tmp # add vim backup directory to prevent errors like https://stackoverflow.com/questions/8428210/cannot-create-backup-fileadd-to-overwrite
    vim +PlugUpdate +PlugClean! +qa
  else
    fancy_echo "No vim in this image; skipping vim plugins"
  fi

  fancy_echo "Installing Claude Code and gems (parallel)"
  if ! command -v claude &>/dev/null; then
    curl -fsSL https://claude.ai/install.sh | bash &
  fi
  # gem is not on PATH here when Ruby comes from mise or rbenv (they activate in
  # interactive shells only), and sudo's secure_path never has it, so the old
  # `sudo gem install` failed with "gem: command not found". Find it, and use
  # sudo only when its gem directory is not ours to write.
  install_gems() {
    local gem_bin candidate
    gem_bin="$(command -v gem || true)"
    for candidate in "$HOME/.local/share/mise/shims/gem" "$HOME/.rbenv/shims/gem" /usr/local/rvm/rubies/default/bin/gem; do
      [ -n "$gem_bin" ] && break
      [ -x "$candidate" ] && gem_bin="$candidate"
    done
    # A shim calls its manager (mise) and gem calls ruby, both by name, so their
    # directories go on PATH too. This runs in a background subshell, so the
    # change stays here.
    [ -n "$gem_bin" ] && PATH="$(dirname "$gem_bin"):$HOME/.local/bin:$PATH"
    if [ -z "$gem_bin" ]; then
      fancy_echo "No Ruby in this image; skipping gems"
      return 0
    fi
    if [ -w "$("$gem_bin" environment gemdir)" ]; then
      "$gem_bin" install git_remote_branch ripper-tags
    else
      sudo "$gem_bin" install git_remote_branch ripper-tags
    fi
  }
  install_gems &
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
