#!/bin/sh
#
# Moves every keyboard to the next keyboard layout, for Super+Alt+Space
# (tide SPEC.md §16). Hyprland 0.56.2's `switchxkblayout all next` moves
# each keyboard on from its own layout, so a keyboard plugged in after a
# switch, which starts on the first, would stay out of step for good.
# Instead this takes the layout after the main keyboard's (the one last
# typed on) and sets that one on all of them. With one layout, it sets
# that one again, which changes nothing.

if ! command -v hyprctl >/dev/null 2>&1; then
    echo "next-layout.sh: no hyprctl" >&2
    exit 1
fi

if ! devices=$(hyprctl devices -j); then
    echo "next-layout.sh: couldn't list the keyboards" >&2
    exit 1
fi

# The main keyboard's layout index and its layouts ("us,de"), as
# "INDEX LAYOUTS", else the first keyboard's when none is main.
if command -v jq >/dev/null 2>&1; then
    main=$(printf '%s\n' "$devices" | jq -r '([.keyboards[] | select(.main)] + .keyboards)[0] | "\(.active_layout_index) \(.layout)"')
elif command -v python3 >/dev/null 2>&1; then
    main=$(printf '%s\n' "$devices" | python3 -c '
import json, sys
keyboards = json.load(sys.stdin)["keyboards"]
k = ([k for k in keyboards if k.get("main")] + keyboards)[0]
print(k["active_layout_index"], k["layout"])
')
else
    echo "next-layout.sh: reading hyprctl's keyboards needs jq or python3" >&2
    exit 1
fi
index=${main%% *}
layouts=${main#* }
case "$index" in
    ''|*[!0-9]*)
        echo "next-layout.sh: couldn't find a keyboard's layout in: $devices" >&2
        exit 1
        ;;
esac

# One more than the commas in "us,de", and the one after the current,
# back to the first after the last.
count=$(printf '%s' "$layouts" | tr -cd , | wc -c)
count=$((count + 1))
next=$(((index + 1) % count))

result=$(hyprctl switchxkblayout all "$next")
if test "$result" != ok; then
    echo "next-layout.sh: couldn't switch every keyboard to layout $next: $result" >&2
    exit 1
fi
