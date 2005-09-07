# $Id$
#
# POSIX shell login session startup commands
#
# This scripts contains common initialization commands for the initial
# log in session for all POSIX-compatible shells.

# read environment
test -f "$HOME"/.shrc && export ENV="$HOME"/.shrc

# set a script that will be sourced on exiting the shell
test -f "$HOME"/.exitrc && trap ". $HOME/.exitrc" EXIT

# read local commands
test -f "$HOME"/.profile.local && . "$HOME"/.profile.local

# vi: set sw=4 ts=33:
