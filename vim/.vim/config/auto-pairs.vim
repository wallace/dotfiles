" auto-pairs (jiangmiao/auto-pairs) — replaces the unmaintained vim-autoclose.
"
" Default pairs () [] {} "" '' `` are already on. The only Ruby-specific
" addition is pipes for block params (|x, y|); #{...} interpolation works
" via the default {→} pair after you type '#'.
"
" Use AutoPairsDefine() so the same-character pipe pair gets registered in
" auto-pairs' internal closer-matching tables.

augroup AutoPairsRuby
  autocmd!
  autocmd FileType ruby,eruby
        \ let b:AutoPairs = AutoPairsDefine({'|': '|'})
augroup END
