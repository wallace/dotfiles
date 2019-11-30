let test#strategy = "vimux"

let test#runners = {'Ruby': ['GitHub']}

nmap <silent> <leader>rr :TestNearest<CR>
nmap <silent> <leader>rf :TestFile<CR>
nmap <silent> <leader>ra :TestSuite<CR>
nmap <silent> <leader>rl :TestLast<CR>

" Run last command executed by VimuxRunCommand
map <Leader>vl :VimuxRunLastCommand<CR>

let g:VimuxOrientation = "h"
