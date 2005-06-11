# -*- mode: sh -*-
# $Id$
#
# Bourne Again Shell startup commands
#
# This script contains bash-specific customizations and enhancements.
# Common POSIX-compatible functions and settings are included from
# .shrc.

# source the user's environment file
if test -z "$ENV"
then
    if test -f "$HOME"/.shrc
    then
        ENV="$HOME"/.shrc
    fi
    export ENV
fi
test -n "$ENV" && . "$ENV"

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

# set the prompt and title
PS1='\[${bold}\]\n\u@\h `dirs`\n\$\[${normal}\] '
PROMPT_COMMAND="echo \"${titlestart}${title}${titlefinish}\""

# set environment for interactive sessions
case $- in *i*)
    # set command completions
    if type complete >/dev/null 2>&1
    then
        if complete -o >/dev/null 2>&1
        then
            COMPDEF="-o complete"
        fi
        complete -a {,un}alias >/dev/null 2>&1
        complete -d {c,p,push,pop}d,po >/dev/null 2>&1
        complete $COMPDEF -g chgrp >/dev/null 2>&1
        complete $COMPDEF -u chown >/dev/null 2>&1
        complete -j fg >/dev/null 2>&1
        complete -j kill >/dev/null 2>&1
        complete $COMPDEF -c command >/dev/null 2>&1
        complete $COMPDEF -c exec >/dev/null 2>&1
        complete $COMPDEF -c man >/dev/null 2>&1
        complete -e printenv >/dev/null 2>&1
        complete -G "*.java" javac >/dev/null 2>&1
    fi
    ;;
esac

