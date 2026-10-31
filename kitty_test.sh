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

start_test "no Linux file turns remote control on"
assert_false test -e "$_srcdir/config/kitty/linux.conf"
assert_false test -e "$_srcdir/config/kitty/bsd.conf"

test_summary "kitty_test"
