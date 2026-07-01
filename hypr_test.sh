#!/bin/sh
#
# Tests for the Hyprland Wayland desktop configs under config/hypr,
# config/waybar, config/fuzzel, and config/swaync.
#
# These are static presence/parse checks: we can't launch a compositor in CI,
# so we guard against the config files being moved/renamed and against the
# Krohnkite-equivalent keybinds, input settings, and bar modules silently
# disappearing.

. "$(dirname "$0")/shrc_test_lib.sh"

_hypr="$_srcdir/config/hypr/hyprland.conf"
_idle="$_srcdir/config/hypr/hypridle.conf"
_lock="$_srcdir/config/hypr/hyprlock.conf"
_toggle="$_srcdir/config/hypr/scripts/toggle-layout.sh"
_layoutcycle="$_srcdir/config/hypr/scripts/layout-cycle.sh"
_lid="$_srcdir/config/hypr/scripts/lid.sh"
_theme="$_srcdir/config/hypr/scripts/theme.sh"
_themed="$_srcdir/config/hypr/scripts/theme-daemon.sh"
_fuzzellaunch="$_srcdir/config/hypr/scripts/launch-fuzzel.sh"
_apply="$_srcdir/config/hypr/scripts/apply-input.sh"
_waybar_cfg="$_srcdir/config/waybar/config.jsonc"
_waybar_css="$_srcdir/config/waybar/style.css"
_fuzzel="$_srcdir/config/fuzzel/fuzzel.ini"
_swaync_cfg="$_srcdir/config/swaync/config.json"
_swaync_css="$_srcdir/config/swaync/style.css"

################################################################################
# Files exist. Without these guards every assert_contains below would trivially
# match against empty strings.
################################################################################
for _f in "$_hypr" "$_idle" "$_lock" "$_toggle" "$_layoutcycle" "$_lid" \
          "$_theme" "$_themed" "$_fuzzellaunch" "$_apply" \
          "$_waybar_cfg" "$_waybar_css" \
          "$_srcdir/config/waybar/common.css" \
          "$_srcdir/config/waybar/colors-dark.css" \
          "$_srcdir/config/waybar/colors-light.css" \
          "$_srcdir/config/waybar/style-light.css" \
          "$_srcdir/config/swaync/common.css" \
          "$_srcdir/config/swaync/colors-dark.css" \
          "$_srcdir/config/swaync/colors-light.css" \
          "$_srcdir/config/swaync/style-light.css" \
          "$_fuzzel" "$_srcdir/config/fuzzel/fuzzel-light.ini" \
          "$_swaync_cfg" "$_swaync_css"; do
    start_test "exists: ${_f##*/config/}"
    assert_true test -f "$_f"
done

_hypr_body=$(cat "$_hypr")

################################################################################
# Layout: master is the default, new windows go to the stack (Krohnkite Tile).
################################################################################
start_test "default layout is master"
assert_contains "layout = master" "$_hypr_body"

start_test "new windows join the stack, not the master"
assert_contains "new_status = slave" "$_hypr_body"

################################################################################
# Input: focus follows mouse; handedness is auto-applied per device (no
# hardcoded device names / placeholders).
################################################################################
start_test "follow_mouse is enabled"
assert_contains "follow_mouse = 1" "$_hypr_body"

start_test "global default is right-handed (trackpads keep left button primary)"
_input_block=$(sed -n '/^input {/,/^}/p' "$_hypr")
assert_contains "left_handed = false" "$_input_block"

start_test "no hardcoded per-device blocks remain"
_devcount=$(grep -c '^device {' "$_hypr")
assert_true test "$_devcount" -eq 0

start_test "handedness is auto-applied by apply-input.sh at login"
assert_contains "exec-once = ~/.config/hypr/scripts/apply-input.sh" "$_hypr_body"

_apply_body=$(cat "$_apply")
start_test "apply-input classifies touchpads vs mice"
assert_contains "touchpad" "$_apply_body"
start_test "apply-input sets mice left_handed via hyprctl"
assert_contains "left_handed" "$_apply_body"
assert_contains "scroll_factor" "$_apply_body"

start_test "hyprland.conf has no REPLACE-ME placeholders"
assert_not_contains "REPLACE-ME" "$_hypr_body"

################################################################################
# Keyboard: Dvorak layout with Caps Lock as Compose (matching `setup`).
################################################################################
start_test "keyboard layout is US Dvorak"
assert_contains "kb_variant = dvorak" "$_input_block"
start_test "Caps Lock is the compose key"
assert_contains "kb_options = compose:caps" "$_input_block"

################################################################################
# Lock, screenshots, and playback keys (from xbindkeysrc).
################################################################################
start_test "lock is bound to SUPER+L"
assert_contains "\$mainMod, L, exec, \$lock" "$_hypr_body"
start_test "Print takes a screenshot (grim) with an explicit PNG MIME type"
assert_contains ", Print," "$_hypr_body"
assert_contains "grim" "$_hypr_body"
# Explicit --type so paste works without relying on xdg-mime inference.
assert_contains "wl-copy --type image/png" "$_hypr_body"
start_test "playback keys use playerctl"
assert_contains "playerctl play-pause" "$_hypr_body"

# The calculator launches a GUI, so it must NOT fire under the lock screen:
# plain `bind`, not `bindl`.
start_test "calculator key is not active while locked (plain bind)"
assert_contains "bind = , XF86Calculator" "$_hypr_body"
assert_not_contains "bindl = , XF86Calculator" "$_hypr_body"

################################################################################
# Krohnkite-equivalent master/stack keybinds.
################################################################################
start_test "mfact decrease bind (SUPER+H)"
assert_contains "layoutmsg, mfact -" "$_hypr_body"
start_test "mfact increase bind (SUPER+L)"
assert_contains "layoutmsg, mfact +" "$_hypr_body"

start_test "add window to master bind"
assert_contains "layoutmsg, addmaster" "$_hypr_body"
start_test "remove window from master bind"
assert_contains "layoutmsg, removemaster" "$_hypr_body"

start_test "swap with master bind"
assert_contains "layoutmsg, swapwithmaster" "$_hypr_body"

start_test "cycle master orientation bind"
assert_contains "layoutmsg, orientationnext" "$_hypr_body"

start_test "monocle fullscreen keeps gaps/bar (state 1)"
assert_contains "fullscreen, 1" "$_hypr_body"

start_test "toggle floating bind"
assert_contains "togglefloating" "$_hypr_body"

start_test "close window bind"
assert_contains "killactive" "$_hypr_body"

start_test "master<->dwindle toggle invokes the toggle script"
assert_contains "toggle-layout.sh" "$_hypr_body"

################################################################################
# Resize submap (modal resize mode).
################################################################################
start_test "resize submap is defined"
assert_contains "submap = resize" "$_hypr_body"
start_test "resize submap resets"
assert_contains "submap = reset" "$_hypr_body"

################################################################################
# Workspaces 1-10 via SUPER+N and move via SUPER+Shift+N.
################################################################################
start_test "workspace switch binds present (10)"
_ws=$(grep -c '^bind = \$mainMod, [0-9], workspace,' "$_hypr")
assert_true test "$_ws" -eq 10

start_test "move-to-workspace binds present (10)"
_wsmove=$(grep -c '^bind = \$mainMod SHIFT, [0-9], movetoworkspacesilent,' "$_hypr")
assert_true test "$_wsmove" -eq 10

################################################################################
# Mouse drag to move (left) and resize (right) with SUPER.
################################################################################
start_test "SUPER + left mouse moves windows"
assert_contains "bindm = \$mainMod, mouse:272, movewindow" "$_hypr_body"
start_test "SUPER + right mouse resizes windows"
assert_contains "bindm = \$mainMod, mouse:273, resizewindow" "$_hypr_body"

################################################################################
# Look: rounded corners, blur, no gaps.
################################################################################
start_test "corners are rounded"
assert_contains "rounding = 6" "$_hypr_body"
start_test "blur is enabled"
_blur=$(sed -n '/blur {/,/}/p' "$_hypr")
assert_contains "enabled = true" "$_blur"
start_test "inner gaps are zero"
assert_contains "gaps_in = 0" "$_hypr_body"
start_test "outer gaps are zero"
assert_contains "gaps_out = 0" "$_hypr_body"

################################################################################
# Dim inactive windows (matching the KDE diminactive effect).
################################################################################
start_test "inactive windows are dimmed"
assert_contains "dim_inactive = true" "$_hypr_body"

################################################################################
# Krohnkite/KDE-matching keybinds: app launchers, close, monocle, layout cycle.
################################################################################
start_test "close window is bound to SUPER+BackSpace (Krohnkite Meta+Backspace)"
assert_contains "BackSpace, killactive" "$_hypr_body"

start_test "terminal launcher bound to SUPER+T"
assert_contains "\$mainMod, T, exec" "$_hypr_body"

# SUPER+<letter> launchers from xbindkeysrc.
for _app in browser1 browser2 browser3 home irc google-calendar google-chat \
            google-meet notepad bluetooth-connect remote-desktop youtube-music; do
    start_test "app-launch bind present: $_app"
    assert_contains "exec, $_app" "$_hypr_body"
done

start_test "add/remove master moved off letters onto = / -"
assert_contains "\$mainMod, equal, layoutmsg, addmaster" "$_hypr_body"
assert_contains "\$mainMod, minus, layoutmsg, removemaster" "$_hypr_body"
start_test "float is on SUPER+Shift+F and SUPER+Insert (F is browser2)"
assert_contains "\$mainMod SHIFT, F, togglefloating" "$_hypr_body"
assert_contains "\$mainMod, Insert, togglefloating" "$_hypr_body"
assert_contains "\$mainMod, F, exec, browser2" "$_hypr_body"
start_test "resize submap entered with SUPER+Shift+R"
assert_contains "\$mainMod SHIFT, R, submap, resize" "$_hypr_body"
start_test "no true-fullscreen (state 0) bind"
assert_not_contains "fullscreen, 0" "$_hypr_body"

start_test "monocle bound to SUPER+grave"
assert_contains "\$mainMod, grave, fullscreen, 1" "$_hypr_body"

start_test "layout cycle (next/prev) invokes layout-cycle.sh"
assert_contains "layout-cycle.sh next" "$_hypr_body"
assert_contains "layout-cycle.sh prev" "$_hypr_body"

################################################################################
# Laptop lid handling: bound to the lid switch, driven by lid.sh.
################################################################################
start_test "lid switch (close) is bound"
assert_contains "switch:on:Lid Switch" "$_hypr_body"
start_test "lid switch (open) is bound"
assert_contains "switch:off:Lid Switch" "$_hypr_body"
start_test "lid binds invoke lid.sh"
assert_contains "lid.sh close" "$_hypr_body"
assert_contains "lid.sh open" "$_hypr_body"

start_test "lid.sh only suspends when no external display is connected"
_lid_body=$(cat "$_lid")
assert_contains "systemctl suspend" "$_lid_body"
# The suspend must be guarded by the external-display check, not unconditional.
assert_contains 'if test -z "$external"' "$_lid_body"

start_test "lid.sh disables the internal panel on close"
assert_contains "disable" "$_lid_body"

start_test "lid.sh auto-detects the internal panel (eDP/LVDS/DSI), no placeholder"
assert_contains "eDP|LVDS|DSI" "$_lid_body"
assert_not_contains "REPLACE-ME" "$_lid_body"
# Must use `monitors all` so a disabled panel is still found on the open path.
start_test "lid.sh detects the panel from 'monitors all' (incl. disabled)"
assert_contains "monitors all" "$_lid_body"

# Re-enabling must use auto scale like the catch-all monitor rule; a hardcoded
# scale of 1 would reset a HiDPI panel every time the lid is opened.
start_test "lid.sh re-enables the panel with auto scale"
assert_contains "preferred, auto, auto" "$_lid_body"
assert_not_contains "preferred, auto, 1" "$_lid_body"

################################################################################
# Tray applets: network + volume/sound.
################################################################################
_waybar_body=$(cat "$_waybar_cfg")
start_test "network tray applet autostarts"
assert_contains "exec-once = nm-applet" "$_hypr_body"
start_test "waybar exposes a network module"
assert_contains "\"network\"" "$_waybar_body"
start_test "waybar exposes a volume/sound module"
assert_contains "\"pulseaudio\"" "$_waybar_body"

################################################################################
# Autostart wires up bar, notifications, idle, hotplug, wallpaper.
################################################################################
for _svc in hypridle swww-daemon; do
    start_test "autostart: $_svc"
    assert_contains "exec-once = $_svc" "$_hypr_body"
done

start_test "theme daemon autostarts"
assert_contains "exec-once = ~/.config/hypr/scripts/theme-daemon.sh" "$_hypr_body"

# waybar and swaync are launched by theme.sh (with the light/dark style), not
# by their own exec-once lines.
_theme_body=$(cat "$_theme")
start_test "theme.sh launches waybar"
assert_contains "waybar -s" "$_theme_body"
start_test "theme.sh launches swaync"
assert_contains "swaync --style" "$_theme_body"

################################################################################
# hypridle: dim, lock, and screen-off listeners exist.
################################################################################
_idle_body=$(cat "$_idle")
start_test "hypridle dims the backlight"
assert_contains "brightnessctl -s set" "$_idle_body"
start_test "hypridle locks the session"
assert_contains "loginctl lock-session" "$_idle_body"
start_test "hypridle turns the display off (DPMS)"
assert_contains "dpms off" "$_idle_body"

################################################################################
# Waybar: three timezone clocks, tray, and battery.
################################################################################
_waybar_body=$(cat "$_waybar_cfg")
start_test "waybar has a London clock"
assert_contains "Europe/London" "$_waybar_body"
start_test "waybar has a San Francisco clock"
assert_contains "America/Los_Angeles" "$_waybar_body"
start_test "waybar centre has three clock modules"
_clocks=$(sed -n '/"modules-center"/p' "$_waybar_cfg" | grep -o 'clock' | grep -c clock)
assert_true test "$_clocks" -eq 3
start_test "waybar has a tray"
assert_contains "\"tray\"" "$_waybar_body"
start_test "waybar has a battery module"
assert_contains "\"battery\"" "$_waybar_body"

# JSON validity of the waybar config (strip // and /* */ comments first) and
# the swaync config, when a JSON parser is available.
if command -v python3 >/dev/null 2>&1; then
    start_test "waybar config.jsonc parses as JSON (comments stripped)"
    if sed -e 's://.*$::' "$_waybar_cfg" \
         | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
        assert_true true
    else
        assert_true false
    fi

    start_test "swaync config.json parses as JSON"
    if python3 -c 'import sys,json; json.load(sys.stdin)' < "$_swaync_cfg" 2>/dev/null; then
        assert_true true
    else
        assert_true false
    fi
else
    echo "SKIP: JSON parse checks (python3 not installed)"
fi

################################################################################
# fuzzel launcher.
################################################################################
_fuzzel_body=$(cat "$_fuzzel")
start_test "fuzzel has a colors section (themed)"
assert_contains "[colors]" "$_fuzzel_body"

################################################################################
# Monitors are auto-placed by Hyprland; no display-hotplug daemon or names.
################################################################################
start_test "monitor catch-all rule auto-places outputs"
assert_contains "monitor = , preferred, auto, auto" "$_hypr_body"

################################################################################
# Zero placeholders anywhere in the shipped desktop config.
################################################################################
start_test "no REPLACE-ME placeholders in any shipped config file"
_placeholders=$(grep -rl 'REPLACE-ME' \
    "$_srcdir/config/hypr" "$_srcdir/config/waybar" \
    "$_srcdir/config/fuzzel" "$_srcdir/config/swaync" 2>/dev/null || true)
assert_equal "" "$_placeholders"

################################################################################
# Touchpad gesture uses the current Hyprland 0.51+ syntax.
################################################################################
start_test "workspace gesture uses the new 0.51 gesture syntax"
assert_contains "gesture = 3, horizontal, workspace" "$_hypr_body"
start_test "the removed gestures:workspace_swipe option is not an active directive"
# The word may appear in a comment (for pre-0.51 users); ensure it's never an
# actual config line.
_ws_active=$(grep -E '^[[:space:]]*workspace_swipe' "$_hypr" || true)
assert_equal "" "$_ws_active"

################################################################################
# Time-based light/dark theming.
################################################################################
start_test "launcher bind uses the theme-aware fuzzel wrapper"
assert_contains "Space, exec, ~/.config/hypr/scripts/launch-fuzzel.sh" "$_hypr_body"

start_test "file-manager bind (SUPER+E) launches yazi"
assert_contains "\$mainMod, E, exec" "$_hypr_body"
assert_contains "yazi" "$_hypr_body"

start_test "theme boundaries are 07:00 (light) and 19:00 (dark)"
assert_contains "LIGHT_START=7" "$_theme_body"
assert_contains "DARK_START=19" "$_theme_body"

start_test "theme.sh drives the system colour-scheme (kitty + GTK follow it)"
assert_contains "color-scheme" "$_theme_body"

start_test "theme.sh exposes light and dark modes"
assert_contains "prefer-light" "$_theme_body"
assert_contains "prefer-dark" "$_theme_body"

start_test "theme daemon re-applies at each boundary"
_themed_body=$(cat "$_themed")
assert_contains "\"\$theme\" sleep" "$_themed_body"

start_test "fuzzel launcher themes by current mode"
_fuzzellaunch_body=$(cat "$_fuzzellaunch")
assert_contains "theme.sh\" mode" "$_fuzzellaunch_body"

# theme.sh records the applied mode in a marker; launch-fuzzel.sh must read it
# so a manual `theme.sh light`/`theme.sh dark` override themes fuzzel too (the
# time-of-day mode is only the fallback).
start_test "theme.sh writes the mode marker and fuzzel launcher reads it"
assert_contains "theme-mode" "$_theme_body"
assert_contains "theme-mode" "$_fuzzellaunch_body"

test_summary "hypr_test"
