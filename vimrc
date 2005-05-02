" $Id$
" Vim startup commands

" DEFAULT OPTIONS
set nocompatible                " make Vim default to nicer options

" READING OPTIONS
set modeline                    " use settings from file being edited

" INPUT OPTIONS
if has("mouse")
    "set mouse=a                " uncomment to enable extended mouse support
endif

" COMMAND OPTIONS
set wildmenu                    " ambiguous filename completion shows menu
set wildmode=longest:full       " filename completion lists when ambiguous

" DISPLAY OPTIONS
"set list                      " don't specially mark characters by default
:if version >= 600
    "set listchars=tab:\|\ ,trail:_,extends:>,precedes:<,eol:$
    "set listchars=tab:\|\ ,trail:_,extends:>,precedes:<
    set listchars=tab:>-,trail:-,extends:>,precedes:<
:elseif version >= 500
    "set listchars=tab:\|\ ,trail:_,extends:+
    set listchars=tab:>-,trail:-,extends:+
:endif
set more                        " use a pager for long listings
set nonumber                    " don't show line numbers
set notitle                     " don't change terminal's title
set laststatus=2                " always show status line for each window
set showmode                    " always show command or insert mode
set shortmess=aoOtTI            " brief messages, no ENTER to continue, no intro
set sidescroll=1		" scroll sideways smoothly
"set tabstop=8                   " real tabs are every 8 columns
set nowrap                      " don't wrap long lines
if has("cmdline_info")
    set showcmd                 " show partial commands
    set ruler                   " show line and column information
endif
if has("syntax")
    syntax on                   " use syntax highlighting if available
endif

" SAVING OPTIONS
"set backup                      " save a copy of the original file
set backupext=~                 " backup files end in ~
"set expandtab                   " convert tabs into spaces

" EDITING OPTIONS
set autoindent                  " new line inherits previous line's indentation
set backspace=2                 " backspaces can go over lines
set esckeys                     " allow arrow keys in insert mode
set noerrorbells visualbell     " flash screen instead of ringing bell
set shiftround                  " manual shift aligns on columns
set showmatch                   " show matching brackets
set shiftround                  " indentation aligns on columns
"set shiftwidth=4                " indentation width is 4 spaces
set showbreak=+                 " specially mark continued lines with a plus
set smartindent                 " automatically indent program code
set smarttab                    " tab does indent at start, tab otherwise
"set softtabstop=4               " tab inserts spaces but feels like tabs
"set textwidth=78                " wrap lines at 78 columns

" SEARCH OPTIONS
set nohlsearch                  " don't highlight matches after searching
set incsearch                   " search while typing
set noignorecase                " make searches case-sensitive
set tags+=./tags;/              " search up the tree for tags files
set nowrapscan                  " do not allow searches to wrap beyond end of file

" BINARY EDITING
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

