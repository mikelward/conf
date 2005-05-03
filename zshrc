# -*- mode: sh -*-
# $Id$
# Z Shell interactive session startup commands

# update the xterm title after every command
precmd()
{
	[[ -t 1 ]] || return
	local ts
	local tf
	case $TERM in
	aixterm|dtterm|putty|rxvt|xterm*)
		ts="\e]0;"
		tf="\a"
		;;
	screen*)
		ts="\e]k"
		tf="\e]\\"
		;;
	*)
		ts="`tput tsl`"
		tf="`tput fsl`"
		;;
	esac
	test -n "$ts" && print -Pn "${ts}%m<$(basename $(tty))> %n $0${tf}"
}

# update the xterm title when running a command
preexec()
{
	[[ -t 1 ]] || return
	local ts
	local tf
	local comm
	case $1 in
	# resuming an existing job
	fg*|%*)
		local spec
		spec=${1#fg}
		case $spec in
		[0-9]*)
			# process identifier
			comm=$(ps -o comm= -p $spec)
			;;
		*)
			# job identifier
			# normalise %, %+, and %% to +, otherwise just strip %
			spec=$(echo $spec | sed -e 's/^%%\?//')
			spec=${spec:-+}
			case $spec in
			+|-)
				# find job number from zsh's $jobstates array
				local i=0
				for jobstate in $jobstates
				do
					i=$(($i+1))
					echo $jobstate | IFS=: read state mark pidstate
					if test "$mark" = "$spec"
					then
						job=$i
						break
					fi
				done
				comm=$jobtexts[$job]
				;;
			\?*)
				# job string search unsupported
				comm=unknown
				;;
			*)
				comm=$jobtexts[$spec]
				;;
			esac
			;;
		esac
		;;
	# executing a new command
	*)
		comm=$1
		;;
	esac
	case $TERM in
	aixterm|dtterm|putty|rxvt|xterm*)
		ts="\e]0;"
		tf="\a"
		;;
	screen*)
		ts="\e]k"
		tf="\e]\\"
		;;
	*)
		ts="`tput tsl`"
		tf="`tput fsl`"
		;;
	esac
	test -n "$ts" && print -Pn "${ts}%m<$(basename $(tty))> %n ${comm}${tf}"
}

# set prompt
prompt='
%B%n@%m `dirs`
%#%b '

# set non-alphanumeric characters that constitute a word
# (remove / so Alt-Backspace deletes only one path component)
# (remove <>& so redirection not part of path)
# (remove ; so command list separator not part of word)
#WORDCHARS=
WORDCHARS="`echo $WORDCHARS | sed -e 's/[/<>&;]\+//'`"

# set key bindings
bindkey -e
bindkey '^X?' expand-cmd-path
bindkey '^[p' history-beginning-search-backward
bindkey '^[n' history-beginning-search-forward

# enable some options originally from csh
setopt banghist
setopt braceexpand
#setopt chasedots
setopt correct
#setopt cshnullglob
setopt extendedglob
#setopt extendedhistory
setopt histignorespace
setopt histreduceblanks
setopt nohup
#setopt nomatch
setopt noksharrays

# set some options originally from ksh
setopt interactivecomments
#setopt kshglob
setopt markdirs
#setopt shwordsplit
setopt promptsubst

# set some zsh-specific options
setopt appendhistory
setopt autocd
setopt autolist
#setopt autopushd
setopt automenu
setopt nobeep
setopt incappendhistory
#unsetopt listbeep
setopt listrowsfirst
setopt magicequalsubst
setopt numericglobsort
#setopt nullglob
setopt pathdirs
setopt promptpercent

# set aliases
alias h='history'
alias j='jobs -l'
alias l='ls -Fx'
alias l.='ls -d .*'
alias la='ls -a'
alias ll='ls -l'
alias lt='ls -t'
alias latest='ls -lt | head'
alias psme='ps -fU $USER'

# set command completions
compctl -a {,un}alias
compctl -b bindkey
compctl -/ {c,push,pop}d
compctl -E {print,set,unset}env
compctl -c exec
compctl -j fg
compctl -j kill
compctl -c man
compctl -u {ch}own
compctl -o {set,unset}opt
compctl -c {whence,where,which}

