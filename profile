#!/bin/sh
#
# Commands to run for any POSIX shell when the user logs in.
#
# zlogin and bash_profile should be symlinks to this file.
# (zprofile should not exist, or should be empty.)
#

# zsh will have already read .shrc via the .zshrc symlink,
# so only source .shrc for other shells here
if test -z "${ZSH_VERSION:-}"; then
    test -f "$HOME"/.shrc && . "$HOME"/.shrc
fi

# set a script that will be sourced on exiting the shell
# XXX temporarily disabled due to https://github.com/kovidgoyal/kitty/issues/1867
#test -f "$HOME"/.exitrc && trap '. "$HOME/.exitrc"' EXIT

if test -t 0; then
	# disable flow control so applications can use ^Q and ^S
	type stty >/dev/null 2>/dev/null && stty -ixon
fi

# finish with a zero exit status so the first prompt is '$' rather than '?'
true
