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
# Bound to SUPER+period (next) and SUPER+comma (prev) in hyprland.conf.
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

case "$new" in
    tile)
        hyprctl keyword general:layout master
        hyprctl dispatch layoutmsg orientationleft
        ;;
    threecolumn)
        hyprctl keyword general:layout master
        hyprctl dispatch layoutmsg orientationcenter
        ;;
    columns)
        hyprctl keyword general:layout dwindle
        ;;
esac

printf '%s\n' "$new" > "$state"
