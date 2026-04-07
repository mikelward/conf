#!/bin/sh
#
# Tests for amethyst.yml.
#

. "$(dirname "$0")/shrc_test_lib.sh"

_amethyst="$_srcdir/amethyst.yml"

# Test that mod1 (hot key prefix) is option.
_mod1=$(sed -n '/^mod1:/,/^[^ ]/{ /^  - /p; }' "$_amethyst" | sed 's/^  - //')
assert_equal "mod1 is option" "option" "$_mod1"

# Test that mod2 includes option.
_mod2=$(sed -n '/^mod2:/,/^[^ ]/{ /^  - /p; }' "$_amethyst")
assert_contains "mod2 includes option" "option" "$_mod2"

test_summary "amethyst_test"
