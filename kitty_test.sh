#!/bin/sh
#
# Tests for kitty's config. Remote control can run anything as you, so on a
# Mac it's on only through a socket in your own $TMPDIR, and nowhere else.

. "$(dirname "$0")/shrc_test_lib.sh"

_kitty_conf="$_srcdir/config/kitty/kitty.conf"
_macos_conf="$_srcdir/config/kitty/macos.conf"

start_test "kitty.conf includes the per-OS file, before local.conf"
assert_true grep -Eq '^include \$\{KITTY_OS\}\.conf$' "$_kitty_conf"
_os_line=$(grep -n '^include \${KITTY_OS}\.conf$' "$_kitty_conf" | cut -d: -f1)
_local_line=$(grep -n '^include local\.conf$' "$_kitty_conf" | cut -d: -f1)
assert_true test -n "$_os_line"
assert_true test -n "$_local_line"
assert_true test "${_os_line:-0}" -lt "${_local_line:-0}"

start_test "remote control is off in the shared config, so Linux keeps kitty's default"
assert_false grep -Eq '^(allow_remote_control|listen_on)( |$)' "$_kitty_conf"

start_test "on a Mac, remote control is socket-only"
assert_true test -f "$_macos_conf"
assert_true grep -Eq '^allow_remote_control +socket-only$' "$_macos_conf"
assert_false grep -Eq '^allow_remote_control +(yes|y|true|socket|password)$' "$_macos_conf"

start_test "on a Mac, the socket is relative, so it's in the per-user \$TMPDIR, not /tmp"
assert_true grep -Eq '^listen_on +unix:kitty$' "$_macos_conf"
assert_false grep -Eq '^listen_on +(unix:/|unix:@|tcp)' "$_macos_conf"

start_test "on a Mac, text is about Linux's size and isn't thickened"
assert_true grep -Eq '^font_size +14(\.0)?$' "$_macos_conf"
assert_true grep -Eq '^text_composition_strategy +platform$' "$_macos_conf"

# The window_padding_width kitty ends up with for an OS: kitty reads the
# file top to bottom, following includes where they sit, and the last
# setting wins. It prints the smallest of the one to four sides given.
_padding() {
    awk -v os="$1" -v dir="$_srcdir/config/kitty" '
        function read(file,   line, f, i, min) {
            while ((getline line < file) > 0) {
                if (line ~ /^include /) {
                    f = substr(line, 9)
                    gsub(/\$\{KITTY_OS\}/, os, f)
                    read(dir "/" f)
                } else if (line ~ /^window_padding_width /) {
                    n = split(substr(line, 22), v, " ")
                    min = v[1]
                    for (i = 2; i <= n; i++) if (v[i] + 0 < min + 0) min = v[i]
                    pad = min
                }
            }
            close(file)
        }
        BEGIN { pad = 0; read(dir "/kitty.conf"); print pad }'
}

start_test "on a Mac, text clears the rounded window corners, 4.7 pt in"
assert_true awk -v p="$(_padding macos)" 'BEGIN { exit !(p >= 4.7) }'

start_test "Linux keeps text against the window edge"
assert_true test "$(_padding linux)" = 0

start_test "Linux keeps its font size and legacy text"
assert_true grep -Eq '^font_size +11\.0$' "$_kitty_conf"
assert_true grep -Eq '^text_composition_strategy +legacy$' "$_kitty_conf"

start_test "no Linux file turns remote control on"
assert_false test -e "$_srcdir/config/kitty/linux.conf"
assert_false test -e "$_srcdir/config/kitty/bsd.conf"

start_test "on a Mac, a bell runs tide-bell, and nowhere else does"
assert_true grep -Eq '^command_on_bell +~/\.config/kitty/tide-bell$' "$_macos_conf"
assert_false grep -Eq '^command_on_bell ' "$_kitty_conf"
assert_true test -x "$_srcdir/config/kitty/tide-bell"

# A stand-in kitten and open, on PATH, record what tide-bell asks.
_bin=$(mktemp -d)
cat >"$_bin/kitten" <<'STUB'
#!/bin/sh
echo "$*" >>"$TIDE_BELL_LOG"
test -n "$KITTEN_FAILS" && exit 1
printf '[{"id": 1, "platform_window_id": %s, "tabs": [{"windows": [{"id": 7}]}]}]\n' "${PLATFORM_ID:-4242}"
STUB
cat >"$_bin/open" <<'STUB'
#!/bin/sh
test "$1" = -g && shift
echo "$1"
STUB
chmod +x "$_bin/kitten" "$_bin/open"
_log=$(mktemp)

start_test "tide-bell asks kitty which macOS window rang, and tells tide"
_out=$(PATH="$_bin:$PATH" TIDE_BELL_LOG="$_log" KITTY_WINDOW_ID=7 TIDE_BELL_OPEN="$_bin/open" \
    sh "$_srcdir/config/kitty/tide-bell" 2>&1)
assert_true grep -q '^@ ls --match id:7$' "$_log"
assert_true test "$_out" = "hammerspoon://tide-bell?window=4242"

start_test "tide-bell fails, saying why, without a window to name"
: >"$_log"
_out=$(PATH="$_bin:$PATH" TIDE_BELL_LOG="$_log" TIDE_BELL_OPEN="$_bin/open" sh "$_srcdir/config/kitty/tide-bell" 2>&1)
assert_true test $? -ne 0
assert_true test -n "$(printf '%s' "$_out" | grep KITTY_WINDOW_ID)"
_out=$(PATH="$_bin:$PATH" TIDE_BELL_LOG="$_log" KITTY_WINDOW_ID=7 KITTEN_FAILS=1 TIDE_BELL_OPEN="$_bin/open" \
    sh "$_srcdir/config/kitty/tide-bell" 2>&1)
assert_true test -n "$(printf '%s' "$_out" | grep 'kitten @ ls failed')"
assert_false test -n "$(printf '%s' "$_out" | grep hammerspoon)"
rm -rf "$_bin" "$_log"

start_test "Ctrl+N opens a new OS window, and nothing else takes it"
assert_true grep -Eq '^map +ctrl\+n +new_os_window$' "$_kitty_conf"
assert_true test "$(grep -Ec '^map +ctrl\+n ' "$_kitty_conf" "$_macos_conf" | awk -F: '{ n += $2 } END { print n }')" -eq 1

test_summary "kitty_test"
