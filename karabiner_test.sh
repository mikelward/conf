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

# Physical Alt+Tab no longer switches applications: it's tide for macOS's swap with
# the master, in tide for macOS's rule below (tidemo SPEC.md §7.2). Two manipulators,
# Ctrl+Tab with and without shift, and none on physical Alt.
start_test "only Ctrl+Tab and Ctrl+Page Down and Up are mapped here, not Alt+Tab"
_manipulators=$(grep -c '"type": "basic"' "$_karabiner")
assert_equal "4" "$_manipulators"
assert_not_contains '"mandatory": ["left_option"' "$_rule"

# Ctrl+Page Down and Up are the next and previous tab on Linux. The
# rotation makes them Command+Page Down and Up, which a Mac browser
# ignores, so they're Ctrl+Tab and Ctrl+Shift+Tab, a Mac's next and
# previous tab, emitted as left_option for the rotation. Either Ctrl. Not
# in terminals, whose own rule sends them on as Control+Page Down and Up.
if command -v python3 >/dev/null 2>&1; then
    _tab_pairs=$(python3 -c '
import json, sys
for m in json.load(open(sys.argv[1]))["rules"][0]["manipulators"]:
    f, t = m["from"], m["to"][0]
    c = (m.get("conditions") or [{}])[0]
    print(f["key_code"], "+".join(f["modifiers"]["mandatory"]), "->", t["key_code"], "+".join(t["modifiers"]),
          c.get("type", "-"), " ".join(c.get("bundle_identifiers", [])))
' "$_karabiner")
    start_test "Ctrl+Page Down and Up are Ctrl+Tab and Ctrl+Shift+Tab, outside terminals"
    assert_contains "page_down control -> tab left_option frontmost_application_unless ^net" "$_tab_pairs"
    assert_contains "page_up control -> tab left_option+shift frontmost_application_unless ^net" "$_tab_pairs"
    assert_equal "2" "$(printf '%s\n' "$_tab_pairs" | grep '^page_' | grep -c 'kitty.*ghostty.*Terminal.*iterm2')"
    start_test "the rule's name still starts as setup-macos and tide for macOS find it"
    assert_equal "Ctrl+Tab goes to the next tab" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["rules"][0]["description"][:29])' "$_karabiner")"
fi

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
        print(f["key_code"], "+".join(f["modifiers"].get("mandatory", [])) or "-", "->", t["key_code"], "+".join(t["modifiers"]))
