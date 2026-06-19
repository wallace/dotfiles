export ZSH="$HOME/.oh-my-zsh"

# Consolidate all PATH exports at the beginning
export BUN_INSTALL="$HOME/.bun"
export PATH="$HOME/bin:$PATH"
export PATH="$BUN_INSTALL/bin:$PATH"
export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.rbenv/shims:$PATH"
export PATH="$HOME/.nodenv/shims:$PATH"
export PATH="/opt/homebrew/opt/mysql@5.7/bin:$PATH"
export GOPATH="$HOME/go"
export PATH="$PATH:${GOPATH}/bin"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
export PATH="$PATH:$HOME/.maestro/bin"
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH="$PATH:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools"

# Check if system is Linux/Ubuntu (only init brew if installed)
if [[ $(uname) == "Linux" ]] && [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

ZSH_THEME=""

# Pure prompt setup
if [[ $(uname) == "Linux" ]]; then
    [ -d "/home/linuxbrew/.linuxbrew/share/zsh/site-functions" ] \
        && fpath+=("/home/linuxbrew/.linuxbrew/share/zsh/site-functions")
    [ -d "$HOME/.zsh/pure" ] && fpath+=("$HOME/.zsh/pure")
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

# Lazy load nodenv
nodenv() {
    unset -f nodenv
    eval "$(nodenv init -)"
    nodenv "$@"
}

# Use rvm in Codespaces, rbenv (lazy) everywhere else
if [ -n "$CODESPACES" ]; then
    [[ -s "$HOME/.rvm/scripts/rvm" ]] && source "$HOME/.rvm/scripts/rvm"
else
    rbenv() {
        unset -f rbenv
        eval "$(rbenv init -)"
        rbenv "$@"
    }
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

export EDITOR=nvim

# Aliases
if [[ $(uname) == "Darwin" ]]; then
    alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
fi

# Base16 Shell with existence check
BASE16_SHELL="$HOME/.config/base16-shell/"
if [ -s "$BASE16_SHELL/profile_helper.sh" ]; then
    eval "$("$BASE16_SHELL/profile_helper.sh")"
fi

# Less configuration
export LESS="-RSM~gIsw"

# FZF configuration (with more focused search)
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git/*"'
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
    SSH_BRIDGE_LOG="$HOME/.ssh/agent.sock.log"

    if ! ss -a 2>/dev/null | grep -q "$SSH_AUTH_SOCK"; then
        mkdir -p "$(dirname "$SSH_AUTH_SOCK")"
        rm -f "$SSH_AUTH_SOCK"
        (setsid socat UNIX-LISTEN:"$SSH_AUTH_SOCK",fork EXEC:"$NPIPERELAY -ei -s //./pipe/openssh-ssh-agent" &) >>"$SSH_BRIDGE_LOG" 2>&1
    fi
fi

# SSH Agent: macOS uses the launchd-managed agent (SSH_AUTH_SOCK is set
# automatically). On Linux, rely on systemd --user or your DE's agent.
# WSL2 handling above is the only case where we manage the socket ourselves.

# bun completions
[ -s "/Users/jonathanwallace/.bun/_bun" ] && source "/Users/jonathanwallace/.bun/_bun"

# bun
export DOTNET_ROOT="/opt/homebrew/opt/dotnet/libexec"

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
export TRANSCRIPT_ROSTER_DIR="$HOME/Documents/first-obsidian/03-Projects/transcript-pipeline"
export VOICE_PIPELINE_PYTHON="$HOME/.venvs/voice-pipeline/bin/python"
[ -f "$HOME/.config/voice-pipeline/env" ] && { set -a; source "$HOME/.config/voice-pipeline/env"; set +a; }

# ─── Copilot CLI: lean by default, load MCP servers & skills on demand ────────
#
# Default session loads NO MCP servers and NO custom skills. Sources & switches:
#   - User MCP servers   : ~/.copilot/mcp-config.json is empty (all moved to snippets)
#   - Built-in MCP        : github-mcp-server / computer-use -> off via the alias below
#   - Port MCP + skill    : port@agent-skills plugin disabled in ~/.copilot/settings.json
#   - Custom skills       : ~/.copilot/skills/ is empty (all moved to the library)
#   - Repo workspace MCP  : .github/mcp.json in a repo still loads; silence per-session with
#                           `copilot --disable-mcp-server <name>` (e.g. github-agentic-workflows)
#
# Library locations:
#   MCP snippets : ~/.copilot/snippets/mcp/<name>.json   (one server each)
#   Skills       : ~/.copilot/snippets/skills/<name>/    (each has a SKILL.md)
#
# Load things on demand with the copilot-load helper (~/.local/bin/copilot-load):
#   copilot-load list                                  # show available MCP + skills
#   copilot-load run --mcp datadog,splunk              # start with these MCP servers
#   copilot-load run --skill identify-noisy-neighbor   # start with this skill
#   copilot-load run --mcp datadog --skill adversarial-review -- -p "..."  # args after --
#
# Add new items interactively (prompts for details):
#   copilot-load add-mcp        # name, http/local, url or command+args, headers/env
#   copilot-load add-skill      # name, then copy a folder or scaffold a new SKILL.md
#
# Mid-session toggles inside Copilot: /mcp (servers), /skills (skills), /plugin (Port),
# and /env to see everything currently loaded.
#
# Restore-all (undo the lean defaults): copy back the newest backups -
#   ~/.copilot/mcp-config.json.bak.*  and  ~/.copilot/settings.json.bak.*
alias copilot='copilot --disable-builtin-mcps'
