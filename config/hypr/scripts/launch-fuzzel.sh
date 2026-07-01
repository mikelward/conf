#!/bin/sh
#
# Launch fuzzel with colours matching the current light/dark theme.
# Bound to SUPER+Space. Uses fuzzel's --config to pick a full config file per
# mode (dark = the default fuzzel.ini, light = fuzzel-light.ini), which differ
# only in their [colors] section.

mode=$("$HOME/.config/hypr/scripts/theme.sh" mode)

if test "$mode" = light; then
    exec fuzzel --config "$HOME/.config/fuzzel/fuzzel-light.ini"
else
    exec fuzzel
fi