' "$_arrow_file")

    start_test "Ctrl+arrow emits Option+arrow (word movement) after the rotation"
    assert_contains "left_arrow left_control -> left_arrow left_command" "$_pairs"
    assert_contains "right_arrow left_control -> right_arrow left_command" "$_pairs"

    # Ctrl+Shift+arrow selects by word on Linux. A mandatory-modifier match
    # fails when shift is held too, so each arrow needs its own manipulator.
    start_test "Ctrl+Shift+arrow emits Option+Shift+arrow (select by word)"
    assert_contains "left_arrow left_control+shift -> left_arrow left_command+shift" "$_pairs"
    assert_contains "right_arrow left_control+shift -> right_arrow left_command+shift" "$_pairs"

    # Either Ctrl moves by word on Linux. Left to the rotation, right Ctrl is
    # Command too, and Cmd+arrow jumps to the line ends.
    start_test "right Ctrl+arrow moves and selects by word too"
    assert_contains "left_arrow right_control -> left_arrow left_command" "$_pairs"
    assert_contains "right_arrow right_control -> right_arrow left_command" "$_pairs"
    assert_contains "left_arrow right_control+shift -> left_arrow left_command+shift" "$_pairs"
    assert_contains "right_arrow right_control+shift -> right_arrow left_command+shift" "$_pairs"

    # Win+Shift+arrow moves the window a Space (Amethyst's throw-space-left/
    # right, on mod3 in amethyst.yml). Its own chord, Control+Option+Shift:
    # left to the rotation it would be Option+Shift+arrow, select-by-word.
    start_test "Win+Shift+arrow emits Control+Option+Shift+arrow, Amethyst's throw"
    assert_contains "left_arrow left_command+shift -> left_arrow left_option+left_command+shift" "$_pairs"
    assert_contains "right_arrow left_command+shift -> right_arrow left_option+left_command+shift" "$_pairs"

    # Alt+arrow moves by word too, as Option does on a Mac keyboard. Left to
    # the rotation it's Control+arrow, which jumps to the line ends.
    # Alt+Left/Right are Back and Forward in browsers and Finder, as on
    # Linux: Command+[ and ], which the rotation makes from left_control.
    # Only there, since editors take Command+[ to outdent; first, so they
    # come before the word movement below.
    _back=$(python3 -c '
import json, sys
ms = json.load(open(sys.argv[1]))["rules"][0]["manipulators"]
for i, m in enumerate(ms):
    f, t = m["from"], m["to"][0]
    if f["modifiers"].get("mandatory") == ["left_option"]:
        c = m.get("conditions") or [{}]
        print(i, f["key_code"], "->", t["key_code"], "+".join(t["modifiers"]), c[0].get("type", "-"), " ".join(c[0].get("bundle_identifiers", [])))
' "$_arrow_file")
    start_test "Alt+Left/Right are Back and Forward in browsers and Finder, before the word movement"
    assert_contains "left_arrow -> open_bracket left_control frontmost_application_if" "$_back"
    assert_contains "right_arrow -> close_bracket left_control frontmost_application_if" "$_back"
    assert_contains "^com\\.google\\.Chrome" "$_back"
    assert_contains "^com\\.apple\\.Safari$" "$_back"
    assert_contains "^com\\.apple\\.finder$" "$_back"
    assert_not_contains "kitty" "$_back"
    assert_equal "open_bracket" "$(printf '%s\n' "$_back" | grep ' left_arrow ' | head -1 | cut -d' ' -f4)"
    assert_equal "close_bracket" "$(printf '%s\n' "$_back" | grep ' right_arrow ' | head -1 | cut -d' ' -f4)"

    start_test "Alt+arrow emits Option+arrow, word movement, rather than Control+arrow"
    assert_contains "left_arrow left_option -> left_arrow left_command" "$_pairs"
    assert_contains "right_arrow left_option -> right_arrow left_command" "$_pairs"
    start_test "Alt+Shift+arrow emits Option+Shift+arrow (select by word)"
    assert_contains "left_arrow left_option+shift -> left_arrow left_command+shift" "$_pairs"
    assert_contains "right_arrow left_option+shift -> right_arrow left_command+shift" "$_pairs"

    start_test "Win+arrow emits Control+Option+arrow, the Space shortcut"
    assert_contains "left_arrow left_command -> left_arrow left_option+left_command" "$_pairs"
    assert_contains "right_arrow left_command -> right_arrow left_option+left_command" "$_pairs"

    # The collision this layout exists to avoid: Win's Space chord and the
    # word movement must stay apart, so only Ctrl and Alt produce bare
    # Option+arrow, and Ctrl doesn't produce the Space chord.
    start_test "only Ctrl and Alt emit bare Option+arrow"
    assert_equal "6" "$(printf '%s\n' "$_pairs" | grep -c -- '_arrow left_command$')"
    assert_equal "0" "$(printf '%s\n' "$_pairs" | grep -- '_arrow left_command$' | grep -vc -e ' left_control ' -e ' right_control ' -e ' left_option ')"
    start_test "Ctrl+arrow does not emit the Space chord"
    assert_not_contains "left_control -> left_arrow left_option" "$_pairs"
    assert_not_contains "left_control -> right_arrow left_option" "$_pairs"
    assert_not_contains "right_control -> left_arrow left_option" "$_pairs"
    assert_not_contains "right_control -> right_arrow left_option" "$_pairs"

    # Plain Home and End are tide for macOS's, which looks at what has
    # focus: Command+Left, the line's start, is Back in a browser when no
    # text field has it (tidemo SPEC.md §10). Ctrl+Home and End are never
    # that, so they stay here: the document's ends, Command+Up and Down,
    # emitted as left_control for the rotation. Shift passes through to
    # select.
    start_test "plain Home and End are left alone, for tide for macOS"
    assert_not_contains "home - ->" "$_pairs"
    assert_not_contains "end - ->" "$_pairs"
    start_test "Ctrl+Home/End go to the document's start and end, from either Ctrl"
    assert_contains "home left_control -> up_arrow left_control" "$_pairs"
    assert_contains "end left_control -> down_arrow left_control" "$_pairs"
    assert_contains "home right_control -> up_arrow left_control" "$_pairs"
    assert_contains "end right_control -> down_arrow left_control" "$_pairs"
    _home=$(python3 -c '
import json, sys
r = json.load(open(sys.argv[1]))["rules"][1]
print(r["description"][:50])
for m in r["manipulators"]:
    print(m["from"]["modifiers"].get("optional"), json.dumps(m["conditions"]))
' "$_arrow_file")
    start_test "the Ctrl+Home/End rule keeps Shift, and leaves the terminals alone"
    assert_contains "Ctrl+Home/End go to the document's start and end" "$_home"
    assert_equal "4" "$(printf '%s\n' "$_home" | grep -c "\['shift'\].*frontmost_application_unless.*kitty.*ghostty.*Terminal.*iterm2")"
    assert_equal "5" "$(printf '%s\n' "$_home" | wc -l | tr -d ' ')"
fi

start_test "eighteen arrow manipulators: left and right Ctrl, Alt and Win, with and without Shift, per arrow, and Alt's Back and Forward"
assert_equal "18" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["rules"][0]["manipulators"]))' "$_arrow_file")"

