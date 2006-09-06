# $Id: zshenv 174 2005-07-23 04:53:33Z michael $
#
# Z Shell interactive startup commands
#
# This script contains zsh-specific customizations and enhancements
# for interactive sessions.

precmd()
{
    # store the status of the previous interactive command for use in the prompt
    laststatus=$?

    # the currently running foreground job is the shell
    command=$0

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
    [[ -t 1 ]] && eval settitle "\"$title\""
}

settitle()
{
    test -n "$titlestart" && print -Pn "${titlestart}$*${titlefinish}"
}

# set prompt and window title format
shellinfo='$(dirs -l)'
PS1='$(eval echo "\"%B%{\$${promptcolor:-blue}%}${promptstring}%b\"")'

# set non-alphanumeric characters that constitute a word
# (remove / so Alt-Backspace deletes only one path component)
# (remove <>& so redirection not part of path)
# (remove ; so command list separator not part of word)
#WORDCHARS=
WORDCHARS="`echo $WORDCHARS | sed -e 's/[/<>&;]\+//'`"

# set key bindings
bindkey -e
bindkey -M emacs '^[b' backward-word
bindkey -M emacs '^[f' forward-word
bindkey -M emacs '^[p' history-beginning-search-backward
bindkey -M emacs '^[n' history-beginning-search-forward
bindkey -M emacs '^X?' expand-cmd-path

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
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}'

# source local settings
test -r "$HOME"/.zshrc.local && . "$HOME"/.zshrc.local

# finish with a zero exit status
true

# vi: set sw=4:
