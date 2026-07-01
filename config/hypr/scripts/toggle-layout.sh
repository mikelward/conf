#!/bin/sh
#
# Toggle Hyprland's general layout between master and dwindle.
# Bound to SUPER+SHIFT+Backslash in hyprland.conf.

current=$(hyprctl getoption general:layout -j | grep -o '"str": *"[^"]*"' | cut -d'"' -f4)

if test "$current" = "master"; then
    hyprctl keyword general:layout dwindle
else
    hyprctl keyword general:layout master
fi
