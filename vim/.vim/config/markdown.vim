" Open markdown files with Chrome.
autocmd BufEnter *.md exe 'noremap <leader>md :!open -a "Google Chrome.app" %:p<CR>'
