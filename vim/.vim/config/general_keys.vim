" Use <Leader><Leader> as a shortcut to enter commands (faster and less strain
"  than hitting Shift-: in most cases).
" nnoremap <Leader><Leader> :
" conflicts with easymotion plugin

""" Writing Buffers / Quitting
""""""""""""""""""""""""""""""
" Keybinds for quickly writing files and/or closing windows

" <Leader>w writes the current buffer to disk.
map <Leader>w :w!<CR>

" <Leader>W writes the current buffer to disk and quits the window.
map <Leader>W :wq!<CR>

" <Leader>q quits the current window
map <Leader>q :q!<CR>

" <Leader>Q quits all windows.
map <Leader>Q :qa!<CR>

""" Navigation
""""""""""""""
" Keybinds for moving about in vim buffers/windows.

" <Leader>h moves to the window to the left of the current window,
" <Leader>j moves to the window below the current window,
" <Leader>k moves to the window above the current window, and
" <Leader>l moves to the window to the right of the current window.
map <Leader>h :TmuxNavigateLeft<CR>
map <Leader>j <C-W>j
map <Leader>k <C-W>k
map <Leader>l <C-W>l

" Use <TAB> to navigate to the top-left most window.
" See :help C-W_C-W for info on why this mapping does what it does.
""" Why is this useful?
""" Because if you're using NERDTree the way I have it configured,
""" it will always be the top-left most window when it's toggled.
""" So in practice, this binds <TAB> to navigate to the NERDTree window.
map <TAB> 1<C-W><C-W>

" use <Leader>C to display hidden chars
map <Leader>C :set list!<CR>

" make escape, <Esc> easier, to hit
inoremap jj <Esc>

" switch ' and `, because:
" ' jumps to the start of the line where a mark is
" ` jumps to the exact location of a mark
" because jumping to the exact location is more useful,
" I like it to be closer to the home row, so I switch the keys.
noremap ' `
noremap ` '

" Edit another file in the same directory as the current file
" uses expression to extract path from current file's path
map <Leader>e :e <C-R>=expand("%:p:h") . '/'<CR>
map <Leader>s :split <C-R>=expand("%:p:h") . '/'<CR>
map <Leader>v :vnew <C-R>=expand("%:p:h") . '/'<CR>""

" Arrow keys resize vim panes
nnoremap <silent> <Up> :resize -2<CR>
nnoremap <silent> <Down> :resize +2<CR>
nnoremap <silent> <Left> :vertical resize +2<CR>
nnoremap <silent> <Right> :vertical resize -2<CR>

" Always assume paste mode when pasting from system clipboard
noremap <silent> <C-r>* <C-o>:setl paste<CR><C-r>*<C-o>:setl nopaste<CR>
