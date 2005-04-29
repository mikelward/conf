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
	test -n "$ts" && print -Pn "${ts}%m<$(basename $(tty))> %n $0${tf}"
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
	test -n "$ts" && print -Pn "${ts}%m<$(basename $(tty))> %n $1${tf}"
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
setopt incappendhistory
setopt listrowsfirst
setopt magicequalsubst
setopt nobeep
#setopt nolistbeep
#setopt nullglob
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

