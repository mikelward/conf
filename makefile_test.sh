#!/bin/bash
#
# Tests for the Makefile targets.
#

. "$(dirname "$0")/shrc_test_lib.sh"

_srcdir="$(cd "$(dirname "$0")" && pwd)"

# Test that expected targets exist
_targets=$(make -C "$_srcdir" -pRrq 2>/dev/null | sed -n '/^# Files/,$ s/^\([a-z][-a-z]*\):.*/\1/p' | sort -u)

start_test "all target exists"
assert_contains "all" "$_targets"
start_test "install target exists"
assert_contains "install" "$_targets"
start_test "install-dotfiles target exists"
assert_contains "install-dotfiles" "$_targets"
start_test "install-vcs target exists"
assert_contains "install-vcs" "$_targets"
start_test "vcs-build target exists"
assert_contains "vcs-build" "$_targets"
start_test "test target exists"
assert_contains "test" "$_targets"

# vcs-build must use --remote so the submodule tracks main HEAD instead of
# the parent's pinned commit, and must wire up core.hooksPath so the
# post-merge / post-rewrite hooks fire automatically on pull / rebase.
_vcs_build_recipe=$(make -C "$_srcdir" -n vcs-build 2>/dev/null)
start_test "vcs-build uses --remote to track main HEAD"
assert_contains "submodule update --remote" "$_vcs_build_recipe"
start_test "vcs-build wires up core.hooksPath"
assert_contains "core.hooksPath gittemplates/hooks" "$_vcs_build_recipe"

# Bare `make` (no target) must build, not install. Verify the default
# target is `all`, that `all` depends on vcs-build, and that its recipe
# does NOT invoke the install-* targets.
start_test "default target is all"
_default_target=$(make -C "$_srcdir" -pRrq 2>/dev/null |
    sed -n 's/^\.DEFAULT_GOAL := //p')
assert_equal "all" "$_default_target"
_all_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null | grep '^all:')
start_test "all depends on vcs-build"
assert_contains "vcs-build" "$_all_deps"
_default_recipe=$(make -C "$_srcdir" -n 2>/dev/null)
start_test "bare make does not run confinst"
assert_not_contains "confinst" "$_default_recipe"
start_test "bare make does not run install-vcs"
assert_not_contains "install-vcs" "$_default_recipe"

start_test "install depends on install-dotfiles"
_install_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null | grep '^install:')
assert_contains "install-dotfiles" "$_install_deps"
start_test "install depends on install-vcs"
assert_contains "install-vcs" "$_install_deps"

# Test that the VCS test target depends on vcs-build so the submodule
# binary is built before tests that require it.
start_test "test-shrc-vcs depends on vcs-build"
_vcs_test_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null | grep '^test-shrc-vcs:')
assert_contains "vcs-build" "$_vcs_test_deps"

# Test that per-test sub-targets exist so `make -j` can schedule them in
# parallel. Each test script gets its own make target; `test-all` aggregates
# them and `test` dispatches to `test-all` with -j.
start_test "test-all target exists"
assert_contains "test-all" "$_targets"
start_test "test-lint target exists"
assert_contains "test-lint" "$_targets"
start_test "test-nu-parse target exists"
assert_contains "test-nu-parse" "$_targets"
start_test "test-nu-config target exists"
assert_contains "test-nu-config" "$_targets"
start_test "test-shrc-dash target exists"
assert_contains "test-shrc-dash" "$_targets"
start_test "test-shrc-bash target exists"
assert_contains "test-shrc-bash" "$_targets"
start_test "test-shrc-vcs target exists"
assert_contains "test-shrc-vcs" "$_targets"
start_test "test-shrc-prompt target exists"
assert_contains "test-shrc-prompt" "$_targets"
start_test "test-shrc-fish target exists"
assert_contains "test-shrc-fish" "$_targets"
start_test "test-shrc-fish-prompt target exists"
assert_contains "test-shrc-fish-prompt" "$_targets"
start_test "test-gitconfig target exists"
assert_contains "test-gitconfig" "$_targets"
start_test "test-makefile target exists"
assert_contains "test-makefile" "$_targets"
start_test "test-amethyst target exists"
assert_contains "test-amethyst" "$_targets"

# Test that test-all depends on every per-test sub-target so that a single
# `make test-all` invocation covers the full test suite.
    start_test "test-all depends on $_sub"
_test_all_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null | grep '^test-all:')
for _sub in test-lint test-nu-parse test-nu-config \
            test-shrc-dash test-shrc-bash \
            test-shrc-vcs \
            test-shrc-prompt test-shrc-fish test-shrc-fish-prompt \
            test-gitconfig test-makefile test-amethyst; do
    assert_contains "$_sub" "$_test_all_deps"
done
unset _sub

# Test that `make test` dispatches to the parallel build. We check the recipe
# rather than running it to avoid recursion and to keep the test fast.
start_test "test recipe invokes parallel make"
_test_recipe=$(make -C "$_srcdir" -n test 2>/dev/null)
assert_contains "-j" "$_test_recipe"
start_test "test recipe targets test-all"
assert_contains "test-all" "$_test_recipe"

start_test "TEST_JOBS=1 uses -j 1"
_recipe_j1=$(make -C "$_srcdir" -n test TEST_JOBS=1 2>/dev/null)
assert_contains "-j 1" "$_recipe_j1"

# test-lint must gracefully skip fish when it's not installed (fish is
# optional, unlike shellcheck/dash/bash which are required). Verify by
# running test-lint under a PATH that hides fish and checking that a
# SKIP line appears instead of the recipe erroring out.
start_test "test-lint succeeds when fish is missing"
_bare_path="$_testdir/bare_bin"
mkdir -p "$_bare_path"
# Populate the stub directory with everything test-lint's required tools
# need (shellcheck, dash, bash, plus the shell builtins/coreutils the
# recipe itself calls). Omit `fish` so we exercise the skip branch.
for _tool in bash dash shellcheck make awk sed grep sh env cat command test nproc; do
    if _real=$(command -v "$_tool" 2>/dev/null); then
        ln -sf "$_real" "$_bare_path/$_tool"
    fi
done
_lint_out=$(PATH="$_bare_path" make -C "$_srcdir" test-lint 2>&1)
_lint_rc=$?
assert_equal "0" "$_lint_rc"
start_test "test-lint skips fish -n when missing"
assert_contains \
    "SKIP: fish" "$_lint_out"
rm -rf "$_bare_path"

test_summary "makefile"
