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

# --- Arrow keys: Ctrl+arrow word movement, Win+arrow Space switching ---
#
# Physical Ctrl sends Command after the rotation, and Cmd+arrow jumps to the
# start or end of the line. Word movement is Option+arrow on macOS, so the rule
# emits left_command -- the key the rotation turns into Option.
#
# That Option+arrow must not also be the Space-switching shortcut: symbolic
# hotkeys can't tell a synthesized Option+Left from a physical one, so Ctrl+Left
# would switch Spaces. setup-macos binds Spaces to Ctrl+Option+arrow instead,
# and physical Win+arrow (left_command to Karabiner) emits left_option +
# left_command, which the rotation turns into exactly Control+Option.

_arrow_file="$_srcdir/config/karabiner/assets/complex_modifications/pc-arrows.json"

start_test "the arrow rule exists"
assert_true test -f "$_arrow_file"

_arrow=$(cat "$_arrow_file")

if command -v python3 >/dev/null 2>&1; then
    start_test "the arrow rule is valid JSON"
    assert_true python3 -m json.tool "$_arrow_file" /dev/null
fi

start_test "the arrow rule has a title"
assert_contains '"title"' "$_arrow"
start_test "the arrow rule has manipulators"
assert_contains '"manipulators"' "$_arrow"

start_test "both arrows are mapped"
assert_contains '"key_code": "left_arrow"' "$_arrow"
assert_contains '"key_code": "right_arrow"' "$_arrow"

# Each manipulator as "from -> to" on one line, so the pairing is asserted
# rather than each half appearing somewhere in the file.
if command -v python3 >/dev/null 2>&1; then
    _pairs=$(python3 -c '
import json, sys
for rule in json.load(open(sys.argv[1]))["rules"]:
    for m in rule["manipulators"]:
        f, t = m["from"], m["to"][0]
        print(f["key_code"], "+".join(f["modifiers"]["mandatory"]), "->", "+".join(t["modifiers"]))
' "$_arrow_file")

    start_test "Ctrl+arrow emits Option+arrow (word movement) after the rotation"
    assert_contains "left_arrow left_control -> left_command" "$_pairs"
    assert_contains "right_arrow left_control -> left_command" "$_pairs"

    # Ctrl+Shift+arrow selects by word on Linux. A mandatory-modifier match
    # fails when shift is held too, so each arrow needs its own manipulator.
    start_test "Ctrl+Shift+arrow emits Option+Shift+arrow (select by word)"
    assert_contains "left_arrow left_control+shift -> left_command+shift" "$_pairs"
    assert_contains "right_arrow left_control+shift -> left_command+shift" "$_pairs"

    start_test "Win+arrow emits Control+Option+arrow, the Space shortcut"
    assert_contains "left_arrow left_command -> left_option+left_command" "$_pairs"
    assert_contains "right_arrow left_command -> left_option+left_command" "$_pairs"

    # The collision this layout exists to avoid: nothing but Ctrl may produce
    # bare Option+arrow, and Ctrl must not produce the Space chord.
    start_test "no manipulator besides Ctrl emits bare Option+arrow"
    assert_equal "2" "$(printf '%s\n' "$_pairs" | grep -c -- '-> left_command$')"
    start_test "Ctrl+arrow does not emit the Space chord"
    assert_not_contains "left_control -> left_option" "$_pairs"
fi

start_test "six manipulators: Ctrl and Ctrl+Shift and Win, per arrow"
assert_equal "6" "$(grep -c '"type": "basic"' "$_arrow_file")"

test_summary "karabiner_test"
