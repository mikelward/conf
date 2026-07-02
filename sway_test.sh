#!/bin/sh
#
# Tests for the Sway Wayland desktop configs under config/sway and
# config/swaylock, plus the Sway-side behaviour of the shared waybar config
# and theme.sh (config/hypr/scripts).
#
# These are static presence/parse checks, like hypr_test.sh: we can't launch
# a compositor in CI, so we guard against files being moved/renamed and
# against the keybinds, input policy, per-host include, and idle wiring
# silently disappearing.

. "$(dirname "$0")/shrc_test_lib.sh"

_sway="$_srcdir/config/sway/config"
_lid="$_srcdir/config/sway/scripts/lid.sh"
_tmpl="$_srcdir/config/sway/config.local.template"
_ex_laptop="$_srcdir/config/sway/config.local.example-laptop"
_ex_desktop="$_srcdir/config/sway/config.local.example-desktop"
_readme="$_srcdir/config/sway/README.md"
_swaylock="$_srcdir/config/swaylock/config"
_waybar_cfg="$_srcdir/config/waybar/config.jsonc"
_theme="$_srcdir/config/hypr/scripts/theme.sh"

################################################################################
# Files exist. Without these guards every assert_contains below would trivially
# match against empty strings.
################################################################################
for _f in "$_sway" "$_lid" "$_tmpl" "$_ex_laptop" "$_ex_desktop" \
          "$_readme" "$_swaylock" "$_waybar_cfg" "$_theme"; do
    start_test "exists: ${_f##*/config/}"
    assert_true test -f "$_f"
done

start_test "lid.sh is executable"
assert_true test -x "$_lid"

_sway_body=$(cat "$_sway")

################################################################################
# Dynamic tiling: autotiling autostarts (guarded so its absence isn't fatal).
################################################################################
start_test "autotiling autostarts"
assert_contains "autotiling" "$_sway_body"
start_test "autotiling is guarded against not being installed"
assert_contains "command -v autotiling" "$_sway_body"

################################################################################
# Look: flat and traditional -- no gaps, thin borders, no titlebars, and the
# shared Nord scheme as the dark defaults.
################################################################################
start_test "borders are thin pixel borders (no titlebars)"
assert_contains "default_border pixel 2" "$_sway_body"
assert_contains "default_floating_border pixel 2" "$_sway_body"

start_test "inner and outer gaps are zero"
assert_contains "gaps inner 0" "$_sway_body"
assert_contains "gaps outer 0" "$_sway_body"

start_test "focused/unfocused border colours use the shared scheme"
assert_contains "client.focused          #88c0d0" "$_sway_body"
assert_contains "client.unfocused        #3b4252" "$_sway_body"

################################################################################
# Input: static type-matched handedness -- mice left-handed (right button
# primary), touchpads right-handed (left button primary) -- with the touchpad
# block AFTER the pointer block so touchpads win.
################################################################################
start_test "pointers (mice) are left-handed (right button primary)"
_pointer_block=$(sed -n '/^input type:pointer {/,/^}/p' "$_sway")
assert_contains "left_handed enabled" "$_pointer_block"

start_test "touchpads are right-handed (left button primary)"
_touchpad_block=$(sed -n '/^input type:touchpad {/,/^}/p' "$_sway")
assert_contains "left_handed disabled" "$_touchpad_block"

start_test "touchpad block comes after the pointer block"
_pointer_line=$(grep -n '^input type:pointer {' "$_sway" | cut -d: -f1)
_touchpad_line=$(grep -n '^input type:touchpad {' "$_sway" | cut -d: -f1)
assert_true test "$_touchpad_line" -gt "$_pointer_line"

start_test "no global scroll_factor (per-host/per-device only)"
_scroll_active=$(grep -E '^[[:space:]]*scroll_factor' "$_sway" || true)
assert_equal "" "$_scroll_active"

start_test "focus follows mouse"
assert_contains "focus_follows_mouse yes" "$_sway_body"

start_test "SUPER+drag moves, SUPER+right-drag resizes (floating_modifier normal)"
assert_contains "floating_modifier \$mod normal" "$_sway_body"

