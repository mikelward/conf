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
start_test "bootstrap target exists"
assert_contains "bootstrap" "$_targets"
start_test "vcs-build target exists"
assert_contains "vcs-build" "$_targets"
start_test "vcs-sync target exists"
assert_contains "vcs-sync" "$_targets"
start_test "vcs-fetch target exists"
assert_contains "vcs-fetch" "$_targets"
start_test "test target exists"
assert_contains "test" "$_targets"
start_test "test-full target exists"
assert_contains "test-full" "$_targets"

# vcs-sync is the setup target: it wires repo-local hooksPath and
# clones vcs (or pulls it) as a plain directory under conf/.
_vcs_sync_recipe=$(make -C "$_srcdir" -n vcs-sync 2>/dev/null)
start_test "vcs-sync wires up core.hooksPath"
assert_contains "core.hooksPath gittemplates/hooks" "$_vcs_sync_recipe"
start_test "vcs-sync clones or pulls vcs"
assert_contains "git -C vcs pull" "$_vcs_sync_recipe"
# `git -C vcs rev-parse --git-dir` walks up to the parent conf repo when
# vcs/ exists as a plain directory, which would silently `pull` from
# conf instead of cloning vcs. Guard with a vcs/.git existence test.
start_test "vcs-sync does not rely on git rev-parse for the existence check"
assert_not_contains "rev-parse" "$_vcs_sync_recipe"
start_test "vcs-sync guards on vcs/.git so a plain vcs/ dir triggers a clone"
assert_contains "vcs/.git" "$_vcs_sync_recipe"
_vcs_fetch_recipe=$(make -C "$_srcdir" -n vcs-fetch 2>/dev/null)
start_test "vcs-fetch remains a compatibility alias for vcs-sync"
assert_equal "$_vcs_sync_recipe" "$_vcs_fetch_recipe"

# End-to-end: drive vcs-sync against a fake conf repo whose vcs/ is a
# plain (non-checkout) directory. The bug was that `git -C vcs rev-parse
# --git-dir` succeeded by walking up to the parent conf repo, so the
# recipe took the pull branch and ran `git -C vcs pull` against conf
# instead of cloning vcs. The fixed recipe must take the clone branch.
# Stub `git clone` so the test doesn't hit the network: a stub on PATH
# records its argv to a sentinel file and exits 0 without doing
# anything, then we assert the sentinel was written.
start_test "vcs-sync clones when vcs/ exists but is not a git checkout"
_fake_conf="$_testdir/fake_conf_no_vcs_checkout"
rm -rf "$_fake_conf"
mkdir -p "$_fake_conf/vcs"
(cd "$_fake_conf" && git init -q && git config core.hooksPath gittemplates/hooks)
# Smoke-check the bug premise: rev-parse from inside vcs/ should walk
# up and succeed against the parent fake conf repo.
(cd "$_fake_conf/vcs" && git rev-parse --git-dir >/dev/null 2>&1)
assert_equal "0" "$?"
cp "$_srcdir/Makefile" "$_fake_conf/Makefile"
_stub_bin="$_testdir/vcs_sync_stub_bin"
mkdir -p "$_stub_bin"
_clone_log="$_testdir/vcs_sync_clone_called"
_pull_log="$_testdir/vcs_sync_pull_called"
rm -f "$_clone_log" "$_pull_log"
# Wrap git so `git clone ...` and `git -C vcs pull` go to sentinels but
# everything else (rev-parse, config, etc.) reaches the real git.
_real_git=$(command -v git)
cat >"$_stub_bin/git" <<EOF
#!/bin/sh
if test "\$1" = clone; then
    printf '%s\n' "\$*" >"$_clone_log"
    exit 0
fi
if test "\$1" = -C && test "\$2" = vcs && test "\$3" = pull; then
    printf '%s\n' "\$*" >"$_pull_log"
    exit 0
fi
exec "$_real_git" "\$@"
EOF
chmod +x "$_stub_bin/git"
PATH="$_stub_bin:$PATH" make -C "$_fake_conf" vcs-sync >/dev/null 2>&1
assert_true test -f "$_clone_log"
start_test "vcs-sync does not pull when vcs/ is not a git checkout"
assert_false test -f "$_pull_log"
rm -rf "$_fake_conf" "$_stub_bin" "$_clone_log" "$_pull_log"

