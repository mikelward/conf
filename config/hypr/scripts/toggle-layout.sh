#!/bin/sh
#
# Toggle Hyprland's general layout between master and dwindle.
# Bound to SUPER+SHIFT+Backslash in hyprland.lua / hyprland.conf.

# Hyprland 0.55 replaced `hyprctl keyword` with Lua (`hyprctl eval`, which
# prints "ok" on success) and getoption's colon paths with dots; probe once
# and fall back to the legacy hyprlang syntax on <= 0.54.
if test "$(hyprctl eval 'return true' 2>/dev/null)" = "ok"; then
    hypr_lua=1
else
    hypr_lua=
fi

if test -n "$hypr_lua"; then
    current=$(hyprctl getoption general.layout -j | grep -o '"str": *"[^"]*"' | cut -d'"' -f4)
else
    current=$(hyprctl getoption general:layout -j | grep -o '"str": *"[^"]*"' | cut -d'"' -f4)
fi

set_layout() {
    if test -n "$hypr_lua"; then
        hyprctl eval "hl.config({ general = { layout = \"$1\" } })"
    else
        hyprctl keyword general:layout "$1"
    fi
}

if test "$current" = "master"; then
    set_layout dwindle
else
    set_layout master
fi