################################################################################
# Keyboard: US Dvorak with Caps Lock as Compose (matching `setup`).
################################################################################
_kbd_block=$(sed -n '/^input type:keyboard {/,/^}/p' "$_sway")
start_test "keyboard layout is US Dvorak"
assert_contains "xkb_variant dvorak" "$_kbd_block"
start_test "Caps Lock is the compose key"
assert_contains "xkb_options compose:caps" "$_kbd_block"

################################################################################
# Keybinds: launchers, lock, close, exit (matching the Hyprland build).
################################################################################
start_test "terminal launcher bound to SUPER+T"
assert_contains "bindsym \$mod+t exec \$term" "$_sway_body"

for _app in browser1 browser2 browser3 home irc google-calendar google-chat \
            google-meet notepad bluetooth-connect remote-desktop youtube-music; do
    start_test "app-launch bind present: $_app"
    assert_contains "exec $_app" "$_sway_body"
done

start_test "launcher bind uses the shared theme-aware fuzzel wrapper"
assert_contains "bindsym \$mod+space exec ~/.config/hypr/scripts/launch-fuzzel.sh" "$_sway_body"

start_test "file-manager bind (SUPER+E) launches yazi"
assert_contains "bindsym \$mod+e exec \$term -e yazi" "$_sway_body"

start_test "close window is bound to SUPER+BackSpace"
assert_contains "bindsym \$mod+BackSpace kill" "$_sway_body"

start_test "lock is bound to SUPER+L (swaylock)"
assert_contains "bindsym \$mod+l exec \$lock" "$_sway_body"
assert_contains "swaylock -f" "$_sway_body"

start_test "float is on SUPER+Shift+F and SUPER+Insert (F is browser2)"
assert_contains "bindsym \$mod+Shift+f floating toggle" "$_sway_body"
assert_contains "bindsym \$mod+Insert floating toggle" "$_sway_body"
assert_contains "bindsym \$mod+f exec browser2" "$_sway_body"

################################################################################
# Manual tiling overrides: split h/v, split toggle, monocle, layout cycle.
################################################################################
start_test "manual split binds (h/v for the next window)"
assert_contains "splith" "$_sway_body"
assert_contains "splitv" "$_sway_body"

start_test "split toggle on SUPER+O"
assert_contains "bindsym \$mod+o split toggle" "$_sway_body"

start_test "monocle is a fullscreen toggle on SUPER+grave"
assert_contains "bindsym \$mod+grave fullscreen toggle" "$_sway_body"

start_test "layout cycle binds on SUPER+. and SUPER+,"
assert_contains "bindsym \$mod+period layout toggle all" "$_sway_body"
assert_contains "bindsym \$mod+comma layout toggle split" "$_sway_body"

start_test "focus next/prev on SUPER+J/K"
assert_contains "bindsym \$mod+j focus next" "$_sway_body"
assert_contains "bindsym \$mod+k focus prev" "$_sway_body"

################################################################################
# Resize mode (modal, SUPER+Shift+R, Esc/Enter exits).
################################################################################
start_test "resize mode is defined and entered with SUPER+Shift+R"
assert_contains "mode \"resize\"" "$_sway_body"
assert_contains "bindsym \$mod+Shift+r mode \"resize\"" "$_sway_body"
start_test "resize mode exits on Escape and Return"
_resize_block=$(sed -n '/^mode "resize" {/,/^}/p' "$_sway")
assert_contains "bindsym Escape mode \"default\"" "$_resize_block"
assert_contains "bindsym Return mode \"default\"" "$_resize_block"

################################################################################
# Workspaces 1-10 via SUPER+N and move via SUPER+Shift+N.
################################################################################
start_test "workspace switch binds present (10)"
_ws=$(grep -c '^bindsym \$mod+[0-9] workspace number' "$_sway")
assert_true test "$_ws" -eq 10

start_test "move-to-workspace binds present (10)"
_wsmove=$(grep -c '^bindsym \$mod+Shift+[0-9] move container to workspace number' "$_sway")
assert_true test "$_wsmove" -eq 10

start_test "3-finger swipe cycles workspaces"
assert_contains "bindgesture swipe:3:right workspace next_on_output" "$_sway_body"
assert_contains "bindgesture swipe:3:left workspace prev_on_output" "$_sway_body"

################################################################################
# Media/brightness keys work while locked; the calculator must not.
################################################################################
start_test "volume/brightness/playback keys are --locked"
assert_contains "bindsym --locked XF86AudioRaiseVolume" "$_sway_body"
assert_contains "bindsym --locked XF86MonBrightnessUp" "$_sway_body"
assert_contains "playerctl play-pause" "$_sway_body"

start_test "calculator key is not active while locked (plain bindsym)"
assert_contains "bindsym XF86Calculator" "$_sway_body"
assert_not_contains "bindsym --locked XF86Calculator" "$_sway_body"

################################################################################
# Screenshots (grim) with an explicit PNG MIME type.
################################################################################
start_test "Print takes a screenshot to the clipboard"
assert_contains "bindsym Print exec grim" "$_sway_body"
assert_contains "wl-copy --type image/png" "$_sway_body"

################################################################################
# Laptop lid: bound to the lid switch (locked + reload), driven by lid.sh.
################################################################################
start_test "lid switch close/open bindings invoke lid.sh"
assert_contains "bindswitch --locked --reload lid:on exec ~/.config/sway/scripts/lid.sh close" "$_sway_body"
assert_contains "bindswitch --locked --reload lid:off exec ~/.config/sway/scripts/lid.sh open" "$_sway_body"

_lid_body=$(cat "$_lid")
start_test "lid.sh only suspends when no other output is active"
assert_contains "systemctl suspend" "$_lid_body"
assert_contains 'test "$active" -eq 0' "$_lid_body"

start_test "lid.sh disables the internal panel on close, enables on open"
assert_contains "disable" "$_lid_body"
assert_contains "enable" "$_lid_body"

start_test "lid.sh auto-detects the internal panel (eDP/LVDS/DSI), no placeholder"
assert_contains "eDP|LVDS|DSI" "$_lid_body"
assert_not_contains "REPLACE-ME" "$_lid_body"

start_test "lid.sh keeps the TODO about moving the policy to logind"
assert_contains "TODO" "$_lid_body"
assert_contains "HandleLidSwitch" "$_lid_body"

################################################################################
# Per-host overrides: config.local included AFTER the input blocks (so local
# input lines win) and BEFORE swaybg/swayidle (so $wallpaper/$idle_* overrides
# take effect).
################################################################################
start_test "config.local is included"
assert_contains "include ~/.config/sway/config.local" "$_sway_body"

_include_line=$(grep -n '^include ~/.config/sway/config.local' "$_sway" | cut -d: -f1)
_touchpad_line=$(grep -n '^input type:touchpad {' "$_sway" | cut -d: -f1)
_idle_line=$(grep -n '^exec swayidle' "$_sway" | cut -d: -f1)
_bg_line=$(grep -n 'swaybg -i \$wallpaper' "$_sway" | cut -d: -f1)

start_test "include comes after the input blocks"
assert_true test "$_include_line" -gt "$_touchpad_line"
start_test "include comes before swayidle and swaybg"
assert_true test "$_include_line" -lt "$_idle_line"
assert_true test "$_include_line" -lt "$_bg_line"

start_test "template and examples ship, and the desktop example disables suspend"
assert_contains "idle_suspend_cmd" "$(cat "$_tmpl")"
assert_contains "set \$idle_suspend_cmd true" "$(cat "$_ex_desktop")"
assert_contains "output" "$(cat "$_ex_laptop")"

################################################################################
# Idle/lock: swayidle mirrors hypridle (dim -> lock -> screen off -> suspend)
# with per-host variables.
################################################################################
start_test "idle timeouts and suspend command are overridable variables"
assert_contains "set \$idle_dim_timeout 150" "$_sway_body"
assert_contains "set \$idle_lock_timeout 300" "$_sway_body"
assert_contains "set \$idle_dpms_timeout 330" "$_sway_body"
assert_contains "set \$idle_suspend_timeout 1800" "$_sway_body"
assert_contains "set \$idle_suspend_cmd systemctl suspend" "$_sway_body"

start_test "swayidle dims, locks, blanks, and locks before sleep"
assert_contains "brightnessctl -s set 10%" "$_sway_body"
assert_contains "loginctl lock-session" "$_sway_body"
assert_contains "output * power off" "$_sway_body"
assert_contains "before-sleep 'loginctl lock-session'" "$_sway_body"

