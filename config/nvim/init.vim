set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath
source ~/.vimrc
" make it easier to get to command mode from terminal mode
tnoremap <Esc> <C-\><C-n>
" make "cw" consistent with other "w" commands
set cpoptions-=_
