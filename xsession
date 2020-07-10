#!/bin/sh
echo "$(date +"%F %T.%N") xsession"
xfsettingsd
xfce4-power-manager
type compton && compton --daemon --backend xrender --paint-on-overlay
type pasystray && (setsid pasystray&)
exec i3
if type xmonad >/dev/null 2>&1; then
  trayer --edge top --align right --expand true --width 3 --widthtype percent --tint 0x000000 --transparent true --height 19 --SetPartialStrut true &
  exec xmonad
fi
exec xterm
#exec i3 || exec xterm
#exec startxfce4 || exec mate-session || exec cinnamon-session || exec xterm
#exec wingo
