#!/bin/bash
echo "$(date +"%F %T.%N") xsession"

(setsid xfsettingsd&)
(setsid xfce4-power-manager&)
type compton && compton --daemon --backend xrender --paint-on-overlay
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
#if type xmonad; then
#  trayer --edge top --align right --expand true --width 3 --widthtype percent --tint 0x000000 --transparent true --height 19 --SetPartialStrut true &
#  exec xmonad
#fi
exec startxfce4 || exec mate-session || exec cinnamon-session || exec xterm
exec wingo
exec xterm
