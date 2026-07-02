#!/bin/sh
#
# Cycle through tiling layouts, approximating the Krohnkite layout set the
# KDE setup used (Tile, ThreeColumn, Columns). Hyprland has no native
# ThreeColumn/Columns, so we map to the closest built-in behaviour:
#
#   tile        -> master layout, orientation left   (master/stack)
#   threecolumn -> master layout, orientation center (master centred, stack
#                                                     split to both sides)
#   columns     -> dwindle layout                    (BSP, column-ish)
#
# Monocle is a separate direct toggle (SUPER+grave -> fullscreen 1), not part
# of this cycle, since in Hyprland it's a per-window state rather than a layout.
#
# Bound to SUPER+period (next) and SUPER+comma (prev) in hyprland.lua / hyprland.conf.
#
# Usage: layout-cycle.sh next|prev

dir="${1:-next}"
state="${XDG_RUNTIME_DIR:-/tmp}/hypr-layout"
cur=$(cat "$state" 2>/dev/null || echo tile)

case "$dir" in
    next)
        case "$cur" in
            tile)        new=threecolumn ;;
            threecolumn) new=columns ;;
            *)           new=tile ;;
        esac
        ;;
    prev)
        case "$cur" in
            tile)        new=columns ;;
            columns)     new=threecolumn ;;
            *)           new=tile ;;
        esac
        ;;
    *)
        echo "usage: $0 next|prev" >&2
        exit 1
        ;;
esac

# Hyprland 0.55 replaced `hyprctl keyword` with Lua (`hyprctl eval`, which
# prints "ok" on success) and dispatch's plain strings with Lua dispatchers;
# probe once and fall back to the legacy hyprlang syntax on <= 0.54.
if test "$(hyprctl eval 'return true' 2>/dev/null)" = "ok"; then
    hypr_lua=1
else
    hypr_lua=
fi

set_layout() {
    if test -n "$hypr_lua"; then
        hyprctl eval "hl.config({ general = { layout = \"$1\" } })"
    else
        hyprctl keyword general:layout "$1"
    fi
}

layoutmsg() {
    if test -n "$hypr_lua"; then
        hyprctl dispatch "hl.dsp.layout(\"$1\")"
    else
        hyprctl dispatch layoutmsg "$1"
    fi
}

case "$new" in
    tile)
        set_layout master
        layoutmsg orientationleft
        ;;
    threecolumn)
        set_layout master
        layoutmsg orientationcenter
        ;;
    columns)
        set_layout dwindle
        ;;
esac

printf '%s\n' "$new" > "$state"
