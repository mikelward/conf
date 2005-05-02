# -*- mode: sh -*-
# $Id$
# Bash login session startup commands

# read login commands
if test -f "$HOME"/.profile
then
	. "$HOME"/.profile
fi

# read environment
if test -f "$HOME"/.bashrc
then
	BASH_ENV="$HOME"/.bashrc
fi
if test -n "$BASH_ENV"
then
	export BASH_ENV
	. "$BASH_ENV"
fi

