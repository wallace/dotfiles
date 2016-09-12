""" Global settings for editing files

" Automatically indent lines, and try to do it intelligently
set autoindent
set smartindent

" backspace behaves 'normally' (goes across lines, etc.)
set backspace=indent,eol,start
" Same for left/right nav keys.
set whichwrap+=<,>,h,l

" Change how tabs, line-endings and trailing white space appears when :set list
" has been set.
" Determines which character ">" to display when the screen is too narrow for the
" amount of text on a line.
set listchars=tab:▸\ ,eol:¬,trail:☠,precedes:<,extends:>

" Use spaces instead of tabs, and
" prefer 3 spaces.
set softtabstop=2
set tabstop=2
set shiftwidth=2
set expandtab

" Automatically reload a file if it's changed outside of vim (or in another
" window)
set autoread

" use horizontal scrolling
set nowrap
" try not to wrap in the middle of a word
set linebreak
" use an 80-character line limit
set textwidth=80

" format settings
" t - Auto-wrap text using textwidth
" c - Auto-wrap comments using textwidth, inserting the current comment
" leader automatically.
" r - Automatically insert the current comment leader after hitting <Enter>
" in Insert mode.
" q - Allow formatting of comments with "gq".
" Note that formatting will not change blank lines or lines containing
" only the comment leader. A new paragraph starts after such a line,
" or when the comment leader changes.
" n - When formatting text, recognize numbered lists.
" 2 - When formatting text, use the indent of the second line of a paragraph
" for the rest of the paragraph, instead of the indent of the first line.
" 1 - Don't break a line after a one-letter word. It's broken before it
" instead (if possible).
set formatoptions=tcrqn21

" Automatically restore cursor position when possible
"autocmd BufReadPost *
"   \ if line("'\"") > 1 && line("'\"") <= line("$") |
"   \ exe "normal! g`\"" |
"   \ endif

" % to bounce from do to end etc.
runtime! macros/matchit.vim

" Use the lhaste bash function (provided my custom .bash_profile) to post
" visually selected content into hastebin and copy the URL into the clipboard.
cnoreabbrev lhaste w !lhaste

" Move visual block
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

" Make a mark, goes to the beginning of the file, aligns, and travels back to the mark.
nnoremap <leader><tab> mtgg=G`t`
