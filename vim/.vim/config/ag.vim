""" Keybindings
"""""""""""""""

" Use <Leader>a to prompt you for an Ack! search
map <Leader>a :Ag<SPACE>

" In visual mode, yank the selected text in to register and then use ag to
" search throughout the current project
vnoremap <Leader>fip y:Ag"<C-R>""<CR>
