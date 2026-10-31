#!/bin/sh
#
# Tests for the Karabiner-Elements complex modifications.
#
# Each rule's whole job is to survive the hidutil rotation setup-macos applies,
# and the direction it has to point is counterintuitive: it names the key the
# rotation turns into what macOS should see. The Ctrl+Tab rule emits
# left_option because that's the key the rotation turns into Control; a
# well-meaning "fix" to left_control would silently produce Cmd+Tab instead.

. "$(dirname "$0")/shrc_test_lib.sh"

_karabiner="$_srcdir/config/karabiner/assets/complex_modifications/pc-alt-tab.json"

# Sanity: the rule is present. Without this guard every assert below trivially
# matches an empty string, hiding a moved or renamed rule.
start_test "the Ctrl+Tab rule exists"
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

# The binding being remapped: physical Ctrl+Tab, which the rotation would make
# Cmd+Tab, the application switcher.
start_test "the rule triggers on tab"
assert_contains '"key_code": "tab"' "$_rule"
start_test "the rule triggers on left_control, the physical Ctrl key"
assert_contains '"mandatory": ["left_control"]' "$_rule"

# Karabiner's canonical name is left_option; left_alt is at best an alias, and
# an unrecognized modifier name is not reported as an error -- it just never
# matches, which looks exactly like the rule not being enabled.
start_test "the rule does not use the left_alt spelling"
assert_not_contains '"left_alt"' "$_rule"

# The output side. left_option is what the hidutil rotation turns into
# Control, so physical Ctrl+Tab is Ctrl+Tab, the next tab, as on Linux.
start_test "the rule emits left_option, which the rotation makes Control"
assert_contains '"modifiers": ["left_option"]' "$_rule"
start_test "the rule does not emit left_command, which would become Option"
assert_not_contains '"left_command"' "$_rule"

# Shift+Ctrl+Tab goes to the previous tab. Without its own manipulator the
# mandatory-modifier match fails.
start_test "shift is handled for the previous tab"
assert_contains '"mandatory": ["left_control", "shift"]' "$_rule"

# Physical Alt+Tab no longer switches applications: it's tilemo's swap with
# the master, in tilemo's rule below (tilemo SPEC.md §7.2). Two manipulators,
# Ctrl+Tab with and without shift, and none on physical Alt.
start_test "only Ctrl+Tab is mapped here, not Alt+Tab"
_manipulators=$(grep -c '"type": "basic"' "$_karabiner")
assert_equal "2" "$_manipulators"
assert_not_contains '"mandatory": ["left_option"' "$_rule"

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

    # Win+Shift+arrow moves the window a Space (Amethyst's throw-space-left/
    # right, on mod3 in amethyst.yml). Its own chord, Control+Option+Shift:
    # left to the rotation it would be Option+Shift+arrow, select-by-word.
    start_test "Win+Shift+arrow emits Control+Option+Shift+arrow, Amethyst's throw"
    assert_contains "left_arrow left_command+shift -> left_option+left_command+shift" "$_pairs"
    assert_contains "right_arrow left_command+shift -> left_option+left_command+shift" "$_pairs"

    # Alt+arrow moves by word too, as Option does on a Mac keyboard. Left to
    # the rotation it's Control+arrow, which jumps to the line ends.
    start_test "Alt+arrow emits Option+arrow, word movement, rather than Control+arrow"
    assert_contains "left_arrow left_option -> left_command" "$_pairs"
    assert_contains "right_arrow left_option -> left_command" "$_pairs"
    start_test "Alt+Shift+arrow emits Option+Shift+arrow (select by word)"
    assert_contains "left_arrow left_option+shift -> left_command+shift" "$_pairs"
    assert_contains "right_arrow left_option+shift -> left_command+shift" "$_pairs"

    start_test "Win+arrow emits Control+Option+arrow, the Space shortcut"
    assert_contains "left_arrow left_command -> left_option+left_command" "$_pairs"
    assert_contains "right_arrow left_command -> left_option+left_command" "$_pairs"

    # The collision this layout exists to avoid: Win's Space chord and the
    # word movement must stay apart, so only Ctrl and Alt produce bare
    # Option+arrow, and Ctrl doesn't produce the Space chord.
    start_test "only Ctrl and Alt emit bare Option+arrow"
    assert_equal "4" "$(printf '%s\n' "$_pairs" | grep -c -- '-> left_command$')"
    assert_equal "0" "$(printf '%s\n' "$_pairs" | grep -- '-> left_command$' | grep -vc -e ' left_control ' -e ' left_option ')"
    start_test "Ctrl+arrow does not emit the Space chord"
    assert_not_contains "left_control -> left_option" "$_pairs"
fi

start_test "twelve manipulators: Ctrl, Alt and Win, with and without Shift, per arrow"
assert_equal "12" "$(grep -c '"type": "basic"' "$_arrow_file")"

# tilemo's rule (mikelward/tilemo SPEC.md §7.1): physical Win+key becomes
# Ctrl+Option+Command+key, which tilemo registers, so Option keeps its own
# meanings. Through the rotation that means emitting left_option (Control),
# left_command (Option) and left_control (Command).
_tilemo_file="$_srcdir/config/karabiner/assets/complex_modifications/tilemo.json"

start_test "tilemo's rule exists"
assert_true test -f "$_tilemo_file"

# The rule was timo.json before the repo was renamed; a copy left behind
# would list the same rule twice in Karabiner's Add rule dialog.
start_test "the old timo.json rule is gone"
assert_false test -e "$_srcdir/config/karabiner/assets/complex_modifications/timo.json"

_tilemo=$(cat "$_tilemo_file")

if command -v python3 >/dev/null 2>&1; then
    start_test "tilemo's rule is valid JSON"
    assert_true python3 -m json.tool "$_tilemo_file" /dev/null

    # tilemo finds its rule in karabiner.json by a description starting
    # "tilemo:" (tilemo keys.karabiner_ready, which still accepts the old
    # "timo:" during the rename); renaming it turns tilemo's keys back to
    # plain Option.
    start_test "tilemo's rule description starts with tilemo:, which tilemo looks for"
    assert_equal "tilemo:" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["rules"][0]["description"][:7])' "$_tilemo_file")"

    _tilemo_bad=$(python3 - "$_tilemo_file" <<'PY'
import json, sys
hyper = {"left_option", "left_command", "left_control"}
for m in json.load(open(sys.argv[1]))["rules"][0]["manipulators"]:
    f = m["from"]
    if f.get("key_code") == "left_command":
        continue
    # Physical Alt+Tab, tilemo's swap with the master: checked below.
    if f.get("key_code") == "tab" and f["modifiers"]["mandatory"] == ["left_option"]:
        continue
    if f["modifiers"]["mandatory"] != ["left_command"] or f["modifiers"].get("optional") != ["shift"]:
        print("from", f)
    for t in m["to"]:
        if set(t["modifiers"]) != hyper:
            print("to", t)
PY
)
    start_test "every Win combination emits Ctrl+Option+Command, keeping Shift"
    assert_equal "" "$_tilemo_bad"
fi

start_test "tilemo's rule matches the physical Win key, left_command"
assert_contains '"mandatory": [' "$_tilemo"
assert_contains '"left_command"' "$_tilemo"

start_test "a lone Win tap sends Super+F20, tilemo's workspace list, not Super+Space"
assert_contains '"to_if_alone"' "$_tilemo"
assert_contains '"key_code": "f20"' "$_tilemo"

if command -v python3 >/dev/null 2>&1; then
    # Physical Alt+Tab is tilemo's swap with the master (tilemo SPEC.md
    # §7.2): left_option (physical Alt) + Tab emits left_option +
    # left_command + shift, which the rotation turns into
    # Control+Option+Shift+Tab, a combination nothing else uses. Without
    # Command, so no Win combination can make it.
    _alt_tab=$(python3 - "$_tilemo_file" <<'PY'
import json, sys
for m in json.load(open(sys.argv[1]))["rules"][0]["manipulators"]:
    f = m["from"]
    if f.get("key_code") == "tab" and f["modifiers"]["mandatory"] == ["left_option"]:
        t = m["to"][0]
        print(t["key_code"], "+".join(sorted(t["modifiers"])))
PY
)
    start_test "physical Alt+Tab emits Control+Option+Shift+Tab for tilemo"
    assert_equal "tab left_command+left_option+shift" "$_alt_tab"
fi

start_test "Win+click and Win+drag carry the same modifiers, for tilemo's mouse"
assert_contains '"pointing_button": "button1"' "$_tilemo"
assert_contains '"pointing_button": "button2"' "$_tilemo"
assert_contains '"pointing_button": "button3"' "$_tilemo"

start_test "tilemo's rule doesn't use the left_alt spelling"
assert_not_contains '"left_alt"' "$_tilemo"

