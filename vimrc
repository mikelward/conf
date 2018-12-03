" Vim startup commands
"
if has("multi_byte")
    set encoding=utf-8	" have to do this to make the Unicode listchars work
endif

if has("gui_running")
    source $VIMRUNTIME/mswin.vim	" make Ctrl+C/Ctrl+V copy/paste in gvim
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
set list listchars=extends:»,precedes:«,tab:\ \ ,trail:-  " base rules used whether show_whitespace is on or off
set list	" list is always enabled, see ToogleWhitespace()
set nowrap	" don't wrap long lines (show extends character instead)
set more	" use a pager for long listings
set nonumber	" don't show line numbers
set noicon	" don't change terminal's title
set notitle	" don't change terminal's title
set laststatus=2	" always show status line for each window
set showmode	" always show command or insert mode
set shortmess+=FIOt	" no file details or intro messages
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

" Highlight the character at &textwidth (default 80) + 1 columns
if exists("&colorcolumn")
  set colorcolumn=+1
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
set autowrite                    " allow jumping to tags etc. even if buffer is modified
set cinoptions=:0,g0	" labels are not indented (in C/C++ files)
set cinoptions+=(0	" hanging indent to align function parameters
set completeopt=menu,menuone	" ^X^O shows a menu
set completeopt+=longest,preview	" ^X^O shows a help/docstring preview
set expandtab	" use spaces rather than tabs for indentation
set smarttab	" backspace deletes one indentation level
set shiftround	" manual shift aligns on columns

set backspace=2	" backspaces can go over lines
set noerrorbells visualbell	" flash screen instead of ringing bell
set showbreak=+	" specially mark continued lines with a plus

set virtualedit=onemore	" allow cursor to be positioned at end of line
                                 " best with autocmd InsertLeave
if has("statusline")
    set statusline=%f%=%{(&ft!=''?&ft:'unknown')}\ %10(%4l,%c%V%)\ %6P  " put the filetype in the statusline
endif

" run goimports when saving a .go file
let g:gofmt_command = "goimports"

" teach tagbar how to use exuberant-ctags tags files
let g:tagbar_type_go = {
    \ 'ctagstype': 'go',
    \ 'kinds' : [
        \'p:package',
        \'f:function',
        \'v:variables',
        \'t:type',
        \'c:const'
    \]
\}

if has("x11")
    set clipboard=unnamed	" yank to X selection buffer
endif
if has("mouse")
    set mouse=                   " regain use of right mouse button
endif
if exists("&signcolumn")
    set signcolumn=yes	" always show the sign/mark gutter
endif

" allow # character at current indentation level (must appear on own line)
inoremap # X<BS>#

function! ToggleWhitespace()
  if exists("b:show_whitespace")
    let b:show_whitespace = !b:show_whitespace
  else
    let b:show_whitespace = 1
  endif
  if b:show_whitespace
    set listchars-=tab:\ \ 	" revert previous whitespace chars
    set listchars+=tab:\|\ 	" show tabs as "|   "
    echo "Showing whitespace"
  else
    set listchars-=tab:\|\ 	" revert previous whitespace chars
    set listchars+=tab:\ \ 	" show tabs as "    " even with list mode on
    echo "Hiding whitespace"
  endif
endfunction


function! TogglePaste()
  if &paste
    set nopaste
    echo "Disabling paste mode"
  else
    set paste
    echo "Enabling paste mode"
  endif
endfunction

" KEYBOARD BINDINGS
let mapleader = ","
map <Leader>b :make<CR>
map <C-b> :make<CR>
map <Leader>n :cnext<CR>
map <C-n> :tabnew<CR>
map <Leader>p :cprevious<CR>
"map <Leader>t :TagbarToggle<CR>
map <Leader>s :split<CR>
map <C-s> :write<CR>
map <Leader>t :make test<CR>
map <C-t> :make test<CR>
map <Leader>v :vsplit<CR>
map <Leader>w :call ToggleWhitespace()<CR>
map <C-w> :quit<CR>
map <Leader>. :tag<CR>
map <Leader>, :pop<CR>
map <Leader>/ :TComment<CR>
map <silent> <A-Up> :wincmd k<CR>
map <silent> <A-Down> :wincmd j<CR>
map <silent> <A-Left> :wincmd h<CR>
map <silent> <A-Right> :wincmd l<CR>
map <silent> <M-Up> :wincmd k<CR>
map <silent> <M-Down> :wincmd j<CR>
map <silent> <M-Left> :wincmd h<CR>
map <silent> <M-Right> :wincmd l<CR>

nmap <BS> X	" make backspace work in normal mode

if version >= 600
    " per-file type rules
    filetype on	" enable per-user file type customizations
    filetype plugin on
    filetype indent on
endif

if has("autocmd")
    " make insert mode return to where insertion started
    " best when paired with virtualedit
    autocmd InsertLeave * :normal `^

    if has("windows")
        " use tabpages by default
        "autocmd BufAdd * nested tab ball
        set showtabline=2
    endif

    " teach Vim about some more file types
    autocmd BufRead,BufNewFile *.go setlocal filetype=go
    autocmd BufRead,BufNewFile *.log setlocal filetype=log

    " per file-type rules
    autocmd FileType fstab setlocal listchars+=tab:>\  " intentional trailing space
    autocmd FileType go setlocal shiftwidth=8 tabstop=8 textwidth=0 noexpandtab colorcolumn=0
    autocmd FileType go autocmd BufWritePre <buffer> Fmt
    autocmd FileType gitcommit setlocal viminfo= textwidth=80
    autocmd FileType hgcommit setlocal viminfo= textwidth=80
    autocmd FileType markdown setlocal textwidth=80
    autocmd FileType svn setlocal viminfo= textwidth=80
    autocmd FileType text setlocal textwidth=80

    " make :make jump to C assertion errors
    autocmd FileType c set errorformat^=%*[^:]:\ %f:%l:\ %m

    " when creating a new file, use a template from ~/templates if it exists
    fun! InsertFile(filename)
        call setline(1, readfile(a:filename))
        let b:lastline = line('$')
        call setpos('.', [0, b:lastline, 0, 0])
    endfun
    autocmd BufNewFile * call ReadTemplate()
    fun! ReadTemplate()
        let b:filename = bufname('%')
        let b:basename = substitute(b:filename, '\(.*\)\.\(.*\)', '\1', '')
        let b:extension = substitute(b:filename, '\(.*\)\.\(.*\)', '\2', '')
        let b:test_template = $HOME . '/templates/test_template.' . b:extension
        let b:template = $HOME . '/templates/template.' . b:extension
        if b:basename =~ '_test' && filereadable(b:test_template)
            call InsertFile(b:test_template)
        elseif filereadable(b:template)
            call InsertFile(b:template)
        endif
    endfun

    " append a modeline using the current settings
    fun! AppendModeline()
        let l:modeline = printf(" vim: set ts=%d sw=%d tw=%d %s:",
                         \ &tabstop, &shiftwidth, &textwidth,
                         \ (&expandtab == 1)? "et": "noet" )
        let l:modeline = substitute(&commentstring, "%s", l:modeline, "")
        call append(line("$"), l:modeline)
    endfun

    " per-project rules
    autocmd BufRead,BufNewFile */apt*/*.{c,cc,h} setlocal sw=4 ts=8 noexpandtab
    autocmd BufRead,BufNewFile */bash*/*.{c,h} setlocal sw=2 ts=8 expandtab cinoptions=>4,n-2,{2,^-2,:2,=2,g0,h2,p5,t0,+2,(0,u0,w1,m1
    autocmd BufRead,BufNewFile */coreutils*/*.{c,h} setlocal sw=2 ts=8 expandtab cinoptions=>4,n-2,{2,^-2,:2,=2,g0,h2,p5,t0,+2,(0,u0,w1,m1
    autocmd BufRead,BufNewFile */ersatz*/*.{c,h} setlocal sw=2 ts=8 noexpandtab
    autocmd BufRead,BufNewFile */glibc*/*.{c,h} setlocal sw=2 ts=8 expandtab cinoptions=>4,n-2,{2,^-2,:2,=2,g0,h2,p5,t0,+2,(0,u0,w1,m1
    autocmd BufRead,BufNewFile */gnome-terminal*/*.{c,h} setlocal sw=2 ts=8 expandtab cinoptions=>4,n-2,{2,^-2,:2,=2,g0,h2,p5,t0,+2,(0,u0,w1,m1
    autocmd BufRead,BufNewFile */inspircd/*.{c,cpp,h} setlocal shiftwidth=4 tabstop=4 noexpandtab
    autocmd BufRead,BufNewFile */isc-dhcp/*.{c,h} setlocal shiftwidth=8 tabstop=8 noexpandtab
    autocmd BufRead,BufNewFile */nagios*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    autocmd BufRead,BufNewFile */openbsd*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    autocmd BufRead,BufNewFile */postfix*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    autocmd BufRead,BufNewFile */procmail*/*.{c,h} setlocal sw=3 ts=8 noexpandtab
    autocmd BufRead,BufNewFile */putty*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    autocmd BufRead,BufNewFile */sudo*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    autocmd BufRead,BufNewFile */terminal*/*.{c,h} setlocal sw=4 ts=8 expandtab
    autocmd BufRead,BufNewFile */uemacs*/*.{c,h} setlocal sw=8 ts=8 noexpandtab
    autocmd BufRead,BufNewFile */unreal*/*.{c,cpp,h} setlocal shiftwidth=4 tabstop=4 noexpandtab
    autocmd BufRead,BufNewFile */zsh*/*.[ch] setlocal sw=4 ts=8 noexpandtab

    autocmd QuickFixCmdPost [^l]* nested cwindow
    autocmd QuickFixCmdPost    l* nested lwindow

    " Highlight the current line in the current buffer
    " TODO: Disable cursorline in leaving buffer on :split
    if exists("&cursorline")
        autocmd BufEnter * setlocal cursorline
        autocmd BufLeave * setlocal nocursorline
        "set cursorline
    endif
endif

if has("eval")
    let is_bash = 1	" use bash syntax for #!/bin/sh files
endif

" SEARCH OPTIONS
set hlsearch	" disable highlighting of matches
set incsearch	" jump to partial match as you type
set noignorecase	" case is important in search terms
set tags+=./tags;/	" search up the tree for tags files

" LOCAL CUSTOMIZATIONS
if filereadable(expand("~/.vimrc.local"))
    source ~/.vimrc.local
endif

" vi: set sw=4 ts=33 noet:
