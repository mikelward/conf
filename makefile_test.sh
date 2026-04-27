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
start_test "vcs-fetch target exists"
assert_contains "vcs-fetch" "$_targets"
start_test "test target exists"
assert_contains "test" "$_targets"
start_test "test-full target exists"
assert_contains "test-full" "$_targets"

# vcs-fetch is the network-doing target: it tracks the vcs submodule's
# main HEAD and wires up core.hooksPath so post-merge / post-rewrite
# fire. vcs-build composes vcs-fetch + the binary build.
_vcs_fetch_recipe=$(make -C "$_srcdir" -n vcs-fetch 2>/dev/null)
start_test "vcs-fetch uses --remote to track main HEAD"
assert_contains "submodule update --remote" "$_vcs_fetch_recipe"
start_test "vcs-fetch wires up core.hooksPath"
assert_contains "core.hooksPath gittemplates/hooks" "$_vcs_fetch_recipe"

# Bare `make` (no target) must build, not install. Verify the default
# target is `all`, that `all` depends on vcs-build, and that its recipe
# does NOT invoke the install-* targets.
start_test "default target is all"
# `vcs-build`'s recipe uses `$(MAKE) ...`, which `make -pRrq` follows
# into sub-makes -- producing a second copy of the database (and a
# second `.DEFAULT_GOAL := all` line). sort -u dedupes; if the parent
# and child ever disagreed we'd see the conflict instead of silently
# picking one.
_default_target=$(make -C "$_srcdir" -pRrq 2>/dev/null |
    sed -n 's/^\.DEFAULT_GOAL := //p' | sort -u)
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

# test-vcs's stamp depends on the real-file vcs/vcs binary (not on the
# PHONY vcs-build), so `make test` doesn't trigger a network fetch --
# only an actual binary change re-triggers it.
start_test "test-vcs stamp depends on vcs/vcs"
_test_vcs_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null |
    grep '^\.test-cache/test-vcs\.stamp:')
assert_contains "vcs/vcs" "$_test_vcs_deps"
start_test "test-vcs stamp does not depend on vcs-build"
assert_not_contains "vcs-build" "$_test_vcs_deps"

# test-full must wipe the stamp cache before delegating to test, so a
# `make test-full` invocation always re-runs every test even if stamps
# would otherwise be up-to-date.
_test_full_recipe=$(make -C "$_srcdir" -n test-full 2>/dev/null)
start_test "test-full wipes the stamp cache"
assert_contains "rm -rf .test-cache" "$_test_full_recipe"
start_test "test-full delegates to test"
assert_contains "test" "$_test_full_recipe"

# Test that per-topic sub-targets exist so `make -j` can schedule them in
# parallel. test-all aggregates them and `test` dispatches to test-all
# with -j.
start_test "test-all target exists"
assert_contains "test-all" "$_targets"
for _sub in test-dash test-bash test-zsh test-prompt test-vcs \
            test-fish test-nu test-lint \
            test-gitconfig test-makefile test-amethyst; do
    start_test "$_sub target exists"
    assert_contains "$_sub" "$_targets"
done
unset _sub

# Test that test-all depends on every per-topic sub-target so that a single
# `make test-all` invocation covers the full test suite.
_test_all_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null | grep '^test-all:')
for _sub in test-dash test-bash test-zsh test-prompt test-vcs \
            test-fish test-nu test-lint \
            test-gitconfig test-makefile test-amethyst; do
    start_test "test-all depends on $_sub"
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

# test-fish must gracefully skip when fish isn't installed (fish is
# optional). Verify by running test-fish under a PATH that hides fish
# and checking that a SKIP line appears instead of the recipe erroring
# out. test-fish bundles the fish syntax check (fish -n) and the bash
# behavioral drivers; both rely on `command -v fish` for skip-detect.
start_test "test-fish succeeds when fish is missing"
_bare_path="$_testdir/bare_bin"
mkdir -p "$_bare_path"
# Populate the stub directory with everything the recipe itself calls
# (shell builtins/coreutils, plus bash for the behavioral drivers).
# Omit `fish` so we exercise the skip branch.
for _tool in bash dash make awk sed grep sh env cat command test nproc mkdir touch; do
    if _real=$(command -v "$_tool" 2>/dev/null); then
        ln -sf "$_real" "$_bare_path/$_tool"
    fi
done
# -B forces the recipe to run even if the stamp is up-to-date from a
# prior invocation, otherwise we'd assert against an empty "Nothing to
# be done" message instead of the SKIP line we want to see.
_fish_out=$(PATH="$_bare_path" make -B -C "$_srcdir" test-fish 2>&1)
_fish_rc=$?
assert_equal "0" "$_fish_rc"
start_test "test-fish prints SKIP when fish is missing"
assert_contains "SKIP: test-fish" "$_fish_out"
rm -rf "$_bare_path"

test_summary "makefile"
