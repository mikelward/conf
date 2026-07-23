#!/bin/sh
#
# Session/power menu for the waybar power button (custom/power module).
# Presents Lock / Logout / Suspend / Reboot / Shutdown via fuzzel --dmenu,
# themed to match the current light/dark mode the same way launch-fuzzel.sh
# themes the app launcher (mode marker first, time-of-day fallback).
#
# Logout is session- and compositor-aware:
#   - under uwsm, `uwsm stop` tears down the whole session unit cleanly
#     (a bare compositor exit would leave the unit and its children behind);
#   - otherwise exit whichever compositor is running (Hyprland or Sway).

marker="${XDG_RUNTIME_DIR:-/tmp}/theme-mode"
mode=$(cat "$marker" 2>/dev/null)
case "$mode" in
    light|dark) ;;
    *) mode=$("$HOME/.config/hypr/scripts/theme.sh" mode) ;;
esac

# fuzzel picks up the themed config the same way the launcher does; extra
# args put dmenu mode on and size the menu to the five fixed choices.
if test "$mode" = light; then
    set -- --config "$HOME/.config/fuzzel/fuzzel-light.ini"
else
    set --
fi

choice=$(printf '%s\n' Lock Logout Suspend Reboot Shutdown \
    | fuzzel --dmenu --lines 5 --width 20 --prompt "session> " "$@")

logout_session() {
    if command -v uwsm >/dev/null 2>&1 && uwsm check is-active >/dev/null 2>&1; then
        exec uwsm stop
    elif test -n "$HYPRLAND_INSTANCE_SIGNATURE" && command -v hyprctl >/dev/null 2>&1; then
        # Hyprland 0.55 dispatches Lua expressions; <= 0.54 the plain name.
        if test "$(hyprctl eval 'return true' 2>/dev/null)" = "ok"; then
            exec hyprctl dispatch 'hl.dsp.exit()'
        else
            exec hyprctl dispatch exit
        fi
    elif test -n "$SWAYSOCK" && command -v swaymsg >/dev/null 2>&1; then
        exec swaymsg exit
    fi
}

case "$choice" in
    Lock)     exec loginctl lock-session ;;
    Logout)   logout_session ;;
    Suspend)  exec systemctl suspend ;;
    Reboot)   exec systemctl reboot ;;
    Shutdown) exec systemctl poweroff ;;
    *)        exit 0 ;;  # menu dismissed
esac
