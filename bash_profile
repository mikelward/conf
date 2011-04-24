# bash-specific commands for login sessions.

# environment and common interactive commands
if test -f ~/.bashrc
then
	. ~/.bashrc
fi

# common login commands
if test -f ~/.profile
then
	. ~/.profile
fi

# finish with a zero exit status
true
