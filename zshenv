# $Id$
#
# Z Shell common startup commands
#
# This script contains zsh-specific customizations and enhancements
# for all sessions.
# Common POSIX-compatible functions and settings are included from
# .shrc.

# read the common environment for all POSIX shells
# (must be a function so the emulate command only affects the
# execution of statements from ~/.shrc)
source_common_commands()
{
    emulate -L ksh
    if test -f ~/.shrc
    then
        export ENV=~/.shrc
        source ~/.shrc
    else
        export ENV=
    fi
}

source_common_commands

# enable some options originally from csh
setopt banghist
setopt braceexpand
setopt correct
setopt histignorespace
setopt histreduceblanks
setopt noksharrays

# set some options originally from ksh
setopt checkjobs
setopt interactivecomments
setopt kshglob
setopt promptsubst

# set some zsh-specific options
setopt appendhistory
setopt autocd
setopt autolist
setopt automenu
setopt extendedhistory
setopt globdots
setopt incappendhistory
setopt nolistambiguous
setopt nolistbeep
setopt listrowsfirst
setopt magicequalsubst
setopt numericglobsort
setopt nullglob
setopt promptpercent

# vi: set sw=4 ts=33:
