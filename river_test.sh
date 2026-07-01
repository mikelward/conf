#!/bin/bash
#
# Tests for the river Wayland desktop config under config/river,
# config/waybar, config/fuzzel, config/swaync, config/swayidle,
# config/swaylock and config/kanshi.
#
# Behavioural checks that map onto the spec: no gaps, distinct focus
# borders, KDE-parity keybinds, the three-clock ordering (SF, London,
# local -- local rightmost), screenshot/lock binds, themed launcher/lock,
# and graceful per-host structure.

. "$(dirname "$0")/shrc_test_lib.sh"

_river="$_srcdir/config/river"
_waybar="$_srcdir/config/waybar"
_fuzzel="$_srcdir/config/fuzzel"
_swaync="$_srcdir/config/swaync"
_swayidle="$_srcdir/config/swayidle"
_swaylock="$_srcdir/config/swaylock"
_kanshi="$_srcdir/config/kanshi"

_base=$(cat "$_river/base" 2>/dev/null)
_init=$(cat "$_river/init" 2>/dev/null)
_swayidle_cfg=$(cat "$_swayidle/config" 2>/dev/null)

### Files present ############################################################

for f in \
	"$_river/init" "$_river/base" \
	"$_river/hosts/examples/template.sh" \
	"$_river/hosts/examples/example-laptop.sh" \
	"$_river/hosts/examples/example-desktop.sh" \
	"$_river/README.md" \
	"$_waybar/config" "$_waybar/style.css" "$_waybar/scripts/battery.sh" \
	"$_fuzzel/fuzzel.ini" \
	"$_swaync/config.json" "$_swaync/style.css" \
	"$_swayidle/config" "$_swaylock/config" \
	"$_kanshi/config" "$_kanshi/hosts/examples/template.conf"; do
	start_test "exists: ${f#"$_srcdir"/}"
	assert_true test -f "$f"
done

# Examples must NOT sit directly in hosts/ where kanshi's "hosts/*.conf"
# glob (and the river hostname match) would pick them up.
start_test "no example kanshi profiles in the loaded hosts/ dir"
assert_true test -z "$(find "$_kanshi/hosts" -maxdepth 1 -name 'example-*.conf' 2>/dev/null)"
start_test "no example river host files loose in hosts/"
assert_true test -z "$(find "$_river/hosts" -maxdepth 1 -name 'example-*.sh' 2>/dev/null)"

### Executable bits (river execs init; waybar execs battery.sh) #############

start_test "init is executable"
assert_true test -x "$_river/init"
start_test "battery.sh is executable"
assert_true test -x "$_waybar/scripts/battery.sh"

### Shell syntax ############################################################

for f in "$_river/init" "$_river/base" \
	"$_river/hosts/examples/template.sh" \
	"$_river/hosts/examples/example-laptop.sh" \
	"$_river/hosts/examples/example-desktop.sh" \
	"$_waybar/scripts/battery.sh"; do
	start_test "sh -n: ${f#"$_srcdir"/}"
	assert_true sh -n "$f"
done

### Input / focus ###########################################################

start_test "focus follows cursor (normal)"
assert_contains "focus-follows-cursor normal" "$_base"

### No gaps #################################################################

start_test "rivertile: zero view padding (no inner gaps)"
assert_contains "view-padding 0" "$_base"
start_test "rivertile: zero outer padding (no outer gaps)"
assert_contains "outer-padding 0" "$_base"
start_test "rivertile is the default layout"
assert_contains "default-layout rivertile" "$_base"

### Borders: distinct focused vs unfocused #################################

start_test "focused border colour set"
assert_contains "border-color-focused" "$_base"
start_test "unfocused border colour set"
assert_contains "border-color-unfocused" "$_base"
# Focused (0xffb52a) must differ from unfocused (0x444444).
start_test "focused and unfocused border colours differ"
_focused=$(printf '%s\n' "$_base" | sed -n 's/.*border-color-focused "\(0x[0-9a-fA-F]*\)".*/\1/p' | head -1)
_unfocused=$(printf '%s\n' "$_base" | sed -n 's/.*border-color-unfocused "\(0x[0-9a-fA-F]*\)".*/\1/p' | head -1)
assert_true test "$_focused" != "$_unfocused"

### KDE-parity application keybinds #########################################

start_test "Super+T launches terminal"
assert_contains "map normal Super T spawn terminal" "$_base"
start_test "Super+G launches browser1"
assert_contains "map normal Super G spawn browser1" "$_base"
start_test "Super+H launches browser2"
assert_contains "map normal Super H spawn browser2" "$_base"
start_test "Super+W launches terminal_on_workstation"
assert_contains "map normal Super W spawn terminal_on_workstation" "$_base"
start_test "Super+Y launches music"
assert_contains "map normal Super Y spawn music" "$_base"
start_test "Super+Return zooms (set master)"
assert_contains "map normal Super Return zoom" "$_base"

### Launcher, theme toggle, lock, screenshots ##############################

start_test "Super+Space opens themed launcher"
assert_contains "map normal Super Space spawn" "$_base"
assert_contains "river-theme menu" "$_base"
start_test "launcher falls back to fuzzel without river-theme"
assert_contains "river-theme menu || fuzzel" "$_base"
start_test "Super+Shift+T toggles theme"
assert_contains 'map normal Super+Shift T spawn "river-theme toggle"' "$_base"
start_test "Super+Ctrl+L locks (themed)"
assert_contains "map normal Super+Control L spawn" "$_base"
assert_contains "river-theme lock" "$_base"
start_test "lock keybind falls back to swaylock without river-theme"
assert_contains "river-theme lock || swaylock -f" "$_base"
start_test "Print takes a full screenshot"
assert_contains "map normal None Print spawn" "$_base"
assert_contains "grim" "$_base"
start_test "Super+Shift+S screenshots a region to the clipboard"
assert_contains 'map normal Super+Shift S spawn' "$_base"
assert_contains "wl-copy" "$_base"

### Monocle / fullscreen ####################################################

start_test "Super+grave toggles fullscreen (monocle)"
assert_contains "map normal Super grave toggle-fullscreen" "$_base"

### Mouse move/resize #######################################################

start_test "Super+left-drag moves a window"
assert_contains "map-pointer normal Super BTN_LEFT move-view" "$_base"
start_test "Super+right-drag resizes a window"
assert_contains "map-pointer normal Super BTN_RIGHT resize-view" "$_base"

### Tags 1-9 ################################################################

start_test "tags: focus a tag"
assert_contains "set-focused-tags" "$_base"
start_test "tags: move window to a tag"
assert_contains "set-view-tags" "$_base"

### Themed lock via swayidle ################################################

# A swayidle CONFIG FILE parses one physical line per directive; a trailing
# backslash is NOT a continuation and breaks parsing (swayidle exits, no
# rules arm). Guard against reintroducing shell-style continuations.
start_test "swayidle config has no backslash line-continuations"
_swayidle_cont=$(grep -c '\\$' "$_swayidle/config" 2>/dev/null || true)
assert_equal "0" "$_swayidle_cont"

start_test "swayidle locks via river-theme"
assert_contains "river-theme lock" "$_swayidle_cfg"
start_test "swayidle lock falls back to swaylock without river-theme"
assert_contains "river-theme lock || swaylock -f" "$_swayidle_cfg"
start_test "swayidle blanks screens on idle (wlopm)"
assert_contains "wlopm" "$_swayidle_cfg"

### CSS imports the generated palette #######################################

start_test "waybar style imports theme.css"
assert_contains 'import url("theme.css")' "$(cat "$_waybar/style.css")"
start_test "swaync style imports theme.css"
assert_contains 'import url("theme.css")' "$(cat "$_swaync/style.css")"

### fuzzel: themed + lightly rounded #######################################

start_test "fuzzel uses the repo terminal wrapper"
assert_contains "terminal=terminal" "$(cat "$_fuzzel/fuzzel.ini")"
start_test "fuzzel has a corner radius (light rounding)"
assert_contains "radius=" "$(cat "$_fuzzel/fuzzel.ini")"

### kanshi: shared base + per-host include ##################################

start_test "kanshi includes per-host profiles"
assert_contains 'include "hosts/*.conf"' "$(cat "$_kanshi/config")"

### init: sources base then a per-host file, no hard failure ################

start_test "init sources the base config"
assert_contains 'config_dir/base' "$_init"
start_test "init selects a host file by hostname"
assert_contains 'hosts/$host.sh' "$_init"

### JSON validity + three-clock ordering (needs python3) ####################

if command -v python3 >/dev/null 2>&1; then
	start_test "waybar config is valid JSON"
	assert_true python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$_waybar/config"
	start_test "swaync config is valid JSON"
	assert_true python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$_swaync/config.json"

	# The core spec check: reading right-to-left the clocks must be local,
	# London, San Francisco -- i.e. in modules-right (rendered L->R) the
	# order is SF, then London, then local, with local rightmost. Also
	# assert the timezones and that the tray/network/volume applets exist.
	_checker=$(mktemp)
	cat >"$_checker" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
right = cfg["modules-right"]
errs = []

def idx(name):
    return right.index(name) if name in right else -1

for m in ("clock#sf", "clock#london", "clock#local", "tray", "network", "pulseaudio"):
    if idx(m) < 0:
        errs.append("missing module: " + m)

if not errs:
    sf, lon, loc = idx("clock#sf"), idx("clock#london"), idx("clock#local")
    if not (sf < lon < loc):
        errs.append("clock order must be SF < London < local (got %d,%d,%d)" % (sf, lon, loc))
    if idx("clock#local") != len(right) - 1:
        errs.append("local clock must be the rightmost module")

if cfg.get("clock#sf", {}).get("timezone") != "America/Los_Angeles":
    errs.append("SF clock timezone must be America/Los_Angeles")
if cfg.get("clock#london", {}).get("timezone") != "Europe/London":
    errs.append("London clock timezone must be Europe/London")
if "timezone" in cfg.get("clock#local", {}):
    errs.append("local clock must NOT set a timezone (uses machine local time)")

if errs:
    print("; ".join(errs))
    sys.exit(1)
sys.exit(0)
PY
	start_test "waybar clocks ordered SF, London, local (local rightmost)"
	assert_true python3 "$_checker" "$_waybar/config"
	rm -f "$_checker"
else
	start_test "python3 present for JSON checks"
	echo "  SKIP: python3 not installed" >&2
fi

test_summary "river_test"
