" Use <Space> for <Leader>. (<Leader> is used to start most non-basic keybindings
" in this configuration; I prefer to use <Space> for <Leader>.
let mapleader="\<Space>"

let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif
call plug#begin('~/.vim/plugged')

Plug 'vim-scripts/AnsiEsc.vim'
Plug 'Townk/vim-autoclose'
Plug 'chriskempson/base16-vim'
Plug 'tpope/vim-bundler', { 'for': 'ruby' } " path and tags includes gems from Bundle file
Plug 'github/copilot.vim', { 'on': [] } " Lazy-loaded on InsertEnter
Plug 'chrisbra/csv.vim'
Plug 'Lokaltog/vim-easymotion'
Plug 'tpope/vim-endwise'
Plug 'tpope/vim-fugitive'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'mattn/gist-vim'
Plug 'airblade/vim-gitgutter'
Plug 'tpope/vim-haml'
Plug 'pangloss/vim-javascript'
Plug 'othree/javascript-libraries-syntax.vim'
Plug 'nathanaelkane/vim-indent-guides'
Plug 'itchyny/lightline.vim'
Plug 'wallace/vim-matchit'
Plug 'scrooloose/nerdcommenter'
Plug 'scrooloose/nerdtree', { 'on': ['NERDTree', 'NERDTreeToggle', 'NERDTreeFind'] }
Plug 'tpope/vim-rake'
Plug 'tpope/vim-rails'
Plug 'thoughtbot/vim-rspec'
Plug 'danro/rename.vim'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-rhubarb'
Plug 'vim-ruby/vim-ruby', { 'for': 'ruby' }
Plug 'ecomba/vim-ruby-refactoring', { 'for': 'ruby' }
Plug 'jremmen/vim-ripgrep'
Plug 'slim-template/vim-slim'
Plug 'wallace/snipmate.vim'
Plug 'ervandew/supertab'
Plug 'tpope/vim-surround'
Plug 'godlygeek/tabular'
Plug 'janko-m/vim-test'
Plug 'kana/vim-textobj-user', { 'for': 'ruby' }
Plug 'nelstrom/vim-textobj-rubyblock', { 'for': 'ruby' }
Plug 'christoomey/vim-tmux-navigator'
Plug 'duwanis/tomdoc.vim'
Plug 'tpope/vim-unimpaired'
Plug 'benmills/vimux'
Plug 'mattn/webapi-vim'
Plug 'mbbill/undotree'
Plug 'neoclide/coc.nvim', {'branch': 'release', 'on': []} " Lazy-loaded on InsertEnter
Plug 'Cian911/vim-cadence'
Plug 'ojroques/vim-oscyank'

call plug#end()

" Lazy-load coc.nvim and copilot on first insert
augroup lazy_load_plugins
  autocmd!
  autocmd InsertEnter * ++once call plug#load('coc.nvim', 'copilot.vim')
augroup END

"""" Custom Configs include.
"" All custom config settings are stored in the .vim/config folder to
"" differentiate them from 3rd-party libraries.

let g:gitgutter_realtime = 0
let g:gitgutter_eager = 0

source ~/.vim/config/SudoW.vim
source ~/.vim/config/autoclose.vim
source ~/.vim/config/clojure.vim
source ~/.vim/config/colorscheme.vim
source ~/.vim/config/completion.vim
source ~/.vim/config/display.vim
source ~/.vim/config/editing.vim
source ~/.vim/config/fugitive.vim
source ~/.vim/config/fzf.vim
source ~/.vim/config/general_keys.vim
source ~/.vim/config/general_settings.vim
source ~/.vim/config/gist.vim
source ~/.vim/config/gui.vim
source ~/.vim/config/highlight_trailing_spaces.vim
source ~/.vim/config/markdown.vim
source ~/.vim/config/nerdcommenter.vim
source ~/.vim/config/nerdtree.vim
source ~/.vim/config/rails.vim
source ~/.vim/config/ripgrep.vim
source ~/.vim/config/ruby.vim
source ~/.vim/config/search.vim
source ~/.vim/config/spellcheck.vim
source ~/.vim/config/tabular.vim
source ~/.vim/config/tags.vim
source ~/.vim/config/vim_test.vim
source ~/.vim/config/tempfiles.vim
source ~/.vim/config/tmux_navigator.vim
source ~/.vim/config/undotree.vim
"
"" <cr> should not only clear highlighted search, but flash the current
"" cursor location.
"" causes problems with ack
"" :nnoremap <CR> :nohlsearch<CR>:set cul cuc<cr>:sleep 50m<cr>:set nocul nocuc<cr>/<BS>

set splitright
nnoremap <CR> :noh<CR><CR>
nnoremap <leader>. :vs<CR>:OpenAlternate<CR>

let g:python3_host_prog = '/Users/jonathanwallace/.pyenv/versions/neovim3/bin/python'
