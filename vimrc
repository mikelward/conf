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
set nowrap	" don't wrap long lines (show extends character instead)
set more	" use a pager for long listings
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

" Show a gray vertical line at &textwidth (default 80) columns
if exists("+colorcolumn")
  set colorcolumn=+1
endif
highlight ColorColumn term=reverse ctermbg=lightgrey guibg=lightgrey

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
set cinoptions=:0,g0	" labels are not indented (in C/C++ files)
set cinoptions+=(0	" hanging indent to align function parameters
set completeopt=menu,menuone	" ^X^O shows a menu
set completeopt+=longest,preview	" ^X^O shows a help/docstring preview
set expandtab	" use spaces rather than tabs for indentation
set smarttab	" backspace deletes one indentation level
set shiftround	" manual shift aligns on columns

set backspace=2	" backspaces can go over lines
set esckeys	" allow arrow keys in insert mode
set noerrorbells visualbell	" flash screen instead of ringing bell
set showbreak=+	" specially mark continued lines with a plus

if has("x11") && has("unnamedplus")
    set clipboard=unnamedplus	" yank to X selection buffer
endif

" allow # character at current indentation level (must appear on own line)
inoremap # X<BS>#

function! ShowWhitespace()
    let b:show_whitespace = 1
    echo "Showing whitespace"
    set list
endfunction
function! HideWhitespace()
    let b:show_whitespace = 0
    echo "Hiding whitespace"
    set nolist
endfunction
function! ToggleWhitespace()
    if !exists("b:show_whitespace") || !b:show_whitespace
        call ShowWhitespace()
    else
        call HideWhitespace()
    endif
endfunction
set listchars=tab:\|\ ,trail:_       " tab is "|   ", trail is "_"
if version >= 600
    set listchars+=extends:>,precedes:<
endif
if version >= 700
    set listchars+=nbsp:%
endif
set nolist

function! TogglePaste()
  if &paste
    set nopaste
    echo "Disabling paste mode"
  else
    set paste
    echo "Enabling paste mode"
  endif
endfunction

map <Leader>c :TComment<CR>
map <Leader>w :call ToggleWhitespace()<CR>
map <Leader>p :call TogglePaste()<CR>

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
    " teach Vim about .go files
    au BufRead,BufNewFile *.go setfiletype go

    " per file-type rules
    au BufRead,BufNewFile * if &filetype == 'fstab' | set listchars+=tab:>\  | endif
    au BufRead,BufNewFile * if &filetype == 'go' | set shiftwidth=8 tabstop=8 textwidth=0 noexpandtab | endif
    au BufRead,BufNewFile * if &filetype == 'svn' | set viminfo= | endif

    " make :make jump to C assertion errors
    au BufRead,BufNewFile * if &filetype == 'c' | set errorformat^=%*[^:]:\ %f:%l:\ %m | endif

    " when creating a new file, use a template from ~/templates/template.<filetype extension>
    au BufNewFile * call ReadTemplate() | call AppendModeline()
    fun! ReadTemplate()
        let b:filename = bufname('%')
        let b:extension = substitute(b:filename, '.*\.\(.*\)', '\1', '')
        let b:template = $HOME . '/templates/template.' . b:extension
        if filereadable(b:template)
          call setline(1, readfile(b:template))
          let b:lastline = line('$')
          call setpos('.', [0, b:lastline, 0, 0])
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

    nnoremap <leader>m :call AppendModeline()<CR>

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
    au BufRead,BufNewFile */apt*/*.{c,cc,h} setlocal sw=4 ts=8 noexpandtab
    au BufRead,BufNewFile */bash*/*.{c,h} setlocal sw=2 ts=8 expandtab cinoptions=>4,n-2,{2,^-2,:2,=2,g0,h2,p5,t0,+2,(0,u0,w1,m1
    au BufRead,BufNewFile */coreutils*/*.{c,h} setlocal sw=2 ts=8 expandtab cinoptions=>4,n-2,{2,^-2,:2,=2,g0,h2,p5,t0,+2,(0,u0,w1,m1
    au BufRead,BufNewFile */ersatz*/*.{c,h} setlocal sw=2 ts=8 noexpandtab
    au BufRead,BufNewFile */gnome-terminal*/*.{c,h} setlocal sw=2 ts=8 expandtab cinoptions=>4,n-2,{2,^-2,:2,=2,g0,h2,p5,t0,+2,(0,u0,w1,m1
    au BufRead,BufNewFile */nagios*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    au BufRead,BufNewFile */openbsd*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    au BufRead,BufNewFile */postfix*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    au BufRead,BufNewFile */procmail*/*.{c,h} setlocal sw=3 ts=8 noexpandtab
    au BufRead,BufNewFile */putty*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    au BufRead,BufNewFile */sudo*/*.{c,h} setlocal sw=4 ts=8 noexpandtab
    au BufRead,BufNewFile */terminal*/*.{c,h} setlocal sw=4 ts=8 expandtab
    au BufRead,BufNewFile */uemacs*/*.{c,h} setlocal sw=8 ts=8 noexpandtab
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
