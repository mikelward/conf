# .cshrc - csh startup commands
# $Id$

# set command aliases
alias bell	'echo "\a"'
alias cd..	'cd ..'
alias cx	'chmod +x'
alias d		'dirs'
alias e		'$EDITOR'
alias f		'find . -type f -name \!1 -print \!2* | $PAGER'
alias g		'egrep'
alias h		'history'
alias helpcommand 'man'
alias j		'jobs -l'
alias l		'ls -Fpx'
alias la	'l -A'
alias ll	'l -l'
alias lt	'l -t'
alias m		'make \!* |& tee make.log'
alias p		'$PAGER'
alias pd	'pushd'
alias psme	'ps -f -U $USER'
alias po	'popd'
alias qfind	'sh -c "find \!* 2> /dev/null | $PAGER"'
alias v		'$VISUAL'
unalias vi
unalias vim

# set directories to search for commands
# add directories to look in first (unless already present)
foreach d ( /opt/freeware/bin /usr/gnu/bin /usr/local/bin ~/bin )
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
			# advance to next top level directory
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
foreach dir ( /opt/freeware/info /usr/local/share/info /usr/local/info $HOME/info )
	if ( -d $dir ) then
		setenv INFOPATH ${dir}:${INFOPATH}
	endif
end
if ( ! $?MANPATH ) then
	setenv MANPATH /usr/share/man:/usr/man
endif
foreach dir ( /opt/freeware/man /usr/local/share/man /usr/local/man $HOME/man )
	if ( -d $dir ) then
		setenv MANPATH ${dir}:${MANPATH}
	endif
end

# set environment for interactive sessions
if ( $?prompt ) then
	# set program configuration variables
	if ( -r ~/.vimrc ) then
		setenv VIMINIT "source ~/.vimrc"
	endif
	if ( -r ~/.inputrc ) then
		setenv INPUTRC ~/.inputrc
	endif
	setenv CLICOLOR true
	setenv LESS Eij3MX
	#setenv LESS j3M
	if ( $?TABSIZE ) then
		setenv LESS "${LESS}x${TABSIZE}"
	endif
	setenv TOP I

	# set preferred programs
	setenv BROWSER lynx
	which links >& /dev/null && setenv BROWSER links
	which elinks >& /dev/null && setenv BROWSER elinks
	setenv CVS_RSH ssh
	which ssh >& /dev/null && setenv CVS_RSH ssh
	setenv EDITOR ed
	which vi >& /dev/null && setenv EDITOR vi
	which nvi >& /dev/null && setenv EDITOR nvi
	which vim >& /dev/null && setenv EDITOR vim
	setenv GREP_COLOR 1
	setenv PAGER more
	which less >& /dev/null && setenv PAGER less
	setenv VISUAL "$EDITOR"
	setenv WINTERM xterm

	# set shell options
	set cdpath=( . ~ )
	set color
	set noding
	set filec
	set history=(1000)
	#set prompt="% "
	set savehist=(1000 merge)
endif

# read local settings (company environment, network, etc.)
if ( -r ~/.cshrc.local ) then
	source ~/.cshrc.local
endif

