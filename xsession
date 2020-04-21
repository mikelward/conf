#!/bin/bash
echo "$(date +"%F %T.%N") .xsession" >> "$HOME/xsession.log"
left mice
exec i3 || exec xterm
#exec startxfce4 || exec mate-session || exec cinnamon-session || exec xterm
#xfsettingsd
#exec startxfce4
#exec wingo