# tide for macOS's rule, for its Super key, is tide's own now
# (mikelward/tidemo hammerspoon/tide/karabiner/), installed by its
# installer; a copy here would list the same rule twice in Karabiner.
for _old in tide.json tilemo.json timo.json; do
    start_test "tide's rule isn't here: $_old"
    assert_false test -e "$_srcdir/config/karabiner/assets/complex_modifications/$_old"
done

# --- Terminals: Ctrl is Control and Alt is Meta in kitty and Ghostty ---
#
# The rotation makes physical Ctrl Command everywhere, so in a terminal Ctrl+U,
# Ctrl+K and Ctrl+R never reach the shell. In kitty this rule gives Ctrl back
# to Control by emitting left_option, which the rotation turns into Control,
# and Alt back to Meta by emitting left_command, which it turns into Option
# (kitty's macos_option_as_alt). Copy and paste on Ctrl+C and Ctrl+V are
# kitty's own maps, as on Linux. Ghostty gets the same, with the same keys in
# its own config.
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
    if m.get("conditions") != [{"type": "frontmost_application_if", "bundle_identifiers": ["^net\\.kovidgoyal\\.kitty$", "^com\\.mitchellh\\.ghostty$"]}]:
        print("BAD condition", m.get("conditions"))
    if f["modifiers"].get("optional") != ["shift"] or len(f["modifiers"]["mandatory"]) != 1:
        print("BAD from", f)
    if t["key_code"] != f["key_code"] or len(t["modifiers"]) != 1:
        print("BAD to", t)
    print(f["modifiers"]["mandatory"][0], f["key_code"], "->", t["modifiers"][0])
PY
)
    start_test "every manipulator is kitty's and Ghostty's, keeps Shift and the key, and swaps one modifier"
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

    # Ghostty, the rule's other terminal, has kitty's keys in its own config.
    _ghostty_conf="$_srcdir/config/ghostty/config"
    start_test "Ghostty copies on Ctrl+C, letting it through without a selection, and pastes on Ctrl+V"
    assert_true grep -Eq '^keybind = performable:ctrl\+c=copy_to_clipboard$' "$_ghostty_conf"
    assert_true grep -Eq '^keybind = ctrl\+v=paste_from_clipboard$' "$_ghostty_conf"
    start_test "Ghostty treats left Option as Alt"
    assert_true grep -Eq '^macos-option-as-alt = left$' "$_ghostty_conf"

    # Terminal and iTerm2 copy on Command+C, which the rotation puts on
    # physical Ctrl+C, so that stays copy there; the second rule puts the
    # interrupt, Control+C, on physical Ctrl+Shift+C, as Linux terminals
    # copy on Ctrl+Shift+C and interrupt on Ctrl+C.
    _interrupt=$(python3 - "$_terminal_file" <<'PY'
import json, sys
rules = json.load(open(sys.argv[1]))["rules"]
print(len(rules))
for m in rules[1]["manipulators"] if len(rules) > 1 else []:
    print(json.dumps([m["from"], m["to"], m["conditions"]], sort_keys=True))
PY
)
    start_test "Ctrl+Shift+C in Terminal and iTerm2 is Control+C, the interrupt"
    assert_equal "3
$(python3 -c 'import json; print(json.dumps([{"key_code": "c", "modifiers": {"mandatory": ["left_control", "shift"]}}, [{"key_code": "c", "modifiers": ["left_option"]}], [{"type": "frontmost_application_if", "bundle_identifiers": ["^com\\.apple\\.Terminal$", "^com\\.googlecode\\.iterm2$"]}]], sort_keys=True))')" "$_interrupt"
    start_test "the interrupt rule names Ctrl+Shift+C first, for setup-macos to find"
    assert_equal "Ctrl+Shift+C interrupts in Terminal and iTerm2" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["rules"][1]["description"][:46])' "$_terminal_file")"
    start_test "Ctrl+C itself is left to the rotation in Terminal and iTerm2, as copy"
    assert_not_contains "iterm2" "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["rules"][0]))' "$_terminal_file")"

    # Terminal and iTerm2 get kitty's keys too, where their own settings
    # allow: Ctrl as Control but for copy and paste, which stay theirs on
    # Command+C and V, and Alt as Meta, sent as Escape and the key, which
    # needs no Option-as-Meta setting.
    _term_pairs=$(python3 - "$_terminal_file" <<'PY'
import json, sys
for m in json.load(open(sys.argv[1]))["rules"][2]["manipulators"]:
    if m.get("conditions") != [{"type": "frontmost_application_if", "bundle_identifiers": ["^com\\.apple\\.Terminal$", "^com\\.googlecode\\.iterm2$"]}]:
        print("BAD condition", m.get("conditions"))
    f = m["from"]
    out = " ".join((t.get("modifiers") or ["-"])[0] + ":" + t["key_code"] for t in m["to"])
    print("+".join(f["modifiers"]["mandatory"]), f["key_code"], "->", out)
PY
)
    start_test "the Terminal and iTerm2 rule is theirs alone, named for the terminal rule's place"
    assert_not_contains "BAD" "$_term_pairs"
    assert_equal "Ctrl is Control and Alt is Meta in Terminal and iTerm2" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["rules"][2]["description"][:54])' "$_terminal_file")"
    start_test "Ctrl+U, Ctrl+K and Ctrl+W reach Terminal and iTerm2 as Control"
    assert_contains "left_control u -> left_option:u" "$_term_pairs"
    assert_contains "left_control k -> left_option:k" "$_term_pairs"
    assert_contains "left_control w -> left_option:w" "$_term_pairs"
    start_test "Ctrl+C and Ctrl+V stay copy and paste there; Ctrl+Shift+V is Control+V"
    assert_not_contains "left_control c ->" "$_term_pairs"
    assert_not_contains "left_control v ->" "$_term_pairs"
    assert_contains "left_control+shift v -> left_option:v" "$_term_pairs"
    start_test "Alt+B and Alt+. reach Terminal and iTerm2 as Meta, Escape then the key"
    assert_contains "left_option b -> -:escape -:b" "$_term_pairs"
    assert_contains "left_option period -> -:escape -:period" "$_term_pairs"
    # Karabiner repeats only a sequence's last event: a held Alt+B would
    # move a word, then type b. So the key doesn't repeat.
    start_test "a held Alt+key doesn't repeat the key alone"
    assert_equal "" "$(python3 -c '
