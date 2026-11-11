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
_lock="$_srcdir/config/hypr/hyprlock.conf"
_xdph="$_srcdir/config/hypr/xdph.conf"
_theme="$_srcdir/config/hypr/scripts/theme.sh"
_themed="$_srcdir/config/hypr/scripts/theme-daemon.sh"
_fuzzellaunch="$_srcdir/config/hypr/scripts/launch-fuzzel.sh"
_powermenu="$_srcdir/config/waybar/scripts/power-menu.sh"
_sharepicker="$_srcdir/config/hypr/scripts/share-picker.sh"
_waybar_cfg="$_srcdir/config/waybar/config.jsonc"
_waybar_css="$_srcdir/config/waybar/style.css"
_fuzzel="$_srcdir/config/fuzzel/fuzzel.ini"
_swaync_cfg="$_srcdir/config/swaync/config.json"
_tide_workspaces="$_srcdir/config/tide/workspaces.json"
_swaync_css="$_srcdir/config/swaync/style.css"

################################################################################
# Files exist. Without these guards every assert_contains below would trivially
# match against empty strings.
################################################################################
for _f in "$_hypr" "$_hypr_test" "$_hypr_tmpl" "$_lock" "$_xdph" \
          "$_theme" "$_themed" "$_fuzzellaunch" "$_sharepicker" "$_powermenu" \
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
# hyprland.lua, loaded under a stub of Hyprland's Lua API. Hyprland 0.57
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
for _name; do :; done
if test -n "$FAKE_OTHER_USER"; then
    case "$*" in "-u $(id -u) "*) ;; *) echo "pkill signalled another user's $_name" >> "$FAKE_LOG" ;; esac
fi
test "$_name" != waybar || test -n "$FAKE_WAYBAR_UP"
FAKE
chmod +x "$_tfake/pkill"
# pgrep finds a swaync for the first $FAKE_SWAYNC_LINGERS calls, counted in
# $FAKE_LOG.pgrep, and none after; none at all by default. With
# $FAKE_OTHER_USER set, another user's swaync runs for good: pkill and pgrep
# find it unless they're asked for this user's only.
cat > "$_tfake/pgrep" <<'FAKE'
#!/bin/sh
printf 'pgrep %s\n' "$*" >> "$FAKE_LOG"
if test -n "$FAKE_OTHER_USER"; then
    case "$*" in "-u $(id -u) "*) ;; *) echo "pgrep found another user's" >> "$FAKE_LOG"; exit 0 ;; esac
fi
n=$(cat "$FAKE_LOG.pgrep" 2>/dev/null || echo 0)
echo $((n + 1)) > "$FAKE_LOG.pgrep"
test "$n" -lt "${FAKE_SWAYNC_LINGERS:-0}"
FAKE
chmod +x "$_tfake/pgrep"
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
    rm -f "$_tfake/theme-mode"
    run_follow_again "$@"
}
# run_follow_again: the same, with the mode the last run left in the marker.
run_follow_again() {
    : > "$_tfake/log"
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

# A new swaync started while the old one still holds the notifications name
# can't take it, and once the old one exits there's none.
start_test "theme.sh starts swaync only once the old one has exited"
rm -f "$_tfake/log.pgrep"
run_follow FAKE_SCHEME=prefer-dark FAKE_SWAYNC_LINGERS=3 sh "$_theme" follow
assert_equal 4 "$(grep -c '^pgrep .*-x swaync' "$_tfake/log")"
assert_equal "swaync" "$(grep -E '^(pgrep|swaync)' "$_tfake/log" | tail -n 1 | cut -d' ' -f1)"
rm -f "$_tfake/log.pgrep"

# At login the daemon's first run and the shell's hook style the same scheme
# seconds apart. The fake pgrep finds a swaync on its first call.
start_test "theme.sh follow leaves a running swaync alone when the mode hasn't changed"
run_follow FAKE_SCHEME=prefer-dark sh "$_theme" follow
rm -f "$_tfake/log.pgrep"
run_follow_again FAKE_SCHEME=prefer-dark FAKE_SWAYNC_LINGERS=1 sh "$_theme" follow
assert_not_contains "pkill -u $(id -u) -x swaync" "$(cat "$_tfake/log")"
assert_not_contains "swaync --style" "$(cat "$_tfake/log")"
assert_equal dark "$(cat "$_tfake/theme-mode")"
rm -f "$_tfake/log.pgrep"

start_test "theme.sh follow restarts a running swaync when the mode changes"
run_follow FAKE_SCHEME=prefer-dark sh "$_theme" follow
rm -f "$_tfake/log.pgrep"
run_follow_again FAKE_SCHEME=prefer-light FAKE_SWAYNC_LINGERS=1 sh "$_theme" follow
assert_contains "pkill -u $(id -u) -x swaync" "$(cat "$_tfake/log")"
assert_contains "swaync --style $_tfake/.config/swaync/style-light.css" "$(cat "$_tfake/log")"
rm -f "$_tfake/log.pgrep"

# The marker outlives a session that ended without clearing it.
start_test "theme.sh follow starts swaync when the marker names the mode but none runs"
run_follow FAKE_SCHEME=prefer-dark sh "$_theme" follow
run_follow_again FAKE_SCHEME=prefer-dark sh "$_theme" follow
assert_contains "swaync --style $_tfake/.config/swaync/style.css" "$(cat "$_tfake/log")"

# By hand, the same mode again reloads the styles.
start_test "theme.sh dark restarts a running swaync that's already dark"
run_theme
rm -f "$_tfake/log.pgrep"
: > "$_tfake/log"
env -u SWAYSOCK -u TIDE_BAR PATH="$_tfake:$PATH" FAKE_LOG="$_tfake/log" XDG_RUNTIME_DIR="$_tfake" HOME="$_tfake" XDG_CURRENT_DESKTOP= \
    FAKE_SWAYNC_LINGERS=1 sh "$_theme" dark 9>&1 >/dev/null 2>&1 | cat >/dev/null
assert_contains "swaync --style" "$(cat "$_tfake/log")"
rm -f "$_tfake/log.pgrep"

# pkill and pgrep match every user's processes unless told otherwise. With
# a wallpaper and a fake swaybg under Sway, every program theme.sh stops is
# stopped here.
start_test "theme.sh leaves another user's swaync, waybar and swaybg alone"
mkdir -p "$_tfake/.config/hypr"
: > "$_tfake/.config/hypr/wallpaper-dark.jpg"
printf '#!/bin/sh\nprintf "swaybg %%s\\n" "$*" >> "$FAKE_LOG"\n' > "$_tfake/swaybg"
chmod +x "$_tfake/swaybg"
run_theme SWAYSOCK="$_tfake/no-sway" FAKE_OTHER_USER=1 FAKE_WAYBAR_UP=1
assert_contains "swaync --style" "$(cat "$_tfake/log")"
assert_contains "swaybg -i" "$(cat "$_tfake/log")"
assert_not_contains "another user's" "$(cat "$_tfake/log")"
run_follow FAKE_SCHEME=prefer-dark sh "$_theme" follow
run_follow_again FAKE_SCHEME=prefer-dark FAKE_OTHER_USER=1 sh "$_theme" follow
assert_contains "swaync --style" "$(cat "$_tfake/log")"
assert_not_contains "another user's" "$(cat "$_tfake/log")"
rm -f "$_tfake/swaybg" "$_tfake/.config/hypr/wallpaper-dark.jpg" "$_tfake/log.pgrep"

# swaync's own errors reach the journal, not /dev/null, so one that fails
# to start says why.
start_test "theme.sh passes on swaync's errors"
printf '#!/bin/sh\nprintf "%%s %%s\\n" "swaync" "$*" >> "$FAKE_LOG"\necho "swaync: cannot open display" >&2\n' > "$_tfake/swaync"
_err=$(env -u SWAYSOCK -u XDG_CONFIG_HOME PATH="$_tfake:$PATH" FAKE_LOG="$_tfake/log" XDG_RUNTIME_DIR="$_tfake" HOME="$_tfake" XDG_CURRENT_DESKTOP= \
    TIDE_BAR=quickshell FAKE_SCHEME=prefer-dark sh "$_theme" follow 2>&1 >/dev/null; wait)
assert_contains "swaync: cannot open display" "$_err"
printf '#!/bin/sh\nprintf "%%s %%s\\n" "swaync" "$*" >> "$FAKE_LOG"\n' > "$_tfake/swaync"

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

start_test "theme-daemon.sh starts swaync when an earlier session left the marker"
echo light > "$_tfake/theme-mode"
run_follow_again FAKE_SCHEME=prefer-light timeout 10 sh "$_themed"
assert_equal 1 "$(grep -c '^swaync --style' "$_tfake/log")"
rm -f "$_tfake/sleep"

# A suspend stops sleep's time but not the wall clock. The fake sleep logs
# each sleep, and on its first one the wall clock (the fake date's +%s)
# jumps a day ahead, past the next boundary, as a long suspend would; its
# second ends the daemon. The change must come a few seconds after the
# wake, not after the rest of a sleep that ran to the boundary.
start_test "theme-daemon.sh re-applies within seconds of a resume past the boundary"
_real_date=$(command -v date)
cat > "$_tfake/date" <<FAKE
#!/bin/sh
if test "\$*" = +%s && test -s "$_tfake/epoch"; then cat "$_tfake/epoch"; else exec $_real_date "\$@"; fi
FAKE
cat > "$_tfake/sleep" <<FAKE
#!/bin/sh
printf 'sleep %s\n' "\$1" >> "\$FAKE_LOG"
if test -s "$_tfake/epoch"; then kill "\$PPID"; exit 0; fi
echo \$((\$($_real_date +%s) + 86400)) > "$_tfake/epoch"
FAKE
chmod +x "$_tfake/date" "$_tfake/sleep"
rm -f "$_tfake/epoch"
run_follow TIDE_BAR=waybar timeout 10 sh "$_themed"
_slept=$(awk '/^gsettings set org.gnome.desktop.interface color-scheme/ { n++; if (n == 2) exit } /^sleep / && n == 1 { t += $2 } END { print t + 0 }' "$_tfake/log")
assert_equal 2 "$(grep -c '^gsettings set org.gnome.desktop.interface color-scheme' "$_tfake/log")"
assert_true test "$_slept" -le 5
rm -f "$_tfake/date" "$_tfake/sleep" "$_tfake/epoch"

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

################################################################################
# Tray applets: network + volume/sound.
################################################################################
_waybar_body=$(cat "$_waybar_cfg")
start_test "waybar exposes a network module"
assert_contains "\"network\"" "$_waybar_body"
start_test "waybar exposes a volume/sound module"
assert_contains "\"pulseaudio\"" "$_waybar_body"

# Workspaces by name: Hyprland gives a named workspace an ID of its own,
# -1337 and down, which is what "{id}" showed.
start_test "waybar labels Hyprland's workspaces by name, not ID"
_ws_block=$(sed -n '/"hyprland\/workspaces": {/,/}/p' "$_waybar_cfg")
assert_contains '"format": "{name}"' "$_ws_block"
assert_not_contains '{id}' "$_ws_block"

# The icons are Nerd Font symbols, so a font that has them is in the list:
# Symbols Nerd Font, the icons-only one setup-tide installs.
start_test "waybar's font list ends in Symbols Nerd Font for the icons"
assert_contains '"Symbols Nerd Font"' "$(cat "$_srcdir/config/waybar/common.css")"

# waybar and swaync are launched by theme.sh (with the light/dark style), not
# by their own autostart lines.
_theme_body=$(cat "$_theme")
start_test "theme.sh launches waybar"
assert_contains "waybar -s" "$_theme_body"
start_test "theme.sh launches swaync"
assert_contains "swaync --style" "$_theme_body"

################################################################################
# swaync's text and buttons are legible in both modes.
#
# swaync loads its packaged stylesheet beneath common.css, at the same
# priority, and it paints a notification's buttons and time dark gray or
# white whatever the palette. So common.css colors each one itself; coming
# later, its rules win whatever the packaged selectors (checked on swaync
# 0.9 under a headless sway). Each pair here must reach 4.5:1 (WCAG AA).
################################################################################

# The value of PROPERTY in common.css's last rule that lists SELECTOR.
_swaync_decl() {
    awk -v sel="$1" -v prop="$2" '
        { css = css $0 " " }
        END {
            while ((i = index(css, "/*")) > 0) {
                j = index(substr(css, i + 2), "*/")
                css = substr(css, 1, i - 1) (j ? substr(css, i + j + 3) : "")
            }
            n = split(css, rules, "}")
            for (r = 1; r <= n; r++) {
                if (!(b = index(rules[r], "{"))) continue
                ns = split(substr(rules[r], 1, b - 1), sels, ",")
                hit = 0
                for (s = 1; s <= ns; s++) {
                    gsub(/[ \t]+/, " ", sels[s]); gsub(/^ | $/, "", sels[s])
                    if (sels[s] == sel) hit = 1
                }
                if (!hit) continue
                nd = split(substr(rules[r], b + 1), decls, ";")
                for (d = 1; d <= nd; d++) {
                    if (!(c = index(decls[d], ":"))) continue
                    name = substr(decls[d], 1, c - 1); value = substr(decls[d], c + 1)
                    gsub(/^[ \t]+|[ \t]+$/, "", name); gsub(/^[ \t]+|[ \t]+$/, "", value)
                    if (name == prop) found = value
                }
            }
            print found
        }' "$_srcdir/config/swaync/common.css"
}

# The hex for @NAME in MODE's palette.
_swaync_color() {
    sed -n "s/^@define-color ${1#@}  *\(#[0-9a-fA-F]\{6\}\);.*/\1/p" \
        "$_srcdir/config/swaync/colors-$2.css"
}

# Whether the hex colors FG and BG reach 4.5:1.
_legible() {
    test -n "$1" && test -n "$2" && awk -v a="$1" -v b="$2" '
        function lum(h,   i, c, t) {
            t = 0
            for (i = 0; i < 3; i++) {
                c = index("0123456789abcdef", tolower(substr(h, 2 + 2 * i, 1))) - 1
                c = (c * 16 + index("0123456789abcdef", tolower(substr(h, 3 + 2 * i, 1))) - 1) / 255
                c = c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4
                t += (i == 0 ? 0.2126 : i == 1 ? 0.7152 : 0.0722) * c
            }
            return t
        }
        BEGIN {
            x = lum(a); y = lum(b)
            r = x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05)
            exit !(r >= 4.5)
        }'
}

start_test "swaync's contrast check tells white on swaync's gray from white on light gray"
assert_true _legible "#ffffff" "#303030"
assert_false _legible "#ffffff" "#d8dee9"

start_test "the notification is a plain button, its own background showing through"
assert_equal "transparent" "$(_swaync_decl .notification-default-action background)"

_swaync_bg=$(_swaync_decl .notification background)
for _mode in dark light; do
    for _sel in .notification-default-action .summary .time; do
        start_test "swaync's $_sel is legible on the notification in $_mode mode"
        assert_true _legible "$(_swaync_color "$(_swaync_decl "$_sel" color)" $_mode)" \
            "$(_swaync_color "$_swaync_bg" $_mode)"
    done
    # An action is the button on GTK 3 swaync (0.10 and older), and a
    # flowbox child holding it on GTK 4 (0.11 on).
    for _sel in button.notification-action ".notification-action > button" \
            .inline-reply-button .inline-reply-entry; do
        start_test "swaync's $_sel is legible in $_mode mode"
        assert_true _legible "$(_swaync_color "$(_swaync_decl "$_sel" color)" $_mode)" \
            "$(_swaync_color "$(_swaync_decl "$_sel" background)" $_mode)"
    done
done


################################################################################
# xdph asks tide's share picker what to share (tide SPEC.md §12), in its
# screencopy section.
################################################################################
start_test "xdph's share picker is conf's share-picker.sh, as confinst installs it"
assert_equal '$HOME/.config/hypr/scripts/share-picker.sh' "$(sed -n '/^screencopy {$/,/^}$/s/^ *custom_picker_binary = //p' "$_xdph")"
start_test "xdph keeps its default of no restore token without asking"
assert_not_contains "allow_token_by_default" "$(cat "$_xdph")"

# share-picker.sh: tide's picker where it's installed, xdph's own otherwise.
_sfake=$(mktemp -d)
mkdir "$_sfake/tide" "$_sfake/xdph" "$_sfake/none"
for _p in tide/tide-share-picker xdph/hyprland-share-picker; do
    printf '#!/bin/sh\necho "%s $*"\n' "${_p#*/}" >"$_sfake/$_p"
    chmod +x "$_sfake/$_p"
done
cp "$_sfake/xdph/hyprland-share-picker" "$_sfake/tide/"
_share_picker() {
    env PATH="$1:/usr/bin:/bin" sh "$_sharepicker" --allow-token 2>"$_sfake/err"
}
start_test "share-picker.sh runs tide's picker where tide is installed"
assert_equal "tide-share-picker --allow-token" "$(_share_picker "$_sfake/tide")"
start_test "share-picker.sh runs xdph's own picker without tide"
assert_equal "hyprland-share-picker --allow-token" "$(_share_picker "$_sfake/xdph")"
start_test "share-picker.sh with neither shares nothing, and says why"
_out=$(_share_picker "$_sfake/none"); _status=$?
assert_equal "1 " "$_status $_out"
assert_contains "neither tide-share-picker nor hyprland-share-picker is installed" "$(cat "$_sfake/err")"
rm -rf "$_sfake"

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

    # tide's Workspaces settings (tide SPEC.md §6.5, §16): home is the first
    # standing workspace, and its apps are scripts' launchers for mail,
    # chat, calendar and music, which tide starts there at login. A new
    # window on home asks for a workspace, and mail, chat and calendar are
    # pinned there, so tide's close keys leave them open.
    start_test "tide workspaces.json has the standing workspaces, home first, home's apps and its pinned ones"
    if python3 -c 'import sys, json
s = json.load(sys.stdin)
assert set(s) <= {"standing", "inApps", "namePatterns", "workspaceSettings"}, s
assert s["standing"][0] == "in" and len(s["standing"]) == len({n.lower() for n in s["standing"]})
assert s["inApps"] == ["gmail", "google-chat", "google-calendar", "youtube-music"]
assert s["workspaceSettings"] == {"in": {"askForName": True, "pinnedApps": ["gmail", "google-chat", "google-calendar"]}}, s' < "$_tide_workspaces"; then
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
