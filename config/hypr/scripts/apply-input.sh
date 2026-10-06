#!/bin/sh
#
# Auto-configure pointing devices so no device names need hardcoding.
#   TOUCHPADS keep the global defaults (LEFT button primary), plus the speed
#             and handedness tide's Touchpad settings give them.
#   MICE      get left_handed = true (RIGHT button primary) + a faster wheel,
#             or what tide's Mouse settings say instead.
#
# Devices are classified by name (touchpads report "touchpad"/"trackpad"/
# "synaptics" in their libinput name, which is what Hyprland uses). Runs at
# login from hyprland.lua's autostart; re-run it after hotplugging a mouse or
# touchpad.
# Override the mouse scroll speed with HYPR_MOUSE_SCROLL_FACTOR (default 3).

MOUSE_SCROLL="${HYPR_MOUSE_SCROLL_FACTOR:-3}"

command -v hyprctl >/dev/null 2>&1 || exit 0

# It is spliced into Lua below, so it must be a plain number.
case "$MOUSE_SCROLL" in
    ''|*[!0-9.]*|*.*.*|.)
        echo "apply-input.sh: HYPR_MOUSE_SCROLL_FACTOR must be a number, not '$MOUSE_SCROLL'" >&2
        exit 1
        ;;
esac

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
status=0
IFS='
'
for name in $names; do
    test -n "$name" || continue
    case "$name" in
        *touchpad*|*trackpad*|*synaptics*)
            # Touchpad: tide's touchpad speed and handedness, through
            # hyprland.lua's conf_input.touchpad(), which leaves alone what
            # hyprland.local.lua set for the device.
            lua_name=$(printf '%s' "$name" | sed 's/[\\"]/\\&/g')
            result=$(hyprctl eval "conf_input.touchpad(\"$lua_name\")" 2>&1)
            if test "$result" != ok; then
                echo "apply-input.sh: couldn't configure touchpad '$name': $result" >&2
                status=1
            fi
            ;;
        *)
            # Mouse: right button primary + faster wheel, through
            # hyprland.lua's conf_input.mouse(), which leaves alone what
            # hyprland.local.lua set for the device. The Lua config has no
            # keyword command, so this is an eval, with the name escaped
            # for a Lua string.
            lua_name=$(printf '%s' "$name" | sed 's/[\\"]/\\&/g')
            result=$(hyprctl eval "conf_input.mouse(\"$lua_name\", $MOUSE_SCROLL)" 2>&1)
            if test "$result" != ok; then
                echo "apply-input.sh: couldn't configure mouse '$name': $result" >&2
                status=1
            fi
            ;;
    esac
done
exit $status
