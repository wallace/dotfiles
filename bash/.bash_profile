# Homebrew first: on Linux it lives outside the default PATH, and almost
# everything below (nvim, rbenv, nodenv, delta) is installed through it. Without
# this, a login bash finds none of them and each init line below fails loudly.
# Mirrors the same block in zsh/.zshrc.
if [ "$(uname)" = "Linux" ] && [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# from http://richardhulse.blogspot.com/2008/06/using-git.html
# this should let us use __git_ps1 in our prompt
# Guarded: this is stowed by the git package, which may not be stowed yet.
# shellcheck source=/dev/null
[ -r ~/.git-completion.bash ] && source ~/.git-completion.bash

# export PS1='\w$(__git_ps1 "(%s)") $ '

#bash_prompt()
#{
  #arrow="\[\e[0;33m\]»\[\e[m\]"
  #path="\[\e[0;32m\]\w\[\e[m\]"
  #if [ -n "$SSH_CLIENT" ]; then
    #host="\[\e[0;35m\]\h:\[\e[m\] "
  #fi

  #PS1="$host:$path $arrow "
#}
#PROMPT_COMMAND=bash_prompt

set -o vi

alias ..='cd ..'
alias gpom='git pull origin master'
alias gp='git push --force-with-lease'
# hub is deprecated upstream in favour of gh, and is not installed by default
# on Linux. Aliasing unconditionally makes every 'git' invocation fail with
# "hub: command not found" on any box that lacks it.
command -v hub >/dev/null && alias git=hub

# history settings
export HISTFILE=$HOME/.bash_history
export HISTFILESIZE=10000 # amt of cmds in HISTFILE
export HISTSIZE=10000     # amt of cmds in history list of current session
export HISTAPPEND=true    # all bash shells will share the same history file instead of overwritting
# from http://www.numerati.com/2011/08/03/bash-goodies-turbocharging-your-history/
export PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}history -a; history -c; history -r"
export HISTTIMEFORMAT="%F %T "
export HISTCONTROL=ignoredups:erasedups

# Don't directly execute the result of history expansion.
# Add to editing buffer instead.
shopt -s histverify

# Make space perform history expansion.
#bindkey ' ' magic-space '

if command -v brew >/dev/null; then
  _brew_prefix="$(brew --prefix)"
  # shellcheck source=/dev/null
  [ -r "$_brew_prefix/etc/bash_completion" ] && . "$_brew_prefix/etc/bash_completion"
  unset _brew_prefix
fi

# From http://stackoverflow.com/a/2078422/91029
# Author.: Ole J
# Date...: 23.03.2008
# License: Whatever

