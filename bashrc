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
shopt -s nullglob
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
shellinfo='$(dirs -l)'
PROMPT_COMMAND='laststatus="$?"; eval settitle "\"${title}\""'
PS1='$(eval echo "\"${bold}${promptstring}${normal}\"")'

# set environment for interactive sessions
case $- in *i*)
    # set command completions
    if type complete >/dev/null 2>&1
    then
        if complete -o >/dev/null 2>&1
        then
            COMPDEF="-o complete"
        fi
        complete -a {,un}alias
        complete -d {c,p,push,pop}d,po
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
    fi
    ;;
esac

# vi: set sw=8:
