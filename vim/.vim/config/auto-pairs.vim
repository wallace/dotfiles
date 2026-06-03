" auto-pairs (jiangmiao/auto-pairs) — replaces the unmaintained vim-autoclose.
"
" Default pairs () [] {} "" '' `` are already on. We only need to extend the
" Ruby buffer to also pair pipes (block params like |x, y|) and the string
" interpolation opener #{...}.
"
" Use AutoPairsDefine() rather than a raw dict merge so same-character pairs
" like '|' get registered in the plugin's internal closer-matching tables.

augroup AutoPairsRuby
  autocmd!
  autocmd FileType ruby,eruby
        \ let b:AutoPairs = AutoPairsDefine({'|': '|', '#{': '}'})
augroup END
