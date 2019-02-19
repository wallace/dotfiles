# from http://richardhulse.blogspot.com/2008/06/using-git.html
# this should let us use __git_ps1 in our prompt
source ~/.git-completion.bash

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
alias gp='git push'
alias wd='sd'
alias gemb='gem build *gemspec'
alias box='gem inabox *gem && rm *.gem'
alias gembb='gemb && box'
alias git=hub

cm() {
  if [[ $# > 0 ]]; then
    git commit -m $@
  else
    git commit -v
  fi
}

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

#if [ -f `brew --prefix`/etc/bash_completion ]; then
#  . `brew --prefix`/etc/bash_completion
#fi

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
alias irb='pry'

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
make-completion-wrapper _git _git_checkout_mine git checkout
complete -o bashdefault -o default -o nospace -F _git_checkout_mine c

export EDITOR=`which nvim`

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
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

lhaste()
{
  if [ $# -eq 0 ]; then
    content=$(cat)
  else
    content=$(cat $1)
  fi

  curl -X POST -s -d "$content" http://hastebin.peachtreebilling.local/documents | echo "http://hastebin.peachtreebilling.local/"`ruby -e "puts ARGF.read.to_s.match(/\{\"key\":\"(.+)\"\}/).captures.first"` | pbcopy
}

source ~/.bashrc.local

# define the sd function
IMAC_SD_PATH='/Users/jwallace/Documents/projects/sd/sd'
MBP_SD_PATH='/Users/jonathanwallace/Documents/projects/sd/sd'
if [[ -f $IMAC_SD_PATH ]]; then
  source $IMAC_SD_PATH
  if [[ ! -h ~/bin/sd ]]; then
    $(ln -s $IMAC_SD_PATH ~/bin/sd)
  fi
elif [[ -f $MBP_SD_PATH ]]; then
  source $MBP_SD_PATH
  if [[ ! -h ~/bin/sd ]]; then
    $(ln -s $MBP_SD_PATH ~/bin/sd)
  fi
fi

export FZF_DEFAULT_COMMAND='ag -g "" --hidden --ignore .git'
export FZF_COMPLETION_TRIGGER=',,'

# https://github.com/neovim/neovim/issues/2048#issuecomment-78045837
[[ -f ~/.$TERM.ti ]] || infocmp $TERM | sed 's/kbs=^[hH]/kbs=\\177/' > ~/.$TERM.ti
tic ~/.$TERM.ti

# Base16 Shell
BASE16_SHELL="$HOME/.config/base16-shell/base16-ocean.dark.sh"
[[ -s $BASE16_SHELL ]] && source $BASE16_SHELL

# show colors in macOS
export CLICOLOR=1

source ~/bin/tmuxinator.bash

# Path to the bash it configuration
export BASH_IT="/Users/jonathanwallace/.bash_it"

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

# Load Bash It
source $BASH_IT/bash_it.sh

export PATH="/Users/jonathanwallace/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
export PATH="/usr/local/opt/mysql@5.7/bin:$PATH"
eval "$(nodenv init -)"
export PATH="/usr/local/opt/postgresql@10/bin:$PATH"
