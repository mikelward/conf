# .profile - Bourne Shell login session startup commands
# $Id$

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
if type ssh-agent > /dev/null 2>&1
then
	test -z "$SSH_AUTH_SOCK" && eval `ssh-agent -s`
fi

# interactive commands
if `tty > /dev/null 2>&1`
then
	# disable output control so applications can use ^Q and ^S
	stty -ixon

	# prompt for ssh passphrases to remember
	ssh-add < /dev/null
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

