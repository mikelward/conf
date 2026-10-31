#!/bin/sh
#
# Auto-configure pointing devices so no device names need hardcoding.
#   TOUCHPADS keep the global defaults (LEFT button primary), plus the speed
#             and handedness tide's Touchpad settings give them. A laptop's
#             other built-in pointers count as touchpads too: its pointing
#             stick, whose buttons sit above the touchpad, and the extra
#             "-mouse" node of a touchpad wired over I2C.
#   MICE      get left_handed = true (RIGHT button primary) + a faster wheel,
#             or what tide's Mouse settings say instead.
#   KEYBOARDS get tide's keyboard settings, so one with settings of its own
#             can have them and lose them again.
#   Each takes tide's settings for that one device over its kind's.
#
# Devices are classified by name, the libinput name Hyprland lowercases and
# dashes (see is_touchpad; tide's Touchpad page decides the same way). Runs at
# login from hyprland.lua's autostart; re-run it after hotplugging a mouse,
# touchpad or keyboard.
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

if ! devices=$(hyprctl devices -j); then
    echo "apply-input.sh: hyprctl devices -j failed" >&2
    exit 1
fi

# The device names in one array of hyprctl devices -j: "mice" or
# "keyboards". Prefer jq; fall back to a narrow sed window so another array's
# names aren't picked up.
device_names() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$devices" | jq -r ".$1[].name"
    else
        printf '%s\n' "$devices" \
            | sed -n "/\"$1\"/,/\\]/p" \
            | grep -o '"name": *"[^"]*"' \
            | cut -d'"' -f4
    fi
}
if ! names=$(device_names mice) || ! keyboards=$(device_names keyboards); then
    echo "apply-input.sh: couldn't read the mice and keyboards hyprctl devices -j lists" >&2
    exit 1
fi

# Whether pointer $1 is a touchpad or another of a laptop's built-in
# pointers, which take the touchpad's settings: one that says touchpad or
# trackpad (Apple's bcm5974 doesn't), a pointing stick (a TrackPoint, ALPS's
# DualPoint stick), and anything named by an ACPI ID such as
# "elan1200:00-04f3:309f-touchpad" or "syna8018:00-06cb:ce67-mouse", which is
# an I2C device built into the laptop. A TrackPoint's buttons, and a
# touchpad's, come through those, so left-handed there would swap the
# buttons above the touchpad. Everything else is a mouse. Keep in step with
# tide's shell/lib/input.mjs deviceKind.
is_touchpad() {
    case "$1" in
        *touchpad*|*trackpad*|*synaptics*|*bcm5974*) return 0 ;;
        *trackpoint*|*pointing-stick*|*pointingstick*|*dualpoint-stick*) return 0 ;;
        [a-z0-9][a-z0-9][a-z0-9][a-z0-9][0-9a-f][0-9a-f][0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]:[0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) return 0 ;;
    esac
    return 1
}

# Iterate line by line -- device names contain spaces before Hyprland's
# lowercasing/hyphenation on some setups, so don't split on spaces.
status=0
IFS='
'
for name in $names; do
    test -n "$name" || continue
    if is_touchpad "$name"; then
        # Touchpad: tide's touchpad speed and handedness, through
        # hyprland.lua's conf_input.touchpad(), which leaves alone what
        # hyprland.local.lua set for the device.
        lua_name=$(printf '%s' "$name" | sed 's/[\\"]/\\&/g')
        result=$(hyprctl eval "conf_input.touchpad(\"$lua_name\")" 2>&1)
        if test "$result" != ok; then
            echo "apply-input.sh: couldn't configure touchpad '$name': $result" >&2
            status=1
        fi
    else
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
    fi
done
# Keyboards: tide's keyboard settings, through hyprland.lua's
# conf_input.keyboard(), which leaves alone what hyprland.local.lua set for
# the keyboard.
for name in $keyboards; do
    test -n "$name" || continue
    lua_name=$(printf '%s' "$name" | sed 's/[\\"]/\\&/g')
    result=$(hyprctl eval "conf_input.keyboard(\"$lua_name\")" 2>&1)
    if test "$result" != ok; then
        echo "apply-input.sh: couldn't configure keyboard '$name': $result" >&2
        status=1
    fi
done
exit $status
