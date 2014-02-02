# zsh-specific commands for all sessions.

# Red Hat's /etc/zshrc and /etc/zprofile break things
unsetopt GLOBAL_RCS

#emulate ksh

setopt banghist
setopt braceexpand
setopt correct
setopt histignorespace
setopt histreduceblanks

# nofunctionargzero so that $0 tells us if a script was sourced or run
unsetopt functionargzero
setopt globsubst
setopt interactivecomments
setopt ksharrays
setopt kshglob
unsetopt nomatch
setopt posixbuiltins
setopt promptsubst
setopt rmstarsilent
setopt shfileexpansion
setopt shglob
setopt shwordsplit

setopt autocd
setopt autolist
unsetopt automenu
unsetopt bareglobqual
setopt checkjobs
setopt extendedglob
setopt equals
setopt listrowsfirst
unsetopt menucomplete
setopt numericglobsort
setopt promptpercent
setopt pushdsilent

# read .env in .zshrc for compatibility with other POSIX shells
