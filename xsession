#!/bin/bash
echo "$(date +"%F %T.%N") .xsession" >> "$HOME/xsession.log"
xfsettingsd
type compton && compton --daemon
exec i3 || exec xterm
#exec startxfce4 || exec mate-session || exec cinnamon-session || exec xterm
#exec wingo
