""" Keybindings
"""""""""""""""

" :Rg is provided by fzf.vim. Its default command honors FZF_DEFAULT_COMMAND
" plus the query you type, so no extra g:rg_command is needed.

" Use <Leader>a to prompt you for an Ack! search
map <Leader>a :Rg<SPACE>

" In visual mode, yank the selected text in to register and then use ag to
" search throughout the current project
vnoremap <Leader>fip y:Rg "<C-R>""<CR>
