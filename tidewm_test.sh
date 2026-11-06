#!/bin/sh
#
# Tests for config/tidewm/config, tidewm's config for tide's tidewm session.
# tidewm can't run in CI, so these check the file as tidewm reads it
# (tidewm's docs/config.md): every line is a directive it takes, every
# binding runs commands it knows, no key is bound twice, and each key that
# runs an app in hyprland.lua runs it here too, through tide launch.

. "$(dirname "$0")/shrc_test_lib.sh"

_cfg="$_srcdir/config/tidewm/config"
_hypr="$_srcdir/config/hypr/hyprland.lua"

start_test "exists: tidewm/config"
assert_true test -f "$_cfg"

# The file's lines, comments and blank lines left out, with a block's
# lines (input NAME { ... }) prefixed "  " so they read as settings.
_lines=$(awk '
    /^[[:space:]]*(#|$)/ { next }
    /^[[:space:]]*}[[:space:]]*$/ { inblock = 0; next }
    inblock { sub(/^[[:space:]]+/, ""); print "  " $0; next }
    /{[[:space:]]*$/ { inblock = 1; sub(/[[:space:]]*{[[:space:]]*$/, ""); print; next }
    { print }' "$_cfg")

start_test "every line is a directive tidewm takes"
_bad=$(printf '%s\n' "$_lines" | grep -v '^  ' | awk '{ print $1 }' | grep -vxE \
    'set|bindsym|bindswitch|for_window|output|input|mode|single_window|dim_inactive|focus_guard|include' || true)
assert_equal "" "$_bad"

start_test "the file's blocks are input blocks, which take a setting a line"
_blocks=$(grep -E '{[[:space:]]*$' "$_cfg" | grep -vE '^input ' || true)
assert_equal "" "$_blocks"

# A binding's commands: what follows its keys, with $mod and $runenv as
# set. Each command starts with a word tidewm's IPC knows (docs/ipc.md).
_bindings=$(printf '%s\n' "$_lines" | awk '$1 == "bindsym" || $1 == "bindswitch" {
    i = 2
    while ($i ~ /^--/) i++
    cmd = ""
    for (j = i + 1; j <= NF; j++) cmd = cmd (cmd == "" ? "" : " ") $j
    print cmd }')
start_test "every binding runs commands tidewm knows"
_unknown=$(printf '%s\n' "$_bindings" | while IFS= read -r _cmd; do
    case "$_cmd" in
        exec\ *) printf '%s\n' exec; continue ;;
    esac
    printf '%s\n' "$_cmd" | tr ';' '\n' | awk 'NF { print $1 }'
done | grep -vxE 'exec|kill|exit|layout|mfact|nmaster|zoom|focus|maximize|fullscreen|floating|workspace|move|input|output|mode|reload|grant|dim|sticky|urgent|nop|rename|persist|unpersist|chvt|unlock|switch' || true)
assert_equal "" "$_unknown"

# A key, as tidewm matches it: its modifiers in any order, and any case.
# A press is "-", so read never sees an empty first field.
_keys=$(printf '%s\n' "$_lines" | awk '$1 == "bindsym" {
    i = 2; flags = ""
    while ($i ~ /^--/) { if ($i == "--release") flags = flags $i; i++ }
    print (flags == "" ? "-" : flags) " " tolower($i) }' | while read -r _flags _combo; do
    printf '%s %s\n' "$_flags" "$(printf '%s\n' "$_combo" | tr '+' '\n' | sort | tr '\n' '+')"
done)
start_test "no key is bound twice"
assert_equal "" "$(printf '%s\n' "$_keys" | sort | uniq -d)"

start_test "every tide launch names the app its window grant is for"
assert_equal "" "$(grep 'exec tide launch' "$_cfg" | grep -v 'tide launch --app ' || true)"

# hyprland.lua's app keys, as key("SHIFT + G"), app(...): each is bound
# here, $mod+Shift+g, to a tide launch of the same program.
start_test "each of hyprland.lua's app keys launches the same app here"
_missing=$(grep -oE 'hl\.bind\(key\("[^"]+"\), app\([^)]*\)' "$_hypr" | while IFS= read -r _bind; do
    _k=$(printf '%s\n' "$_bind" | sed 's/^hl\.bind(key("\([^"]*\)").*/\1/')
    _prog=$(printf '%s\n' "$_bind" | sed -n 's/.*app(\(runenv \.\. " \)\{0,1\}\([a-z0-9_.-]*\).*/\2/p')
    _combo='$mod'$(printf '%s\n' "$_k" | sed 's/ + /+/g; s/SHIFT/Shift/; s/^/+/' | awk -F+ '{ $NF = tolower($NF); OFS = "+"; print }' OFS=+)
    case "$_prog" in
        terminal) _prog=kitty ;;
    esac
    # The line for that key, and whether it launches the program, bare or
    # through runenv.
    _line=$(grep -F "bindsym $_combo exec tide launch " "$_cfg" | head -n 1)
    case "$_line " in
        *"-- $_prog "* | *'-- $runenv '"$_prog "*) ;;
        *) printf '%s %s\n' "$_k" "$_prog" ;;
    esac
