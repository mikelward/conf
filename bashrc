# .bashrc - Bash startup commands
# $Id$

# source the user's environment file
if test -z "$ENV"
then
	if test -f "$HOME"/.shrc
	then
		ENV="$HOME"/.shrc
	fi
	export ENV
fi
if test -n "$ENV"
then
	. "$ENV"
fi

# set shell options
shopt -s checkwinsize
shopt -s cmdhist
shopt -s extglob
shopt -s histappend
shopt -u huponexit
shopt -s xpg_echo

# ksh style cd
cd()
{
	opts=
	case $1 in
	-*)
		opts=$1
		shift
		;;
	esac

	case $# in
	2)
		builtin cd $opts "${PWD/$1/$2}"
		;;
	1)
		builtin cd $opts "$1"
		;;
	0)
		builtin cd $opts "$HOME"
		;;
	esac
}

# set environment for interactive sessions
case $- in *i*)

	# set the prompt
	#PS1='\[\e[1m\]\n\u@\h $PWD\n\$\[\e[0m\] '
	if type tput >& /dev/null
	then
		PS1='\[`tput bold`\]\n\u@\h ${PWD/#$HOME/~}\n\$\[`tput sgr0`\] '
	else
		#PS1='\[\e[1m\]\n\u@\h ${PWD/#$HOME/~}\n\$\[\e[0m\] '
		PS1='\n\u@\h ${PWD/#$HOME/~}\n\$ '
	fi

	# set the xterm title
	case "$TERM" in
	aixterm|dtterm|rxvt|xterm*)
		PROMPT_COMMAND='echo -n "]0;${HOSTNAME%%.*}<${TTY##/*/}>"'
		#PROMPT_COMMAND='echo -n "]0;${USER}@${HOSTNAME%%.*}<${TTY##/*/}>"'
		;;
	screen*)
		PROMPT_COMMAND='echo -n "]0;${HOSTNAME%%.*}<${TTY##/*/}>"'
		#PROMPT_COMMAND='echo -n "]0;${USER}@${HOSTNAME%%.*}<${TTY##/*/}>"'
		;;
	esac

	# set command completions
	if type complete >& /dev/null
	then
		complete -a {,un}alias
		complete -d {c,push,pop}d
		complete -o default -g chgrp
		complete -o default -u chown
		complete -j fg
		complete -j kill
		complete -c command
		complete -o default -c exec
		complete -o default -c man
		complete -o default -c sudo
		complete -e printenv
		complete -G "*.java" javac
	fi
	;;
esac

