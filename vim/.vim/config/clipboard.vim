" Yanks, deletes and puts go through the system clipboard.
"
" "unnamedplus" (the + register) rather than "unnamed" (the * register): on
" macOS both registers are the same pasteboard, but on Wayland and X11 the *
" register is the middle-click "primary selection", not the Ctrl+V clipboard.
set clipboard=unnamedplus

" Homebrew's Vim on Linux is built without +clipboard (no X11 or Wayland
" libraries), so the + and * registers do nothing by default. Vim 9.2 can
" instead hand those registers to external commands through a "clipboard
" provider", so route them to wl-copy / wl-paste.
"
" Neovim ships its own wl-copy provider and does not need any of this.
if !has('nvim') && has('clipboard_provider') && !has('clipboard')
  function! s:ClipAvailable() abort
    return !empty($WAYLAND_DISPLAY) && executable('wl-copy') && executable('wl-paste')
  endfunction

  " a:type is a getregtype() value: 'v', 'V', or "\<C-V>{width}". Only a
  " linewise yank should carry a trailing newline into the clipboard.
  function! s:ClipCopy(reg, type, lines) abort
    let text = join(a:lines, "\n")
    if a:type[0] ==# 'V'
      let text .= "\n"
    endif
    call system('wl-copy', text)
  endfunction

  " Returning an empty list leaves the register untouched, which is what we
  " want when the clipboard is empty or holds something that is not text.
  " Text ending in a newline is pasted linewise, anything else characterwise,
  " which is what Vim's native clipboard support does.
  function! s:ClipPaste(reg) abort
    let text = system('wl-paste --no-newline 2>/dev/null')
    if v:shell_error
      return []
    endif
    if text[-1:] ==# "\n"
      return ['V', split(text[:-2], "\n", 1)]
    endif
    return ['v', split(text, "\n", 1)]
  endfunction

  let v:clipproviders['wayland_cli'] = {
        \ 'available': function('s:ClipAvailable'),
        \ 'copy':      {'+': function('s:ClipCopy'),  '*': function('s:ClipCopy')},
        \ 'paste':     {'+': function('s:ClipPaste'), '*': function('s:ClipPaste')},
        \ }
  set clipmethod^=wayland_cli
endif
