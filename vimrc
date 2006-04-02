" $Id$
"
" Vim startup commands

" COMMON OPTIONS
" read common startup commands for all Vi implementations
if filereadable(expand("~/.exrc"))
    source ~/.exrc
end

" DEFAULT OPTIONS
set nocompatible	" make Vim default to nicer options

" READING OPTIONS
set modeline	" use settings from file being edited

" COMMAND OPTIONS
set wildmode=list	" filename completion lists when ambiguous

" DISPLAY OPTIONS
set listchars=extends:>,precedes:<,tab:\|\ ,trail:-
set more	" use a pager for long listings
set nonumber	" don't show line numbers
set notitle	" don't change terminal's title
set highlight=sub,Su	" use a simple underline for the status bar
set laststatus=2	" always show status line for each window
set statusline=%t\ %m%=%l,%c	" show the file name and cursor position
set showmode	" always show command or insert mode
set shortmess=I	" no intro message
set wrap	" wrap long lines
if has("cmdline_info")
    set showcmd	" show partial commands
    set ruler	" show line and column information
endif
if has("syntax")
    syntax on	" use syntax highlighting if available
endif

if &term == "putty"
    set background=dark	" PuTTY has a black background by default
endif
if &term == "cygwin"
    set background=dark	" Cygwin has a black background by default
endif

" SAVING OPTIONS
set backupext=~	" backup files end in ~

" EDITING OPTIONS
set autoindent	" indentation level automatically controlled
set cinoptions=:0,g0,(0	" labels are not indented (in C/C++ files)
set expandtab	" use spaces rather than tabs for indentation
set smartindent	" indentation level automatically controlled
set shiftround	" manual shift aligns on columns
" allow # character at current indentation level (must appear on own line)
inoremap # X<BS>#

set backspace=2	" backspaces can go over lines
set esckeys	" allow arrow keys in insert mode
set noerrorbells visualbell	" flash screen instead of ringing bell
set showmatch	" show matching brackets
set showbreak=+	" specially mark continued lines with a plus
set textwidth=80	" wrap lines longer than 80 characters

" per-file type rules
filetype on	" enable per-user file type customizations
filetype plugin on
filetype indent on

let is_bash = 1	" use bash syntax for #!/bin/sh files

" disable line wrapping for program source files
au BufRead *.{c,cc,cpp,h,hh,hpp} setlocal tw=0
au BufRead *.{html,shtml,php,php3,php4,php5} setlocal tw=0

" edit binary files in binary mode using the output of xxd
augroup Binary
    au!
    au BufReadPre  *.bin,*.exe.*.jpg,*.pcx let &bin=1
    au BufReadPost *.bin,*.exe.*.jpg,*.pcx if &bin | %!xxd
    au BufReadPost *.bin,*.exe.*.jpg,*.pcx set ft=xxd | endif
    au BufWritePre *.bin,*.exe.*.jpg,*.pcx if &bin | %!xxd -r
    au BufWritePre *.bin,*.exe.*.jpg,*.pcx endif
    au BufWritePost *.bin,*.exe.*.jpg,*.pcx if &bin | %!xxd
    au BufWritePost *.bin,*.exe.*.jpg,*.pcx set nomod | endif
augroup END

" per-project rules
au BufRead,BufNewFile */lics/*.{c,cpp,h} setlocal sw=4 ts=4 expandtab
au BufRead,BufNewFile */zsh/*.[ch] setlocal sw=4 ts=8 noexpandtab

" SEARCH OPTIONS
set ignorecase	" case is unimportant in search terms
set tags+=./tags;/	" search up the tree for tags files

" LOCAL CUSTOMIZATIONS
if filereadable(expand("~/.vimrc.local"))
    source ~/.vimrc.local
endif

" vi: set sw=4 ts=33 noet:
