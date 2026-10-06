#!/bin/sh
#
# Applies the time-based light/dark theme, then sleeps until the next
# 07:00/19:00 boundary and re-applies. Runs for the life of the session --
# started by hyprland.lua's autostart, or by exec in config/sway/config
# (theme.sh detects which compositor is running) -- so it always has the
# session's Wayland/D-Bus environment. theme.sh launches waybar and swaync
# with the matching style, so they are NOT started separately by the
# compositor configs.
#
# In tide with its Quickshell shell (TIDE_BAR=quickshell, set by
# tide-shell, which runs this), the shell owns the schedule and sets the
# color scheme (tide SPEC.md §15). Setting it here too would fight the
# shell, which puts its own back at once: a blink at each of this clock's
# edges. So there this only styles swaync and the wallpaper once, for the
# scheme now (swaync has to start), and the shell runs
# ~/.config/tide/appearance-hook after each change it makes.

theme="$HOME/.config/hypr/scripts/theme.sh"

# Only where the shell can set the color scheme: with no gsettings, no
# GNOME schema for it (`writable` fails then), or a dconf lock on it
# (`writable` prints false, and still succeeds), the clock decides.
if test "${TIDE_BAR:-}" = quickshell &&
    test "$(gsettings writable org.gnome.desktop.interface color-scheme 2>/dev/null)" = true; then
    "$theme" follow
    # Stays up: tide-shell's unit ends with it.
    while true; do
        sleep 86400
    done
fi

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
