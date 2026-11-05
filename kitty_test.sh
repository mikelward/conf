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

start_test "Linux keeps its font size and legacy text"
assert_true grep -Eq '^font_size +11\.0$' "$_kitty_conf"
assert_true grep -Eq '^text_composition_strategy +legacy$' "$_kitty_conf"

start_test "no Linux file turns remote control on"
assert_false test -e "$_srcdir/config/kitty/linux.conf"
assert_false test -e "$_srcdir/config/kitty/bsd.conf"

start_test "Ctrl+N opens a new OS window, and nothing else takes it"
assert_true grep -Eq '^map +ctrl\+n +new_os_window$' "$_kitty_conf"
assert_true test "$(grep -Ec '^map +ctrl\+n ' "$_kitty_conf" "$_macos_conf" | awk -F: '{ n += $2 } END { print n }')" -eq 1

test_summary "kitty_test"
