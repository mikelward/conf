# bash-specific commands to run for all interactive shells.

# commands common to all sh-like shells
if test -f ~/.shrc
then
	. ~/.shrc
fi

# bash options
shopt -s autocd
shopt -s checkwinsize
shopt -s lithist
shopt -s extglob	# ksh-like globbing
shopt -s xpg_echo

# ksh style aliases
alias autoload='typeset -fu'
alias float='typeset -E'
alias functions='typeset -f'
alias integer='typeset -i'
alias nameref='typeset -n'
alias nohup='nohup '
alias r='fc -s'
alias redirect='command exec'
alias stop='kill -s STOP'
alias sudo='sudo '
# ksh-like command alias expands aliases, defeating the purpose of command
if alias command >/dev/null 2>&1
then
	unalias command
fi

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
		builtin cd $opts "${PWD/$1/$2}" >/dev/null
		;;
	1)
		builtin cd $opts "$1" >/dev/null
		;;
	0)
		builtin cd $opts "$HOME" >/dev/null
		;;
	esac
}

# pop a directory without printing the directory stack
popd()
{
	command popd "$@" >/dev/null
}

# push a directory without printing the directory stack
pushd()
{
	command pushd "$@" >/dev/null
}


# ksh style whence
whence()
{
	typeset arg opts pathonly verbose
	OPTIND=1
	pathonly=false
	verbose=false
	while getopts pv flag
	do
		case $flag in
		p)
			pathonly=true
			;;
		v)
			verbose=true
			;;
		*)
			printf "%s\n" "Unknown option $1"
			return
			;;
		esac
	done
	shift $(($OPTIND - 1))

	if $pathonly; then
		type -P "$@"
	elif $verbose; then
		command -V "$@"
	else
		command -v "$@"
	fi
}

getcommand()
{
	case $1 in
	fg|%*)
		test "$1" = "fg" && shift
		if test $# -eq 0
		then
			jobs %+ 2>/dev/null | while read num state rest
			do
				printf "%s\n" "$rest"
				break
			done
		else
			jobs "$@" 2>/dev/null | while read num state rest
			do
				printf "%s\n" "$rest"
				break
			done
		fi
		;;
	*)
	for arg in "$@"
	do
		printf "%s " "$arg"
	done
	printf "\n"
		;;
	esac
}


precmd()
{
	laststatus=$?
	command=
	eval settitle "\"${title}\""
	setcolor "$promptcolor"
	eval "echo \"${preprompt}\""
	case $TERM in putty|xterm*)
		bell;;
	esac
}

preexec()
{
	command=$(getcommand $BASH_COMMAND)
	eval "settitle \"$title\""
	setcolor normal
}

has_debug_trap=false
if trap '' DEBUG >/dev/null 2>&1; then
	has_debug_trap=true
fi

PROMPT_COMMAND='precmd'
trap preexec DEBUG

if $has_debug_trap; then
	commandcolor=bold
	PS1="$PS1"'\[$(setcolor ${commandcolor})\]'
fi

# history format
HISTTIMEFORMAT="%H:%M	"

# custom tab completions
if type complete >/dev/null 2>&1
then
	if complete -o >/dev/null 2>&1
	then
		COMPDEF="-o complete"
	else
		COMPDEF="-o default"
	fi
	complete -a alias unalias
	complete -o bashdefault -d cd pushd popd pd po
	complete $COMPDEF -g chgrp 2>/dev/null
	complete $COMPDEF -u chown
	complete -j fg
	complete -j kill
	complete $COMPDEF -c command
	complete $COMPDEF -c exec
	complete $COMPDEF -c man
	complete -e printenv
	complete -G "*.java" javac
	complete -F complete_runner -o nospace -o default nohup 2>/dev/null
	complete -F complete_runner -o nospace -o default sudo 2>/dev/null
	complete -F complete_services service
	complete -F complete_pcp_archive {pmdumptext,pminfo,pmstat,pmval,acxstat}

	# the -a argument to most PCP commands is looking for a .0 file
	complete_pcp_archive()
	{
		if test "$3" = "-a"
		then
			set -- `compgen -f -X '!*.0' $2`
		else
			set -- `compgen -f $2`
		fi
		COMPREPLY=("$@")
	}

	# completion function for commands such as sudo that take a
	# command as the first argument but should complete the second
	# argument as if it was the first
	complete_runner()
	{
		# completing the command name
		# $1 = sudo
		# $3 = sudo
		# $2 = partial command (or complete command but no space was typed)
		if test "$1" = "$3"
		then
			set -- `compgen -c "$2"`
		# completing other arguments
		else
			# $1 = sudo
			# $3 = command after sudo (i.e. second word)
			# $2 = arguments to command
			# use the custom completion as printed by complete -p,
			# fall back to filename/bashdefault
			local comps
			comps=`complete -p "$3" 2>/dev/null`
			# "complete -o default -c man" => "-o default -c"
			# "" => "-o bashdefault -f"
			comps=${comps#complete }
			comps=${comps% *}
			comps=${comps:--o bashdefault -f}
			set -- `compgen $comps "$2"`
		fi
		COMPREPLY=("$@")
	}

	# completion function for Red Hat service command
	complete_services()
	{
		OIFS="$IFS"
		IFS='
		'
		local i=0
		for file in $(find /etc/init.d/ -type f -name "$2*" -perm -u+rx)
		do
			file=${file##*/}
			COMPREPLY[$i]=$file
			i=$(($i + 1))
		done
		IFS="$OIFS"
	}
fi

case $- in *i*)
	bind -m vi-command '"!"':history-expand-line >/dev/null 2>&1
	# for some reason glob-expand-word doesn't work here, but insert-completions is fine
	bind -m vi-command '"*"':insert-completions >/dev/null 2>&1
	;;
esac

# disable Ctrl+D = EOF
IGNOREEOF=yes

# finish with a zero exit status
true

# vim: set ts=4 sw=4 tw=0 noet:
