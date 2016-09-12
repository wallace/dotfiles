""""""""""""""""""""""""""""""""
"" Set Ruby-specific keybindings
""""""""""""""""""""""""""""""""

autocmd FileType ruby call LoadRubyKeybindings()
autocmd FileType eruby call LoadRubyKeybindings()
autocmd FileType haml call LoadRubyKeybindings()
autocmd FileType yaml call LoadRubyKeybindings()

fun LoadRubyKeybindings()
   " bind control-l to hashrocket
   imap <buffer> <C-l> <Space>=><Space>"

   " bind control-k to turn the current word into a symbol
   imap <buffer> <C-k> <C-o>b:<Esc>Ea
   nmap <buffer> <C-k> lbi:<Esc>E

   " set the foldmethod to 'syntax'
   " setlocal foldmethod=syntax
   " setlocal foldlevel=2
endfun

let g:rspec_command = 'call VimuxRunCommand("bundle exec rspec {spec}\n")'
map <Leader>rr :call RunNearestSpec()<CR>
map <Leader>rf :call RunCurrentSpecFile()<CR>
map <Leader>rl :call RunLastSpec()<CR>
map <Leader>ra :call RunAllSpecs()<CR>
