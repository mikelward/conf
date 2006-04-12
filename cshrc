# $Id$
# C Shell startup commands

# set shell options for all sessions
set nonomatch

# set default flags
if ( { grep --color=auto --quiet "" ~/.cshrc } ) >&/dev/null then
    alias grep	'grep --color=auto'
endif
if ( { ls --color=auto --format=single-column --directory / } ) >&/dev/null then
    alias ls	'ls --color=auto --classify --format=single-column'
else
    alias ls	'ls -1F'
endif

# set directories to search for commands
# add directories to look in first (unless already present)
foreach d ( /opt/*/bin /usr/X11R6/bin /usr/kerberos/bin /usr/posix/bin /usr/gnu/bin /usr/local/bin ~/bin )
    if ( -d $d ) then
        foreach p ( $path )
            # advance to next top level directory
            if ( $d == $p ) break; continue
        end
        set path=( $d $path )
    endif
end
# add directories to look in last (unless already present)
foreach d ( /usr/bin /bin )
    if ( -d $d ) then
        foreach p ( $path )
            # this directory already present, skip it
            if ( $d == $p ) break; continue
        end
        set path=( $path $d )
    endif
end
# add current directory (always searched last)
foreach p ( $path )
    set newpath=( )
    if ( $p != . ) then
        set newpath=( $newpath $p )
    endif
end
set path=( $path . )

# set directories to search for documentation pages
if ( ! $?INFOPATH ) then
    setenv INFOPATH /usr/share/info:/usr/info
endif
foreach dir ( /opt/*/info /usr/local/share/info /usr/local/info $HOME/info )
    if ( -d $dir ) then
        setenv INFOPATH ${dir}:${INFOPATH}
    endif
end
if ( ! $?MANPATH ) then
    setenv MANPATH /usr/share/man:/usr/man
endif
foreach dir ( /opt/*/man /usr/local/share/man /usr/local/man $HOME/man )
    if ( -d $dir ) then
        setenv MANPATH ${dir}:${MANPATH}
    endif
end

# set environment for interactive sessions
if ( $?prompt ) then
    # set preferred programs
    which lynx >&/dev/null && setenv BROWSER lynx
    which links >&/dev/null && setenv BROWSER links
    which elinks >&/dev/null && setenv BROWSER elinks
    which rsh >&/dev/null && setenv CVS_RSH ssh
    which ssh >&/dev/null && setenv CVS_RSH ssh
    which ed >&/dev/null && setenv EDITOR ed
    which vi >&/dev/null && setenv EDITOR vi
    which nvi >&/dev/null && setenv EDITOR nvi
    which vim >&/dev/null && setenv EDITOR vim
    which more >&/dev/null && setenv PAGER more
    which less >&/dev/null && setenv PAGER less
    setenv VISUAL "$EDITOR"
    setenv WINTERM xterm

    # set file locations
    if ( -r ~/.vimrc ) then
    setenv VIMINIT "source ~/.vimrc"
    endif
    if ( -r ~/.inputrc ) then
    setenv INPUTRC ~/.inputrc
    endif

    # determine the graphics mode escape sequences
    if ( { which tput } ) >& /dev/null then
    set bold="`tput bold`"
    set underline="`tput smul`"
    set normal="`tput sgr0`"
    set black="`tput setaf 0`"
    set red="`tput setaf 1`"
    set green="`tput setaf 2`"
    set yellow="`tput setaf 3`"
    set blue="`tput setaf 4`"
    set magenta="`tput setaf 5`"
    set cyan="`tput setaf 6`"
    set white="`tput setaf 7`"
    endif

    # set preferred program options
    setenv CLICOLOR true
    setenv GREP_COLOR 1
    setenv LESS -eFj3MRX
    setenv LSCOLORS 'exfxcxcxbxdxdx'
    setenv LS_COLORS 'no=00:fi=00:di=00;34:ln=00;35:or=07;35:so=00;32:pi=00;32:ex=00;31:bd=00;33:cd=00;33:'
    if ( $?TABSIZE ) then
    setenv LESS "${LESS}x${TABSIZE}"
    endif
    setenv TOP -I
    setenv WWW_HOME "http://endbracket.net/michael/links"

    # set shell options for interactive sessions
    set cdpath=( . ~ )
    set color
    set noding
    set filec
    set history=(1000)
    set prompt="% "
    set savehist=(1000 merge)
endif

# set command aliases
alias apt	'aptitude'
alias bell	'echo "\a"'
alias cd..	'cd ..'
alias cx	'chmod +x'
alias d	'dirs'
if ( $?EDITOR ) then
    alias e                      '$EDITOR'
else
    alias e                      'vi'
endif
alias f	'find . -type f -name \!1 -print \!2* | $PAGER'
alias g	'grep -En'
alias h	'history'
alias hup	'kill -HUP'
alias helpcommand	'man'
alias j	'jobs -l'
alias l	'ls'
alias la	'l -A'
alias latest	'ls -t -1 \!* | head -n 1'
alias ll	'l -l'
alias lt	'l -lt'
alias m	'(make \!* > make.log) |& tee -a make.log'
alias p	'$PAGER'
alias pd	'pushd'
alias psme	'ps -f -U $USER'
alias po	'popd'
alias qfind	'sh -c "find \!* 2> /dev/null | $PAGER"'
alias rtags	'ctags -R'
alias retags	'find . \( -name "*.c" -o -name "*.h" \
	    -o -name "*.a" -o -name "*.s" \
	    -o -name "*.C" -o -name "*.H" \
	    -o -name "*.cc" -o -name "*.hh" \
	    -o -name "*.cpp" -o -name "*.hpp" \
	    -o -name "*.cxx" -o -name "*.hxx" \
	    -o -name "*.c++" -o -name "*.h++" \
	    -o -name "*.l" \
	    -o -name "*.p" -o -name "*.pas" \
	    -o -name "*.pl" -o -name "*.pm" \
	    -o -name "*.py" \
	    -o -name "*.y" -o -name "*.yy" \) \
	    -print | etags -'
if ( $?VIEWER ) then
    alias v                      '$VIEWER'
else
    alias v                      'view'
endif
unalias vi
unalias vim

# read local settings (company environment, network, etc.)
if ( -r ~/.cshrc.local ) then
    source ~/.cshrc.local
endif

# vi: set sw=4 ts=33:
