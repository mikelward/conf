# zsh-specific commands for all sessions.

# Red Hat's /etc/zshrc and /etc/zprofile break things
unsetopt GLOBAL_RCS

#emulate ksh

setopt banghist
setopt braceexpand
setopt correct
setopt dvorak
setopt histignorespace
# TODO: consider disabling
setopt histreduceblanks

# nofunctionargzero so that $0 tells us if a script was sourced or run
unsetopt functionargzero
# TODO: figure out if the opposite is ever useful
setopt globsubst
# TODO: investigate Ctrl+Z
setopt interactivecomments
setopt ksharrays
setopt kshglob
unsetopt nomatch
setopt posixbuiltins
setopt promptsubst
setopt rmstarsilent
setopt shfileexpansion
# requires globsubst
setopt shglob
# TODO: disable after using emulate everywhere necessary?
setopt shwordsplit

setopt autocd
setopt autolist
# with nomenucomplete, menu is after two Tabs
setopt automenu
# *(/) is awesome
setopt bareglobqual
setopt checkjobs
setopt equals
setopt listrowsfirst
# with automenu, menu is after two Tabs
unsetopt menucomplete
# TODO: just use <->?
setopt numericglobsort
# for %{...%} in particular
setopt promptpercent
setopt pushdsilent

# read .env in .zshrc for compatibility with other POSIX shells
