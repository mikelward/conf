#!/bin/sh
#
# Laptop lid handler for Hyprland, bound to the Lid Switch in hyprland.conf.
#
#   close: disable the internal panel. Suspend ONLY when no external display
#          is connected -- a docked laptop with the lid shut keeps running on
#          its external screen (kanshi then repositions the remaining output).
#   open:  re-enable the internal panel.
#
# For this to be the authoritative lid handler, systemd-logind must be told to
# ignore the lid (HandleLidSwitch=ignore); setup-hypr installs that drop-in.
#
# >>> PLACEHOLDER: set INTERNAL to your laptop's internal panel name.
# Find it with `hyprctl monitors` (usually eDP-1; eDP-2 on some machines). <<<
INTERNAL="${HYPR_INTERNAL_OUTPUT:-eDP-1}"

action="$1"

# Names of all currently-connected monitors, one per line.
monitors=$(hyprctl monitors -j | grep -o '"name": *"[^"]*"' | cut -d'"' -f4)

# Anything that isn't the internal panel counts as an external display.
external=$(printf '%s\n' "$monitors" | grep -v "^${INTERNAL}\$")

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
