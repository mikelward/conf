type xmodmap >/dev/null && xmodmap "$HOME/.Xmodmap"
type xbindkeys >/dev/null && xbindkeys
type pulseaudio >/dev/null && pulseaudio -D
type gnome-screensaver >/dev/null && gnome-screensaver
#gnome-power-manager
exec xfce4-session
#exec gnome-session