################################################################################
# Autostart: theming daemon (shared -- it launches waybar + swaync), swaybg,
# tray applets. waybar/swaync must NOT have their own exec lines.
################################################################################
start_test "shared theme daemon autostarts (owns waybar + swaync)"
assert_contains "exec ~/.config/hypr/scripts/theme-daemon.sh" "$_sway_body"
_waybar_exec=$(grep -E '^exec (--[a-z-]+ )*waybar' "$_sway" || true)
assert_equal "" "$_waybar_exec"

start_test "wallpaper via swaybg (plain), guarded on the image existing"
assert_contains "swaybg -i \$wallpaper -m fill" "$_sway_body"
assert_contains "test -f \$wallpaper" "$_sway_body"

start_test "network tray applet autostarts"
assert_contains "exec nm-applet" "$_sway_body"

################################################################################
# No dimming: Sway can't dim inactive windows; make sure nobody re-adds a
# bogus option, and the README documents the limitation.
################################################################################
start_test "no dim_inactive option (unsupported in Sway)"
_dim_active=$(grep -E '^[[:space:]]*dim_inactive' "$_sway" || true)
assert_equal "" "$_dim_active"
start_test "README notes Sway cannot dim inactive windows"
assert_contains "dim" "$(cat "$_readme")"

################################################################################
# Window rules: float the usual transient dialogs.
################################################################################
start_test "pavucontrol and nm-connection-editor float"
assert_contains "for_window [app_id=\"pavucontrol\"] floating enable" "$_sway_body"
assert_contains "for_window [app_id=\"nm-connection-editor\"] floating enable" "$_sway_body"

################################################################################
# Shared waybar config carries both compositors' modules and stays valid JSON.
################################################################################
_waybar_body=$(cat "$_waybar_cfg")
start_test "waybar has sway workspaces + window modules"
assert_contains "sway/workspaces" "$_waybar_body"
assert_contains "sway/window" "$_waybar_body"
start_test "waybar keeps the hyprland modules (still shared)"
assert_contains "hyprland/workspaces" "$_waybar_body"

if command -v python3 >/dev/null 2>&1; then
    start_test "waybar config.jsonc still parses as JSON (comments stripped)"
    if sed -e 's://.*$::' "$_waybar_cfg" \
         | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
        assert_true true
    else
        assert_true false
    fi
else
    echo "SKIP: JSON parse check (python3 not installed)"
fi

################################################################################
# Shared theme.sh is compositor-aware: sway borders via swaymsg, wallpaper via
# swaybg, and the hyprctl path is still there for the Hyprland build.
################################################################################
_theme_body=$(cat "$_theme")
start_test "theme.sh sets sway border colours via swaymsg"
assert_contains "swaymsg \"client.focused" "$_theme_body"
assert_contains "swaymsg \"client.unfocused" "$_theme_body"
start_test "theme.sh detects sway by SWAYSOCK (not just the binary)"
assert_contains "SWAYSOCK" "$_theme_body"
start_test "theme.sh still drives hyprland borders (shared both ways)"
assert_contains "hyprctl keyword general:col.active_border" "$_theme_body"
start_test "theme.sh swaps the wallpaper with swaybg under sway"
assert_contains "swaybg -i" "$_theme_body"

################################################################################
# swaylock: flat lock screen in the shared scheme.
################################################################################
_swaylock_body=$(cat "$_swaylock")
start_test "swaylock uses the shared colour scheme"
assert_contains "color=2e3440" "$_swaylock_body"
assert_contains "ring-color=88c0d0" "$_swaylock_body"
start_test "swaylock indicator is thin and flat (2px, like the borders)"
assert_contains "indicator-thickness=2" "$_swaylock_body"

################################################################################
# lid.sh parses as shell.
################################################################################
start_test "lid.sh parses as shell"
assert_true sh -n "$_lid"

################################################################################
# Zero required placeholders in the shipped config (the base config must be
# identical on every machine).
################################################################################
start_test "no REPLACE-ME placeholders in any shipped sway config file"
_placeholders=$(grep -rl 'REPLACE-ME' \
    "$_srcdir/config/sway" "$_srcdir/config/swaylock" 2>/dev/null || true)
assert_equal "" "$_placeholders"

test_summary "sway_test"
