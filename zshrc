# $Id: zshenv 174 2005-07-23 04:53:33Z michael $
# zsh-specific commands for interactive sessions.

if test -f ~/.shrc
then
	. ~/.shrc
fi

# set zsh-specific aliases
alias h="history -d"

precmd()
{
	# store the status of the previous interactive command for use in the prompt
	laststatus=$?

	# the currently running foreground job is the shell (without any leading minus)
	command=${0#-}

	# set the window title
	[[ -t 1 ]] && eval settitle "\"$title\""
}

preexec()
{
	# get the canonical name of the command just invoked
	case $1 in
		# resuming an existing job
		fg*|%*)
		local spec
		spec=${1#fg}
		spec=${spec# }
		case $spec in
			[0-9]*)
			# process identifier
			command=$(ps -o comm= -p $spec)
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
				command=$jobtexts[$job]
				;;
				\?*)
				# job name contains $spec
				# string the leading ?
				spec=$(echo $spec | sed -e 's/^\?//')
				for jobtext in $jobtexts
				do
					stripped=$(echo "$jobtext" | sed -e "s/$spec//")
					if test "$jobtext" != "$stripped"
					then
						command=$jobtext
						break
					fi
				done
				#command=unknown
				;;
				*)
				# job name begins with $spec
				for jobtext in $jobtexts
				do
					stripped=$(echo "$jobtext" | sed -e "s/^$spec//")
					if test "$jobtext" != "$stripped"
					then
						command=$jobtext
						break
					fi
				done
				;;
			esac
			;;
		esac
		;;
		# executing a new command
		*)
		command=$1
		;;
	esac

	# set the window title
	[[ -t 1 ]] && eval settitle "\"$title\""

	# reset the terminal attributes (disable bold, underline, reverse, etc.)
	# in case these were set in promptstring or commandstring
	print -n "${normal}"
}

settitle()
{
	test -n "$titlestart" && print -Pn "${titlestart}$*${titlefinish}"
}

commandstring="%{${bold}%}"
commandcolor=bold

# set prompt and window title format
if test -n "$promptstring"
then
	PS1='%{$(setcolor ${promptcolor})%}$(eval echo -n "\"${promptstring}\"")%{$(setcolor "normal")%}%{$(setcolor ${commandcolor})%}'
fi

HISTFILE=~/.zsh_history
SAVEHIST=${HISTSIZE:-128}

# set non-alphanumeric characters that constitute a word
# use defaults (words are separated by whitespace)
#WORDCHARS=
#
# replace the word before the cursor with its realpath
# (resolves symlinks if the word is a file name)
expand-word-path ()
{
	CUTBUFFER=
	zle backward-word
	zle set-mark-command
	zle forward-word
	zle copy-region-as-kill
	local word=$CUTBUFFER

	local realpath=$(realpath $word 2>/dev/null)
	if test -n "$realpath"
	then
		zle backward-kill-word
		zle -U "$realpath"
	fi
}

zle -N expand-word-path expand-word-path

# customize built-in key bindings
#
bindkey -M emacs '^[b' backward-word
bindkey -M emacs '^[f' forward-word
bindkey -M emacs '^[p' history-beginning-search-backward
bindkey -M emacs '^[n' history-beginning-search-forward
bindkey -M emacs '^[^' expand-history
bindkey -M emacs '^[*' expand-word
bindkey -M emacs '^[=' list-choices
bindkey -M emacs '^X?' expand-cmd-path
bindkey -M emacs '^X/' expand-word-path

bindkey -M vicmd '!' expand-history
bindkey -M vicmd '*' expand-word
bindkey -M vicmd '=' list-choices

# use emacs bindings
bindkey -e

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
compctl -M '' 'm:{a-zA-Z}={A-Za-z}'

# make file name completion case-insensitive
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}'

# finish with a zero exit status
true
