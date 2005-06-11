# -*- mode: sh -*-
# $Id$
#
# Bourne Again Shell login session startup commands
#
# This script contains bash-specific customizations and enhancements
# for the initial log in session.

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

