# $Id$
#
# POSIX shell login session startup commands
#
# This scripts contains common initialization commands for the initial
# log in session for all POSIX-compatible shells.

# read environment
test -f "$HOME"/.shrc && export ENV="$HOME"/.shrc

# interactive commands
if type tty >/dev/null 2>/dev/null && tty >/dev/null
then
    # disable flow control so applications can use ^Q and ^S
    type stty >/dev/null 2>/dev/null && stty -ixon
fi

# set a script that will be sourced on exiting the shell
test -f "$HOME"/.exitrc && trap ". $HOME/.exitrc" EXIT

# start the SSH agent if desired
if test $WANT_SSH_AGENT
then
    if test -z $SSH_AUTH_SOCK
	then
		if type ssh-agent >/dev/null 2>/dev/null
		then
			eval $(ssh-agent)
		fi
	fi
	if test -n $SSH_AUTH_SOCK
	then
		if type ssh-add >/dev/null 2>/dev/null
		then
			if ! ssh-add -l >/dev/null
			then
				ssh-add
			fi
		fi
	fi
fi

# read local commands
test -f "$HOME"/.profile.local && . "$HOME"/.profile.local

# finish with a zero exit status
true
