if has('nvim')
  " Run retag in the background because we use neovim. This is neovim specific.
  " nnoremap <leader>rt :call jobstart("ctags --extra=+f -R *")<CR>
  " au BufWritePre *.rb :call jobstart("ctags --extra=+f -R *")
else
  " stolen from Janus configs for now
  map <Leader>rt :!ripper-tags -R --exclude=vendor<CR><CR>
endif
map <C-\> :tnext<CR>
