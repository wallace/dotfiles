" Use ; for <Leader>. (<Leader> is used to start most non-basic keybindings
" in this configuration; I prefer to use ; for <Leader> since it's right on
" the home row, but change it as you prefer and all the keybindings will be
" updated appropriately.
let mapleader="\<Space>"

"  """ Vundle settings.
" Make use of Vundle to handle our packages with five easy steps:
" 1) Set config settings required for Vundle to startup.
set nocompatible
filetype off
" 2) Add Vundle to the runtime path.
set rtp+=~/.vim/bundle/Vundle.vim/
" 3) Initialize Vundle.
call vundle#begin()
" 4) Let Vundle manage Vundle.
Plugin 'VundleVim/Vundle.vim'
" 5) Include all of the bundles that we want to make use of.
" All of these references are to github repositories unless otherwise noted.
Plugin 'vim-scripts/ack.vim'
Plugin 'rking/ag.vim'
Plugin 'Townk/vim-autoclose'
Plugin 'chriskempson/base16-vim'
Plugin 'corntrace/bufexplorer'
Plugin 'duff/vim-bufonly'
Plugin 'tpope/vim-bundler'
Plugin 'bkad/CamelCaseMotion'
Plugin 'tpope/vim-classpath'
Plugin 'guns/vim-clojure-highlight'
Plugin 'guns/vim-clojure-static'
Plugin 'kchmck/vim-coffee-script'
Plugin 'chrisbra/csv.vim'
Plugin 'ctrlpvim/ctrlp.vim'
Plugin 'tpope/vim-cucumber'
Plugin 'tpope/vim-dispatch'
Plugin 'Lokaltog/vim-easymotion'
Plugin 'tpope/vim-endwise'
Plugin 'tpope/vim-fireplace'
Plugin 'tpope/vim-fugitive'
Plugin 'shumphrey/fugitive-gitlab.vim'
Plugin 'junegunn/fzf'
Plugin 'junegunn/fzf.vim'
Plugin 'mattn/gist-vim'
Plugin 'airblade/vim-gitgutter'
Plugin 'tpope/vim-haml'
Plugin 'pangloss/vim-javascript'
Plugin 'othree/javascript-libraries-syntax.vim'
Plugin 'nathanaelkane/vim-indent-guides'
Plugin 'itchyny/lightline.vim'
Plugin 'wallace/vim-matchit'
Plugin 'scrooloose/nerdcommenter'
Plugin 'scrooloose/nerdtree'
Plugin 'cyphactor/vim-open-alternate'
Plugin 'puppetlabs/puppet-syntax-vim'
Plugin 'tpope/vim-rake'
Plugin 'tpope/vim-rails'
Plugin 'kien/rainbow_parentheses.vim'
Plugin 'thoughtbot/vim-rspec'
Plugin 'danro/rename.vim'
Plugin 'tpope/vim-repeat'
Plugin 'vim-ruby/vim-ruby'
Plugin 'ecomba/vim-ruby-refactoring'
Plugin 'tpope/vim-salve'
Plugin 'slim-template/vim-slim'
Plugin 'jpalardy/vim-slime'
Plugin 'adamlowe/vim-slurper'
Plugin 'wallace/snipmate.vim'
Plugin 'altercation/vim-colors-solarized'
Plugin 'ervandew/supertab'
Plugin 'tpope/vim-surround'
"Bundle 'scrooloose/syntastic'
Plugin 'godlygeek/tabular'
Plugin 'kana/vim-textobj-user'
Plugin 'nelstrom/vim-textobj-rubyblock'
Plugin 'majutsushi/tagbar'
Plugin 'christoomey/vim-tmux-navigator'
Plugin 'duwanis/tomdoc.vim'
Plugin 'tpope/vim-unimpaired'
Plugin 'benmills/vimux'
Plugin 'skalnik/vim-vroom'
Plugin 'mattn/webapi-vim'
Plugin 'neomake/neomake'
Plugin 'Shougo/deoplete.nvim'
Plugin 'mbbill/undotree'

call vundle#end()         "required
filetype plugin indent on "required
"
"""" Custom Configs include.
"" All custom config settings are stored in the .vim/config folder to
"" differentiate them from 3rd-party libraries.

let g:gitgutter_realtime = 0
let g:gitgutter_eager = 0

source ~/.vim/config/SudoW.vim
source ~/.vim/config/ag.vim
source ~/.vim/config/autoclose.vim
source ~/.vim/config/bufexplorer.vim
source ~/.vim/config/clojure.vim
source ~/.vim/config/colorscheme.vim
source ~/.vim/config/completion.vim
source ~/.vim/config/ctrlp.vim
source ~/.vim/config/display.vim
source ~/.vim/config/editing.vim
source ~/.vim/config/fugitive.vim
source ~/.vim/config/fugitive_gitlab.vim
source ~/.vim/config/fzf.vim
source ~/.vim/config/general_keys.vim
source ~/.vim/config/general_settings.vim
source ~/.vim/config/gist.vim
source ~/.vim/config/gui.vim
source ~/.vim/config/nerdcommenter.vim
source ~/.vim/config/nerdtree.vim
source ~/.vim/config/rails.vim
source ~/.vim/config/rainbow_parentheses.vim
source ~/.vim/config/ruby.vim
source ~/.vim/config/search.vim
source ~/.vim/config/slime.vim
source ~/.vim/config/spellcheck.vim
source ~/.vim/config/tabular.vim
source ~/.vim/config/tags.vim
source ~/.vim/config/tempfiles.vim
source ~/.vim/config/tmux_navigator.vim
source ~/.vim/config/neomake.vim
source ~/.vim/config/undotree.vim
"
"" <cr> should not only clear highlighted search, but flash the current
"" cursor location.
"" causes problems with ack
"" :nnoremap <CR> :nohlsearch<CR>:set cul cuc<cr>:sleep 50m<cr>:set nocul nocuc<cr>/<BS>
let g:deoplete#enable_at_startup = 1

set splitright
nnoremap <CR> :noh<CR><CR>
nnoremap <leader>. :vs<CR>:OpenAlternate<CR>