import json, sys
for m in json.load(open(sys.argv[1]))["rules"][2]["manipulators"]:
    t = m["to"]
    if t[0].get("key_code") == "escape" and t[-1].get("repeat") is not False:
        print(m["from"]["key_code"])
' "$_terminal_file")"

    start_test "Ghostty interrupts on Ctrl+Shift+C and types the next key on Ctrl+Shift+V, as kitty does"
    assert_true grep -Fqx 'keybind = ctrl+shift+c=text:\x03' "$_ghostty_conf"
    assert_true grep -Fqx 'keybind = ctrl+shift+v=text:\x16' "$_ghostty_conf"

    start_test "Tab, Space and Ctrl+Up/Down are left to the rotation"
    assert_not_contains " tab " "$_terminal_pairs"
    assert_not_contains " spacebar " "$_terminal_pairs"
    assert_not_contains "left_control up_arrow" "$_terminal_pairs"
    assert_not_contains "left_control down_arrow" "$_terminal_pairs"
fi

# The lock screen's password field (loginwindow, frontmost there) clears on
# Ctrl+U, as tide's lock does. The rotation makes physical Ctrl+U Cmd+U,
# which does nothing there, so the rule emits Command+A and Backspace:
# left_control, which the rotation turns into Command, then a bare
# Backspace. A Mac keyboard's own Command+U does the same.
_lock_file="$_srcdir/config/karabiner/assets/complex_modifications/pc-lock.json"

start_test "the lock screen rule exists"
assert_true test -f "$_lock_file"

if command -v python3 >/dev/null 2>&1; then
    start_test "the lock screen rule is valid JSON"
    assert_true python3 -m json.tool "$_lock_file" /dev/null

    _lock=$(python3 - "$_lock_file" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("title", bool(d.get("title")))
for r in d["rules"]:
    print("description", r["description"][:45])
    for m in r["manipulators"]:
        f = m["from"]
        to = " ".join(t["key_code"] + ("+" + "+".join(t["modifiers"]) if t.get("modifiers") else "") for t in m["to"])
        print(f["key_code"], "+".join(f["modifiers"]["mandatory"]), "->", to, json.dumps(m.get("conditions")))
PY
)
    start_test "the lock screen rule has a title, and says what it does first"
    assert_contains "title True" "$_lock"
    assert_contains "description Ctrl+U clears the password at the lock" "$_lock"

    _at_lock='[{"type": "frontmost_application_if", "bundle_identifiers": ["^com\\.apple\\.loginwindow$"]}]'
    start_test "either Ctrl+U selects all and deletes, at the lock screen only"
    assert_contains "u left_control -> a+left_control delete_or_backspace $_at_lock" "$_lock"
    assert_contains "u right_control -> a+left_control delete_or_backspace $_at_lock" "$_lock"
    start_test "a Mac keyboard's Command+U does the same"
    assert_contains "u left_command -> a+left_control delete_or_backspace $_at_lock" "$_lock"
    assert_contains "u right_command -> a+left_control delete_or_backspace $_at_lock" "$_lock"
    start_test "nothing else: four manipulators, each at the lock screen"
    assert_equal "4" "$(printf '%s\n' "$_lock" | grep -c -- ' -> ')"
    assert_equal "4" "$(printf '%s\n' "$_lock" | grep -c -F -- "$_at_lock")"
fi

# Caps Lock held, or a MacBook's Fn, with the arrows: Home, End, Page Up and
# Page Down, the keys themselves, and with Ctrl, Ctrl+Home, End, Page Up and
# Page Down: the document's ends and the previous and next tab. A
# Caps Lock tap is still Caps Lock, which tide's hidutil mapping makes F18,
# Compose. Home and End go on to tide for macOS, which makes them the line's
# ends in a text field. Ctrl's outside terminals are the keys the rotation
# turns into Command+Up and Down (left_control); in terminals Control+Home
# and End, with left_option, which the rotation makes Control.
_nav_file="$_srcdir/config/karabiner/assets/complex_modifications/pc-nav.json"

start_test "the navigation rule exists"
assert_true test -f "$_nav_file"

if command -v python3 >/dev/null 2>&1; then
    start_test "the navigation rule is valid JSON"
    assert_true python3 -m json.tool "$_nav_file" /dev/null

    _nav=$(python3 - "$_nav_file" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("title", bool(d.get("title")))
for r in d["rules"]:
    print("description", r["description"][:40])
    for m in r["manipulators"]:
        f = m["from"]
        mods = f.get("modifiers", {})
        key = "+".join(mods.get("mandatory", []) + [f["key_code"]])
        if "to_if_alone" in m:
            print("hold", key, "sets", m["to"][0]["set_variable"]["name"],
                  "tap", m["to_if_alone"][0]["key_code"],
                  "release", m["to_after_key_up"][0]["set_variable"]["value"])
            continue
        conds = m.get("conditions", [])
        where = "layer" if any(c["type"] == "variable_if" for c in conds) else "plain"
        term = ("terminal" if any(c["type"] == "frontmost_application_if" for c in conds)
                else "app" if any(c["type"] == "frontmost_application_unless" for c in conds) else "all")
        to = " ".join("+".join(t.get("modifiers", []) + [t["key_code"]]) for t in m["to"])
        print(where, term, key, "shift" if "shift" in mods.get("optional", []) else "noshift", "->", to)
PY
)
    start_test "the navigation rule has a title, and says what it does first"
    assert_contains "title True" "$_nav"
    assert_contains "description Caps Lock or Fn with the arrows is Home" "$_nav"

    start_test "holding Caps Lock is the layer; a tap is still Caps Lock, Compose"
    assert_contains "hold caps_lock sets pc_nav_layer tap caps_lock release 0" "$_nav"
    # macOS ignores a Caps Lock tap with no time held, so plain Caps Lock,
    # without tide for macOS's F18, wouldn't toggle.
    start_test "the Caps Lock tap is held long enough for macOS to take it"
    assert_equal "200" "$(python3 -c 'import json,sys; print([m for m in json.load(open(sys.argv[1]))["rules"][0]["manipulators"] if m["from"]["key_code"] == "caps_lock"][0]["to_if_alone"][0].get("hold_down_milliseconds"))' "$_nav_file")"
    start_test "F18 too, should Karabiner see the mapped key"
    assert_contains "hold f18 sets pc_nav_layer tap f18 release 0" "$_nav"

    # The Caps Lock layer, then Fn: the same keys.
    for _via in "layer " "plain fn+"; do
        _w=${_via% *}
        _p=${_via#* }
        start_test "$_w ${_p}arrows are Home, End, Page Up and Page Down everywhere, selecting with shift"
        assert_contains "$_w all ${_p}left_arrow shift -> home" "$_nav"
        assert_contains "$_w all ${_p}right_arrow shift -> end" "$_nav"
        assert_contains "$_w all ${_p}up_arrow shift -> page_up" "$_nav"
        assert_contains "$_w all ${_p}down_arrow shift -> page_down" "$_nav"
        start_test "$_w ${_p}Up and Down with Ctrl: the previous and next tab, as Ctrl+Page Up and Down"
        assert_contains "$_w app ${_p}control+up_arrow noshift -> left_option+shift+tab" "$_nav"
        assert_contains "$_w app ${_p}control+down_arrow noshift -> left_option+tab" "$_nav"
        assert_contains "$_w terminal ${_p}control+up_arrow noshift -> left_option+page_up" "$_nav"
        assert_contains "$_w terminal ${_p}control+down_arrow noshift -> left_option+page_down" "$_nav"
        start_test "$_w ${_p}arrows with Ctrl: the document's start and end, as Ctrl+Home and End"
        assert_contains "$_w app ${_p}control+left_arrow shift -> left_control+up_arrow" "$_nav"
        assert_contains "$_w app ${_p}control+right_arrow shift -> left_control+down_arrow" "$_nav"
        assert_contains "$_w terminal ${_p}control+left_arrow shift -> left_option+home" "$_nav"
        assert_contains "$_w terminal ${_p}control+right_arrow shift -> left_option+end" "$_nav"
    done

    # Alt+Home is a PC browser's home page, not the document's start.
    start_test "nothing on Alt: Ctrl+Home and End are the document's ends"
    assert_not_contains " option+" "$_nav"
    assert_not_contains "+option+" "$_nav"

    start_test "nothing else: 24 key manipulators, 8 of them for terminals"
    assert_equal "24" "$(printf '%s\n' "$_nav" | grep -c -- ' -> ')"
    assert_equal "8" "$(printf '%s\n' "$_nav" | grep -c -- '^[a-z]* terminal ')"
fi

# Apps' own PC keys: Ctrl+Alt+key, Google Docs' way, as Command+Option+key;
# Ctrl+Backspace and Ctrl+Delete deleting a word; Ctrl+Y redo; Chrome's
# Ctrl+J and Ctrl+H; Finder's F2. Each output names the key the rotation
# turns into what macOS should see: left_control for Command, left_command
# for Option. Not in the terminals, which take Ctrl and Alt themselves.
_apps_file="$_srcdir/config/karabiner/assets/complex_modifications/pc-apps.json"

start_test "the apps rule exists"
assert_true test -f "$_apps_file"

if command -v python3 >/dev/null 2>&1; then
    start_test "the apps rule is valid JSON"
    assert_true python3 -m json.tool "$_apps_file" /dev/null

    # Each manipulator as "rule key mandatory optional -> to... where",
    # where is the condition types, then each one's bundle IDs or devices.
    _apps=$(python3 - "$_apps_file" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("title", d.get("title"))
for i, r in enumerate(d["rules"]):
    print("description", i, r["description"])
    for m in r["manipulators"]:
        f = m["from"]
        mods = f.get("modifiers", {})
        to = " ".join("+".join(t.get("modifiers", []) + [t["key_code"]]) for t in m["to"])
        where = " ".join(c["type"] + ":" + ",".join(c.get("bundle_identifiers", []) or [s["input_source_id"] for s in c.get("input_sources", [])]
                                                     or [json.dumps(x, sort_keys=True) for x in c.get("identifiers", [])])
                         for c in m.get("conditions", [])) or "everywhere"
        print(i, f["key_code"], "+".join(mods.get("mandatory", [])) or "-", "+".join(mods.get("optional", [])) or "-", "->", to, where)
PY
)
    _terms='^net\.kovidgoyal\.kitty$,^com\.mitchellh\.ghostty$,^com\.apple\.Terminal$,^com\.googlecode\.iterm2$'
    _not_terms="frontmost_application_unless:$_terms"

    start_test "the apps rule has a title, and each rule says what it does first"
    assert_contains "title PC keyboard apps" "$_apps"
    assert_contains "description 0 Ctrl+Alt+key is Command+Option+key outside terminals" "$_apps"
    assert_contains "description 1 Ctrl+Backspace and Ctrl+Delete delete a word, and Ctrl+Y redoes, outside terminals" "$_apps"
    assert_contains "description 2 Ctrl+J opens Downloads and Ctrl+H History in Chrome and Brave" "$_apps"
    assert_contains "description 3 F2 renames in Finder" "$_apps"

    start_test "the terminals the apps rule leaves alone are the Ctrl+Home rule's"
    assert_equal "$_terms" "$(python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))["rules"][1]["manipulators"][0]
print(",".join(m["conditions"][0]["bundle_identifiers"]))
' "$_arrow_file")"

    # Google Docs: Ctrl+Alt+M comments, Ctrl+Alt+1 to 6 are headings,
    # Ctrl+Alt+C and V copy and paste formatting; Sheets: Ctrl+Alt+= and -
    # insert and delete cells. On a Mac each is Command+Option. Shift
    # passes through, for Ctrl+Alt+Shift+H, version history.
    start_test "Ctrl+Alt+M, 1, 6, C, V, = and - are Command+Option with the key, outside terminals"
    for _k in m 1 6 c v equal_sign hyphen; do
        assert_contains "0 $_k left_control+left_option shift -> left_control+left_command+$_k $_not_terms" "$_apps"
    done
    start_test "every Ctrl+Alt manipulator keeps its key and Shift, and leaves the terminals alone"
    assert_equal "" "$(printf '%s\n' "$_apps" | NOT_TERMS="$_not_terms" python3 -c '
import os, sys
for line in sys.stdin:
    w = line.split()
    if w[0] == "0" and w[2:] != ["left_control+left_option", "shift", "->", "left_control+left_command+" + w[1], os.environ["NOT_TERMS"]]:
        print(line, end="")
')"
    start_test "Ctrl+Alt takes letters, digits and punctuation: 47 keys"
    assert_equal "47" "$(printf '%s\n' "$_apps" | grep -c '^0 ')"
    # Command+Option with these is something else on a Mac: switching
    # tabs, Force Quit, a Finder search, the Dock. Ctrl+Alt+F1 to F12 are
    # Linux's text consoles.
    start_test "Ctrl+Alt leaves the arrows, editing keys, Space, Escape and F keys to the rotation"
    for _k in left_arrow right_arrow up_arrow down_arrow tab spacebar return_or_enter delete_or_backspace delete_forward escape home end page_up page_down f1 f2; do
        assert_not_contains "0 $_k " "$_apps"
    done

    # The rotation makes Ctrl+Backspace Command+Backspace, which deletes to
    # the line's start; a word is Option+Backspace. Either Ctrl, as the
    # arrow rule's word moves take.
    start_test "either Ctrl+Backspace and Ctrl+Delete are Option with the key, deleting a word"
    for _c in left_control right_control; do
        assert_contains "1 delete_or_backspace $_c - -> left_command+delete_or_backspace $_not_terms" "$_apps"
        assert_contains "1 delete_forward $_c - -> left_command+delete_forward $_not_terms" "$_apps"
    done
    # Karabiner's key codes are physical keys, in QWERTY's places, and
    # macOS reads the letter through the input source. So a manipulator
    # that changes the letter has a copy for each layout it knows: QWERTY,
    # and Dvorak, whose Y, Z, J and H sit on QWERTY's T, /, C and J. Any
    # other layout, Dvorak - QWERTY Command among them, gets neither.
    _qwerty="input_source_if:^com\\.apple\\.keylayout\\.(US|ABC|USExtended|British|British-PC|Australian|Canadian)\$"
    _dvorak="input_source_if:^com\\.apple\\.keylayout\\.Dvorak\$"

    # Command+Y is History in Chrome; Command+Shift+Z is a Mac's redo.
    start_test "Ctrl+Y is Command+Shift+Z, redo, outside terminals, in QWERTY"
    assert_contains "1 y left_control - -> left_control+shift+z $_not_terms $_qwerty" "$_apps"
    start_test "Ctrl+Y is Command+Shift+Z in Dvorak too, from and to Dvorak's keys"
    assert_contains "1 t left_control - -> left_control+shift+slash $_not_terms $_dvorak" "$_apps"
    start_test "nothing else in the word and redo rule"
    assert_equal "6" "$(printf '%s\n' "$_apps" | grep -c '^1 ')"

    # Chrome and Brave, as the arrow rule names them, Chrome's apps
    # included. Ctrl+H is left to the rotation as Command+H, which hides
    # the app, so it's sent as Command+Y, History; tide for macOS makes
    # Command+Y find and replace in Google Docs, Sheets and Slides.
    _chrome="frontmost_application_if:^com\\.google\\.Chrome,^com\\.brave\\.Browser"
    start_test "Ctrl+J is Command+Shift+J, Downloads, and Ctrl+H Command+Y, History, in Chrome and Brave"
    assert_contains "2 j left_control - -> left_control+shift+j $_chrome $_qwerty" "$_apps"
    assert_contains "2 h left_control - -> left_control+y $_chrome $_qwerty" "$_apps"
    start_test "in Dvorak, from and to Dvorak's J, H and Y"
    assert_contains "2 c left_control - -> left_control+shift+c $_chrome $_dvorak" "$_apps"
    assert_contains "2 j left_control - -> left_control+t $_chrome $_dvorak" "$_apps"
    assert_equal "4" "$(printf '%s\n' "$_apps" | grep -c '^2 ')"

    # A manipulator that takes or sends a letter means it for one layout,
    # but for the Ctrl+Alt rule's, which take every letter alike: it names
    # the input source, and each QWERTY one has its
    # Dvorak twin, its keys moved to where Dvorak puts the same letters
    # (the US Dvorak layout, as Apple's and xkb's us(dvorak) have it).
    _layouts=$(python3 - "$_apps_file" <<'PY2'
import json, sys
QWERTY = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "open_bracket", "close_bracket",
          "a", "s", "d", "f", "g", "h", "j", "k", "l", "semicolon", "quote",
          "z", "x", "c", "v", "b", "n", "m", "comma", "period", "slash"]
DVORAK = "',.pyfgcrl/=" "aoeuidhtns-" ";qjkxbmwvz"
# Where Dvorak types each letter, as a physical key.
AT = {ch: QWERTY[i] for i, ch in enumerate(DVORAK) if ch.isalpha()}
LETTERS = set("abcdefghijklmnopqrstuvwxyz")
def src(m):
    return [s["input_source_id"] for c in m.get("conditions", []) if c["type"] == "input_source_if" for s in c["input_sources"]]
def rest(m):
    return [c for c in m.get("conditions", []) if c["type"] != "input_source_if"]
rules = json.load(open(sys.argv[1]))["rules"]
ms = [m for r in rules for m in r["manipulators"]]
alike = rules[0]["manipulators"]
dvorak = [m for m in ms if src(m) == ["^com\\.apple\\.keylayout\\.Dvorak$"]]
for m in ms:
    f, t = m["from"]["key_code"], m["to"][0]["key_code"]
    if (f in LETTERS or t in LETTERS) and not src(m) and m not in alike:
        print("no layout", f, t)
    if src(m) and src(m)[0].startswith("^com\\.apple\\.keylayout\\.(US|"):
        twin = json.loads(json.dumps(m))
        twin["from"]["key_code"] = AT[f]
        twin["to"][0]["key_code"] = AT[t]
        if not any(d["from"] == twin["from"] and d["to"] == twin["to"] and rest(d) == rest(m) for d in dvorak):
            print("no Dvorak twin", f, t)
print(len(dvorak), "Dvorak")
PY2
)
    start_test "every manipulator that takes or sends a letter names its layout, but for Ctrl+Alt's"
    assert_not_contains "no layout" "$_layouts"
    start_test "each QWERTY one has a Dvorak twin, and there are three"
    assert_not_contains "no Dvorak twin" "$_layouts"
    assert_contains "3 Dvorak" "$_layouts"
    start_test "a Dvorak Y is QWERTY's T, Z its /, J its C and H its J"
    assert_equal "t slash c j" "$(python3 -c '
q = "qwertyuiop[]asdfghjkl;'"'"'zxcvbnm,./"
d = "'"'"',.pyfgcrl/=aoeuidhtns-;qjkxbmwvz"
print(" ".join({"/": "slash"}.get(q[d.index(c)], q[d.index(c)]) for c in "yzjh"))
')"
    start_test "Chrome and Brave are the arrow rule's bundle IDs"
    assert_contains "\"^com\\\\.google\\\\.Chrome\"" "$_arrow"
    assert_contains "\"^com\\\\.brave\\\\.Browser\"" "$_arrow"

    # Finder renames on Return. Not a Mac keyboard's F2, which is
    # brightness. Delete stays as it is: as Command+Backspace it would
    # move the file being renamed to the Trash.
    _mac_kbd='{"is_built_in_keyboard": true},{"vendor_id": 1452},{"vendor_id": 76}'
    start_test "F2 is Return in Finder, from a PC keyboard"
    assert_contains "3 f2 - - -> return_or_enter frontmost_application_if:^com\\.apple\\.finder\$ device_unless:$_mac_kbd" "$_apps"
    assert_equal "1" "$(printf '%s\n' "$_apps" | grep -c '^3 ')"
    start_test "Delete is left alone in Finder"
    assert_not_contains " delete_forward - " "$_apps"
    assert_not_contains "finder" "$(printf '%s\n' "$_apps" | grep ' delete_')"

    # Plain Home and End are tide for macOS's, which looks at what has
    # focus; Ctrl+Space stays Spotlight.
    start_test "plain Home and End and Ctrl+Space are left alone"
    assert_not_contains " home - " "$_apps"
    assert_not_contains " end - " "$_apps"
    assert_not_contains " spacebar " "$_apps"

    # Across conf's rule files: no two manipulators take the same key with
    # the same modifiers where the same conditions hold, and none of the
    # apps rule's keys is another file's outside the terminals, where
    # Karabiner would use whichever rule sits higher.
    _clash=$(python3 - "$_srcdir/config/karabiner/assets/complex_modifications" <<'PY'
import glob, json, os, sys
TERMS = {"^net\\.kovidgoyal\\.kitty$", "^com\\.mitchellh\\.ghostty$", "^com\\.apple\\.Terminal$", "^com\\.googlecode\\.iterm2$"}
seen, apps, others = {}, [], []
for path in sorted(glob.glob(os.path.join(sys.argv[1], "*.json"))):
    name = os.path.basename(path)
    for r in json.load(open(path))["rules"]:
        for m in r["manipulators"]:
            f = m["from"]
            mods = f.get("modifiers", {})
            key = (f.get("key_code"), tuple(sorted(mods.get("mandatory", []))), tuple(sorted(mods.get("optional", []))),
                   json.dumps(m.get("conditions", []), sort_keys=True))
            if key in seen:
                print("same", name, seen[key], key)
            seen[key] = name
            (apps if name == "pc-apps.json" else others).append((name, f.get("key_code"), set(mods.get("mandatory", [])), m.get("conditions", [])))
def side(mods):
    # "control" in a rule is either Ctrl.
    return {x for m in mods for x in (("left_control", "right_control") if m == "control" else (m,))}
def terminals_only(conds):
    return any(c["type"] == "frontmost_application_if" and set(c["bundle_identifiers"]) <= TERMS for c in conds)
for _, k, mods, _ in apps:
    for name, k2, mods2, conds2 in others:
        if k == k2 and side(mods) & side(mods2) and side(mods) - {"left_control", "right_control"} == side(mods2) - {"left_control", "right_control"} and not terminals_only(conds2):
            print("clash", k, sorted(mods), name)
PY
)
    start_test "no two manipulators in conf's rule files take the same key, modifiers and conditions"
    assert_not_contains "same" "$_clash"
    start_test "the apps rule's keys are no other rule's outside the terminals"
    assert_not_contains "clash" "$_clash"
fi

test_summary "karabiner_test"
