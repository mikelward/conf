# $Id$
#
# Bourne Again Shell startup commands
#
# This script contains bash-specific customizations and enhancements.
# Common POSIX-compatible functions and settings are included from
# .shrc.

# source the user's environment file
if test -f "$HOME"/.shrc
then
    export ENV="$HOME"/.shrc
    . "$ENV"
else
    ENV=
fi

# set shell options
shopt -s checkwinsize
shopt -s cmdhist
shopt -s dotglob
shopt -s extglob
quiet shopt -s failglob
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
            echo "$arg"
        else
            command $opts "$arg"
        fi
    done
}

# set the prompt and window title
PROMPT_COMMAND='laststatus="$?"; eval settitle "\"${title}\""'
PS1='$(eval echo "\"""$""${promptcolor:-normal}${promptstring}${normal}\"")'

# set up command history
HISTTIMEFORMAT="%H:%M	"

# set environment for interactive sessions
case $- in *i*)
    # set command completions
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
        complete -F complete_runner nohup
        complete -F complete_runner sudo
        complete -F complete_services service

        # completion function for commands such as sudo that take a
        # command as the first argument but should revert to file
        # completion for subsequent arguments
        complete_runner()
        {
            if test "$1" = "$3"
            then
                set -- `compgen -c $2`
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
	# for some reason glob-expand-word doesn't work here,
	# but insert-completions is fine
	bind -m vi-command '"*"':insert-completions

    ;;
esac

# source local settings
test -r "$HOME"/.bashrc.local && . "$HOME"/.bashrc.local

# finish with a 0 exit status
true

# vi: set sw=4:
