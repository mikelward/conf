#!/bin/sh
#
# Tests for the Hyprland Wayland desktop configs under config/hypr,
# config/waybar, config/fuzzel, config/swaync, and config/kanshi.
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
_waybar_cfg="$_srcdir/config/waybar/config.jsonc"
_waybar_css="$_srcdir/config/waybar/style.css"
_fuzzel="$_srcdir/config/fuzzel/fuzzel.ini"
_swaync_cfg="$_srcdir/config/swaync/config.json"
_swaync_css="$_srcdir/config/swaync/style.css"
_kanshi="$_srcdir/config/kanshi/config"

################################################################################
# Files exist. Without these guards every assert_contains below would trivially
# match against empty strings.
################################################################################
for _f in "$_hypr" "$_idle" "$_lock" "$_toggle" "$_layoutcycle" "$_lid" \
          "$_theme" "$_themed" "$_fuzzellaunch" \
          "$_waybar_cfg" "$_waybar_css" \
          "$_srcdir/config/waybar/common.css" \
          "$_srcdir/config/waybar/colors-dark.css" \
          "$_srcdir/config/waybar/colors-light.css" \
          "$_srcdir/config/waybar/style-light.css" \
          "$_srcdir/config/swaync/common.css" \
          "$_srcdir/config/swaync/colors-dark.css" \
          "$_srcdir/config/swaync/colors-light.css" \
          "$_srcdir/config/swaync/style-light.css" \
          "$_fuzzel" "$_swaync_cfg" "$_swaync_css" "$_kanshi"; do
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
# Input: focus follows mouse, and per-device blocks exist for handedness and
# scroll speed.
################################################################################
start_test "follow_mouse is enabled"
assert_contains "follow_mouse = 1" "$_hypr_body"

start_test "global default is right-handed (trackpads keep left button primary)"
_input_block=$(sed -n '/^input {/,/^}/p' "$_hypr")
assert_contains "left_handed = false" "$_input_block"

start_test "mice are set left_handed = true (right button primary) per device"
assert_contains "left_handed = true" "$_hypr_body"

start_test "per-device scroll_factor is set in a device block"
assert_contains "scroll_factor" "$_hypr_body"

start_test "there are at least two mouse device blocks (multiple pointers)"
_devcount=$(grep -c '^device {' "$_hypr")
assert_true test "$_devcount" -ge 2

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

for _app in browser1 browser2 music; do
    start_test "app-launch bind present: $_app"
    assert_contains "exec, $_app" "$_hypr_body"
done

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
for _svc in hypridle kanshi swww-daemon; do
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
# fuzzel launcher and kanshi profiles.
################################################################################
_fuzzel_body=$(cat "$_fuzzel")
start_test "fuzzel has a colors section (themed)"
assert_contains "[colors]" "$_fuzzel_body"

_kanshi_body=$(cat "$_kanshi")
for _p in undocked docked clamshell workstation; do
    start_test "kanshi profile: $_p"
    assert_contains "profile $_p {" "$_kanshi_body"
done

# kanshi matches the first profile whose listed outputs are all connected, so
# the two-output profiles (docked, workstation) must precede the one-output
# ones (clamshell, undocked) or they'd be shadowed.
start_test "kanshi lists two-output profiles before one-output ones"
_docked_ln=$(grep -n '^profile docked {' "$_kanshi" | cut -d: -f1)
_workstation_ln=$(grep -n '^profile workstation {' "$_kanshi" | cut -d: -f1)
_clamshell_ln=$(grep -n '^profile clamshell {' "$_kanshi" | cut -d: -f1)
_undocked_ln=$(grep -n '^profile undocked {' "$_kanshi" | cut -d: -f1)
assert_true test "$_docked_ln" -lt "$_clamshell_ln"
start_test "kanshi workstation precedes clamshell"
assert_true test "$_workstation_ln" -lt "$_clamshell_ln"
start_test "kanshi workstation precedes undocked"
assert_true test "$_workstation_ln" -lt "$_undocked_ln"

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

test_summary "hypr_test"
