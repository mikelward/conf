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

# set the window title
settitle()
{
	if test -n "$TITLESTART"
	then
		eval echo -n \""${TITLESTART}${TITLESTRING}${TITLEFINISH}"\"
	fi
	if test -n "$ICONSTART"
	then
		eval echo -n \""${ICONSTART}${ICONSTRING}${ICONFINISH}"\"
	fi
}

# set environment for interactive sessions
case $- in *i*)

	# set the prompt
	if type tput >/dev/null 2>&1
	then
		BOLD="`tput bold`"
		NORMAL="`tput sgr0`"
	fi
	PS1='\[$BOLD\]\n\u@\h ${PWD/#$HOME/~}\n\$\[$NORMAL\] '

	# set the xterm title
	ICONSTRING='${HOSTNAME%%.*}<${TTY##/*/}>'
	TITLESTRING='${HOSTNAME%%.*}<${TTY##/*/}> ${USER} ${0##/*/} ${PWD}'
	STATUSSTRING='${0##/*/}'
	case "$TERM" in
	aixterm|dtterm|putty|rxvt|xterm*)
		ICONSTART="]1;"
		ICONFINISH=""
		TITLESTART="]2;"
		TITLEFINISH=""
		;;
	esac
	PROMPT_COMMAND='settitle'

	# set command completions
	if type complete >/dev/null 2>&1
	then
		if complete -o >/dev/null 2>&1
		then
			COMPDEF="-o complete"
		fi
		complete -a {,un}alias >/dev/null 2>&1
		complete -d {c,p,push,pop}d,po >/dev/null 2>&1
		complete $COMPDEF -g chgrp >/dev/null 2>1
		complete $COMPDEF -u chown >/dev/null 2>1
		complete -j fg >/dev/null 2>1
		complete -j kill >/dev/null 2>1
		complete $COMPDEF -c command >/dev/null 2>1
		complete $COMPDEF -c exec >/dev/null 2>1
		complete $COMPDEF -c man >/dev/null 2>1
		complete $COMPDEF -c sudo >/dev/null 2>1
		complete -e printenv >/dev/null 2>1
		complete -G "*.java" javac >/dev/null 2>1
	fi
	;;
esac