_post_merge=$(sed -n '1,80p' "$_srcdir/gittemplates/hooks/post-merge")
_post_rewrite=$(sed -n '1,80p' "$_srcdir/gittemplates/hooks/post-rewrite")
start_test "post-merge pulls vcs to its remote HEAD"
assert_contains "git -C vcs pull" "$_post_merge"
start_test "post-rewrite pulls vcs to its remote HEAD"
assert_contains "git -C vcs pull" "$_post_rewrite"
# Same parent-discovery guard as in the Makefile recipe -- the hooks
# must not delegate the existence check to `git rev-parse`. Strip
# comments before asserting so the rationale comment (which mentions
# rev-parse) doesn't satisfy assert_not_contains by accident.
_post_merge_code=$(printf '%s\n' "$_post_merge" | sed 's/[[:space:]]*#.*$//')
_post_rewrite_code=$(printf '%s\n' "$_post_rewrite" | sed 's/[[:space:]]*#.*$//')
start_test "post-merge guards on vcs/.git so a plain vcs/ dir is skipped"
assert_contains "vcs/.git" "$_post_merge_code"
assert_not_contains "rev-parse" "$_post_merge_code"
start_test "post-rewrite guards on vcs/.git so a plain vcs/ dir is skipped"
assert_contains "vcs/.git" "$_post_rewrite_code"
assert_not_contains "rev-parse" "$_post_rewrite_code"

# End-to-end: run the post-merge hook itself with cwd inside a fake conf
# whose vcs/ is a plain directory and assert the hook does NOT call
# `git -C vcs pull`. Same git stub trick as the vcs-sync test above.
start_test "post-merge does not pull when vcs/ is not a git checkout"
_fake_conf="$_testdir/fake_conf_post_merge"
rm -rf "$_fake_conf"
mkdir -p "$_fake_conf/vcs"
(cd "$_fake_conf" && git init -q)
_stub_bin="$_testdir/post_merge_stub_bin"
mkdir -p "$_stub_bin"
_pull_log="$_testdir/post_merge_pull_called"
rm -f "$_pull_log"
_real_git=$(command -v git)
cat >"$_stub_bin/git" <<EOF
#!/bin/sh
if test "\$1" = -C && test "\$2" = vcs && test "\$3" = pull; then
    printf '%s\n' "\$*" >"$_pull_log"
    exit 0
fi
exec "$_real_git" "\$@"
EOF
chmod +x "$_stub_bin/git"
(cd "$_fake_conf" && PATH="$_stub_bin:$PATH" sh "$_srcdir/gittemplates/hooks/post-merge")
assert_false test -f "$_pull_log"
rm -rf "$_fake_conf" "$_stub_bin" "$_pull_log"

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
_vcs_build_recipe=$(make -C "$_srcdir" -n vcs-build 2>/dev/null)
start_test "vcs-build delegates directly to the vcs Makefile"
assert_contains "make -C vcs" "$_vcs_build_recipe"
start_test "vcs-build does not reuse the parent vcs/vcs freshness check"
assert_not_contains "make vcs/vcs" "$_vcs_build_recipe"
# Once vcs is cloned, vcs-build must not hit the network on every
# invocation -- staying current is the post-merge/post-rewrite hook
# chain's job. Verified by checking that no clone/pull/hooks-config
# commands appear in `make -n`'s recipe trace when vcs/Makefile already
# exists. (`make test` ensures vcs/ is cloned before this test runs.)
_default_recipe=$(make -C "$_srcdir" -n 2>/dev/null)
start_test "bare make does not run confinst"
assert_not_contains "confinst" "$_default_recipe"
start_test "bare make does not run install-vcs"
assert_not_contains "install-vcs" "$_default_recipe"
start_test "bare make does not pull vcs"
assert_not_contains "git -C vcs pull" "$_default_recipe"
start_test "bare make does not reconfigure repo hooks"
assert_not_contains "core.hooksPath" "$_default_recipe"

# install-vcs must explicitly pull vcs to its remote HEAD before
# installing, so installers always ship the latest even when conf
# hasn't been pulled recently (the default `make` path deliberately
# skips that fetch). install-vcs sequences vcs-sync, vcs-build, and
# `make -C vcs install` via sub-make so `make -j install-vcs` doesn't
# race the clone/pull against the build.
_install_vcs_recipe=$(make -C "$_srcdir" -n install-vcs 2>/dev/null)
start_test "install-vcs runs vcs-sync to ship the latest vcs"
assert_contains "git -C vcs pull" "$_install_vcs_recipe"
start_test "install-vcs runs vcs-build"
assert_contains "make vcs-build" "$_install_vcs_recipe"
start_test "install-vcs runs the vcs install"
assert_contains "make -C vcs install" "$_install_vcs_recipe"

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
