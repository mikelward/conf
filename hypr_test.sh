#!/bin/sh
#
# Tests for the Hyprland Wayland desktop configs under config/hypr,
# config/waybar, config/fuzzel, and config/swaync.
#
# hyprland.lua itself is tested by config/hypr/hyprland_test.lua against a
# stub of Hyprland's Lua API; this runs it. The rest are presence/parse checks
# and script behavior tests with a fake hyprctl: we can't launch a compositor
# in CI.

. "$(dirname "$0")/shrc_test_lib.sh"

_hypr="$_srcdir/config/hypr/hyprland.lua"
_hypr_test="$_srcdir/config/hypr/hyprland_test.lua"
_hypr_tmpl="$_srcdir/config/hypr/hyprland.local.lua.template"
_idle="$_srcdir/config/hypr/hypridle.conf"
_lock="$_srcdir/config/hypr/hyprlock.conf"
_theme="$_srcdir/config/hypr/scripts/theme.sh"
_themed="$_srcdir/config/hypr/scripts/theme-daemon.sh"
_fuzzellaunch="$_srcdir/config/hypr/scripts/launch-fuzzel.sh"
_powermenu="$_srcdir/config/waybar/scripts/power-menu.sh"
_apply="$_srcdir/config/hypr/scripts/apply-input.sh"
_nextlayout="$_srcdir/config/hypr/scripts/next-layout.sh"
_waybar_cfg="$_srcdir/config/waybar/config.jsonc"
_waybar_css="$_srcdir/config/waybar/style.css"
_fuzzel="$_srcdir/config/fuzzel/fuzzel.ini"
_swaync_cfg="$_srcdir/config/swaync/config.json"
_swaync_css="$_srcdir/config/swaync/style.css"

################################################################################
# Files exist. Without these guards every assert_contains below would trivially
# match against empty strings.
################################################################################
for _f in "$_hypr" "$_hypr_test" "$_hypr_tmpl" "$_idle" "$_lock" \
          "$_theme" "$_themed" "$_fuzzellaunch" "$_apply" "$_nextlayout" "$_powermenu" \
          "$_waybar_cfg" "$_waybar_css" \
          "$_srcdir/config/waybar/common.css" \
          "$_srcdir/config/waybar/colors-dark.css" \
          "$_srcdir/config/waybar/colors-light.css" \
          "$_srcdir/config/waybar/style-light.css" \
          "$_srcdir/config/swaync/common.css" \
          "$_srcdir/config/swaync/colors-dark.css" \
          "$_srcdir/config/swaync/colors-light.css" \
          "$_srcdir/config/swaync/style-light.css" \
          "$_fuzzel" "$_srcdir/config/fuzzel/fuzzel-light.ini" \
          "$_swaync_cfg" "$_swaync_css" \
          "$_srcdir/config/uwsm/env" "$_srcdir/config/uwsm/env-hyprland"; do
    start_test "exists: ${_f##*/config/}"
    assert_true test -f "$_f"
done


################################################################################
# hyprland.lua, loaded under a stub of Hyprland's Lua API. Hyprland 0.56
# embeds Lua 5.5; the config also runs on 5.4, which is what most
# distributions (and the CI runner) package today.
################################################################################
_lua=
for _l in lua5.5 lua5.4 lua; do
    if command -v "$_l" >/dev/null 2>&1 \
        && "$_l" -e 'os.exit((_VERSION == "Lua 5.5" or _VERSION == "Lua 5.4") and 0 or 1)' 2>/dev/null; then
        _lua=$_l
        break
    fi
done
if test -n "$_lua"; then
    start_test "hyprland_test.lua passes"
    _lua_out=$("$_lua" "$_hypr_test" 2>&1)
    _lua_status=$?
    printf '%s\n' "$_lua_out"
    assert_equal 0 "$_lua_status"
elif test -n "${CI:-}"; then
    # CI installs Lua; a skip there would pass without testing the config.
    start_test "Lua 5.5 or 5.4 is installed for hyprland_test.lua"
    assert_true false
else
    skip_block "hyprland_test.lua (neither Lua 5.5 nor 5.4 is installed)"
fi

start_test "the conf-format config is gone (Hyprland 0.56 reads only hyprland.lua)"
assert_false test -e "$_srcdir/config/hypr/hyprland.conf"
assert_false test -e "$_srcdir/config/hypr/hyprland.conf.local.template"

# The Lua config has no `hyprctl keyword`, and `hyprctl dispatch` takes a Lua
# dispatcher, so the old forms fail at runtime.
start_test "no script uses hyprctl keyword or a conf-style dispatch"
_old_ipc=$(grep -rnE --exclude='*.md' 'hyprctl (keyword|dispatch [a-z])' \
    "$_srcdir/config/hypr" "$_srcdir/config/waybar" || true)
assert_equal "" "$_old_ipc"

