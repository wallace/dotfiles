""" Keybindings
"""""""""""""""

" Use smart case with ripgrep
let g:rg_command = 'rg --vimgrep -S'

" Use <Leader>a to prompt you for an Ack! search
map <Leader>a :Rg<SPACE>

" In visual mode, yank the selected text in to register and then use ag to
" search throughout the current project
vnoremap <Leader>fip y:Rg"<C-R>""<CR>
