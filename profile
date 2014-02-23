# Commands to run for any POSIX shell when the user logs in.

test -f "$HOME"/.shrc && . "$HOME"/.shrc

# set a script that will be sourced on exiting the shell
test -f "$HOME"/.exitrc && trap ". $HOME/.exitrc" EXIT

if type tty >/dev/null 2>/dev/null && tty >/dev/null
then
	# disable flow control so applications can use ^Q and ^S
	type stty >/dev/null 2>/dev/null && stty -ixon
fi

# finish with a zero exit status
true
