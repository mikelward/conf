# $Id$
#
# C Shell login session startup commands

# set environment script in case a Bourne-like shell is invoked within csh
test -f "$HOME"/.shrc && setenv ENV "$HOME"/.shrc

# start the ssh agent
if ! ( $?SSH_AUTH_SOCK ) then
    eval `ssh-agent`
endif

# commands that only work when running on a terminal
if ( { tty } ) >& /dev/null then
    # disable flow control so applications can use ^Q and ^S
    if ( { which stty } ) >& /dev/null stty -ixon

    # obtain SSH credentials
    if ( { which ssh-add } && ! { ssh-add -l ) > /dev/null then
        ssh-add
    endif
endif

# read local settings (company environment, etc.)
if ( -r ~/.login.local ) then
    source ~/.login.local
endif

# vi: set sw=4 ts=33:
