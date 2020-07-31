#!/bin/bash
echo "$(date +"%F %T.%N") xsession"

xfsettingsd
xfce4-power-manager
type compton && compton --daemon --backend xrender --paint-on-overlay
type pasystray && (setsid pasystray&)
type qtile && exec qtile --log-level=DEBUG
type i3 && exec i3
if type xmonad; then
  trayer --edge top --align right --expand true --width 3 --widthtype percent --tint 0x000000 --transparent true --height 19 --SetPartialStrut true &
  exec xmonad
fi
exec xterm
#exec i3 || exec xterm
#exec startxfce4 || exec mate-session || exec cinnamon-session || exec xterm
#exec wingo
