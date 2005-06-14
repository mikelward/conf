# -*- mode: sh -*-
# $Id$
#
# Bourne Again Shell login session startup commands
#
# This script contains bash-specific customizations and enhancements
# for the initial log in session.

# read environment
test -f "$HOME"/.bashrc && BASH_ENV="$HOME"/.bashrc
test -n "$BASH_ENV" && . "$BASH_ENV"

# read login commands
test -f "$HOME"/.profile && . "$HOME"/.profile