################################################################################
# apply-input.sh, against a fake hyprctl: each mouse goes through
# hyprland.lua's conf_input.mouse() by `hyprctl eval`, each touchpad through
# conf_input.touchpad(), and each keyboard through conf_input.keyboard().
################################################################################
_fake=$(mktemp -d)
cat > "$_fake/hyprctl" <<'FAKE'
#!/bin/sh
case "$1" in
    devices)
        test -z "$FAKE_DEVICES_FAIL" || exit 1
        if test -n "$FAKE_DEVICES"; then
            printf '%s\n' "$FAKE_DEVICES"
        else
            printf '%s\n' '{"mice": [{"name": "logitech-usb-receiver"}, {"name": "synps/2-synaptics-touchpad"}, {"name": "odd \"quoted\" mouse"}], "keyboards": [{"name": "at-keyboard"}, {"name": "logitech-usb-receiver"}]}'
        fi
        ;;
    eval)
        printf '%s\n' "$2" >> "$FAKE_LOG"
        printf '%s\n' "${FAKE_EVAL_REPLY:-ok}"
        ;;
esac
FAKE
chmod +x "$_fake/hyprctl"
_apply_run() {
    : > "$_fake/log"
    PATH="$_fake:${APPLY_PATH:-$PATH}" FAKE_LOG="$_fake/log" sh "$_apply" 2>"$_fake/err"
}

start_test "apply-input configures each mouse (wheel at 3), touchpad and keyboard through conf_input"
_apply_run
assert_equal 0 "$?"
_apply_log=$(cat "$_fake/log")
assert_contains 'conf_input.mouse("logitech-usb-receiver", 3)' "$_apply_log"
assert_contains 'conf_input.touchpad("synps/2-synaptics-touchpad")' "$_apply_log"
assert_not_contains 'conf_input.mouse("synps/2-synaptics-touchpad"' "$_apply_log"
assert_contains 'conf_input.keyboard("at-keyboard")' "$_apply_log"
assert_not_contains 'conf_input.mouse("at-keyboard"' "$_apply_log"

start_test "apply-input configures a receiver that's a mouse and a keyboard as both"
assert_contains 'conf_input.keyboard("logitech-usb-receiver")' "$_apply_log"

start_test "apply-input escapes quotes in a device name for Lua"
assert_contains 'conf_input.mouse("odd \"quoted\" mouse", 3)' "$_apply_log"

start_test "apply-input reads hyprctl's own layout without jq, keeping each list apart"
mkdir "$_fake/nojq-apply"
for _tool in sh sed grep cut; do
    _path=$(command -v "$_tool") && ln -s "$_path" "$_fake/nojq-apply/$_tool"
done
FAKE_DEVICES='{
    "mice": [
        {
            "address": "0x1",
            "name": "trackball",
            "defaultSpeed": 0.00000
        }
    ],
    "keyboards": [
        {
            "address": "0x2",
            "name": "at-keyboard",
            "layout": "us",
            "main": true
        }
    ],
    "tablets": [
        {
            "address": "0x3",
            "name": "pen-tablet"
        }
    ]
}' APPLY_PATH="$_fake/nojq-apply" _apply_run
assert_equal 0 "$?"
_apply_log=$(cat "$_fake/log")
assert_contains 'conf_input.mouse("trackball", 3)' "$_apply_log"
assert_contains 'conf_input.keyboard("at-keyboard")' "$_apply_log"
assert_not_contains 'conf_input.mouse("at-keyboard"' "$_apply_log"
assert_not_contains "pen-tablet" "$_apply_log"

start_test "apply-input reports a device listing hyprctl couldn't give"
FAKE_DEVICES_FAIL=1 _apply_run
assert_equal 1 "$?"
assert_equal "" "$(cat "$_fake/log")"
assert_contains "hyprctl devices -j failed" "$(cat "$_fake/err")"

start_test "apply-input honors HYPR_MOUSE_SCROLL_FACTOR"
HYPR_MOUSE_SCROLL_FACTOR=2.25 _apply_run
assert_contains '"logitech-usb-receiver", 2.25)' "$(cat "$_fake/log")"

start_test "apply-input refuses a scroll factor that isn't a number"
HYPR_MOUSE_SCROLL_FACTOR='1) os.exit(' _apply_run
assert_equal 1 "$?"
assert_equal "" "$(cat "$_fake/log")"
assert_contains "must be a number" "$(cat "$_fake/err")"

start_test "apply-input reports a device Hyprland rejected"
FAKE_EVAL_REPLY='error: hl.device: unknown field' _apply_run
assert_equal 1 "$?"
assert_contains "couldn't configure mouse 'logitech-usb-receiver'" "$(cat "$_fake/err")"
assert_contains "couldn't configure keyboard 'at-keyboard': error: hl.device: unknown field" "$(cat "$_fake/err")"
rm -rf "$_fake"

################################################################################
# next-layout.sh, against a fake hyprctl: every keyboard goes to the layout
# after the main keyboard's, by its index, so keyboards out of step come back
# into it. Run with jq, then with python3 alone, since it takes either.
################################################################################
_fake=$(mktemp -d)
cat > "$_fake/hyprctl" <<'FAKE'
#!/bin/sh
case "$1" in
    devices)
        printf '%s\n' "$FAKE_DEVICES"
        ;;
    switchxkblayout)
        printf '%s\n' "$*" >> "$FAKE_LOG"
        printf '%s\n' "${FAKE_SWITCH_REPLY:-ok}"
        ;;