# --- Terminals: Ctrl is Control and Alt is Meta in kitty ---
#
# The rotation makes physical Ctrl Command everywhere, so in a terminal Ctrl+U,
# Ctrl+K and Ctrl+R never reach the shell. In kitty this rule gives Ctrl back
# to Control by emitting left_option, which the rotation turns into Control,
# and Alt back to Meta by emitting left_command, which it turns into Option
# (kitty's macos_option_as_alt). Copy and paste on Ctrl+C and Ctrl+V are
# kitty's own maps, as on Linux.
_terminal_file="$_srcdir/config/karabiner/assets/complex_modifications/pc-terminal.json"

start_test "the terminal rule exists"
assert_true test -f "$_terminal_file"

_terminal=$(cat "$_terminal_file")

start_test "the terminal rule has a title"
assert_contains '"title"' "$_terminal"

start_test "the terminal rule doesn't use the left_alt spelling"
assert_not_contains '"left_alt"' "$_terminal"

if command -v python3 >/dev/null 2>&1; then
    start_test "the terminal rule is valid JSON"
    assert_true python3 -m json.tool "$_terminal_file" /dev/null

    # Each manipulator as "physical-modifier key -> emitted-modifier key",
    # with anything off-pattern (another app, Shift not passed through, a
    # different key out) reported instead.
    _terminal_pairs=$(python3 - "$_terminal_file" <<'PY'
import json, sys
for m in json.load(open(sys.argv[1]))["rules"][0]["manipulators"]:
    f, (t,) = m["from"], m["to"]
    if m.get("conditions") != [{"type": "frontmost_application_if", "bundle_identifiers": ["^net\\.kovidgoyal\\.kitty$"]}]:
        print("BAD condition", m.get("conditions"))
    if f["modifiers"].get("optional") != ["shift"] or len(f["modifiers"]["mandatory"]) != 1:
        print("BAD from", f)
    if t["key_code"] != f["key_code"] or len(t["modifiers"]) != 1:
        print("BAD to", t)
    print(f["modifiers"]["mandatory"][0], f["key_code"], "->", t["modifiers"][0])
PY
)
    start_test "every manipulator is kitty's, keeps Shift and the key, and swaps one modifier"
    assert_not_contains "BAD" "$_terminal_pairs"

    start_test "Ctrl+U, Ctrl+K and Ctrl+F reach kitty as Control"
    assert_contains "left_control u -> left_option" "$_terminal_pairs"
    assert_contains "left_control k -> left_option" "$_terminal_pairs"
    assert_contains "left_control f -> left_option" "$_terminal_pairs"

    start_test "Ctrl+C and Ctrl+V reach kitty as Control too, for its copy and paste maps"
    assert_contains "left_control c -> left_option" "$_terminal_pairs"
    assert_contains "left_control v -> left_option" "$_terminal_pairs"

    start_test "Alt+B and Alt+. reach kitty as Option, its Meta"
    assert_contains "left_option b -> left_command" "$_terminal_pairs"
    assert_contains "left_option period -> left_command" "$_terminal_pairs"

    start_test "every Ctrl manipulator emits Control, and every Alt one Option"
    assert_equal "" "$(printf '%s\n' "$_terminal_pairs" | grep -v -e '^left_control .* -> left_option$' -e '^left_option .* -> left_command$')"

    # Tab is the Alt+Tab rule's; Space under Control is macOS's input source
    # switch; Control+Up and Down are Mission Control, which setup-macos
    # leaves on.
    # The rule only makes Ctrl and Alt arrive as Control and Option; kitty's
    # config does the rest.
    _kitty_conf="$_srcdir/config/kitty/kitty.conf"
    start_test "kitty copies on Ctrl+C, interrupting without a selection, and pastes on Ctrl+V"
    assert_true grep -Eq '^map ctrl\+c +copy_or_interrupt$' "$_kitty_conf"
    assert_true grep -Eq '^map ctrl\+v +paste_from_clipboard$' "$_kitty_conf"
    start_test "kitty treats left Option as Alt"
    assert_true grep -Eq '^macos_option_as_alt +left$' "$_kitty_conf"

    start_test "Tab, Space and Ctrl+Up/Down are left to the rotation"
    assert_not_contains " tab " "$_terminal_pairs"
    assert_not_contains " spacebar " "$_terminal_pairs"
    assert_not_contains "left_control up_arrow" "$_terminal_pairs"
    assert_not_contains "left_control down_arrow" "$_terminal_pairs"
fi

test_summary "karabiner_test"
