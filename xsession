#!/bin/bash
echo "$(date +"%F %T.%N") xsession"
xfsettingsd
type compton && compton --daemon --backend glx --paint-on-overlay
exec i3 || exec xterm
#exec startxfce4 || exec mate-session || exec cinnamon-session || exec xterm
#exec wingo
