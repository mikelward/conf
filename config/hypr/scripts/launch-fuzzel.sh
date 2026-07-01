#!/bin/sh
#
# Launch fuzzel with colours matching the current light/dark theme.
# Bound to SUPER+Space. Uses fuzzel's --override so it reuses the exact
# [colors] keys from fuzzel.ini rather than a second copy of the config.

mode=$("$HOME/.config/hypr/scripts/theme.sh" mode)

if test "$mode" = light; then
    exec fuzzel \
        --override colors.background=eceff4f0 \
        --override colors.text=2e3440ff \
        --override colors.match=5e81acff \
        --override colors.selection=d8dee9ff \
        --override colors.selection-text=2e3440ff \
        --override colors.selection-match=5e81acff \
        --override colors.border=5e81acff \
        --override colors.prompt=4c566aff
else
    exec fuzzel \
        --override colors.background=2e3440f0 \
        --override colors.text=eceff4ff \
        --override colors.match=88c0d0ff \
        --override colors.selection=3b4252ff \
        --override colors.selection-text=eceff4ff \
        --override colors.selection-match=88c0d0ff \
        --override colors.border=88c0d0ff \
        --override colors.prompt=d8dee9ff
fi
