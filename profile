# $Id$
#
# POSIX shell login session startup commands
#
# This scripts contains common initialization commands for the initial
# log in session for all POSIX-compatible shells.

# read environment
test -f "$HOME"/.shrc && export ENV="$HOME"/.shrc

# start an SSH agent if necessary
if test -z "$SSH_AUTH_SOCK"
then
    exists ssh-agent && eval `ssh-agent -s`
fi

# interactive commands
if exists tty && quiet tty
then
    # disable flow control so applications can use ^Q and ^S
    exists stty && stty -ixon

    # obtain SSH credentials
    if test -n "$SSH_AUTH_SOCK"
    then
        if exists ssh-add && ! quiet ssh-add -l
        then
            ssh-add
        fi
    fi

    # obtain Kerberos credentials
    if exists klist && ! klist -s
    then
        exists kinit && kinit
    fi
fi

# set a script that will be sourced on exiting the shell
test -f "$HOME"/.exitrc && trap ". $HOME/.exitrc" EXIT

# read local commands
test -f "$HOME"/.profile.local && . "$HOME"/.profile.local

# vi: set sw=4 ts=33:
