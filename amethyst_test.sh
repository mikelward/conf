#!/bin/sh
#
# Tests for amethyst.yml.
#

. "$(dirname "$0")/shrc_test_lib.sh"

_amethyst="$_srcdir/amethyst.yml"

# Sanity: the config file is present. Without this guard the rest of the
# asserts all trivially match empty strings, hiding a moved/renamed config.
start_test "amethyst.yml exists"
assert_true test -f "$_amethyst"

# Test that mod1 (hot key prefix) is option.
start_test "mod1 is option"
_mod1=$(sed -n '/^mod1:/,/^[^ ]/{ /^  - /p; }' "$_amethyst" | sed 's/^  - //')
assert_equal "option" "$_mod1"

# Test that mod2 includes option and control (modifier bundle for
# space-throw bindings). Both must be present — losing one would silently
# make Meta+Shift+N a no-op.
start_test "mod2 includes option"
_mod2=$(sed -n '/^mod2:/,/^[^ ]/{ /^  - /p; }' "$_amethyst")
assert_contains "option" "$_mod2"
start_test "mod2 includes control"
assert_contains "control" "$_mod2"

# Required top-level scalars. If any of these go missing, Amethyst falls
# back to defaults that don't match the rest of the keybindings.
start_test "mouse-follows-focus is true"
assert_contains \
    "mouse-follows-focus: true" "$(cat "$_amethyst")"
start_test "follow-space-thrown-windows is true"
assert_contains \
    "follow-space-thrown-windows: true" "$(cat "$_amethyst")"
start_test "new-windows-to-main is false"
assert_contains \
    "new-windows-to-main: false" "$(cat "$_amethyst")"
start_test "window-margins is true"
assert_contains \
    "window-margins: true" "$(cat "$_amethyst")"
start_test "window-margin-size is 5"
assert_contains \
    "window-margin-size: 5" "$(cat "$_amethyst")"

# Layouts list should include the four we actually cycle through plus
# fullscreen (bound to the backtick key).
    start_test "layouts includes $_l"
_layouts=$(sed -n '/^layouts:/,/^[^ ]/{ /^  - /p; }' "$_amethyst")
for _l in tall 3column-left column wide fullscreen; do
    assert_contains "- $_l" "$_layouts"
done

# Per-binding block: each action should declare a mod and a key. Check
# a representative sample that maps one-to-one with Krohnkite bindings.
# The awk script extracts "action mod key" triples from the YAML.
_bindings=$(awk '
    /^[a-z][-a-z0-9]*:$/ {
        name = $1; sub(/:$/, "", name)
        mod = ""; key = ""
        next
    }
    /^  mod:/ { mod = $2 }
    /^  key:/ {
        key = $2; gsub(/"/, "", key)
        if (name != "" && mod != "" && key != "")
            print name, mod, key
        name = ""; mod = ""; key = ""
    }
' "$_amethyst")

# expand-main / shrink-main use mod1 with \ and /, matching Krohnkite.
start_test "expand-main bound to mod1 backslash"
assert_contains \
    "expand-main mod1 backslash" "$_bindings"
start_test "shrink-main bound to mod1 slash"
assert_contains \
    "shrink-main mod1 slash" "$_bindings"
start_test "select-fullscreen-layout bound to mod1 grave"
assert_contains \
    "select-fullscreen-layout mod1 grave" "$_bindings"
start_test "cycle-layout-backward bound to mod1 comma"
assert_contains \
    "cycle-layout-backward mod1 comma" "$_bindings"
start_test "cycle-layout bound to mod1 period"
assert_contains \
    "cycle-layout mod1 period" "$_bindings"
start_test "swap-main bound to mod1 return"
assert_contains \
    "swap-main mod1 return" "$_bindings"

# All nine throw-space-N bindings should exist and use mod2.
    start_test "throw-space-$_n bound to mod2 $_n"
for _n in 1 2 3 4 5 6 7 8 9; do
    assert_contains \
        "throw-space-$_n mod2 $_n" "$_bindings"
done

test_summary "amethyst_test"
