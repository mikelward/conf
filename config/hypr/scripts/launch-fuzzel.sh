#!/bin/sh
#
# Launch fuzzel with colours matching the current light/dark theme.
# Bound to SUPER+Space. Uses fuzzel's --config to pick a full config file per
# mode (dark = the default fuzzel.ini, light = fuzzel-light.ini), which differ
# only in their [colors] section.
#
# Prefer the mode marker theme.sh writes when it applies a theme, so a manual
# `theme.sh light`/`theme.sh dark` override is respected here too; fall back
# to computing the mode from the time of day.

marker="${XDG_RUNTIME_DIR:-/tmp}/theme-mode"
mode=$(cat "$marker" 2>/dev/null)
case "$mode" in
    light|dark) ;;
    *) mode=$("$HOME/.config/hypr/scripts/theme.sh" mode) ;;
esac

set --
if test "$mode" = light; then
    set -- --config "$HOME/.config/fuzzel/fuzzel-light.ini"
fi
# In the quickspace session, apps start through `quickspace launch`, so the
# focus guard lets the chosen app's first window take focus (its window
# class isn't known here, hence the wildcard).
case ":${XDG_CURRENT_DESKTOP:-}:" in
    *:quickspace:*) set -- "$@" "--launch-prefix=quickspace launch --app '*' --" ;;
esac
exec fuzzel "$@"
