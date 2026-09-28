#!/bin/sh
#
# Laptop lid handler for Sway, wired to the lid switch via bindswitch in
# ~/.config/sway/config.
#
#   close: disable the internal panel. Suspend ONLY when no other output is
#          still active -- a docked laptop with the lid shut keeps running on
#          its external screen (Sway moves the workspaces over by itself).
#   open:  re-enable the internal panel.
#
# For this to be the authoritative lid handler, systemd-logind must be told
# to ignore the lid (HandleLidSwitch=ignore); setup-sway installs that
# drop-in. The Hyprland build no longer shares it: it leaves suspend to
# logind's defaults (HandleLidSwitch=suspend, HandleLidSwitchDocked=ignore),
# so with this drop-in installed an undocked lid close under Hyprland won't
# suspend. The sway config is due for removal, so this stays as it is.
#
# The internal panel is auto-detected as the first output whose connector is
# an internal type (eDP/LVDS/DSI). `swaymsg -t get_outputs` includes disabled
# outputs, so the `open` path still finds the panel after `close` disabled
# it. Override by passing a name as the second argument (see config.local)
# or via SWAY_INTERNAL_OUTPUT.

action="$1"

INTERNAL="${2:-$SWAY_INTERNAL_OUTPUT}"
if test -z "$INTERNAL"; then
    INTERNAL=$(swaymsg -t get_outputs \
        | grep -o '"name": *"[^"]*"' \
        | cut -d'"' -f4 \
        | grep -iE '^(eDP|LVDS|DSI)' \
        | head -n1)
    test -n "$INTERNAL" || INTERNAL=eDP-1
fi

case "$action" in
    close)
        swaymsg output "$INTERNAL" disable
        # After disabling the panel, any output still active must be an
        # external display. None left -> undocked -> safe to sleep (swayidle's
        # before-sleep locks the session first).
        active=$(swaymsg -t get_outputs | grep -c '"active": true')
        if test "$active" -eq 0; then
            systemctl suspend
        fi
        ;;
    open)
        swaymsg output "$INTERNAL" enable
        ;;
    *)
        echo "usage: $0 close|open [output-name]" >&2
        exit 1
        ;;
esac
