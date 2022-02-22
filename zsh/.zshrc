# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in ~/.oh-my-zsh/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to automatically update without prompting.
# DISABLE_UPDATE_PROMPT="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS=true

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in ~/.oh-my-zsh/plugins/*
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi
export EDITOR=`which vim`

# Vi mode
bindkey -v
export KEYTIMEOUT=1

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
alias gpfl="ggfl"
alias vim=nvim

# Initializes nodenv which will add it to the path
# so that vim is happy (but not in codespaces)
if [ "$CODESPACES" != "true" ]; then
  eval "$(nodenv init -)"
fi

# Base16 Shell, https://github.com/chriskempson/base16-shell
BASE16_SHELL="$HOME/.config/base16-shell/"
[ -n "$PS1" ] && \
    [ -s "$BASE16_SHELL/profile_helper.sh" ] && \
        eval "$("$BASE16_SHELL/profile_helper.sh")"

BASE16_SHELL="$HOME/.config/base16-shell/base16-solarized.light.sh"
[[ -s $BASE16_SHELL ]] && source $BASE16_SHELL

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

if which rbenv > /dev/null
then
  eval "$(rbenv init -)"
fi

## fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# --files: List files that would be searched but do not search
# --no-ignore: Do not respect .gitignore, etc...
# --hidden: Search hidden files and folders
# --follow: Follow symlinks
# --glob: Additional conditions for search (in this case ignore everything in the .git/ folder)
export FZF_DEFAULT_COMMAND='rg --files --no-ignore --hidden --follow --glob "!.git/*"'
export FZF_COMPLETION_TRIGGER=',,'

export PATH="/usr/local/opt/mysql@5.7/bin:$PATH"

# Set up go for using protobufs and generating the handlers
GOPATH="$HOME/go"
PATH="${PATH}:${GOPATH}/bin"

# Set up direnv to work with zsh
if which direnv > /dev/null; then
  eval "$(direnv hook $SHELL)"
fi

#ruby-build installs a non-Homebrew OpenSSL for each Ruby version installed and these are never upgraded.
#
#To link Rubies to Homebrew's OpenSSL 1.1 (which is upgraded) add the following
#to your ~/.zshrc:
#  export RUBY_CONFIGURE_OPTS="--with-openssl-dir=$(brew --prefix openssl@1.1)"
#
#Note: this may interfere with building old versions of Ruby (e.g <2.4) that use
#OpenSSL <1.1.
export RUBY_CONFIGURE_OPTS="--with-openssl-dir=$(brew --prefix openssl@1.1)"

export PATH

# TODO: find a good home for this line. gives me the ability to jump into full
# vim editor for a command, https://unix.stackexchange.com/a/6622.
bindkey -M vicmd v edit-command-line

export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv 1>/dev/null 2>&1; then
  eval "$(pyenv init -)"
fi
