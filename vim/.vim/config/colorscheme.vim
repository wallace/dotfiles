" Enable syntax highlighting.
syntax enable

" Tell Vim which way round the colorscheme below runs. This said 'light' while
" the colorscheme on the next line is the *dark* variant, which left Vim
" picking light-background variants of highlight groups on top of dark colors.
" Set to match the colorscheme, so the two agree.
"
" Note this is not the same question as what kitty is themed to: kitty is
" currently on Solarized *Light*. If you want Vim to match the terminal rather
" than the other way round, flip both of these lines to 'light' together --
" never one without the other.
set background=dark

" Use the solarized colorscheme.
silent! colorscheme base16-solarized-dark
