#!/bin/bash
echo "$(date +"%F %T.%N") .xsession" >> "$HOME/xsession.log"
exec startxfce4 || exec mate-session || exec cinnamon-session || exec xterm
#xfsettingsd
#exec startxfce4
#exec wingo
