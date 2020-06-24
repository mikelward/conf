#!/bin/sh
echo "$(date +"%F %T.%N") xsession"
xfsettingsd
xfce4-power-manager
type compton && compton --daemon --backend xrender --paint-on-overlay
type pasystray && (setsid pasystray&)
exec i3 || exec xterm
#exec startxfce4 || exec mate-session || exec cinnamon-session || exec xterm
#exec wingo
