if exists("loaded_autoswap")
    finish
endif
let loaded_autoswap = 1

" Preserve external compatibility options, then enable full vim compatibility...
let s:save_cpo = &cpo
set cpo&vim

augroup AutoSwap
    autocmd!
    autocmd SwapExists *  call HandleSwapfile(expand('<afile>:p'))
augroup END

function! HandleSwapfile (filename)
    call EchoOnBufEnter("Swapfile detected, opening read-only")
    let v:swapchoice = 'o'
endfunction

" Print a message after the autocommand completes
" (so you can see it, but don't have to hit <ENTER> to continue)...
function! EchoOnBufEnter (msg)
    augroup BufEnterEcho
        autocmd!
        " Print the message on finally entering the buffer...
        exec 'autocmd BufWinEnter *  echon "\r'.printf("%-60s", a:msg).'"'

        " And then remove these autocmds, so it's a "one-shot" deal...
        autocmd BufWinEnter *  augroup BufEnterEcho
        autocmd BufWinEnter *  autocmd!
        autocmd BufWinEnter *  augroup END
    augroup END
endfunction

" Restore previous external compatibility options
let &cpo = s:save_cpo
