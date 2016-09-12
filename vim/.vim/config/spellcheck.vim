au BufRead,BufNewFile *.markdown,*.md set filetype=markdown
autocmd FileType gitcommit,markdown setlocal spell
autocmd FileType gitcommit,markdown set complete+=kspell

set dictionary-=/usr/share/dict/words dictionary+=/usr/share/dict/words
