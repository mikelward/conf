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

# After a pull or rebase that changed config/hypr, the hooks reload Hyprland
# when it's running, so an autoreload that caught a file mid-rewrite clears.
_fake_conf="$_testdir/fake_conf_reload"
_stub_bin="$_testdir/reload_stub_bin"
_reload_log="$_testdir/reload_called"
rm -rf "$_fake_conf" "$_stub_bin"
mkdir -p "$_fake_conf/config/hypr" "$_stub_bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\n' "$_reload_log" >"$_stub_bin/hyprctl"
chmod +x "$_stub_bin/hyprctl"
(
    cd "$_fake_conf" &&
        git init -q &&
        git config user.email test@example.com && git config user.name test &&
        echo one >config/hypr/hyprland.lua && echo a >README && git add . &&
        git commit -qm one &&
        echo two >config/hypr/hyprland.lua && git commit -qam two &&
        echo b >README && git commit -qam three
)
# Hyprland reads its config from this checkout, through confinst's links.
_saved_xdg_config_home=${XDG_CONFIG_HOME-unset}
XDG_CONFIG_HOME="$_testdir/reload_xdg"
export XDG_CONFIG_HOME
mkdir -p "$XDG_CONFIG_HOME/hypr"
ln -sf "$_fake_conf/config/hypr/hyprland.lua" "$XDG_CONFIG_HOME/hypr/hyprland.lua"
# run_hook HOOK FROM [ENV...]: runs the hook as if HEAD had moved from FROM.
run_hook() {
    _hook=$1
    _from=$2
    shift 2
    rm -f "$_reload_log"
    (cd "$_fake_conf" && git update-ref ORIG_HEAD "$_from" &&
        env PATH="$_stub_bin:$PATH" "$@" sh "$_srcdir/gittemplates/hooks/$_hook" rebase)
}
start_test "post-merge reloads Hyprland after a pull that changed config/hypr"
run_hook post-merge HEAD~2 HYPRLAND_INSTANCE_SIGNATURE=x
assert_equal "reload" "$(cat "$_reload_log" 2>/dev/null)"
start_test "post-rewrite reloads Hyprland after a rebase that changed config/hypr"
run_hook post-rewrite HEAD~2 HYPRLAND_INSTANCE_SIGNATURE=x
assert_equal "reload" "$(cat "$_reload_log" 2>/dev/null)"
start_test "post-merge reloads Hyprland after any pull in conf"
run_hook post-merge HEAD~1 HYPRLAND_INSTANCE_SIGNATURE=x
assert_equal "reload" "$(cat "$_reload_log" 2>/dev/null)"
start_test "post-merge leaves Hyprland alone outside conf"
rm -f "$_reload_log"
(cd "$_testdir" && mkdir -p not_conf && cd not_conf && env PATH="$_stub_bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=x sh "$_srcdir/gittemplates/hooks/post-merge")
assert_false test -f "$_reload_log"
rmdir "$_testdir/not_conf"
start_test "post-merge leaves Hyprland alone in a repo with its own config/hypr"
rm -f "$_reload_log"
(cd "$_testdir" && mkdir -p other/config/hypr && echo x >other/config/hypr/hyprland.lua && cd other &&
    env PATH="$_stub_bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=x sh "$_srcdir/gittemplates/hooks/post-merge")
assert_false test -f "$_reload_log"
rm -rf "$_testdir/other"
start_test "post-merge leaves Hyprland alone outside a Hyprland session"
run_hook post-merge HEAD~2 HYPRLAND_INSTANCE_SIGNATURE=
assert_false test -f "$_reload_log"
# A rebase that replays a local config/hypr change onto an unrelated
# upstream commit leaves the tips equal there, but rewrote the file.
(
    cd "$_fake_conf" &&
        _upstream=$(git symbolic-ref --short HEAD) &&
        git checkout -q -b local HEAD~1 &&
        echo mine >config/hypr/hyprland.lua && git commit -qam mine &&
        git branch -q before-rebase &&
        git rebase -q "$_upstream"
)
start_test "the rebase left config/hypr the same at both tips"
assert_true sh -c "cd '$_fake_conf' && git diff --quiet before-rebase HEAD -- config/hypr"
start_test "post-rewrite reloads after a rebase replayed a config/hypr change"
run_hook post-rewrite before-rebase HYPRLAND_INSTANCE_SIGNATURE=x
assert_equal "reload" "$(cat "$_reload_log" 2>/dev/null)"
# A rebase with nothing to replay only fast-forwards: git runs
# post-checkout and no post-rewrite. Drive it through git itself.
(
    cd "$_fake_conf" &&
        _upstream=$(git symbolic-ref --short HEAD) &&
        git checkout -q -b behind "$_upstream~1" &&
        git config core.hooksPath "$_srcdir/gittemplates/hooks"
)
start_test "a fast-forward rebase reloads Hyprland"
rm -f "$_reload_log"
(cd "$_fake_conf" && env PATH="$_stub_bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=x git rebase -q local)
assert_true test -s "$_reload_log"
start_test "post-checkout leaves Hyprland alone outside a Hyprland session"
rm -f "$_reload_log"
(cd "$_fake_conf" && env PATH="$_stub_bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE= sh "$_srcdir/gittemplates/hooks/post-checkout" HEAD HEAD 1)
assert_false test -f "$_reload_log"
# A pull that stops on a conflict runs no post-merge; finishing it with
# `git commit` runs post-commit, as a merge commit. The setup runs the
# hooks too, so it keeps them away from a real Hyprland session.
(
    HYPRLAND_INSTANCE_SIGNATURE= && export HYPRLAND_INSTANCE_SIGNATURE &&
        cd "$_fake_conf" &&
        git checkout -q -b theirs behind &&
        echo theirs >README && echo new >config/hypr/hyprland.lua &&
        git commit -qam theirs &&
        git checkout -q -b ours behind &&
        echo ours >README && git commit -qam ours
)
(cd "$_fake_conf" && env PATH="$_stub_bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=x git merge -q theirs >/dev/null 2>&1)
start_test "a conflicted merge stops before any reload"
assert_false test -f "$_reload_log"
rm -f "$_reload_log"
(cd "$_fake_conf" && echo both >README && git add README &&
    env PATH="$_stub_bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=x git commit -q --no-edit)
start_test "committing the resolved merge reloads Hyprland"
assert_true test -s "$_reload_log"
start_test "a plain commit doesn't reload Hyprland"
rm -f "$_reload_log"
(cd "$_fake_conf" && echo more >README && env PATH="$_stub_bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE=x git commit -qam more)
assert_false test -f "$_reload_log"
# A failed vcs pull still fails the hook, reload check or not.
mkdir -p "$_fake_conf/vcs/.git"
cat >"$_stub_bin/git" <<EOF
#!/bin/sh
if test "\$1" = -C && test "\$2" = vcs && test "\$3" = pull; then
    exit 1
fi
exec "$(command -v git)" "\$@"
EOF
chmod +x "$_stub_bin/git"
start_test "post-merge still fails when the vcs pull fails"
run_hook post-merge HEAD~1 HYPRLAND_INSTANCE_SIGNATURE=
assert_equal "1" "$?"
start_test "post-rewrite still fails when the vcs pull fails"
run_hook post-rewrite HEAD~1 HYPRLAND_INSTANCE_SIGNATURE=
assert_equal "1" "$?"
rm -rf "$_fake_conf" "$_stub_bin" "$_reload_log" "$XDG_CONFIG_HOME"
if test "$_saved_xdg_config_home" = unset; then
    unset XDG_CONFIG_HOME
else
    XDG_CONFIG_HOME=$_saved_xdg_config_home
fi

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

# A suite asserting on a file it never sources -- inputrc, the atuin
# config -- still has to re-run when that file changes. Without the
# dependency the stamp stays fresh and `make test` reports a pass for a
# setting nothing looked at.
start_test "test-bash stamp depends on the files its tests assert on"
_test_bash_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null |
    grep '^\.test-cache/test-bash\.stamp:')
assert_contains "inputrc" "$_test_bash_deps"
assert_contains "config/atuin/config.toml" "$_test_bash_deps"

start_test "test-zsh stamp depends on the atuin config too"
# shrc_test.sh runs under both shells, so the assertion exists in both.
_test_zsh_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null |
    grep '^\.test-cache/test-zsh\.stamp:')
assert_contains "config/atuin/config.toml" "$_test_zsh_deps"

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
            test-gitconfig test-makefile test-amethyst \
            test-claude-settings; do
    start_test "$_sub target exists"
    assert_contains "$_sub" "$_targets"
done
unset _sub

# Test that test-all depends on every per-topic sub-target so that a single
# `make test-all` invocation covers the full test suite.
_test_all_deps=$(make -C "$_srcdir" -pRrq 2>/dev/null | grep '^test-all:')
for _sub in test-dash test-bash test-zsh test-prompt test-vcs \
            test-fish test-nu test-lint \
            test-gitconfig test-makefile test-amethyst \
            test-claude-settings; do
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

# The prompt timing runs alone, after the parallel suites, so their load
# can't land on it.
start_test "test recipe runs test-prompt-perf after test-all"
_perf_line=$(printf '%s\n' "$_test_recipe" | grep -n 'test-prompt-perf' | head -n 1 | cut -d: -f1)
_all_line=$(printf '%s\n' "$_test_recipe" | grep -n 'test-all' | head -n 1 | cut -d: -f1)
assert_true test -n "$_perf_line"
assert_true test "${_perf_line:-0}" -gt "${_all_line:-0}"
start_test "test-all leaves out test-prompt-perf"
assert_not_contains "test-prompt-perf" "$_test_all_deps"

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

# test-claude-settings skips when python3 is missing, and must not stamp
# itself on the way past — a stamp written by the skip branch would mark the
# suite green on a machine that never ran it.
start_test "test-claude-settings succeeds when python3 is missing"
_nopy_path="$_testdir/nopy_bin"
mkdir -p "$_nopy_path"
for _tool in sh make awk sed grep env cat command test mkdir touch echo; do
    if _real=$(command -v "$_tool" 2>/dev/null); then
        ln -sf "$_real" "$_nopy_path/$_tool"
    fi
done
# Point the nested make at its own CACHE. The real one is shared with the
# test-claude-settings target that `make -j` may be running right now, so
# deleting its stamp here would either race the assertion below or throw away
# a valid cache entry.
_nopy_cache="$_testdir/nopy_cache"
rm -rf "$_nopy_cache"
_settings_stamp="$_nopy_cache/test-claude-settings.stamp"
_nopy_out=$(PATH="$_nopy_path" make -B -C "$_srcdir" CACHE="$_nopy_cache" test-claude-settings 2>&1)
_nopy_rc=$?
assert_equal "0" "$_nopy_rc"
start_test "test-claude-settings prints SKIP when python3 is missing"
assert_contains "SKIP: test-claude-settings" "$_nopy_out"
start_test "the skip branch leaves no stamp behind"
assert_false test -e "$_settings_stamp"
rm -rf "$_nopy_path" "$_nopy_cache"
unset _tool _real

test_summary "makefile"
