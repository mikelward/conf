#!/bin/sh
echo "$(date +"%F %T.%N") xsession"
xfsettingsd
xfce4-power-manager
type compton && compton --daemon --backend glx --paint-on-overlay --mark-ovredir-focused
type pasystray && (setsid pasystray&)
exec i3 || exec xterm
#exec startxfce4 || exec mate-session || exec cinnamon-session || exec xterm
#exec wingo
