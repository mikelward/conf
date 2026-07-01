#!/bin/sh
#
# Time-based light/dark theming for the Hyprland desktop.
# Light from 07:00 to 18:59, dark otherwise. Drives:
#   - the freedesktop colour-scheme preference (kitty and GTK apps follow it)
#   - waybar   (relaunched with -s style.css / style-light.css)
#   - swaync   (relaunched with --style style.css / style-light.css)
#   - Hyprland window border colours (hyprctl)
#   - a mode marker read by launch-fuzzel.sh
#
# Usage:
#   theme.sh mode                print "light" or "dark" for the current time
#   theme.sh sleep               print seconds until the next 07:00/19:00 edge
#   theme.sh [auto|light|dark]   apply a theme (auto = by time; the default)

LIGHT_START=7     # first hour of light mode
DARK_START=19     # first hour of dark mode

cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
marker="${XDG_RUNTIME_DIR:-/tmp}/theme-mode"

current_mode() {
    # %H is zero-padded (00-23); strip the leading zero so "08"/"09" aren't
    # treated as octal in the arithmetic comparison below (POSIX-safe).
    h=$(date +%H)
    h=${h#0}
    h=${h:-0}
    if test "$h" -ge "$LIGHT_START" && test "$h" -lt "$DARK_START"; then
        echo light
    else
        echo dark
    fi
}

seconds_until_boundary() {
    now=$(date +%s)
    today=$(date +%Y-%m-%d)
    tomorrow=$(date -d 'tomorrow' +%Y-%m-%d 2>/dev/null)
    # First upcoming boundary among today's two edges and tomorrow's light edge.
    for t in "$today ${LIGHT_START}:00:00" \
             "$today ${DARK_START}:00:00" \
             "$tomorrow ${LIGHT_START}:00:00"; do
        ts=$(date -d "$t" +%s 2>/dev/null) || continue
        if test "$ts" -gt "$now"; then
            echo $((ts - now))
            return
        fi
    done
    echo 3600   # fallback: re-check in an hour
}

apply() {
    mode="$1"

    # 1) System colour-scheme preference. kitty (via its *.auto.conf themes)
    #    and GTK apps follow this through xdg-desktop-portal.
    if command -v gsettings >/dev/null 2>&1; then
        if test "$mode" = light; then
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
            gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
        else
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
            gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
        fi
    fi

    # 2) waybar: relaunch with the matching style.
    if test "$mode" = light; then
        wstyle="$cfg/waybar/style-light.css"
    else
        wstyle="$cfg/waybar/style.css"
    fi
    if command -v waybar >/dev/null 2>&1; then
        pkill -x waybar 2>/dev/null
        waybar -s "$wstyle" >/dev/null 2>&1 &
    fi

    # 3) swaync: relaunch with the matching style.
    if test "$mode" = light; then
        sstyle="$cfg/swaync/style-light.css"
    else
        sstyle="$cfg/swaync/style.css"
    fi
    if command -v swaync >/dev/null 2>&1; then
        pkill -x swaync 2>/dev/null
        swaync --style "$sstyle" >/dev/null 2>&1 &
    fi

    # 4) Hyprland border colours.
    if command -v hyprctl >/dev/null 2>&1; then
        if test "$mode" = light; then
            hyprctl keyword general:col.active_border "rgba(5e81acff)" >/dev/null 2>&1
            hyprctl keyword general:col.inactive_border "rgba(d8dee9ff)" >/dev/null 2>&1
        else
            hyprctl keyword general:col.active_border "rgba(88c0d0ff)" >/dev/null 2>&1
            hyprctl keyword general:col.inactive_border "rgba(3b4252ff)" >/dev/null 2>&1
        fi
    fi

    # 5) Optional wallpaper swap via swww if you keep per-mode wallpapers.
    #    >>> PLACEHOLDER: drop wallpaper-light.jpg / wallpaper-dark.jpg in
    #    ~/.config/hypr, or delete this block. <<<
    wall="$HOME/.config/hypr/wallpaper-$mode.jpg"
    if command -v swww >/dev/null 2>&1 && test -f "$wall"; then
        swww img "$wall" >/dev/null 2>&1
    fi

    # Record the active mode for launch-fuzzel.sh.
    printf '%s\n' "$mode" > "$marker"
}

case "${1:-auto}" in
    mode)  current_mode ;;
    sleep) seconds_until_boundary ;;
    light) apply light ;;
    dark)  apply dark ;;
    auto)  apply "$(current_mode)" ;;
    *)     echo "usage: $0 [mode|sleep|auto|light|dark]" >&2; exit 1 ;;
esac
