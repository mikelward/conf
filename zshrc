# -*- mode: sh -*-
# $Id$
#
# Z Shell interactive startup commands
#
# This script contains zsh-specific customizations and enhancements
# for interactive sessions.
# Functions and settings for all sessions are automatically included from
# .zshenv.

precmd()
{
    command=$0

    # set the window title
    [[ -t 1 ]] && settitle
}

preexec()
{
    # get the canonical name of the command just invoked
    case $1 in
        # resuming an existing job
        fg*|%*)
            local spec
            spec=${1#fg}
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
                    # job string search unsupported
                    command=unknown
                    ;;
                *)
                    command=$jobtexts[$spec]
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
    [[ -t 1 ]] && settitle
}

settitle()
{
    test -n "$titlestart" && print -Pn "${titlestart}${title}${titlefinish}"
}

# set prompt and window title format
promptchars='%# '
prompt=$promptchars

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
setopt correct
setopt histignorespace
setopt histreduceblanks
setopt noksharrays

# set some options originally from ksh
setopt checkjobs
setopt interactivecomments
setopt kshglob
setopt promptsubst

# set some zsh-specific options
setopt appendhistory
setopt autocd
setopt autolist
setopt automenu
setopt extendedhistory
setopt globdots
setopt incappendhistory
setopt nolistambiguous
setopt nolistbeep
setopt listrowsfirst
setopt magicequalsubst
setopt numericglobsort
setopt nullglob
setopt promptpercent

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

