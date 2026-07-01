#!/bin/sh
#
# Laptop lid handler for Hyprland, bound to the Lid Switch in hyprland.conf.
#
#   close: disable the internal panel. Suspend ONLY when no external display
#          is connected -- a docked laptop with the lid shut keeps running on
#          its external screen (Hyprland auto-places the remaining output).
#   open:  re-enable the internal panel.
#
# For this to be the authoritative lid handler, systemd-logind must be told to
# ignore the lid (HandleLidSwitch=ignore); setup-hypr installs that drop-in.
#
# The internal panel is auto-detected as the first output whose connector is an
# internal type (eDP/LVDS/DSI). Use `monitors all` (which includes DISABLED
# outputs) so the `open` path can still find the panel after `close` disabled
# it -- plain `hyprctl monitors` lists active outputs only. Override with
# HYPR_INTERNAL_OUTPUT if needed.
INTERNAL="$HYPR_INTERNAL_OUTPUT"
if test -z "$INTERNAL"; then
    INTERNAL=$(hyprctl monitors all -j \
        | grep -o '"name": *"[^"]*"' \
        | cut -d'"' -f4 \
        | grep -iE '^(eDP|LVDS|DSI)' \
        | head -n1)
    test -n "$INTERNAL" || INTERNAL=eDP-1
fi

action="$1"

# External displays = currently ACTIVE monitors (plain `monitors`) that aren't
# the internal panel. We want active outputs here, so a disabled/disconnected
# external doesn't count toward "keep running while docked".
active=$(hyprctl monitors -j | grep -o '"name": *"[^"]*"' | cut -d'"' -f4)
external=$(printf '%s\n' "$active" | grep -v "^${INTERNAL}\$")

case "$action" in
    close)
        hyprctl keyword monitor "${INTERNAL}, disable"
        if test -z "$external"; then
            # No external display -> safe to sleep. hypridle's before_sleep_cmd
            # locks the session first.
            systemctl suspend
        fi
        ;;
    open)
        hyprctl keyword monitor "${INTERNAL}, preferred, auto, 1"
        ;;
    *)
        echo "usage: $0 close|open" >&2
        exit 1
        ;;
esac
