# $Id$
# bash-specific commands to run for all interactive shells.

# commands common to all sh-like shells
if test -f ~/.shrc
then
	. ~/.shrc
fi

# bash options
shopt -s checkwinsize
shopt -s lithist
shopt -s extglob	# ksh-like globbing
shopt -s xpg_echo

# ksh style aliases
alias command='command '
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
			echo "Unknown option $1"
			return
			;;
		esac
	done
	shift $(($OPTIND - 1))

	opts=-
	# whence translates to command -v
	test -z "$verbose" && opts="${opts}v"
	# whence -v translates to command -V
	test -n "$verbose" && opts="${opts}V"
	# whence -p searches only the default PATH
	test -n "$pathonly" && opts="${opts}p"

	for arg
	do
		if test -n "$pathonly"
		then
			typeset path=`type -P "$arg"`
			if test -n "$path"
			then
				if test -n "$verbose"
				then
					echo "$arg is $path"
				else
					echo "$path"
				fi
			fi
		elif test -z "$verbose" && `type -t "$arg" | grep -q alias`
		then
			command $opts -v "$arg" | sed -e 's/^alias [^ ]*=//'
		else
			command $opts "$arg"
		fi
	done
}

# set the title when we run a command
setcommandhook()
{
	if test "${BASH_VERSINFO[0]}" = "3" -a "${BASH_VERSINFO[1]}" -gt "1"
	then
		trap 'command=$BASH_COMMAND; eval settitle "\"${title}\""; trap - DEBUG' DEBUG
	fi
}

# prompt and window title
if test -n "${title}"
then
	PROMPT_COMMAND='laststatus="$?"; command=; eval settitle "\"${title}\""; setcommandhook'
fi
if test -n "${promptstring}"
then
    if test "${BASH_VERSINFO[0]}" = "3" -a "${BASH_VERSINFO[1]}" = "1"
    then
        PS1='$(setcolor ${promptcolor})$(eval echo -n "\"${promptstring}\"")$(setcolor "normal")'
		case $TERM in putty|xterm*)
			PS1="$PS1"'$(bell)'
			;;
		esac
    else
        PS1='\[$(setcolor ${promptcolor})\]$(eval echo -n "\"${promptstring}\"")\[$(setcolor "normal")\]'
		case $TERM in putty|xterm*)
			PS1="$PS1"'\[$(bell)\]'
			;;
		esac
    fi
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
	complete -d cd pushd popd pd po
	complete $COMPDEF -g chgrp
	complete $COMPDEF -u chown
	complete -j fg
	complete -j kill
	complete $COMPDEF -c command
	complete $COMPDEF -c exec
	complete $COMPDEF -c man
	complete -e printenv
	complete -G "*.java" javac
	complete -F complete_runner -o nospace -o bashdefault nohup
	complete -F complete_runner -o nospace -o bashdefault sudo
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
        i=0
        for arg
        do
            COMPREPLY[$i]=$arg
            i=`expr $i + 1`
        done
    }

	# completion function for commands such as sudo that take a
	# command as the first argument but should revert to file
	# completion for subsequent arguments
	complete_runner()
	{
		# completing the command name
		if test "$1" = "$3"
		then
			set -- `compgen -c "$2"`
		# completing other arguments
		else
			set -- `compgen -o default "$2"`
		fi
		if test $# -eq 1
		then
			if test -d "$1"
			then
				COMPREPLY[0]=$1/
			else
				COMPREPLY[0]=$1" "
			fi
		else
		i=0
			for arg
			do
				COMPREPLY[$i]=$arg
				i=`expr $i + 1`
			done
		fi
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

bind -m vi-command '"!"':history-expand-line
# for some reason glob-expand-word doesn't work here, but insert-completions is fine
bind -m vi-command '"*"':insert-completions

# disable Ctrl+D = EOF
IGNOREEOF=yes

# finish with a zero exit status
true
