#!/bin/sh
#
# Tests for the Karabiner-Elements complex modification.
#
# The rule's whole job is to survive the hidutil rotation setup-macos applies,
# and the direction it has to point is counterintuitive: it emits left_control
# because that's the key the rotation turns into Command. A well-meaning "fix"
# to left_command would silently produce Option+Tab instead, so the mapping is
# asserted in both directions here.

. "$(dirname "$0")/shrc_test_lib.sh"

_karabiner="$_srcdir/config/karabiner/assets/complex_modifications/pc-alt-tab.json"

# Sanity: the rule is present. Without this guard every assert below trivially
# matches an empty string, hiding a moved or renamed rule.
start_test "the Alt+Tab rule exists"
assert_true test -f "$_karabiner"

_rule=$(cat "$_karabiner")

# Karabiner silently ignores an asset it can't parse, so a malformed rule looks
# exactly like one that was never installed. Only checked where python3 is
# available; the structural asserts below still run either way.
if command -v python3 >/dev/null 2>&1; then
    start_test "the rule is valid JSON"
    # Second positional is json.tool's output file; without it the reformatted
    # rule is dumped into the test output.
    assert_true python3 -m json.tool "$_karabiner" /dev/null
fi

# Karabiner only lists an asset with a title, and only applies rules under a
# "rules" key.
start_test "the rule has a title"
assert_contains '"title"' "$_rule"
start_test "the rule has a rules array"
assert_contains '"rules"' "$_rule"
start_test "the rule has manipulators"
assert_contains '"manipulators"' "$_rule"

# The binding being remapped.
start_test "the rule triggers on tab"
assert_contains '"key_code": "tab"' "$_rule"
start_test "the rule triggers on left_option"
assert_contains '"left_option"' "$_rule"

# Karabiner's canonical name is left_option; left_alt is at best an alias, and
# an unrecognized modifier name is not reported as an error -- it just never
# matches, which looks exactly like the rule not being enabled.
start_test "the rule does not use the left_alt spelling"
assert_not_contains '"left_alt"' "$_rule"

# The output side. left_control is what the hidutil rotation turns into
# Command; naming left_command here would come out as Option instead.
start_test "the rule emits left_control, which the rotation makes Command"
assert_contains '"left_control"' "$_rule"
start_test "the rule does not emit left_command, which would become Option"
assert_not_contains '"left_command"' "$_rule"

# Shift+Alt+Tab cycles the application switcher backwards. Without its own
# manipulator the mandatory-modifier match fails and reverse cycling does
# nothing at all.
start_test "shift is handled for reverse cycling"
assert_contains '"shift"' "$_rule"

# The swap has to run both ways. Mapping only Alt+Tab would move application
# switching onto the physical Alt key while the rotation left it on the
# physical Ctrl key too -- and next-tab would then have no physical keys at
# all. Four manipulators: each direction, with and without shift.
start_test "the swap is mapped in both directions"
_manipulators=$(grep -c '"type": "basic"' "$_karabiner")
assert_equal "4" "$_manipulators"

start_test "left_control is a trigger, not only an output"
assert_contains '"mandatory": ["left_control"]' "$_rule"

start_test "left_option is an output, not only a trigger"
assert_contains '"modifiers": ["left_option"]' "$_rule"

# Right Alt is deliberately left alone; mapping it would take away a plain
# modifier for no benefit. Both spellings, since either would mean it was
# mapped after all.
start_test "right_option is left alone"
assert_not_contains '"right_option"' "$_rule"
start_test "right_alt is left alone"
assert_not_contains '"right_alt"' "$_rule"

test_summary "karabiner_test"
