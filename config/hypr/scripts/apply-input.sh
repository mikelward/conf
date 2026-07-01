#!/bin/sh
#
# Auto-configure pointing devices so no device names need hardcoding.
#   TOUCHPADS keep the global defaults (LEFT button primary).
#   MICE      get left_handed = true (RIGHT button primary) + a faster wheel.
#
# Devices are classified by name (touchpads report "touchpad"/"trackpad"/
# "synaptics" in their libinput name, which is what Hyprland uses). Runs at
# login via exec-once in hyprland.conf; re-run it after hotplugging a mouse.
# Override the mouse scroll speed with HYPR_MOUSE_SCROLL_FACTOR (default 1.5).

MOUSE_SCROLL="${HYPR_MOUSE_SCROLL_FACTOR:-1.5}"

command -v hyprctl >/dev/null 2>&1 || exit 0

# Pointer device names from the "mice" array. Prefer jq; fall back to a narrow
# sed window so keyboard/tablet names in the same JSON aren't picked up.
if command -v jq >/dev/null 2>&1; then
    names=$(hyprctl devices -j | jq -r '.mice[].name')
else
    names=$(hyprctl devices -j \
        | sed -n '/"mice"/,/\]/p' \
        | grep -o '"name": *"[^"]*"' \
        | cut -d'"' -f4)
fi

# Iterate line by line -- device names contain spaces before Hyprland's
# lowercasing/hyphenation on some setups, so don't split on spaces.
IFS='
'
for name in $names; do
    test -n "$name" || continue
    case "$name" in
        *touchpad*|*trackpad*|*synaptics*)
            # Touchpad: keep the global defaults (left button primary).
            ;;
        *)
            # Mouse: right button primary + faster wheel.
            hyprctl keyword "device[$name]:left_handed" true >/dev/null 2>&1
            hyprctl keyword "device[$name]:scroll_factor" "$MOUSE_SCROLL" >/dev/null 2>&1
            ;;
    esac
done
