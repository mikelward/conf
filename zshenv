# $Id$
# zsh-specific commands for all sessions.

# Red Hat's /etc/zshrc and /etc/zprofile break things
unsetopt GLOBAL_RCS

emulate ksh

setopt banghist
setopt braceexpand
setopt correct
setopt histignorespace
setopt histreduceblanks

unsetopt bareglobqual
setopt checkjobs
setopt interactivecomments
setopt kshglob
setopt posixbuiltins
setopt promptsubst
setopt shwordsplit

setopt autolist
setopt automenu
setopt listrowsfirst
setopt promptsubst
setopt pushdsilent

# read .env in .zshrc for compatibility with other POSIX shells
