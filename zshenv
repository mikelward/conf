# $Id$
# zsh-specific commands for all sessions.

# Red Hat's /etc/zshrc and /etc/zprofile break things
unsetopt GLOBAL_RCS

#emulate ksh

setopt banghist
setopt braceexpand
setopt correct
setopt histignorespace
setopt histreduceblanks

unsetopt bareglobqual
setopt checkjobs
setopt globsubst
setopt interactivecomments
setopt ksharrays
setopt kshglob
setopt posixbuiltins
setopt promptsubst
setopt shfileexpansion
setopt shglob
setopt shwordsplit

setopt autolist
setopt automenu
setopt equals
setopt listrowsfirst
setopt numericglobsort
setopt promptpercent
setopt pushdsilent

# read .env in .zshrc for compatibility with other POSIX shells
