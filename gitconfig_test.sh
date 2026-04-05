#!/bin/sh
#
# Tests for gitconfig.
#

. "$(dirname "$0")/shrc_test_lib.sh"

_gitconfig="$_srcdir/gitconfig"

# Test submodule.recurse is enabled so that git clone automatically
# initializes submodules (e.g. the vcs submodule).
_recurse=$(git config --file "$_gitconfig" submodule.recurse)
assert_equal "submodule.recurse is true" "true" "$_recurse"

test_summary "gitconfig_test"
