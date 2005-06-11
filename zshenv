# -*- mode: sh -*-
# $Id$
#
# Z Shell startup settings (environment part)
#
# This script is used to ensure that all the common POSIX shell
# functions and settings are included from .shrc before everything else.
# For zsh-specific settings, see .zshrc.

emulate -L ksh

if test -f ~/.shrc
then
	source ~/.shrc
fi

