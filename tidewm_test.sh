#!/bin/sh
#
# Tests for config/tidewm/config, this setup's tidewm config, which layers
# its preferences over tide's own (tide's tidewm/tide.conf, tested there).
# tidewm can't run in CI, so these check the file as tidewm reads it
# (tidewm's docs/config.md).

. "$(dirname "$0")/shrc_test_lib.sh"

_cfg="$_srcdir/config/tidewm/config"
_hypr="$_srcdir/config/hypr/hyprland.lua"

start_test "exists: tidewm/config"
assert_true test -f "$_cfg"

# The file's lines, comments and blank lines left out, an input block's
# lines prefixed "  " so they read as settings.
_lines=$(awk '
    /^[[:space:]]*(#|$)/ { next }
    /^[[:space:]]*}[[:space:]]*$/ { inblock = 0; next }
    inblock { sub(/^[[:space:]]+/, ""); print "  " $0; next }
    /{[[:space:]]*$/ { inblock = 1; sub(/[[:space:]]*{[[:space:]]*$/, ""); print; next }
    { print }' "$_cfg")

start_test "tide's config comes first, so these win over it"
assert_equal "include tide.conf" "$(printf '%s\n' "$_lines" | head -n 1)"

start_test "the settings tide's shell writes are included, then nwg-displays' outputs, so they win"
assert_equal "include tide-*.conf
include ~/.config/sway/outputs" "$(printf '%s\n' "$_lines" | tail -n 2)"

start_test "every line is a directive tidewm takes"
_bad=$(printf '%s\n' "$_lines" | grep -v '^  ' | awk '{ print $1 }' | grep -vxE 'set|bindsym|input|include' || true)
assert_equal "" "$_bad"

start_test "no key is bound twice here"
_keys=$(awk '$1 == "bindsym" { i = 2; while ($i ~ /^--/) i++; print tolower($i) }' "$_cfg" | sort)
assert_equal "" "$(printf '%s\n' "$_keys" | uniq -d)"

start_test "every app runs through tide launch, naming the app its grant is for"
assert_equal "" "$(grep 'exec tide launch' "$_cfg" | grep -v 'tide launch --app ' || true)"

# The apps hyprland.lua passes tide's in its apps option: each is bound
# here by the same name, so keys.json serves both sessions.
start_test "each of hyprland.lua's apps has its name here"
_names=$(sed -n 's/^bindsym .*--name=\([a-z0-9_]*\) .*/\1/p' "$_cfg" | sort -u)
_apps=$(grep -oE '(app|t\.bind)\("[a-z0-9_]+"' "$_hypr" | sed 's/.*"\(.*\)"/\1/' | sort -u)
assert_true test -n "$_apps"
assert_equal "" "$(printf '%s\n' "$_apps" | grep -vxF "$_names" || true)"

# What a block of the config sets: each line of `input NAME {` ... `}`.
_block() {
    awk -v head="input $1 {" '$0 == head { on = 1; next } on && /^}/ { on = 0 } on { sub(/^[[:space:]]+/, ""); print }' "$_cfg"
}

start_test "every mouse has hyprland.lua's handedness and wheel speed"
_mouse=$(sed -E -n 's/^ *mouse = \{ left_handed = (true|false), scroll_factor = ([0-9.]*) \},$/\1 \2/p' "$_hypr")
assert_equal "true 3" "$_mouse"
assert_contains "left_handed enabled" "$(_block type:pointer)"
assert_contains "scroll_factor ${_mouse#* }" "$(_block type:pointer)"

start_test "the keyboard is hyprland.lua's Dvorak, with Compose on Caps Lock"
assert_contains "xkb_variant dvorak" "$(_block type:keyboard)"
assert_contains "xkb_options compose:caps,altwin:menu_win" "$(_block type:keyboard)"

# xdg-desktop-portal-wlr reads the file named for the session's first
# desktop that has one (its config.c), here tidewm's.
_xdpw="$_srcdir/config/xdg-desktop-portal-wlr/tidewm"

start_test "screen shares ask tide's picker, as xdpw's dmenu chooser"
assert_equal "[screencast]
chooser_type=dmenu
chooser_cmd=tide-share-picker --dmenu" "$(grep -v -e '^#' -e '^$' "$_xdpw")"

test_summary "tidewm_test"
