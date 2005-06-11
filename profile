# -*- mode: sh -*-
# $Id$
#
# POSIX shell login session startup commands
#
# This scripts contains common initialization commands for the initial
# log in session for all POSIX-compatible shells.

# read environment
test -f "$HOME"/.shrc && export ENV="$HOME"/.shrc

# start the ssh agent if one isn't already running
if test -z "$SSH_AUTH_SOCK"
then
    type ssh-agent >/dev/null 2>&1 && eval `ssh-agent -s`
    type ssh-add >/dev/null 2>&1 && ssh-add </dev/null
    type ssh-add >/dev/null 2>&1 && ssh-add -l >/dev/null 2>&1
    if test $? -ne 0
    then
        echo "No SSH identities" 1>&2
    fi
fi

# interactive commands
if type tty >/dev/null 2>&1 && tty >/dev/null 2>&1
then
    # disable output control so applications can use ^Q and ^S
    type stty >/dev/null 2>&1 && stty -ixon
fi

# set a script that will be sourced on exiting the shell
test -f "$HOME"/.exitrc && trap ". $HOME/.exitrc" EXIT

# read local commands
test -f "$HOME"/.profile.local && . "$HOME"/.profile.local