esac
FAKE
chmod +x "$_fake/hyprctl"
# A PATH of the fake hyprctl and only the tools the script may use: with
# python3 and without jq, so the fallback runs even where jq is installed.
# python3 is linked as the interpreter itself, not a version manager's shim
# (pyenv, asdf), which needs more of the PATH than this one has.
mkdir "$_fake/nojq"
for _tool in sh tr wc; do
    _path=$(command -v "$_tool") && ln -s "$_path" "$_fake/nojq/$_tool"
done
if _python=$(python3 -c 'import sys; print(sys.executable)' 2>"$_fake/err") && test -n "$_python"; then
    ln -s "$_python" "$_fake/nojq/python3"
else
    # Without it, the python3 runs below fail on their own.
    echo "hypr_test.sh: couldn't find python3's interpreter: $(cat "$_fake/err")" >&2
fi
_next_run() {
    : > "$_fake/log"
    FAKE_DEVICES=$1 PATH="$_fake:${2:-$PATH}" FAKE_LOG="$_fake/log" sh "$_nextlayout" 2>"$_fake/err"
}
_kb() {
    printf '{"name": "%s", "layout": "%s", "active_layout_index": %s, "main": %s}' "$1" "$2" "$3" "$4"
}
for _with in jq python3; do
    _p=
    test "$_with" = python3 && _p="$_fake/nojq"
    if test "$_with" = jq && ! command -v jq >/dev/null 2>&1; then
        skip_block "next-layout.sh with jq (jq isn't installed)"
        continue
    fi

    start_test "next-layout ($_with) goes from the main keyboard's first layout to its second"
    _next_run "{\"keyboards\": [$(_kb at-keyboard us,de 0 true)]}" "$_p"
    assert_equal 0 "$?"
    assert_equal "switchxkblayout all 1" "$(cat "$_fake/log")"

    start_test "next-layout ($_with) goes from the last layout back to the first"
    _next_run "{\"keyboards\": [$(_kb at-keyboard us,de,fr 2 true)]}" "$_p"
    assert_equal "switchxkblayout all 0" "$(cat "$_fake/log")"

    start_test "next-layout ($_with) follows the main keyboard, bringing the others into step"
    _next_run "{\"keyboards\": [$(_kb usb-keyboard us,de 0 false), $(_kb at-keyboard us,de 1 true)]}" "$_p"
    assert_equal "switchxkblayout all 0" "$(cat "$_fake/log")"

    start_test "next-layout ($_with) takes the first keyboard when none is main"
    _next_run "{\"keyboards\": [$(_kb at-keyboard us,de 1 false), $(_kb usb-keyboard us,de 0 false)]}" "$_p"
    assert_equal "switchxkblayout all 0" "$(cat "$_fake/log")"

    start_test "next-layout ($_with) with one layout sets it again"
    _next_run "{\"keyboards\": [$(_kb at-keyboard us 0 true)]}" "$_p"
    assert_equal 0 "$?"
    assert_equal "switchxkblayout all 0" "$(cat "$_fake/log")"

    start_test "next-layout ($_with) reports a keyboard it couldn't find a layout for"
    _next_run '{"keyboards": []}' "$_p"
    assert_equal 1 "$?"
    assert_equal "" "$(cat "$_fake/log")"
    assert_contains "next-layout.sh:" "$(cat "$_fake/err")"
done

start_test "next-layout reports a keyboard Hyprland couldn't switch"
FAKE_SWITCH_REPLY='layout idx out of range of 1' _next_run "{\"keyboards\": [$(_kb at-keyboard us,de 0 true)]}"
assert_equal 1 "$?"
assert_contains "couldn't switch every keyboard to layout 1: layout idx out of range of 1" "$(cat "$_fake/err")"

start_test "next-layout says what it needs when it has neither jq nor python3"
rm "$_fake/nojq/python3"
_next_run "{\"keyboards\": [$(_kb at-keyboard us,de 0 true)]}" "$_fake/nojq"
assert_equal 1 "$?"
assert_contains "needs jq or python3" "$(cat "$_fake/err")"
rm -rf "$_fake"

# theme.sh against fakes that log what it starts; waybar only when it's the
# bar.
_tfake=$(mktemp -d)
for _p in waybar swaync; do
    printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "$FAKE_LOG"\n' "$_p" > "$_tfake/$_p"
    chmod +x "$_tfake/$_p"
done
# gsettings logs too; `get` answers $FAKE_SCHEME, and with none, as with no
# schema, it and `writable` fail; `writable` prints $FAKE_WRITABLE (true).
cat > "$_tfake/gsettings" <<'FAKE'
#!/bin/sh
printf 'gsettings %s\n' "$*" >> "$FAKE_LOG"
case "$1" in
    writable)
        test -n "$FAKE_SCHEME" || exit 1
        echo "${FAKE_WRITABLE:-true}"
        ;;
    get)
        test -n "$FAKE_SCHEME" || exit 1
        printf "'%s'\n" "$FAKE_SCHEME"
        ;;
