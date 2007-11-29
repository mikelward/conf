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

" INITIALIZATION OPTIONS
set exrc	" read extra commands from .vimrc in the current directory
set secure	" don't allow .vimrc to spawn shells or write files

" READING OPTIONS
set modeline	" use settings from file being edited
set nostartofline	" keep the current cursor position when reediting a file

" COMMAND OPTIONS
set wildmode=list:longest	" filename completion lists when ambiguous

" DISPLAY OPTIONS
if version >= 600
    set listchars=extends:>,precedes:<,tab:\|\ ,trail:-
    "set listchars=extends:>,precedes:<,tab:>\ ,trail:_
    "set listchars=extends:>,precedes:<,tab:>-,trail:-,eol:$
    "set listchars=extends:>,precedes:<,tab:>·,trail:·,eol:$
    "set listchars=extends:>,precedes:<,tab:··,trail:·
    "set list	" display non printing characters
elseif version >= 500
    set listchars=tab:>\ ,trail:_
    "set list	" display non printing characters
endif
set nowrap	" don't wrap long lines (show extends character instead)
set more	" use a pager for long listings
set nonumber	" don't show line numbers
set notitle	" don't change terminal's title
if &term == "linux"
    set highlight=sb,Sub	" make the status bar bold
    "set highlight=sb,Srb	" make the status bar bold
else
    set highlight=sub,Su	" make the status bar bold
endif
set laststatus=2	" always show status line for each window
set showmode	" always show command or insert mode
set shortmess=I	" no intro or swap file found messages
	" after opening a file already being edited
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

if &background == "light"
    highlight SpecialKey ctermfg=LightGrey
    highlight NonText ctermfg=LightGrey
endif

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
au BufRead,BufNewFile * if &filetype == 'c' || &filetype == 'cpp' || &filetype == 'perl' || &filetype == 'python' || &filetype == 'ruby' | set listchars+=tab:\|\  | endif
au BufRead,BufNewFile * if &filetype == 'make' | set listchars+=tab:\|\  | set list | endif
au BufRead,BufNewFile * if &filetype == 'vim' || &filetype == 'fstab' | set listchars+=tab:>\  | set list | endif
au BufRead,BufNewFile * if &filetype == 'text' || &filetype == 'svn' | set textwidth=66 | endif

au FileType perl set cindent cinkeys-=0#

" per-project rules
au BufRead,BufNewFile */cvs/*.{c,h} setlocal sw=4 ts=8 noexpandtab
au BufRead,BufNewFile */fam/*{.c++,h} setlocal sw=4 ts=8 noexpandtab
au BufRead,BufNewFile */lics/*.{c,cpp,h} setlocal sw=4 ts=4 expandtab
au BufRead,BufNewFile */postfix/*.{c,h} setlocal sw=4 ts=8 noexpandtab
au BufRead,BufNewFile */procmail/*.{c,h} setlocal sw=3 ts=8 noexpandtab
au BufRead,BufNewFile */putty/*.{c,h} setlocal sw=4 ts=8 noexpandtab
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
