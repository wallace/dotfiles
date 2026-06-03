" auto-pairs (jiangmiao/auto-pairs) — replaces the unmaintained vim-autoclose.
"
" Default pairs () [] {} "" '' `` are already on. We only need to extend the
" Ruby buffer to also pair pipes (block params like |x, y|) and the string
" interpolation opener #{...}.

augroup AutoPairsRuby
  autocmd!
  autocmd FileType ruby,eruby let b:AutoPairs = extend(copy(g:AutoPairs),
        \ {'|': '|', '#{': '}'})
augroup END
