# .login - C Shell login session startup commands
# Michael Wardle, November 28, 2004

# set environment script in case a Bourne-like shell is invoked within csh
test -f "$HOME"/.shrc && setenv ENV "$HOME"/.shrc

# commands that only work when running on a terminal
if ( { tty -s } ) then

	# disable output control so applications can use ^S and ^Q
	stty -ixon

	# start the ssh agent
	if ! ( $?SSH_AUTH_SOCK ) then
		eval `ssh-agent`
		ssh-add < /dev/null
	endif
endif

# read local settings (company environment, etc.)
if ( -r ~/.login.local ) then
	source ~/.login.local
endif

