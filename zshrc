# .zshrc - Z Shell interactive session startup script
# $Id$

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
	test -n "$ts" && print -Pn "${ts}%n@%m %~${tf}"
}

# update the xterm title when running a command
preexec()
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
	test -n "$ts" && print -Pn "${ts}%n@%m $1${tf}"
}

# set prompt
prompt='
%B%n@%m `dirs`
%#%b '

# set key bindings
bindkey -e
bindkey '^X?' expand-cmd-path

# enable some options originally from csh
setopt banghist
setopt braceexpand
#setopt chasedots
setopt correct
#setopt cshnullglob
setopt extendedglob
setopt extendedhistory
setopt histignorespace
setopt histreduceblanks
setopt nohup
setopt nomatch
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
setopt listrowsfirst
setopt magicequalsubst
setopt nobeep
#setopt nolistbeep
setopt nullglob
setopt numericglobsort
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
compctl -/ {c,push,pop}d
compctl -c exec
compctl -c man
compctl -c {where,which}
compctl -o {,un}setopt
compctl -E {,un}setenv
compctl -E printenv
compctl -b bindkey
compctl -j fg
compctl -j kill
compctl -u chown

