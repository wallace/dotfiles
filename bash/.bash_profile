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
source '/Users/jwallace/Documents/projects/sd/sd'

# https://github.com/neovim/neovim/issues/2048#issuecomment-78045837
[[ -f ~/.$TERM.ti ]] || infocmp $TERM | sed 's/kbs=^[hH]/kbs=\\177/' > ~/.$TERM.ti
tic ~/.$TERM.ti
