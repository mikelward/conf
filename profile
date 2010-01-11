# $Id$
# Commands to run for any POSIX shell when the user logs in.

# interactive sub-shells run .env, unless this is bash or zsh, because they already ran .env in .bashrc or .zshrc
if test -z "$BASH_VERSION" -a -z "$ZSH_VERSION" || test -n "$BASH_VERSION" -a \( "${BASH##*/}" = "sh" \)
then
	if test -f "$HOME"/.env
	then
		. "$HOME"/.env
	fi
fi

# the name is confusing, but POSIX says $ENV will be automatically run after .profile,
# (bash and zsh don't run $ENV, but this is needed in case sh is started from inside bash or zsh)
if test -f "$HOME"/.shrc
then
	export ENV="$HOME"/.shrc
fi

# set a script that will be sourced on exiting the shell
test -f "$HOME"/.exitrc && trap ". $HOME/.exitrc" EXIT

# start the SSH agent if desired
if false
then
	if test -z "$GNOME_KEYRING_PID"
	then
		if test -z "$SSH_AUTH_SOCK"
		then
			if type ssh-agent >/dev/null 2>/dev/null
			then
				eval $(ssh-agent)
			fi
		fi
		if test -n "$SSH_AUTH_SOCK"
		then
			if type ssh-add >/dev/null 2>/dev/null
			then
				if ! ssh-add -l >/dev/null
				then
					ssh-add
				fi
			fi
		fi
	else
		:
		# eval $(gnome-keyring-daemon --start)
		# export SSH_AUTH_SOCK
	fi
fi

# read local commands
test -f "$HOME"/.profile.local && . "$HOME"/.profile.local

if type tty >/dev/null 2>/dev/null && tty >/dev/null
then
	# disable flow control so applications can use ^Q and ^S
	type stty >/dev/null 2>/dev/null && stty -ixon

	# use Ctrl+_ instead of Ctrl+C so we can use Ctrl+C for copy and paste
	#type stty >/dev/null 2>/dev/null && stty intr '^_'

	# use screen if possible
	#type screen >/dev/null 2>/dev/null && exec screen -R
fi

# finish with a zero exit status
true
