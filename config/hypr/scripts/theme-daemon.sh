#!/bin/sh
#
# Applies the time-based light/dark theme, then sleeps until the next
# 07:00/19:00 boundary and re-applies. Runs for the life of the session --
# started by exec-once in hyprland.conf, or by exec in config/sway/config
# (theme.sh detects which compositor is running) -- so it always has the
# session's Wayland/D-Bus environment. theme.sh launches waybar and swaync
# with the matching style, so they are NOT started separately by the
# compositor configs.

theme="$HOME/.config/hypr/scripts/theme.sh"

while true; do
    "$theme" auto
    # theme.sh prints the seconds until the next boundary; guard against an
    # empty/zero value so a bad clock can't spin the loop.
    secs=$("$theme" sleep)
    case "$secs" in
        ''|*[!0-9]*) secs=3600 ;;
    esac
    test "$secs" -gt 0 2>/dev/null || secs=3600
    sleep "$secs"
done
