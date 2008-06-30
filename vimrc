" $Id$
"
" Vim startup commands
"

" this file is encoded in UTF-8
let &termencoding = &encoding
set encoding=utf-8

" COMMON OPTIONS
" read common startup commands for all Vi implementations
if filereadable(expand("~/.exrc"))
    source ~/.exrc
end

" DEFAULT OPTIONS
set nocompatible	" make Vim default to nicer options

" INITIALIZATION OPTIONS
set exrc	" read extra commands from .vimrc in the current directory
set secure	" don't allow .vimrc to spawn shells or write files

" READING OPTIONS
set modeline	" use settings from file being edited
set nostartofline	" keep the current cursor position when reediting a file

" COMMAND OPTIONS
set wildmode=list:longest	" filename completion lists when ambiguous

" DISPLAY OPTIONS
"set listchars=tab:>\ ,trail:_	" how to display tabs and trailing spaces
set listchars=tab:↦\ ,trail:˽	" how to display tabs and trailing spaces
if version >= 600
    "set listchars+=extends:>,precedes:<
    set listchars+=extends:…,precedes:…
    "set listchars+=eol:$
    set listchars+=eol:↵
    "set listchars+=nbsp:%
    set listchars+=nbsp:⍽
endif
set nowrap	" don't wrap long lines (show extends character instead)
set more	" use a pager for long listings
set nolist	" don't display non-printing characters
set nonumber	" don't show line numbers
set notitle	" don't change terminal's title
set laststatus=2	" always show status line for each window
set showmode	" always show command or insert mode
set shortmess=I	" no intro or swap file found messages
	" after opening a file already being edited
set winminheight=0               " show only the status bars of other buffers after pressing Ctrl+W+_

if has("cmdline_info")
    set showcmd	" show partial commands
    set ruler	" show line and column information
endif
if has("syntax")
    syntax off	" don't ever use syntax highlighting
endif

if &term == "putty"
    set background=dark	" PuTTY has a black background by default
endif
if &term == "cygwin"
    set background=light	" My Cygwin has a white background
endif

colorscheme basic	" Use my own basic syntax highlighting

" SAVING OPTIONS
set backupext=~	" backup files end in ~

" EDITING OPTIONS
set autoindent	" indentation level automatically controlled
set cinoptions=:0,g0,(0	" labels are not indented (in C/C++ files)
"set expandtab	" use spaces rather than tabs for indentation
set smartindent	" indentation level automatically controlled
set shiftround	" manual shift aligns on columns
" allow # character at current indentation level (must appear on own line)
inoremap # X<BS>#

set backspace=2	" backspaces can go over lines
set esckeys	" allow arrow keys in insert mode
set noerrorbells visualbell	" flash screen instead of ringing bell
set showbreak=+	" specially mark continued lines with a plus

" per-file type rules
filetype on	" enable per-user file type customizations
filetype plugin on
filetype indent on

let is_bash = 1	" use bash syntax for #!/bin/sh files

if version >= 600
    " disable line wrapping for program source files
    au BufRead *.{c,cc,cpp,h,hh,hpp} setlocal tw=0
    au BufRead *.{html,shtml,php,php3,php4,php5,inc} setlocal tw=0

    " treat unknown file types as text files
    au BufRead,BufNewFile * setfiletype text
endif

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

" per file-type rules
"au BufRead,BufNewFile * if &filetype == 'c' || &filetype == 'cpp' || &filetype == 'perl' || &filetype == 'python' || &filetype == 'ruby' | set listchars+=tab:\|\  | endif
"au BufRead,BufNewFile * if &filetype == 'fstab' | set listchars+=tab:>\  | endif
au BufRead,BufNewFile * if &filetype == 'text' || &filetype == 'svn' | set textwidth=66 | endif

au FileType perl set cindent cinkeys-=0#

" per-project rules
au BufRead,BufNewFile */acxpcp/*.{c,h} setlocal sw=4 ts=8 noexpandtab
au BufRead,BufNewFile */cvs/*.{c,h} setlocal sw=4 ts=8 noexpandtab
au BufRead,BufNewFile */fam/*{.c++,h} setlocal sw=4 ts=8 noexpandtab
au BufRead,BufNewFile */lics/*.{c,cpp,h} setlocal sw=4 ts=4 expandtab
au BufRead,BufNewFile */postfix/*.{c,h} setlocal sw=4 ts=8 noexpandtab
au BufRead,BufNewFile */procmail/*.{c,h} setlocal sw=3 ts=8 noexpandtab
au BufRead,BufNewFile */putty/*.{c,h} setlocal sw=4 ts=8 noexpandtab
au BufRead,BufNewFile */terminal/*.{c,h} setlocal sw=4 ts=8 expandtab
au BufRead,BufNewFile */zsh/*.[ch] setlocal sw=4 ts=8 noexpandtab

" SEARCH OPTIONS
set nohlsearch	" disable highlighting of matches
set noignorecase	" case is important in search terms
set tags+=./tags;/	" search up the tree for tags files

" LOCAL CUSTOMIZATIONS
if filereadable(expand("~/.vimrc.local"))
    source ~/.vimrc.local
endif

" vi: set sw=4 ts=33 noet:
