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
highlight clear CursorLine
highlight clear CursorLineNr
highlight clear SignColumn
highlight clear NonText
highlight clear SpecialKey
highlight clear SignatureMarkText
highlight clear SignatureMarkerText


" Set up some simple non-intrusive colors
if &background == "light"
    highlight String term=underline cterm=NONE ctermfg=DarkGreen
    highlight Comment term=bold cterm=NONE ctermfg=DarkBlue
    highlight Error term=standout cterm=NONE ctermfg=DarkRed
    highlight NonText term=bold cterm=NONE ctermfg=DarkYellow
    highlight LineNr term=reverse cterm=NONE ctermfg=Gray ctermbg=White
    highlight CursorLineNr term=reverse cterm=reverse
    highlight Visual term=reverse cterm=reverse ctermfg=NONE ctermbg=NONE
else
    highlight String term=underline cterm=NONE ctermfg=LightGreen
    highlight Comment term=bold cterm=NONE ctermfg=LightBlue
    highlight Error term=standout cterm=NONE ctermbg=LightRed
    highlight NonText term=bold cterm=NONE ctermfg=LightYellow
    highlight LineNr term=NONE cterm=NONE ctermfg=Gray ctermbg=Black
    highlight CursorLineNr term=reverse cterm=reverse
    highlight Visual term=reverse cterm=reverse ctermfg=NONE ctermbg=NONE
endif

if exists("+colorcolumn")
    highlight clear ColorColumn
    highlight link ColorColumn Error
endif
highlight link SpecialKey NonText
highlight link SignColumn LineNr
highlight link SignatureMarkText LineNr
highlight link SignatureMarkerText LineNr
