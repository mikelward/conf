# -*- mode: sh -*-
# $Id$
# Bourne Shell login session startup commands

# read environment
if test -f "$HOME"/.shrc
then
	ENV="$HOME"/.shrc
fi
if test -n "$ENV"
then
	export ENV
fi

# start the ssh agent if one isn't already running
if test -z "$SSH_AUTH_SOCK"
then
	type ssh-agent >/dev/null 2>&1 && eval `ssh-agent -s`
	type ssh-add >/dev/null 2>&1 && ssh-add </dev/null
fi

# interactive commands
if type tty >/dev/null 2>&1 && tty >/dev/null 2>&1
then
	# disable output control so applications can use ^Q and ^S
	type stty >/dev/null 2>&1 && stty -ixon
fi

# set a script that will be sourced on exiting the shell
if test -f "$HOME"/.exitrc
then
	trap ". $HOME/.exitrc" EXIT
fi

# read local commands
if test -f "$HOME"/.profile.local
then
	. "$HOME"/.profile.local
fi

