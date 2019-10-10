" set rtp+=~/.fzf
set rtp+=/usr/local/opt/fzf

" Commits for current file
" TODO: this is not working
nnoremap <leader>c :BCommits<cr>

" Tags for current file
nnoremap <leader>t :BTags<cr>

" Tags for project
nnoremap <leader>p :Tags<cr>

" Project dir files
nnoremap <leader>/ :Files<cr>

" Buffers
nnoremap <leader>b :Buffers<cr>