esac
FAKE
chmod +x "$_tfake/gsettings"
# pkill finds a waybar only when $FAKE_WAYBAR_UP is set, and anything else
# always, as the real one would after the launches above.
cat > "$_tfake/pkill" <<'FAKE'
#!/bin/sh
printf 'pkill %s\n' "$*" >> "$FAKE_LOG"
test "$2" != waybar || test -n "$FAKE_WAYBAR_UP"
FAKE
chmod +x "$_tfake/pkill"
# run_theme ENV...: theme.sh starts its programs in the background. Each
# inherits fd 9, the write end of a pipe that `cat` drains, so the pipeline
# ends only once every one of them has logged and exited.
run_theme() {
    : > "$_tfake/log"
    env -u SWAYSOCK -u TIDE_BAR PATH="$_tfake:$PATH" FAKE_LOG="$_tfake/log" XDG_RUNTIME_DIR="$_tfake" HOME="$_tfake" XDG_CURRENT_DESKTOP= \
        "$@" sh "$_theme" dark 9>&1 >/dev/null 2>&1 | cat >/dev/null
}

start_test "theme.sh starts waybar by default"
run_theme
assert_contains "waybar -s" "$(cat "$_tfake/log")"

start_test "theme.sh starts no waybar beside tide's Quickshell bar"
run_theme TIDE_BAR=quickshell
assert_not_contains "waybar" "$(cat "$_tfake/log")"
assert_contains "swaync --style" "$(cat "$_tfake/log")"

# Run by hand in tide there's no TIDE_BAR: only a waybar that's
# already up is restarted. The fake pkill finds one when $FAKE_WAYBAR_UP is
# set.
start_test "theme.sh run by hand in tide starts no waybar when none is up"
run_theme XDG_CURRENT_DESKTOP=tide:Hyprland
assert_not_contains "waybar -s" "$(cat "$_tfake/log")"
assert_contains "swaync --style" "$(cat "$_tfake/log")"

start_test "theme.sh run by hand in tide restarts a waybar that's up"
run_theme XDG_CURRENT_DESKTOP=tide:Hyprland FAKE_WAYBAR_UP=1
assert_contains "waybar -s" "$(cat "$_tfake/log")"

# In tide with the Quickshell bar, the shell sets the color scheme, and the
# rest follows it.
run_follow() {
    : > "$_tfake/log"
    rm -f "$_tfake/theme-mode"
    env -u SWAYSOCK -u XDG_CONFIG_HOME PATH="$_tfake:$PATH" FAKE_LOG="$_tfake/log" XDG_RUNTIME_DIR="$_tfake" HOME="$_tfake" XDG_CURRENT_DESKTOP= \
        TIDE_BAR=quickshell "$@" 9>&1 >/dev/null 2>&1 | cat >/dev/null
}

start_test "theme.sh follow styles swaync for the color scheme, and sets none"
run_follow FAKE_SCHEME=prefer-light sh "$_theme" follow
assert_contains "swaync --style $_tfake/.config/swaync/style-light.css" "$(cat "$_tfake/log")"
assert_not_contains "gsettings set" "$(cat "$_tfake/log")"
run_follow FAKE_SCHEME=prefer-dark sh "$_theme" follow
assert_contains "swaync --style $_tfake/.config/swaync/style.css" "$(cat "$_tfake/log")"
assert_not_contains "gsettings set" "$(cat "$_tfake/log")"

start_test "theme.sh follow falls back to the clock when the scheme can't be read"
run_follow FAKE_SCHEME= sh "$_theme" follow
assert_contains "swaync --style" "$(cat "$_tfake/log")"
assert_not_contains "gsettings set" "$(cat "$_tfake/log")"

start_test "theme.sh follow styles unlocked when the lock can't be made"
: > "$_tfake/log"
env -u SWAYSOCK -u XDG_CONFIG_HOME PATH="$_tfake:$PATH" FAKE_LOG="$_tfake/log" XDG_RUNTIME_DIR="$_tfake/no-such-dir" HOME="$_tfake" XDG_CURRENT_DESKTOP= \
    TIDE_BAR=quickshell FAKE_SCHEME=prefer-dark sh "$_theme" follow 9>&1 >/dev/null 2>&1 | cat >/dev/null
assert_contains "swaync --style $_tfake/.config/swaync/style.css" "$(cat "$_tfake/log")"

start_test "theme.sh scheme reads gsettings' answer"
assert_equal dark "$(PATH="$_tfake:$PATH" FAKE_LOG=/dev/null FAKE_SCHEME=prefer-dark sh "$_theme" scheme)"
assert_equal light "$(PATH="$_tfake:$PATH" FAKE_LOG=/dev/null FAKE_SCHEME=default sh "$_theme" scheme)"
assert_equal "" "$(PATH="$_tfake:$PATH" FAKE_LOG=/dev/null FAKE_SCHEME= sh "$_theme" scheme)"

# What theme.sh starts in the background mustn't hold its lock: swaync
# would keep it for the session, and the next follow would wait on it.
start_test "theme.sh follow's lock isn't held by the swaync it starts"
if test -d /proc/self/fd && command -v flock >/dev/null 2>&1; then
    cat > "$_tfake/swaync" <<'FAKE'
#!/bin/sh
printf 'swaync %s\n' "$*" >> "$FAKE_LOG"
if test -e /proc/$$/fd/8; then echo "swaync holds fd 8" >> "$FAKE_LOG"; fi
FAKE
    run_follow FAKE_SCHEME=prefer-dark sh "$_theme" follow
    assert_contains "swaync --style" "$(cat "$_tfake/log")"
    assert_not_contains "holds fd 8" "$(cat "$_tfake/log")"
    printf '#!/bin/sh\nprintf "%%s %%s\\n" "swaync" "$*" >> "$FAKE_LOG"\n' > "$_tfake/swaync"
fi

# The daemon, against the fakes: its theme.sh is the one under test, and the
# fake sleep ends it. With SIGTERM: CI's runner ignores SIGPIPE, which its
# children inherit, and a pipeline's first command dying of TERM goes
# unannounced.
mkdir -p "$_tfake/.config/hypr/scripts"
ln -sf "$_theme" "$_tfake/.config/hypr/scripts/theme.sh"
printf '#!/bin/sh\nkill "$PPID"\n' > "$_tfake/sleep"
chmod +x "$_tfake/sleep"

start_test "theme-daemon.sh styles once for tide's color scheme, and sets none"
run_follow FAKE_SCHEME=prefer-light timeout 10 sh "$_themed"
assert_not_contains "gsettings set" "$(cat "$_tfake/log")"
assert_equal 1 "$(grep -c '^swaync --style' "$_tfake/log")"
assert_contains "swaync --style $_tfake/.config/swaync/style-light.css" "$(cat "$_tfake/log")"

start_test "theme-daemon.sh keeps the clock when the color scheme can't be read"
run_follow FAKE_SCHEME= timeout 10 sh "$_themed"
assert_contains "gsettings set org.gnome.desktop.interface color-scheme" "$(cat "$_tfake/log")"

start_test "theme-daemon.sh keeps the clock when the color scheme is locked"
run_follow FAKE_SCHEME=prefer-light FAKE_WRITABLE=false timeout 10 sh "$_themed"
assert_contains "gsettings set org.gnome.desktop.interface color-scheme" "$(cat "$_tfake/log")"

start_test "theme-daemon.sh sets the color scheme itself outside tide's Quickshell bar"
run_follow TIDE_BAR=waybar timeout 10 sh "$_themed"
assert_contains "gsettings set org.gnome.desktop.interface color-scheme" "$(cat "$_tfake/log")"
rm -f "$_tfake/sleep"

# tide's shell runs the hook after each change it makes.
_hook="$_srcdir/config/tide/appearance-hook"
start_test "tide's appearance hook restyles for the scheme now, and sets none"
assert_true test -x "$_hook"
run_follow FAKE_SCHEME=prefer-dark sh "$_hook"
assert_contains "swaync --style $_tfake/.config/swaync/style.css" "$(cat "$_tfake/log")"
assert_not_contains "gsettings set" "$(cat "$_tfake/log")"

start_test "tide's appearance hook leaves the styling to the clock when the scheme is locked"
run_follow FAKE_SCHEME=prefer-dark FAKE_WRITABLE=false sh "$_hook"
assert_not_contains "swaync" "$(cat "$_tfake/log")"

# launch-fuzzel.sh, against a fake fuzzel that logs its arguments.
_fuzzel="$_srcdir/config/hypr/scripts/launch-fuzzel.sh"
_ffake=$(mktemp -d)
cat > "$_ffake/fuzzel" <<'FAKE'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done > "$FAKE_LOG"
FAKE
chmod +x "$_ffake/fuzzel"
echo dark > "$_ffake/theme-mode"
run_fuzzel() {
    : > "$_ffake/log"
    env PATH="$_ffake:$PATH" FAKE_LOG="$_ffake/log" XDG_RUNTIME_DIR="$_ffake" "$@" sh "$_fuzzel"
}

start_test "launch-fuzzel launches through tide launch in the tide session"
run_fuzzel XDG_CURRENT_DESKTOP=tide:Hyprland
assert_contains "--launch-prefix=tide launch --app '*' --" "$(cat "$_ffake/log")"

start_test "launch-fuzzel launches directly elsewhere"
run_fuzzel XDG_CURRENT_DESKTOP=KDE
assert_equal "" "$(cat "$_ffake/log")"
rm -rf "$_ffake"

################################################################################
# hyprlock shows the short hostname.
################################################################################
start_test "hyprlock colors the password field white while checking, red when wrong"
assert_contains "check_color = rgba(eceff4ff)" "$(cat "$_lock")"
assert_contains "fail_color = rgba(bf616aff)" "$(cat "$_lock")"

# hyprlock 0.9.0 replaced general:grace with --grace; the option is an error
# on every lock.
start_test "hyprlock.conf sets no grace period"
assert_equal "" "$(sed -n '/^general {/,/^}/{/^ *grace *=/p}' "$_lock")"

start_test "hyprlock has no animations, so typing shows at once"
assert_equal "enabled = false" "$(sed -n '/^animations {/,/^}/s/^ *\(enabled = .*\)$/\1/p' "$_lock")"

start_test "hyprlock shows the short hostname"
_lock_host=$(sed -n 's/^ *text = cmd\[update:[0-9]*\] \(uname -n.*\)$/\1/p' "$_lock")
assert_equal "uname -n | cut -d. -f1" "$_lock_host"

start_test "the hostname command drops the domain"
_fakebin=$(mktemp -d)
printf '#!/bin/sh\necho host1.example.com\n' > "$_fakebin/uname"
chmod +x "$_fakebin/uname"
assert_equal "host1" "$(PATH="$_fakebin:$PATH" sh -c "$_lock_host")"
rm -rf "$_fakebin"

start_test "apply-input parses as shell and is executable"
assert_true sh -n "$_apply"
assert_true test -x "$_apply"

################################################################################
# Tray applets: network + volume/sound.
################################################################################
_waybar_body=$(cat "$_waybar_cfg")
start_test "waybar exposes a network module"
assert_contains "\"network\"" "$_waybar_body"
start_test "waybar exposes a volume/sound module"
assert_contains "\"pulseaudio\"" "$_waybar_body"

# waybar and swaync are launched by theme.sh (with the light/dark style), not
# by their own autostart lines.
_theme_body=$(cat "$_theme")
start_test "theme.sh launches waybar"
assert_contains "waybar -s" "$_theme_body"
start_test "theme.sh launches swaync"
assert_contains "swaync --style" "$_theme_body"

################################################################################
# hypridle: dim, lock, and screen-off listeners exist.
################################################################################
_idle_body=$(cat "$_idle")
start_test "hypridle dims the backlight"
assert_contains "brightnessctl -s set" "$_idle_body"
start_test "hypridle locks the session"
assert_contains "loginctl lock-session" "$_idle_body"
start_test "hypridle turns the display off (DPMS)"
assert_contains "hl.dsp.dpms({ action = \"off\" })" "$_idle_body"

# The timeouts are tide's settings: tide writes them to tide-idle.conf, which
# this sources after its own defaults, tide's SPEC.md §10 timeline, so a
# missing file keeps that timeline; and every listener times out on one.
_idle_vars=$(sed -n 's/^\$\(tide_idle_[a-z_]*\) = \([0-9]*\)$/\1=\2/p' "$_idle" | tr '\n' ' ')
start_test "hypridle's default timeouts are tide's timeline"
assert_equal "tide_idle_dim=150 tide_idle_lock=300 tide_idle_displays_off=330 tide_idle_suspend=1800 " "$_idle_vars"
_idle_source_line=$(grep -n '^source = tide-idle.conf$' "$_idle" | cut -d: -f1)
_idle_last_default=$(grep -n '^\$tide_idle_' "$_idle" | tail -n 1 | cut -d: -f1)
_idle_first_listener=$(grep -n '^listener {' "$_idle" | head -n 1 | cut -d: -f1)
start_test "hypridle sources tide's timeouts after its defaults and before any listener"
assert_equal "yes" "$(test -n "$_idle_source_line" && test "$_idle_source_line" -gt "${_idle_last_default:-0}" && test "$_idle_source_line" -lt "${_idle_first_listener:-0}" && echo yes)"
start_test "every hypridle listener times out on one of tide's settings"
assert_equal "\$tide_idle_dim \$tide_idle_lock \$tide_idle_displays_off \$tide_idle_suspend " "$(sed -n 's/^ *timeout = //p' "$_idle" | tr '\n' ' ')"

# The lock command and the five-minute idle step, run as hypridle runs them
# (/bin/sh -c) against fake tools that log their arguments: the tide session
# goes to tide-lock, a plain Hyprland login to hyprlock.
_idle_lock_cmd=$(sed -n 's/^ *lock_cmd = //p' "$_idle")
_idle_lock_step=$(sed -n '/^listener {/,/^}/{/timeout = \$tide_idle_lock$/,/^}/s/^ *on-timeout = //p}' "$_idle")
_idle_suspend_step=$(sed -n '/^listener {/,/^}/{/timeout = \$tide_idle_suspend$/,/^}/s/^ *on-timeout = //p}' "$_idle")
_idle_suspend_resume=$(sed -n '/^listener {/,/^}/{/timeout = \$tide_idle_suspend$/,/^}/s/^ *on-resume = //p}' "$_idle")
start_test "hypridle's lock command and idle lock and suspend steps are found"
assert_contains "esac" "$_idle_lock_cmd"
assert_contains "esac" "$_idle_lock_step"
assert_contains "esac" "$_idle_suspend_step"
assert_contains "esac" "$_idle_suspend_resume"

_ifake=$(mktemp -d)
for _t in systemctl hyprlock tide loginctl; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/log"\n' "$_t" "$_ifake" > "$_ifake/$_t"
    chmod +x "$_ifake/$_t"
done
# No lock running, so pidof finds nothing.
printf '#!/bin/sh\nexit 1\n' > "$_ifake/pidof"
chmod +x "$_ifake/pidof"
_idle_run() {
    : > "$_ifake/log"
    XDG_CURRENT_DESKTOP="$1" PATH="$_ifake:$PATH" sh -c "$2"
    cat "$_ifake/log"
}
start_test "in the tide session, a lock starts tide-lock.service"
assert_equal "systemctl --user start tide-lock.service" "$(_idle_run tide:Hyprland "$_idle_lock_cmd")"
start_test "in the tide session, the idle step runs tide idle-lock"
assert_equal "tide idle-lock" "$(_idle_run tide:Hyprland "$_idle_lock_step")"
start_test "in a plain Hyprland login, a lock runs hyprlock"
assert_equal "hyprlock " "$(_idle_run Hyprland "$_idle_lock_cmd")"
start_test "in a plain Hyprland login, the idle step locks through logind"
assert_equal "loginctl lock-session" "$(_idle_run Hyprland "$_idle_lock_step")"
start_test "with no desktop set, a lock runs hyprlock"
assert_equal "hyprlock " "$(_idle_run "" "$_idle_lock_cmd")"
# tide decides whether to suspend (on battery only).
start_test "in the tide session, the suspend step runs tide idle-suspend"
assert_equal "tide idle-suspend" "$(_idle_run tide:Hyprland "$_idle_suspend_step")"
start_test "in a plain Hyprland login, the suspend step suspends"
assert_equal "systemctl suspend" "$(_idle_run Hyprland "$_idle_suspend_step")"
# On AC, tide notes the skipped suspend for an unplug; coming back forgets it.
start_test "in the tide session, input after the suspend step cancels tide's unplug suspend"
assert_equal "tide idle-suspend --cancel" "$(_idle_run tide:Hyprland "$_idle_suspend_resume")"
start_test "in a plain Hyprland login, input after the suspend step runs nothing"
assert_equal "" "$(_idle_run Hyprland "$_idle_suspend_resume")"
rm -rf "$_ifake"

################################################################################
# Waybar: window title centred; clocks (SFO, LON, local), tray, and battery
# on the right.
################################################################################
_waybar_body=$(cat "$_waybar_cfg")
start_test "waybar has a London clock"
assert_contains "Europe/London" "$_waybar_body"
start_test "waybar has a San Francisco clock"
assert_contains "America/Los_Angeles" "$_waybar_body"
start_test "waybar centre shows the focused window title (both compositors)"
_center=$(sed -n '/"modules-center"/p' "$_waybar_cfg")
assert_contains "hyprland/window" "$_center"
assert_contains "sway/window" "$_center"
start_test "waybar right has the three clocks in SFO, LON, local order"
_right=$(sed -n '/"modules-right"/p' "$_waybar_cfg")
assert_contains "\"clock#sf\", \"clock#london\", \"clock\"" "$_right"
start_test "waybar San Francisco clock is labelled SFO"
assert_contains "SFO {:%H:%M}" "$_waybar_body"
start_test "waybar network module shows no IP address"
assert_not_contains "{ipaddr}" "$_waybar_body"
start_test "waybar has a tray"
assert_contains "\"tray\"" "$_waybar_body"
start_test "waybar has a battery module"
assert_contains "\"battery\"" "$_waybar_body"

################################################################################
# Session/power button: far-right waybar module driving a theme-aware fuzzel
# dmenu with lock/logout/suspend/reboot/shutdown.
################################################################################
start_test "waybar has the session/power button as the last right module"
_right=$(sed -n '/"modules-right"/p' "$_waybar_cfg")
assert_contains "\"custom/power\"]" "$_right"
start_test "power button launches the power menu script"
assert_contains "waybar/scripts/power-menu.sh" "$_waybar_body"

_powermenu_body=$(cat "$_powermenu")
start_test "power menu offers the five session actions"
assert_contains "Lock Logout Suspend Reboot Shutdown" "$_powermenu_body"
start_test "power menu locks via loginctl"
assert_contains "loginctl lock-session" "$_powermenu_body"
start_test "power menu suspend/reboot/shutdown use systemctl"
assert_contains "systemctl suspend" "$_powermenu_body"
assert_contains "systemctl reboot" "$_powermenu_body"
assert_contains "systemctl poweroff" "$_powermenu_body"

# Logout must tear down a uwsm session unit when there is one, and fall back
# to whichever compositor is running (the waybar config is shared).
start_test "power menu logout prefers uwsm stop"
assert_contains "uwsm stop" "$_powermenu_body"
start_test "power menu logout handles both compositors"
assert_contains "hyprctl dispatch 'hl.dsp.exit()'" "$_powermenu_body"
assert_contains "swaymsg exit" "$_powermenu_body"

start_test "power menu is a themed fuzzel dmenu (mode marker like the launcher)"
assert_contains "fuzzel --dmenu" "$_powermenu_body"
assert_contains "theme-mode" "$_powermenu_body"
assert_contains "fuzzel-light.ini" "$_powermenu_body"

start_test "power menu parses as shell and is executable"
assert_true sh -n "$_powermenu"
assert_true test -x "$_powermenu"

# JSON validity of the waybar config (strip // and /* */ comments first) and
# the swaync config, when a JSON parser is available.
if command -v python3 >/dev/null 2>&1; then
    start_test "waybar config.jsonc parses as JSON (comments stripped)"
    if sed -e 's://.*$::' "$_waybar_cfg" \
         | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null; then
        assert_true true
    else
        assert_true false
    fi

    start_test "swaync config.json parses as JSON"
    if python3 -c 'import sys,json; json.load(sys.stdin)' < "$_swaync_cfg" 2>/dev/null; then
        assert_true true
    else
        assert_true false
    fi
else
    echo "SKIP: JSON parse checks (python3 not installed)"
fi

################################################################################
# fuzzel launcher.
################################################################################
_fuzzel_body=$(cat "$_fuzzel")
start_test "fuzzel has a colors section (themed)"
assert_contains "[colors]" "$_fuzzel_body"

################################################################################
# Zero placeholders anywhere in the shipped desktop config.
################################################################################
start_test "no REPLACE-ME placeholders in any shipped config file"
_placeholders=$(grep -rl 'REPLACE-ME' \
    "$_srcdir/config/hypr" "$_srcdir/config/waybar" \
    "$_srcdir/config/fuzzel" "$_srcdir/config/swaync" 2>/dev/null || true)
assert_equal "" "$_placeholders"

################################################################################
# Time-based light/dark theming.
################################################################################
start_test "theme boundaries are 07:00 (light) and 19:00 (dark)"
assert_contains "LIGHT_START=7" "$_theme_body"
assert_contains "DARK_START=19" "$_theme_body"

start_test "theme.sh drives the system colour-scheme (kitty + GTK follow it)"
assert_contains "color-scheme" "$_theme_body"

start_test "theme.sh exposes light and dark modes"
assert_contains "prefer-light" "$_theme_body"
assert_contains "prefer-dark" "$_theme_body"

start_test "theme daemon re-applies at each boundary"
_themed_body=$(cat "$_themed")
assert_contains "\"\$theme\" sleep" "$_themed_body"

start_test "fuzzel launcher themes by current mode"
_fuzzellaunch_body=$(cat "$_fuzzellaunch")
assert_contains "theme.sh\" mode" "$_fuzzellaunch_body"

# theme.sh records the applied mode in a marker; launch-fuzzel.sh must read it
# so a manual `theme.sh light`/`theme.sh dark` override themes fuzzel too (the
# time-of-day mode is only the fallback).
start_test "theme.sh writes the mode marker and fuzzel launcher reads it"
assert_contains "theme-mode" "$_theme_body"
assert_contains "theme-mode" "$_fuzzellaunch_body"

################################################################################
# Optional uwsm session: env files are shell-sourced, so `export` form with
# metacharacter values quoted; HYPR* vars live in env-hyprland.
################################################################################
_uwsm_env=$(cat "$_srcdir/config/uwsm/env")
_uwsm_env_hypr=$(cat "$_srcdir/config/uwsm/env-hyprland")

start_test "uwsm env files parse as shell"
assert_true sh -n "$_srcdir/config/uwsm/env"
assert_true sh -n "$_srcdir/config/uwsm/env-hyprland"

start_test "uwsm env uses export form"
assert_contains "export XCURSOR_SIZE=24" "$_uwsm_env"

start_test "uwsm env quotes the QT_QPA_PLATFORM metacharacter value"
assert_contains "export QT_QPA_PLATFORM='wayland;xcb'" "$_uwsm_env"
# An unquoted value would end the statement at the ';'.
assert_not_contains "export QT_QPA_PLATFORM=wayland;xcb" "$_uwsm_env"

start_test "HYPR* vars live in env-hyprland, not env"
assert_contains "export HYPRCURSOR_SIZE=24" "$_uwsm_env_hypr"
assert_not_contains "HYPRCURSOR_SIZE" "$_uwsm_env"

################################################################################
# Session PATH: the launcher binds run helper scripts (browser1, home, irc,
# ...) from the scripts repo, but no session flavour runs .profile/.shrc, so
# those binds go through runenv (scripts repo), which sources .shrc
# -- the single source of truth for PATH (add_path dirs plus the ~/scripts.*
# override globs; runenv's own behaviour is tested in the scripts repo).
# Neither hyprland.lua nor uwsm/env may set PATH from a duplicated
# directory list.
################################################################################
start_test "no duplicated PATH directory list in uwsm env"
assert_not_contains "export PATH" "$_uwsm_env"

test_summary "hypr_test"
