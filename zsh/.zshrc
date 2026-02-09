zmodload zsh/zprof
export ZSH="$HOME/.oh-my-zsh"

# Consolidate all PATH exports at the beginning
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.rbenv/shims:$PATH"
export PATH="$HOME/.nodenv/shims:$PATH"
export PATH="/opt/homebrew/opt/mysql@5.7/bin:$PATH"
export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"
export GOPATH="$HOME/go"
export PATH="$PATH:${GOPATH}/bin"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
export PATH="$PATH:$HOME/.maestro/bin"
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH="$PATH:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools"

# Check if system is Linux/Ubuntu
if [[ $(uname) == "Linux" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

ZSH_THEME=""

# Pure prompt setup
if [[ $(uname) == "Linux" ]]; then
    fpath+=("/home/linuxbrew/.linuxbrew/share/zsh/site-functions")
else
    fpath+=("/opt/homebrew/share/zsh/site-functions")
fi
autoload -U promptinit; promptinit
prompt pure

plugins=(git)

source $ZSH/oh-my-zsh.sh

# Set a larger history size (after oh-my-zsh loads)
HISTSIZE=200000
SAVEHIST=200000

# Lazy load nvm
export NVM_DIR="$HOME/.nvm"
nvm() {
    unset -f nvm
    [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && source "/opt/homebrew/opt/nvm/nvm.sh"
    nvm "$@"
}

eval "$(nodenv init -)"
## Lazy load nodenv
#nodenv() {
#    unset -f nodenv
#    eval "$(nodenv init -)"
#    nodenv "$@"
#}

# Use rvm in Codespaces, rbenv everywhere else
if [ -n "$CODESPACES" ]; then
    [[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"
else
    eval "$(rbenv init -)"
fi

# Lazy load pyenv
pyenv() {
    unset -f pyenv
    eval "$(pyenv init -)"
    pyenv "$@"
}

# direnv (cannot be lazy loaded - needs to hook every prompt)
if command -v direnv &> /dev/null; then
    eval "$(direnv hook zsh)"
fi

export EDITOR=`which nvim`

# Aliases
alias gpfl="ggfl"

# Run rubocop over files that differ from the master branch
alias mastrbc="git diff-tree -r --no-commit-id --name-only master@\{u\} head | xargs ls -1 2>/dev/null | xargs rubocop --force-exclusion"

# Run rubocop over files that differ from the main branch
alias mainrbc="git diff-tree -r --no-commit-id --name-only main@\{u\} head | xargs ls -1 2>/dev/null | xargs rubocop --force-exclusion"

# Run rubocop over files that differ from the current branch
alias currrbc="git diff-tree -r --no-commit-id --name-only @\{u\} head | xargs rubocop --force-exclusion"

# Run rubocop over uncommitted files
alias nottrbc="git ls-files -m | xargs ls -1 2>/dev/null | grep '\.rb$' | xargs rubocop --force-exclusion"

# Base16 Shell with existence check
BASE16_SHELL="$HOME/.config/base16-shell/"
if [ -s "$BASE16_SHELL/profile_helper.sh" ]; then
    eval "$("$BASE16_SHELL/profile_helper.sh")"
fi

# Less configuration
export LESS="-RSM~gIsw"

# FZF configuration (with more focused search)
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export FZF_DEFAULT_COMMAND='rg --files --glob "!.git/*"'
export FZF_COMPLETION_TRIGGER=',,'

# Vi mode configuration
bindkey -v
export KEYTIMEOUT=1
bindkey '^R' history-incremental-search-backward
bindkey -M vicmd v edit-command-line

# Additional environment variables
export JAVA_HOME=/Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home
export GEOS_LIBRARY_PATH=/opt/homebrew/lib
export COMPOSE_PROFILES="tourneys,frontend"

# Source codespaces related things if we are in one
[ -n "$CODESPACES" ] && source $HOME/.zsh/codespaces.zsh

# Windows SSH Agent bridge (WSL2 only)
if [[ $(uname -r) == *"WSL2"* ]]; then
    export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
    NPIPERELAY="/mnt/c/Users/jonat/go/bin/npiperelay.exe"

    if ! ss -a 2>/dev/null | grep -q "$SSH_AUTH_SOCK"; then
        mkdir -p "$(dirname $SSH_AUTH_SOCK)"
        rm -f "$SSH_AUTH_SOCK"
        (setsid socat UNIX-LISTEN:"$SSH_AUTH_SOCK",fork EXEC:"$NPIPERELAY -ei -s //./pipe/openssh-ssh-agent" &) >/dev/null 2>&1
    fi
fi

# SSH Agent configuration (macOS/Linux)
if [ -z "$SSH_AUTH_SOCK" ]; then
   # Check for a currently running instance of the agent
   RUNNING_AGENT="`ps -ax | grep 'ssh-agent -s' | grep -v grep | wc -l | tr -d '[:space:]'`"
   if [ "$RUNNING_AGENT" = "0" ]; then
        # Launch a new instance of the agent
        ssh-agent -s &> $HOME/.ssh/ssh-agent
   fi
   eval `cat $HOME/.ssh/ssh-agent`
fi

# bun completions
[ -s "/Users/jonathanwallace/.bun/_bun" ] && source "/Users/jonathanwallace/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
export DOTNET_ROOT="/opt/homebrew/opt/dotnet/libexec"
zprof
export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"

# Git rebase function - checkout main, pull, checkout branch, rebase main, and force push
grebase() {
    if [ -z "$1" ]; then
        echo "Usage: grebase <branch-name>"
        echo "Example: grebase wallace/axts-9-display-pain-level-in-web"
        return 1
    fi

    local branch="$1"
    echo "🔄 Checking out main..."
    git co main && \
    echo "⬇️  Pulling latest changes..." && \
    git pull && \
    echo "🔄 Checking out branch: $branch..." && \
    git co "$branch" && \
    echo "🔀 Rebasing $branch onto main..." && \
    git rebase main && \
    echo "⬆️  Force pushing..." && \
    ggfl
}
