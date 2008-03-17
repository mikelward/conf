# $Id$
# bash-specific commands for login sessions.

# read environment
if test -f ~/.bashrc
then
	~/.bashrc
fi
    
# read common login commands
if test -f ~/.profile
then
	. ~/.profile
fi

# vi: set sw=4 ts=4:
