start()
{
	if type "$1" >/dev/null 2>&1
	then
		log "$@"
		"$@"
	fi
}

tryexec()
{
	log "here"
	if type "$1" >/dev/null 2>&1
	then
		log "exec $@"
		exec "$@"
	fi
}

start xmodmap "$HOME/.Xmodmap"
start xbindkeys
start pulseaudio -D
start gnome-screensaver
start gnome-power-manager
tryexec gnome-session
tryexec xfce4-session
tryexec xterm
