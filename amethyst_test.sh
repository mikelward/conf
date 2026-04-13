#!/bin/sh
#
# Tests for amethyst.yml.
#

. "$(dirname "$0")/shrc_test_lib.sh"

_amethyst="$_srcdir/amethyst.yml"

# Sanity: the config file is present. Without this guard the rest of the
# asserts all trivially match empty strings, hiding a moved/renamed config.
assert_true "amethyst.yml exists" test -f "$_amethyst"

# Test that mod1 (hot key prefix) is option.
_mod1=$(sed -n '/^mod1:/,/^[^ ]/{ /^  - /p; }' "$_amethyst" | sed 's/^  - //')
assert_equal "mod1 is option" "option" "$_mod1"

# Test that mod2 includes option and control (modifier bundle for
# space-throw bindings). Both must be present — losing one would silently
# make Meta+Shift+N a no-op.
_mod2=$(sed -n '/^mod2:/,/^[^ ]/{ /^  - /p; }' "$_amethyst")
assert_contains "mod2 includes option" "option" "$_mod2"
assert_contains "mod2 includes control" "control" "$_mod2"

# Required top-level scalars. If any of these go missing, Amethyst falls
# back to defaults that don't match the rest of the keybindings.
assert_contains "mouse-follows-focus is true" \
    "mouse-follows-focus: true" "$(cat "$_amethyst")"
assert_contains "follow-space-thrown-windows is true" \
    "follow-space-thrown-windows: true" "$(cat "$_amethyst")"
assert_contains "new-windows-to-main is false" \
    "new-windows-to-main: false" "$(cat "$_amethyst")"
assert_contains "window-margins is true" \
    "window-margins: true" "$(cat "$_amethyst")"
assert_contains "window-margin-size is 5" \
    "window-margin-size: 5" "$(cat "$_amethyst")"

# Layouts list should include the four we actually cycle through plus
# fullscreen (bound to the backtick key).
_layouts=$(sed -n '/^layouts:/,/^[^ ]/{ /^  - /p; }' "$_amethyst")
for _l in tall 3column-left column wide fullscreen; do
    assert_contains "layouts includes $_l" "- $_l" "$_layouts"
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
assert_contains "expand-main bound to mod1 backslash" \
    "expand-main mod1 backslash" "$_bindings"
assert_contains "shrink-main bound to mod1 slash" \
    "shrink-main mod1 slash" "$_bindings"
assert_contains "select-fullscreen-layout bound to mod1 grave" \
    "select-fullscreen-layout mod1 grave" "$_bindings"
assert_contains "cycle-layout-backward bound to mod1 comma" \
    "cycle-layout-backward mod1 comma" "$_bindings"
assert_contains "cycle-layout bound to mod1 period" \
    "cycle-layout mod1 period" "$_bindings"
assert_contains "swap-main bound to mod1 return" \
    "swap-main mod1 return" "$_bindings"

# All nine throw-space-N bindings should exist and use mod2.
for _n in 1 2 3 4 5 6 7 8 9; do
    assert_contains "throw-space-$_n bound to mod2 $_n" \
        "throw-space-$_n mod2 $_n" "$_bindings"
done

test_summary "amethyst_test"
