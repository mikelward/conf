#!/bin/bash
#
# Tests for the Makefile targets.
#

. "$(dirname "$0")/shrc_test_lib.sh"

_srcdir="$(cd "$(dirname "$0")" && pwd)"

# Test that expected targets exist
_targets=$(make -C "$_srcdir" -pRrq 2>/dev/null | sed -n '/^# Files/,$ s/^\([a-z][-a-z]*\):.*/\1/p' | sort -u)

assert_contains "install target exists" "install" "$_targets"
assert_contains "install-dotfiles target exists" "install-dotfiles" "$_targets"
assert_contains "install-vcs target exists" "install-vcs" "$_targets"
assert_contains "test target exists" "test" "$_targets"

# Test that install depends on install-dotfiles and install-vcs
_install_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null | grep '^install:')
assert_contains "install depends on install-dotfiles" "install-dotfiles" "$_install_deps"
assert_contains "install depends on install-vcs" "install-vcs" "$_install_deps"

_nushell_test_recipe=$(grep 'shrc_nushell_test' "$_srcdir/Makefile")
assert_contains "test target runs nushell tests with nu" "nu shrc_nushell_test.nu" "$_nushell_test_recipe"
assert_not_contains "test target no longer runs nushell tests via bash" "bash shrc_nushell_test.sh" "$_nushell_test_recipe"

test_summary "makefile"
