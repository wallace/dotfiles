# this is needed because by default SHELL=/bin/bash even after changing the
# default shell thus making tmux start bash
export SHELL=/bin/zsh

# Codespace may not have terminfo for the local terminal (e.g. xterm-kitty)
if ! infocmp "$TERM" &>/dev/null 2>&1; then
    export TERM=xterm-256color
fi

ZSH_THEME="codespaces"
source $ZSH/oh-my-zsh.sh
