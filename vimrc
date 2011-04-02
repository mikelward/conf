" $Id$
"
" Vim startup commands
"
if has("multi_byte")
    set encoding=utf-8	" have to do this to make the Unicode listchars work
endif

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
if version >= 503
    set listchars=tab:>-,trail:_,eol:$
endif
if version >= 600
    set listchars+=extends:>,precedes:<
endif
if version >= 700
    set listchars+=nbsp:%
endif

set nowrap	" don't wrap long lines (show extends character instead)
set more	" use a pager for long listings
set nolist	" don't display non-printing characters
set nonumber	" don't show line numbers
set noicon	" don't change terminal's title
set notitle	" don't change terminal's title
set laststatus=2	" always show status line for each window
set showmode	" always show command or insert mode
set shortmess=I	" no intro or swap file found messages
	" after opening a file already being edited
set winminheight=0	" make Ctrl+W+_ fully minimize other buffers
	" (show only their status bars)

if has("cmdline_info")
    set showcmd	" show partial commands
    set ruler	" show line and column information
endif
if has("syntax")
    syntax on	" turn syntax highlighting on by default
endif

if &term == "putty"
    set background=dark	" PuTTY has a black background by default
endif
if &term == "cygwin"
    set background=light	" My Cygwin has a white background
endif

if version >= 600
    colorscheme basic	" Use my own basic syntax highlighting
endif

" SAVING OPTIONS
set backupext=~	" backup files end in ~

" EDITING OPTIONS
set autoindent	" indentation level automatically controlled
set cinoptions=:0,g0,(0	" labels are not indented (in C/C++ files)
set expandtab	" use spaces rather than tabs for indentation
set smartindent	" indentation level automatically controlled
set smarttab	" backspace deletes one indentation level
set shiftround	" manual shift aligns on columns

set backspace=2	" backspaces can go over lines
set esckeys	" allow arrow keys in insert mode
set noerrorbells visualbell	" flash screen instead of ringing bell
set showbreak=+	" specially mark continued lines with a plus

if has("x11")
    set clipboard=unnamed	" yank to X selection buffer
endif

" allow # character at current indentation level (must appear on own line)
inoremap # X<BS>#

" MARKDOWN SHORTCUTS
" http://stevelosh.com/blog/2010/09/coming-home-to-vim/
nnoremap <leader>1 yypVr=
nnoremap <leader>2 yypVr-
nnoremap <leader>3 yypVr~

" swap commented setting and uncommented setting
nnoremap <leader>s 0xddpki#<Esc>

if version >= 600
    " per-file type rules
    filetype on	" enable per-user file type customizations
    filetype plugin on
    filetype indent on
endif

if has("autocmd")
    " disable line wrapping for program source files
    au BufRead *.{c,cc,cpp,h,hh,hpp} setlocal tw=0
    au BufRead *.{html,shtml,php,php3,php4,php5,inc} setlocal tw=0

    " treat unknown file types as text files
    au BufRead,BufNewFile * setfiletype text

    " per file-type rules
    "au BufRead,BufNewFile * if &filetype == 'c' || &filetype == 'cpp' || &filetype == 'perl' || &filetype == 'python' || &filetype == 'ruby' | set listchars+=tab:\|\  | endif
    "au BufRead,BufNewFile * if &filetype == 'fstab' | set listchars+=tab:>\  | endif
    "au BufRead,BufNewFile * if &filetype == 'text' | set textwidth=66 | endif
    "au BufRead,BufNewFile * if &filetype == 'svn' | set textwidth=80 | set viminfo= | endif
    "au BufRead,BufNewFile * if &filetype == 'haskell' | set textwidth=80 | set expandtab | endif
    
    au BufRead,BufNewFile * if &filetype == 'c' | set errorformat^=%*[^:]:\ %f:%l:\ %m

    au BufNewFile * call ReadTemplate()
    fun ReadTemplate()
        let b:filename = bufname('%')
        let b:extension = substitute(b:filename, '.*\.\(.*\)', '\1', '')
        let b:template = $HOME . '/templates/template.' . b:extension
        if filereadable(b:template)
          call setline(1, readfile(b:template))
          let b:lastline = line('$')
          call setpos('.', [0, b:lastline, 0, 0])
        endif
    endfun

    au FileType perl set cindent cinkeys-=0#

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
    au BufRead,BufNewFile */acxpcp*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    au BufRead,BufNewFile */bash*/*.{c,h} setlocal sw=2 ts=8 expandtab cinoptions=>4,n-2,{2,^-2,:2,=2,g0,h2,p5,t0,+2,(0,u0,w1,m1
    au BufRead,BufNewFile */coreutils*/*.{c,h} setlocal sw=2 ts=8 expandtab cinoptions=>4,n-2,{2,^-2,:2,=2,g0,h2,p5,t0,+2,(0,u0,w1,m1
    au BufRead,BufNewFile */cvs*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    au BufRead,BufNewFile */fam*/*{.c++,h} setlocal sw=4 ts=8 noexpandtab
    au BufRead,BufNewFile */gnome-terminal*/*.{c,h} setlocal sw=2 ts=8 expandtab cinoptions=>4,n-2,{2,^-2,:2,=2,g0,h2,p5,t0,+2,(0,u0,w1,m1
    au BufRead,BufNewFile */lics/*.{c,cpp,h} setlocal sw=4 ts=4 expandtab
    au BufRead,BufNewFile */nagios*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    au BufRead,BufNewFile */postfix*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    au BufRead,BufNewFile */procmail*/*.{c,h} setlocal sw=3 ts=8 noexpandtab
    au BufRead,BufNewFile */putty*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    au BufRead,BufNewFile */sudo*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    au BufRead,BufNewFile */terminal*/*.{c,h} setlocal sw=4 ts=8 expandtab
    au BufRead,BufNewFile */zsh*/*.[ch] setlocal sw=4 ts=8 noexpandtab

endif

if has("eval")
    let is_bash = 1	" use bash syntax for #!/bin/sh files
endif

" SEARCH OPTIONS
set nohlsearch	" disable highlighting of matches
set noignorecase	" case is important in search terms
set tags+=./tags;/	" search up the tree for tags files

" LOCAL CUSTOMIZATIONS
if filereadable(expand("~/.vimrc.local"))
    source ~/.vimrc.local
endif

" vi: set sw=4 ts=33 noet:
