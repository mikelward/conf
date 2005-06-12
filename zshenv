# -*- mode: sh -*-
# $Id$
#
# Z Shell startup settings (environment part)
#
# This script is used to ensure that all the common POSIX shell
# functions and settings are included from .shrc before everything else.
# For zsh-specific settings, see .zshrc.

# Read the common environment for all POSIX shells.
#
# This must be a function so the emulate command only affects the
# execution of statements from ~/.shrc.
source_posix_environment()
{
    emulate -L ksh
    if test -f ~/.shrc
    then
        source ~/.shrc
    fi
}

source_posix_environment

