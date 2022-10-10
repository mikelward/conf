#!/bin/bash
echo "$(date +"%F %T.%N") xsession"

(setsid xfsettingsd&)
(setsid xfce4-power-manager&)
if type picon; then
  picon --daemon --backend xrender
elif type compton; then
  compton --daemon --backend xrender --paint-on-overlay
fi
type pasystray && (setsid pasystray&)
type autorandr && autorandr --change
if type dwm; then
    if type i3statusdwm; then
        (setsid i3statusdwm&)
    elif type slstatus; then
        (setsid slstatus&)
    fi
    exec dwm
fi
type qtile && exec qtile start --log-level=INFO
type i3 && exec i3
exec startxfce4 || exec mate-session || exec cinnamon-session || exec xterm
exec wingo
exec xterm