# Wraps a completion function
# make-completion-wrapper <actual completion function> <name of new func.>
#                         <command name> <list supplied arguments>
# eg.
#   alias agi='apt-get install'
#   make-completion-wrapper _apt_get _apt_get_install apt-get install
# defines a function called _apt_get_install (that's $2) that will complete
# the 'agi' alias. (complete -F _apt_get_install agi)
#
function make-completion-wrapper () {
    local function_name="$2"
    local arg_count=$(($#-3))
    local comp_function_name="$1"
    shift 2
    local function="
function $function_name {
    ((COMP_CWORD+=$arg_count))
    COMP_WORDS=( "$@" \${COMP_WORDS[@]:1} )
    "$comp_function_name"
    return 0
}"
    eval "$function"
}
# and now the commands that are specific to this SO question
#alias gco='git checkout'
#
## we create a _git_checkout_mine function that will do the completion for "gco"
## using the completion function "_git"
#make-completion-wrapper _git _git_checkout_mine git checkout
#
## we tell bash to actually use _git_checkout_mine to complete "gco"
#complete -o bashdefault -o default -o nospace -F _git_checkout_mine gco

# general
alias bi='brew install'

# rails related
alias be='bundle exec'
alias bers='bundle exec rspec spec'
alias beers='bers'

# git related
# alias git=hub
alias gka='gitk --all'
alias gba='git br -a'
alias g='git'
alias s='git st'
alias ga='git add'
alias d='git diff'
alias ds='git diff --staged'
alias ci='git ci'
alias gpo='git pull origin'
alias gpro='git pull --rebase origin'
alias gl='git log'
# http://stevenharman.net/git-clean-delete-already-merged-branches
alias prune='git fetch --prune ; and git branch --merged | grep -v "*" | xargs -n 1 git branch -d'

# switching to neovim
#alias v="nvim"
#alias vi="nvim"
#alias vim="nvim"
#alias vu="nvim +BundleInstall +qall"
#alias vrc="nvim ~/.vimrc"

# Add auto completion for c
alias c='git co'
# _git only exists once bash_completion has loaded; without it the wrapper
# defines a function that calls a command that is not there.
if declare -F _git >/dev/null; then
  make-completion-wrapper _git _git_checkout_mine git checkout
  complete -o bashdefault -o default -o nospace -F _git_checkout_mine c
fi

# An unguarded `which nvim` leaves EDITOR empty when nvim is absent, which
# breaks anything that shells out to $EDITOR rather than falling back.
if command -v nvim >/dev/null; then
  export EDITOR=nvim
elif command -v vim >/dev/null; then
  export EDITOR=vim
fi

# Make less work with RAW ASCII colors
# from http://blog.0x1fff.com/2009/11/linux-tip-color-enabled-pager-less.html
export LESS="-RSM~gIsw"
# R - Raw color codes in output (don't remove color codes)
# S - Don't wrap lines, just cut off too long text
# M - Long prompts ("Line X of Y")
# ~ - Don't show those weird ~ symbols on lines after EOF
# g - Highlight results when searching with slash key (/)
# I - Case insensitive search
# s - Squeeze empty lines to one
# w - Highlight first line after PgDn

alias tmux="TERM=screen-256color-bce tmux"
alias v="nvim"
[ -d "$HOME/.rbenv/bin" ] && export PATH="$HOME/.rbenv/bin:$PATH"
command -v rbenv >/dev/null && eval "$(rbenv init -)"

# shellcheck source=/dev/null
[ -r ~/.bashrc.local ] && source ~/.bashrc.local

# --files: List files that would be searched but do not search
# --no-ignore: Do not respect .gitignore, etc...
# --hidden: Search hidden files and folders
# --follow: Follow symlinks
# --glob: Additional conditions for search (in this case ignore everything in the .git/ folder)
export FZF_DEFAULT_COMMAND='rg --files --no-ignore --hidden --follow --glob "!.git/*"'
export FZF_COMPLETION_TRIGGER=',,'

# https://github.com/neovim/neovim/issues/2048#issuecomment-78045837
# Only the infocmp was guarded before, so 'tic' recompiled the terminfo entry
# on every single shell start. Build and compile once, together.
if [ -n "$TERM" ] && [ ! -f ~/."$TERM".ti ] && command -v infocmp >/dev/null; then
  infocmp "$TERM" | sed 's/kbs=^[hH]/kbs=\\177/' > ~/."$TERM".ti
  command -v tic >/dev/null && tic ~/."$TERM".ti
fi

# Base16 Shell
# Interactive terminals only. This script writes OSC colour-palette escape
# sequences to stdout; sourcing it from a non-interactive shell injects that
# control-character soup into the output of whatever command was actually run,
# which corrupts anything capturing that output.
if [[ $- == *i* ]] && [ -t 1 ]; then
  BASE16_SHELL="$HOME/.config/base16-shell/base16-ocean.dark.sh"
  # shellcheck source=/dev/null
  [[ -s $BASE16_SHELL ]] && source "$BASE16_SHELL"
fi

# macOS-only: ls colour flag. Harmless elsewhere, but keep the intent clear.
[ "$(uname)" = "Darwin" ] && export CLICOLOR=1

# Path to the bash it configuration
export BASH_IT="$HOME/.bash_it"


export SCM_GIT_SHOW_MINIMAL_INFO=true

# Lock and Load a custom theme file
# location /.bash_it/themes/
export BASH_IT_THEME='bobby'

# (Advanced): Change this to the name of your remote repo if you
# cloned bash-it with a remote other than origin such as `bash-it`.
# export BASH_IT_REMOTE='bash-it'

# Your place for hosting Git repos. I use this for private repos.
export GIT_HOSTING='git@git.domain.com'

# Don't check mail when opening terminal.
unset MAILCHECK

# Change this to your console based IRC client of choice.
export IRC_CLIENT='irssi'

# Set this to the command you use for todo.txt-cli
export TODO="t"

# Set this to false to turn off version control status checking within the prompt for all themes
export SCM_CHECK=true

# Set Xterm/screen/Tmux title with only a short hostname.
# Unomment this (or set SHORT_HOSTNAME to something else),
# Will otherwise fall back on $HOSTNAME.
#export SHORT_HOSTNAME=$(hostname -s)

# Set vcprompt executable path for scm advance info in prompt (demula theme)
# https://github.com/djl/vcprompt
#export VCPROMPT_EXECUTABLE=~/.vcprompt/bin/vcprompt

# (Advanced): Uncomment this to make Bash-it reload itself automatically
# after enabling or disabling aliases, plugins, and completions.
# export BASH_IT_AUTOMATIC_RELOAD_AFTER_CONFIG_CHANGE=1

# Load Bash It, if it is installed. bash-it is cloned from upstream rather than
# vendored here, so guard the source: without this, every bash startup on a box
# that never ran the clone fails with "No such file or directory".
#   git clone --depth=1 https://github.com/Bash-it/bash-it.git ~/.bash_it
# shellcheck source=/dev/null
[ -s "$BASH_IT/bash_it.sh" ] && source "$BASH_IT/bash_it.sh"

[ -d "$HOME/.pyenv/bin" ] && export PATH="$HOME/.pyenv/bin:$PATH"
if command -v pyenv >/dev/null; then
  eval "$(pyenv init -)"
  # virtualenv-init is a separate pyenv plugin and is not always installed.
  pyenv commands 2>/dev/null | grep -qx virtualenv-init && eval "$(pyenv virtualenv-init -)"
fi

command -v nodenv >/dev/null && eval "$(nodenv init -)"

# Intel-Homebrew and system-framework paths. These exist only on macOS; adding
# them on Linux just pads PATH with directories that will never resolve.
if [ "$(uname)" = "Darwin" ]; then
  [ -d /usr/local/opt/mysql@5.7/bin ] && export PATH="/usr/local/opt/mysql@5.7/bin:$PATH"
  [ -d /usr/local/opt/postgresql@10/bin ] && export PATH="/usr/local/opt/postgresql@10/bin:$PATH"
  # The original version is saved in .bash_profile.pysave
  _py36=/Library/Frameworks/Python.framework/Versions/3.6/bin
  [ -d "$_py36" ] && PATH="$_py36:${PATH}"
  unset _py36
fi

# Set up go for using protobufs and generating the handlers
GOPATH="$HOME/go"
PATH="${PATH}:${GOPATH}/bin"

export PATH
