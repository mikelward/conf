" Vim color file
" Maintainer:	Mikel Ward <mikel@mikelward.com>

" Remove all existing highlighting and set the defaults.
highlight clear

" Load the syntax highlighting defaults, if it's enabled.
"if exists("syntax_on")
"    syntax reset
"endif

let colors_name = "basic"

" Remove all highlighting
highlight clear Constant
highlight clear Number
highlight clear Statement
highlight clear PreProc
highlight clear Type
highlight clear Special
highlight clear Identifier

highlight clear String
highlight clear Comment
highlight clear Error
highlight clear LineNr
highlight clear SignColumn
highlight clear NonText
highlight clear SpecialKey


" Set up some simple non-intrusive colors
if &background == "light"
    highlight String term=underline cterm=NONE ctermfg=DarkGreen guifg=DarkGreen
    highlight Comment term=bold cterm=NONE ctermfg=DarkBlue guifg=DarkBlue
    highlight Error term=standout cterm=NONE ctermfg=DarkRed guifg=DarkRed
    highlight LineNr term=reverse cterm=NONE ctermfg=DarkYellow guifg=DarkYellow
    highlight clear SignatureMarkText
    highlight link SignatureMarkText LineNr
    highlight NonText term=bold cterm=NONE ctermfg=DarkYellow guifg=DarkYellow
    highlight SpecialKey term=bold cterm=NONE ctermfg=DarkYellow guifg=DarkYellow
    if exists("+colorcolumn")
        highlight clear ColorColumn
        highlight link ColorColumn Error
    endif
    highlight CursorLine term=underline cterm=NONE ctermbg=LightGrey guibg=Grey90
    highlight Visual term=reverse cterm=bold ctermfg=7 ctermbg=4
else
    highlight String term=underline cterm=NONE ctermfg=Magenta guifg=Magenta
    highlight Comment term=bold cterm=NONE ctermfg=Cyan guifg=Cyan
    highlight Error term=standout cterm=NONE ctermbg=Red guifg=Red
    highlight LineNr term=reverse cterm=NONE ctermfg=Yellow guifg=Yellow
    highlight SignatureMarkText term=reverse cterm=NONE ctermfg=Yellow guifg=Yellow
    highlight NonText term=bold cterm=NONE ctermfg=Yellow guifg=Yellow
    highlight SpecialKey term=bold cterm=NONE ctermfg=Yellow guifg=Yellow
    if exists("+colorcolumn")
        highlight clear ColorColumn
        highlight link ColorColumn Error
    endif
    highlight clear SignatureMarkText
    highlight link SignatureMarkText LineNr
    highlight CursorLine term=underline cterm=NONE ctermbg=LightGrey guibg=Grey90
    " TODO: check on dark background
    highlight Visual term=reverse cterm=bold ctermfg=7 ctermbg=4
endif

