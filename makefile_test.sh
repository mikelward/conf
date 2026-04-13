#!/bin/bash
#
# Tests for the Makefile targets.
#

. "$(dirname "$0")/shrc_test_lib.sh"

_srcdir="$(cd "$(dirname "$0")" && pwd)"

# Test that expected targets exist
_targets=$(make -C "$_srcdir" -pRrq 2>/dev/null | sed -n '/^# Files/,$ s/^\([a-z][-a-z]*\):.*/\1/p' | sort -u)

assert_contains "all target exists" "all" "$_targets"
assert_contains "install target exists" "install" "$_targets"
assert_contains "install-dotfiles target exists" "install-dotfiles" "$_targets"
assert_contains "install-vcs target exists" "install-vcs" "$_targets"
assert_contains "vcs-build target exists" "vcs-build" "$_targets"
assert_contains "test target exists" "test" "$_targets"

# Bare `make` (no target) must build, not install. Verify the default
# target is `all`, that `all` depends on vcs-build, and that its recipe
# does NOT invoke the install-* targets.
_default_target=$(make -C "$_srcdir" -pRrq 2>/dev/null |
    sed -n 's/^\.DEFAULT_GOAL := //p')
assert_equal "default target is all" "all" "$_default_target"
_all_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null | grep '^all:')
assert_contains "all depends on vcs-build" "vcs-build" "$_all_deps"
_default_recipe=$(make -C "$_srcdir" -n 2>/dev/null)
assert_not_contains "bare make does not run confinst" "confinst" "$_default_recipe"
assert_not_contains "bare make does not run install-vcs" "install-vcs" "$_default_recipe"

# Test that install depends on install-dotfiles and install-vcs
_install_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null | grep '^install:')
assert_contains "install depends on install-dotfiles" "install-dotfiles" "$_install_deps"
assert_contains "install depends on install-vcs" "install-vcs" "$_install_deps"

# Test that the VCS test target depends on vcs-build so the submodule
# binary is built before tests that require it.
_vcs_test_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null | grep '^test-shrc-vcs:')
assert_contains "test-shrc-vcs depends on vcs-build" "vcs-build" "$_vcs_test_deps"

# Test that per-test sub-targets exist so `make -j` can schedule them in
# parallel. Each test script gets its own make target; `test-all` aggregates
# them and `test` dispatches to `test-all` with -j.
assert_contains "test-all target exists" "test-all" "$_targets"
assert_contains "test-lint target exists" "test-lint" "$_targets"
assert_contains "test-nu-parse target exists" "test-nu-parse" "$_targets"
assert_contains "test-nu-config target exists" "test-nu-config" "$_targets"
assert_contains "test-shrc-dash target exists" "test-shrc-dash" "$_targets"
assert_contains "test-shrc-bash target exists" "test-shrc-bash" "$_targets"
assert_contains "test-shrc-vcs target exists" "test-shrc-vcs" "$_targets"
assert_contains "test-shrc-prompt target exists" "test-shrc-prompt" "$_targets"
assert_contains "test-shrc-fish target exists" "test-shrc-fish" "$_targets"
assert_contains "test-shrc-fish-prompt target exists" "test-shrc-fish-prompt" "$_targets"
assert_contains "test-gitconfig target exists" "test-gitconfig" "$_targets"
assert_contains "test-makefile target exists" "test-makefile" "$_targets"
assert_contains "test-amethyst target exists" "test-amethyst" "$_targets"

# Test that test-all depends on every per-test sub-target so that a single
# `make test-all` invocation covers the full test suite.
_test_all_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null | grep '^test-all:')
for _sub in test-lint test-nu-parse test-nu-config \
            test-shrc-dash test-shrc-bash \
            test-shrc-vcs \
            test-shrc-prompt test-shrc-fish test-shrc-fish-prompt \
            test-gitconfig test-makefile test-amethyst; do
    assert_contains "test-all depends on $_sub" "$_sub" "$_test_all_deps"
done
unset _sub

# Test that `make test` dispatches to the parallel build. We check the recipe
# rather than running it to avoid recursion and to keep the test fast.
_test_recipe=$(make -C "$_srcdir" -n test 2>/dev/null)
assert_contains "test recipe invokes parallel make" "-j" "$_test_recipe"
assert_contains "test recipe targets test-all" "test-all" "$_test_recipe"

# Test that TEST_JOBS is overridable (setting it should change the recipe).
_recipe_j1=$(make -C "$_srcdir" -n test TEST_JOBS=1 2>/dev/null)
assert_contains "TEST_JOBS=1 uses -j 1" "-j 1" "$_recipe_j1"

test_summary "makefile"