done)
assert_equal "" "$_missing"

# hyprland.lua's keys that call tide's shell, as key("SHIFT + Return"),
# exec("qs -c tide ipc call prompt move ...: each is bound here,
# $mod+Shift+Return, to the same call, but for the floating rules, which
# tide's shell writes for hyprland.lua, so can't apply on tidewm yet.
start_test "each of hyprland.lua's shell keys calls the shell here too"
_missing=$(grep -oE 'hl\.bind\(key\("[^"]+"\), exec\("qs -c tide ipc call [a-z ]*[a-z]' "$_hypr" | while IFS= read -r _bind; do
    _k=$(printf '%s\n' "$_bind" | sed 's/^hl\.bind(key("\([^"]*\)").*/\1/')
    _call=$(printf '%s\n' "$_bind" | sed 's/.*exec("\(qs -c tide ipc call [a-z ]*[a-z]\).*/\1/')
    case "$_call" in
        *" floating remember") continue ;;
    esac
    _combo='$mod'$(printf '%s\n' "$_k" | sed 's/ + /+/g; s/SHIFT/Shift/; s/ALT/Alt/; s/^/+/' | awk -F+ '{ if (length($NF) == 1 || $NF == "Space") $NF = tolower($NF); OFS = "+"; print }' OFS=+)
    grep -qxF "bindsym $_combo exec $_call" "$_cfg" || printf '%s %s\n' "$_combo" "$_call"
done)
assert_equal "" "$_missing"

start_test "the settings tide's shell writes are included, last, so they win"
assert_equal "include tide-*.conf" "$(printf '%s\n' "$_lines" | tail -n 1)"

start_test "the session locks through logind, as tide's does"
assert_contains 'bindsym $mod+l exec loginctl lock-session' "$(cat "$_cfg")"

start_test "closing the lid turns the panel off, then has tide lock as its Power page says"
assert_contains 'bindswitch lid:on output eDP-1 disable; exec tide lid-closed' "$(cat "$_cfg")"

start_test "the focus guard is on, as tide's session needs"
assert_contains 'focus_guard enable' "$(cat "$_cfg")"

# xdg-desktop-portal-wlr reads the file named for the session's first
# desktop that has one (its config.c), here tidewm's.
_xdpw="$_srcdir/config/xdg-desktop-portal-wlr/tidewm"

start_test "screen shares ask tide's picker, as xdpw's dmenu chooser"
assert_equal "[screencast]
chooser_type=dmenu
chooser_cmd=tide-share-picker --dmenu" "$(grep -v -e '^#' -e '^$' "$_xdpw")"

test_summary "tidewm_test"
