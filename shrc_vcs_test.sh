#!/bin/bash
#
# Tests for shrc.vcs. Covers both the thin wrappers (which delegate to
# the `vcs` Go binary from the mikelward/vcs submodule, already present
# on PATH when run via `make test-shrc-vcs`) and the pure-shell helpers
# (clone dispatch, status_chars, target_relative_to, allknown, project)
# that don't require the binary. The per-VCS subcommand behaviour lives
# in the `vcs` binary and is tested there.
#
# Requires bash or zsh (uses here-strings).
#

source "$(dirname "$0")/shrc_test_lib.sh"

# The wrapper tests need the `vcs` binary on PATH. `make test-shrc-vcs`
# prepends $(CURDIR)/vcs so this is always true in CI. When running
# directly, mark the whole suite as skipped rather than emitting dozens
# of "command not found" failures.
if ! command -v vcs >/dev/null 2>&1; then
    skip_all "vcs binary not on PATH (run 'make test-shrc-vcs' or 'make vcs-build')"
    test_summary "shrc_vcs"
    exit 0
fi

# Define have_command as a plain PATH lookup. shrc.vcs expects shrc to
# have defined it; we haven't sourced shrc here (only shrc.vcs below),
# so provide a minimal real-command lookup for the cp/mv/rm wrappers
# that call `command vcs detect`.
have_command() {
    command -v "$1" >/dev/null 2>&1
}

# Source shrc.vcs (provides target_relative_to and other functions)
# shellcheck source=shrc.vcs
source "$_srcdir/shrc.vcs" >/dev/null 2>&1

###############
# Test vcs detection

start_test "vcs detects git repo"
mkdir -p "$_testdir/gitrepo/subdir"
mkdir "$_testdir/gitrepo/.git"
result=$(cd "$_testdir/gitrepo" && vcs)
assert_equal "git" "$result"

start_test "vcs detects hg repo"
mkdir -p "$_testdir/hgrepo"
mkdir "$_testdir/hgrepo/.hg"
result=$(cd "$_testdir/hgrepo" && vcs)
assert_equal "hg" "$result"

start_test "vcs detects jj repo"
mkdir -p "$_testdir/jjrepo"
mkdir "$_testdir/jjrepo/.jj"
result=$(cd "$_testdir/jjrepo" && vcs)
assert_equal "jj" "$result"

# Test no vcs. The binary prints "vcs: no version control system
# detected" on stderr for detect failures; capture stderr separately so
# it doesn't leak into the test output.
start_test "vcs returns empty for no repo"
mkdir -p "$_testdir/norepo"
result=$(cd "$_testdir/norepo" && vcs 2>/dev/null)
assert_equal "" "$result"
start_test "vcs returns false for no repo"
(cd "$_testdir/norepo" && vcs 2>/dev/null)
assert_equal "1" "$?"

# rootdir() redirects stderr internally so the preprompt doesn't leak
# "vcs: no version control system detected" every prompt.
start_test "rootdir silent on stderr outside repo"
_stderr=$(cd "$_testdir/norepo" && rootdir 2>&1 >/dev/null)
assert_equal "" "$_stderr"

start_test "vcs detects git from subdir"
result=$(cd "$_testdir/gitrepo/subdir" && vcs)
assert_equal "git" "$result"

start_test "vcs creates .vcs_cache"
assert_true test -f "$_testdir/gitrepo/.vcs_cache"

start_test "vcs uses cache on second call"
result=$(cd "$_testdir/gitrepo" && vcs)
assert_equal "git" "$result"

###############
# Test vcs_backend and vcs_hosting

# git repo should have git backend
start_test "vcs_backend returns git for git repo"
rm -f "$_testdir/gitrepo/.vcs_cache"
result=$(cd "$_testdir/gitrepo" && vcs_backend)
assert_equal "git" "$result"

# hg repo has no backend (cache uses - sentinel)
start_test "vcs_backend returns empty for hg repo"
rm -f "$_testdir/hgrepo/.vcs_cache"
result=$(cd "$_testdir/hgrepo" && vcs_backend)
assert_equal "" "$result"
# Verify the sentinel is written to line 1 of cache
_cache_line1=$(head -1 "$_testdir/hgrepo/.vcs_cache")
start_test "hg cache uses - sentinel for backend"
assert_contains " - " "$_cache_line1"

# Helper: write a git config with a given origin URL into a jj repo's
# embedded git store. The vcs binary reads this config directly.
_write_jj_origin() {
    local _dir="$1"
    local _url="$2"
    mkdir -p "$_dir/.jj/repo/store/git"
    echo "git" > "$_dir/.jj/repo/store/type"
    if test -n "$_url"; then
        cat > "$_dir/.jj/repo/store/git/config" <<EOF
[remote "origin"]
	url = $_url
EOF
    fi
}

# jj repo with git backend + github remote
start_test "vcs_backend returns git for jj-git repo"
_write_jj_origin "$_testdir/jjrepo" "https://github.com/user/repo.git"
rm -f "$_testdir/jjrepo/.vcs_cache"
result=$(cd "$_testdir/jjrepo" && vcs_backend)
assert_equal "git" "$result"
result=$(cd "$_testdir/jjrepo" && vcs_hosting)
start_test "vcs_hosting returns github for github remote"
assert_equal "github" "$result"

# jj repo with gerrit remote
start_test "vcs_hosting returns gerrit for googlesource remote"
_write_jj_origin "$_testdir/jjrepo_gerrit" "https://chromium.googlesource.com/foo/bar"
result=$(cd "$_testdir/jjrepo_gerrit" && vcs_hosting)
assert_equal "gerrit" "$result"

# jj repo with gitlab remote
start_test "vcs_hosting returns gitlab for gitlab.com remote"
_write_jj_origin "$_testdir/jjrepo_gitlab" "https://gitlab.com/user/repo.git"
result=$(cd "$_testdir/jjrepo_gitlab" && vcs_hosting)
assert_equal "gitlab" "$result"

# self-hosted gitlab
start_test "vcs_hosting returns gitlab for self-hosted gitlab"
_write_jj_origin "$_testdir/jjrepo_gitlab_self" "https://gitlab.mycompany.com/group/repo.git"
result=$(cd "$_testdir/jjrepo_gitlab_self" && vcs_hosting)
assert_equal "gitlab" "$result"

# jj repo with bitbucket remote
start_test "vcs_hosting returns bitbucket for bitbucket remote"
_write_jj_origin "$_testdir/jjrepo_bitbucket" "https://bitbucket.org/user/repo.git"
result=$(cd "$_testdir/jjrepo_bitbucket" && vcs_hosting)
assert_equal "bitbucket" "$result"

# jj repo with sourcehut remote
start_test "vcs_hosting returns sourcehut for sr.ht remote"
_write_jj_origin "$_testdir/jjrepo_srht" "https://git.sr.ht/~user/repo"
result=$(cd "$_testdir/jjrepo_srht" && vcs_hosting)
assert_equal "sourcehut" "$result"

# jj repo with no origin remote
start_test "vcs_hosting returns empty for no remote"
_write_jj_origin "$_testdir/jjrepo_noremote" ""
result=$(cd "$_testdir/jjrepo_noremote" && vcs_hosting)
assert_equal "" "$result"

# jj repo with non-git backend
start_test "vcs_backend returns piper for piper backend"
mkdir -p "$_testdir/jjrepo_piper/.jj/repo/store"
echo "piper" > "$_testdir/jjrepo_piper/.jj/repo/store/type"
result=$(cd "$_testdir/jjrepo_piper" && vcs_backend)
assert_equal "piper" "$result"
result=$(cd "$_testdir/jjrepo_piper" && vcs_hosting)
start_test "vcs_hosting returns empty for non-git backend"
assert_equal "" "$result"

# Verify cache format: line 1 has 3 fields, line 2 has rootdir
start_test "vcs_cache line 1 contains backend"
rm -f "$_testdir/jjrepo/.vcs_cache"
(cd "$_testdir/jjrepo" && vcs >/dev/null)
_cache_line1=$(head -1 "$_testdir/jjrepo/.vcs_cache")
_cache_line2=$(sed -n '2p' "$_testdir/jjrepo/.vcs_cache")
assert_contains "git" "$_cache_line1"
start_test "vcs_cache line 1 contains hosting"
assert_contains "github" "$_cache_line1"
_field_count=$(echo "$_cache_line1" | awk '{print NF}')
start_test "vcs_cache line 1 has 3 fields (all set)"
assert_equal "3" "$_field_count"
start_test "vcs_cache line 2 is rootdir"
assert_equal "$_testdir/jjrepo" "$_cache_line2"

# Verify cache has 3 fields on line 1 even when backend and hosting are empty
start_test "vcs_cache line 1 has 3 fields (sentinels)"
rm -f "$_testdir/hgrepo/.vcs_cache"
(cd "$_testdir/hgrepo" && vcs >/dev/null)
_cache_line1=$(head -1 "$_testdir/hgrepo/.vcs_cache")
_field_count=$(echo "$_cache_line1" | awk '{print NF}')
assert_equal "3" "$_field_count"
start_test "hg cache line 1 ends with - -"
assert_contains "- -" "$_cache_line1"

# Verify cache has 3 fields on line 1 when only hosting is empty
start_test "vcs_cache line 1 has 3 fields (hosting sentinel)"
rm -f "$_testdir/jjrepo_noremote/.vcs_cache"
(cd "$_testdir/jjrepo_noremote" && vcs >/dev/null)
_cache_line1=$(head -1 "$_testdir/jjrepo_noremote/.vcs_cache")
_field_count=$(echo "$_cache_line1" | awk '{print NF}')
assert_equal "3" "$_field_count"
start_test "git backend with no hosting ends with -"
assert_contains "git -" "$_cache_line1"

start_test "vcs detects git in path with spaces"
mkdir -p "$_testdir/path with spaces/subdir"
mkdir "$_testdir/path with spaces/.git"
result=$(cd "$_testdir/path with spaces" && vcs)
assert_equal "git" "$result"
result=$(cd "$_testdir/path with spaces" && rootdir)
start_test "rootdir works with spaces in path"
assert_equal "$_testdir/path with spaces" "$result"
result=$(cd "$_testdir/path with spaces" && vcs_backend)
start_test "vcs_backend works with spaces in path"
assert_equal "git" "$result"
result=$(cd "$_testdir/path with spaces/subdir" && rootdir)
start_test "rootdir from subdir works with spaces"
assert_equal "$_testdir/path with spaces" "$result"
result=$(cd "$_testdir/path with spaces/subdir" && rootdir "file.txt")
start_test "rootdir with arg works with spaces"
assert_equal "$_testdir/path with spaces/file.txt" "$result"

start_test "vcs detects git in path with backslash"
mkdir -p "$_testdir/back\\slash"
mkdir "$_testdir/back\\slash/.git"
result=$(cd "$_testdir/back\\slash" && vcs)
assert_equal "git" "$result"
result=$(cd "$_testdir/back\\slash" && rootdir)
start_test "rootdir works with backslash in path"
assert_equal "$_testdir/back\\slash" "$result"

###############
# Test cv (clear vcs cache)

start_test "cv removes .vcs_cache"
(cd "$_testdir/gitrepo" && cv)
assert_false test -f "$_testdir/gitrepo/.vcs_cache"

###############
# Test rootdir

# Re-detect to create cache
start_test "rootdir returns repo root"
(cd "$_testdir/gitrepo/subdir" && vcs >/dev/null)
result=$(cd "$_testdir/gitrepo/subdir" && rootdir)
assert_equal "$_testdir/gitrepo" "$result"

start_test "rootdir with arg returns full path"
result=$(cd "$_testdir/gitrepo/subdir" && rootdir "file.txt")
assert_equal "$_testdir/gitrepo/file.txt" "$result"

start_test "rootdir with multiple args"
result=$(cd "$_testdir/gitrepo/subdir" && rootdir "a.txt" "b.txt")
expected="$_testdir/gitrepo/a.txt
$_testdir/gitrepo/b.txt"
assert_equal "$expected" "$result"

###############
# Test subdir

start_test "subdir returns path under root"
result=$(cd "$_testdir/gitrepo/subdir" && subdir)
assert_equal "subdir" "$result"

start_test "subdir at root returns empty"
result=$(cd "$_testdir/gitrepo" && subdir)
assert_equal "" "$result"

###############
# Test clone dispatch

# clone just dispatches based on URL pattern, stub out git/hg/jj
_clone_log=""
have_command() { return 0; }
jj() { _clone_log="jj $*"; }
hg() { _clone_log="hg $*"; }

start_test "clone dispatches .git to jj git clone"
clone https://github.com/foo/bar.git
assert_equal "jj git clone https://github.com/foo/bar.git" "$_clone_log"

start_test "clone dispatches /hg/ to hg"
_clone_log=""
clone https://hg.example.com/hg/repo
assert_equal "hg clone https://hg.example.com/hg/repo" "$_clone_log"

start_test "clone falls back to git when jj unavailable"
unset -f jj
have_command() { test "$1" != "jj"; }
confirm() { return 0; }
git() { _clone_log="git $*"; }
_clone_log=""
clone https://github.com/foo/bar.git
assert_equal "git clone https://github.com/foo/bar.git" "$_clone_log"

start_test "clone aborts when user declines git fallback"
confirm() { return 1; }
_clone_log=""
clone https://github.com/foo/bar.git
assert_equal "" "$_clone_log"

unset -f git hg jj have_command confirm
unset _clone_log

###############
# Test status_chars

# Stub status to return known output
start_test "status_chars extracts unique sorted chars"
status() {
    printf 'M  file1.txt\nA  file2.txt\n?? file3.txt\nM  file4.txt\n'
}
result=$(status_chars)
assert_equal "?? A M" "$result"

# Stub status returning clean
start_test "status_chars returns empty for clean"
status() { :; }
result=$(status_chars)
assert_equal "" "$result"

# Single status code
start_test "status_chars single modified file"
status() { printf 'M  file1.txt\n'; }
result=$(status_chars)
assert_equal "M" "$result"

# Only untracked files
start_test "status_chars only untracked"
status() { printf '?? file1.txt\n?? file2.txt\n'; }
result=$(status_chars)
assert_equal "??" "$result"

# Two-character status codes (e.g. git staged+unstaged)
start_test "status_chars two-char codes"
status() { printf 'AM file1.txt\nMM file2.txt\n'; }
result=$(status_chars)
assert_equal "AM MM" "$result"

# Status codes with ! (e.g. hg missing)
start_test "status_chars with ! status"
status() { printf '! file1.txt\nM file2.txt\n'; }
result=$(status_chars)
assert_equal "! M" "$result"

# Ignored files (!!) should be recognized
start_test "status_chars ignored and untracked"
status() { printf '!! ignored.txt\n?? untracked.txt\n'; }
result=$(status_chars)
assert_equal "!! ??" "$result"

# Lines with lowercase or non-matching first fields are filtered out
start_test "status_chars filters non-matching lines"
status() { printf 'M  file1.txt\nfoo bar.txt\n123 baz.txt\n'; }
result=$(status_chars)
assert_equal "M" "$result"

# Duplicate codes are deduplicated
start_test "status_chars deduplicates"
status() { printf 'A  f1\nA  f2\nA  f3\n'; }
result=$(status_chars)
assert_equal "A" "$result"

# Many distinct codes are sorted
start_test "status_chars sorts codes"
status() { printf 'R  f1\nD  f2\nA  f3\nM  f4\n'; }
result=$(status_chars)
assert_equal "A D M R" "$result"

unset -f status

###############
# Test allknown

# Stub unknown to return something
start_test "allknown prints unknown files"
unknown() { echo "untracked.txt"; }
result=$(allknown)
assert_equal "untracked.txt" "$result"
start_test "allknown returns false when files unknown"
allknown >/dev/null
assert_equal "1" "$?"

# Stub unknown to return nothing
start_test "allknown returns true when no unknown files"
unknown() { :; }
allknown >/dev/null
assert_equal "0" "$?"

unset -f unknown

###############
# Test target_relative_to

start_test "target_relative_to same parent"
result=$(target_relative_to "src/foo.txt" "src")
assert_equal "foo.txt" "$result"

start_test "target_relative_to sibling dir"
result=$(target_relative_to "src/foo.txt" "lib")
assert_equal "../src/foo.txt" "$result"

start_test "target_relative_to from dot"
result=$(target_relative_to "foo.txt" ".")
assert_equal "foo.txt" "$result"

start_test "target_relative_to nested"
result=$(target_relative_to "a/b/c" "a")
assert_equal "b/c" "$result"

###############
# Test project

# Stub projectroot
start_test "project returns basename of projectroot"
projectroot() { echo "/home/user/repos/myproject"; }
result=$(project)
assert_equal "myproject" "$result"
unset -f projectroot

###############
# Test rm/mv/cp use system commands outside a VCS repo.
# Routing predicate: "cwd is in a repo AND operand is inside it."
# Both halves false here -> system command.

start_test "rm uses command rm outside VCS"
mkdir -p "$_testdir/norepo2"
echo "rm-me" > "$_testdir/norepo2/rmfile.txt"
(cd "$_testdir/norepo2" && rm rmfile.txt)
assert_false test -f "$_testdir/norepo2/rmfile.txt"

start_test "mv uses command mv outside VCS"
echo "mv-me" > "$_testdir/norepo2/mvfile.txt"
(cd "$_testdir/norepo2" && mv mvfile.txt mvd.txt)
assert_true test -f "$_testdir/norepo2/mvd.txt"
start_test "mv removes original outside VCS"
assert_false test -f "$_testdir/norepo2/mvfile.txt"

start_test "cp uses command cp outside VCS"
echo "cp-me" > "$_testdir/norepo2/cpfile.txt"
(cd "$_testdir/norepo2" && cp cpfile.txt cpd.txt)
assert_true test -f "$_testdir/norepo2/cpd.txt"
start_test "cp keeps original outside VCS"
assert_true test -f "$_testdir/norepo2/cpfile.txt"

###############
# Test rm/mv/cp route by operand, not cwd: when cwd is inside a repo
# but the file being operated on lives outside any repo (or in a
# different one), the wrappers must use the system command rather
# than invoking `vcs remove` / `vcs move` / `vcs copy` on paths vcs
# doesn't track. gitrepo/.git was created earlier so cd'ing into it
# makes cwd's rootdir /testdir/gitrepo, and these operands are under
# siblings like /testdir/rm_outside -- outside that tree.

start_test "rm uses command rm when cwd in repo but file outside"
mkdir -p "$_testdir/rm_outside"
echo "rm-me-outside" > "$_testdir/rm_outside/outfile.txt"
(cd "$_testdir/gitrepo" && rm "$_testdir/rm_outside/outfile.txt")
assert_false \
    test -f "$_testdir/rm_outside/outfile.txt"

start_test "mv uses command mv when cwd in repo but file outside"
mkdir -p "$_testdir/mv_outside"
echo "mv-me-outside" > "$_testdir/mv_outside/outfile.txt"
(cd "$_testdir/gitrepo" && mv "$_testdir/mv_outside/outfile.txt" "$_testdir/mv_outside/outmoved.txt")
assert_true \
    test -f "$_testdir/mv_outside/outmoved.txt"
start_test "mv removes original when cwd in repo but file outside"
assert_false \
    test -f "$_testdir/mv_outside/outfile.txt"

start_test "cp uses command cp when cwd in repo but file outside"
mkdir -p "$_testdir/cp_outside"
echo "cp-me-outside" > "$_testdir/cp_outside/outfile.txt"
(cd "$_testdir/gitrepo" && cp "$_testdir/cp_outside/outfile.txt" "$_testdir/cp_outside/outcopied.txt")
assert_true \
    test -f "$_testdir/cp_outside/outcopied.txt"
start_test "cp keeps original when cwd in repo but file outside"
assert_true \
    test -f "$_testdir/cp_outside/outfile.txt"

###############
# Test that vcs-command errors surface instead of being silently
# masked. Before operand-based routing, the wrappers swallowed vcs
# stderr and fell through to the system command on any failure -- so
# a legitimate `vcs move` refusal (conflict, dest exists, backend
# error, ...) was indistinguishable from "not in a repo" and the
# filesystem quietly changed anyway.
#
# gitrepo has only an empty .git/ placeholder, so `git mv` from
# inside it fails for _any_ input. Under the operand-based routing
# the wrapper correctly routes to vcs (src is under cwd's rootdir),
# vcs move fails, and the source stays put -- proving the wrapper
# did NOT silently fall through to plain mv.

start_test "mv: source survives when vcs move fails inside repo"
echo "please-fail" > "$_testdir/gitrepo/vcs_err_src.txt"
(cd "$_testdir/gitrepo" && mv vcs_err_src.txt vcs_err_dst.txt) >/dev/null 2>&1
assert_true \
    test -f "$_testdir/gitrepo/vcs_err_src.txt"
start_test "mv: no silent fall-through to plain mv on vcs failure"
assert_false \
    test -f "$_testdir/gitrepo/vcs_err_dst.txt"
rm -f "$_testdir/gitrepo/vcs_err_src.txt"

# cp's "errors surface" case can't use a filesystem probe: vcs-git's
# `copy` is implemented as `cp` + `git add`, so the destination file
# gets created either way. Check the wrapper's exit status instead --
# on vcs failure it must propagate non-zero, whereas the old blind
# fallback returned 0 once plain cp succeeded.
start_test "cp: wrapper propagates vcs failure exit status"
echo "please-fail" > "$_testdir/gitrepo/vcs_err_cpsrc.txt"
(cd "$_testdir/gitrepo" && cp vcs_err_cpsrc.txt vcs_err_cpdst.txt) >/dev/null 2>&1
_cp_rc=$?
assert_false test "$_cp_rc" -eq 0
command rm -f "$_testdir/gitrepo/vcs_err_cpsrc.txt" "$_testdir/gitrepo/vcs_err_cpdst.txt"

start_test "rm: target survives when vcs remove fails inside repo"
echo "please-fail" > "$_testdir/gitrepo/vcs_err_rm.txt"
(cd "$_testdir/gitrepo" && rm vcs_err_rm.txt) >/dev/null 2>&1
assert_true \
    test -f "$_testdir/gitrepo/vcs_err_rm.txt"
command rm -f "$_testdir/gitrepo/vcs_err_rm.txt"

###############
# Flag handling: any argument starting with `-` makes the wrapper
# defer to the system command. The tests below check the CORRECTNESS
# invariant (flagged invocations don't silently misbehave) rather
# than the routing policy (plain vs vcs) -- whether `rm -r tracked/`
# or `cp -r tracked/` route through vcs is a judgement call that may
# change as the backends evolve, and locking it in here would produce
# a pure-policy regression on a future reconsideration.
#
# The load-bearing case is flag-value separation like `mv -t DESTDIR
# SRC`: an earlier heuristic-parser revision picked DESTDIR as the
# "first positional" and invoked `vcs move -t DESTDIR SRC`, which on
# a real git repo fails with "unknown option -t" and on the fake
# gitrepo here also fails -- leaving SRC in place instead of moving
# it. The bail-on-flags rule sidesteps the whole class of errors by
# letting the system command handle its own flags.

# DESTDIR placed inside the fake gitrepo so a heuristic parser that
# picked DESTDIR as "first positional" would route via `vcs move -t
# DESTDIR SRC`, which git mv rejects (no -t option). Under
# bail-on-flags the wrapper just runs `command mv -t DEST SRC`, which
# works regardless of whether DESTDIR is tracked.
start_test "mv -t DEST SRC: SRC lands in DEST"
mkdir -p "$_testdir/gitrepo/flag_mv_dest"
echo "move-me" > "$_testdir/flag_mv_src.txt"
(cd "$_testdir/gitrepo" && mv -t "$_testdir/gitrepo/flag_mv_dest" "$_testdir/flag_mv_src.txt") >/dev/null 2>&1
assert_true \
    test -f "$_testdir/gitrepo/flag_mv_dest/flag_mv_src.txt"
start_test "mv -t DEST SRC: SRC gone from original location"
assert_false \
    test -f "$_testdir/flag_mv_src.txt"

# Combined short flags: `rm -rf` must not fail on the stacked form
# and must actually remove the target (whether via vcs or plain).
start_test "rm -rf on dir: target gone"
mkdir -p "$_testdir/flag_rm_dir/sub"
echo "delete-me" > "$_testdir/flag_rm_dir/sub/file.txt"
(cd "$_testdir/gitrepo" && rm -rf "$_testdir/flag_rm_dir") >/dev/null 2>&1
assert_false test -d "$_testdir/flag_rm_dir"

# `--` counts as a dash-prefixed arg under the bail-on-flags rule, so
# `rm -- FILE` is simply `command rm -- FILE`. Still removes the file.
start_test "rm -- FILE still removes FILE"
mkdir -p "$_testdir/rm_dashes"
echo "x" > "$_testdir/rm_dashes/--weird"
(cd "$_testdir/gitrepo" && rm -- "$_testdir/rm_dashes/--weird")
assert_false \
    test -f "$_testdir/rm_dashes/--weird"

###############
# Earlier tests unset a bunch of functions (status, projectroot, ...)
# to verify stub-then-call behaviour. Re-source shrc.vcs so the
# dispatch-loop-generated wrappers exist again for the integration
# tests below.
# shellcheck source=shrc.vcs
source "$_srcdir/shrc.vcs" >/dev/null 2>&1

###############
# Test that wrapper functions actually delegate to the binary, not to
# some stale shell fallback. Check the function body text rather than
# running them (cheap, deterministic).

start_test "vcs() calls command vcs"
_vcs_body="$(type vcs)"
assert_contains "command vcs" "$_vcs_body"

start_test "prompt_info() calls command vcs prompt-info"
_prompt_info_body="$(type prompt_info)"
assert_contains \
    "command vcs prompt-info" "$_prompt_info_body"

# Wrappers generated by the command dispatch loop should all call vcs.
start_test "status() calls vcs"
_status_body="$(type status)"
assert_contains "vcs" "$_status_body"

###############
# Test prompt_info and vcs status on a real initialized git repo (fake
# .git dirs satisfy detect but not full commands like status/commit).

_realgit="$_testdir/realgit"
mkdir -p "$_realgit"
git init "$_realgit" >/dev/null 2>&1
(cd "$_realgit" && \
    git -c user.email=test@test.com -c user.name=Test \
        commit --allow-empty -m "test" >/dev/null 2>&1)

start_test "prompt_info succeeds in git repo"
result=$(cd "$_realgit" && prompt_info --color=never)
assert_equal "0" "$?"
start_test "prompt_info output non-empty in git repo"
assert_true test -n "$result"
_first_token="${result%% *}"
start_test "prompt_info output starts with project name"
assert_equal "realgit" "$_first_token"

start_test "prompt_info succeeds (exit 0) in git repo"
(cd "$_realgit" && prompt_info --color=never >/dev/null 2>&1)
assert_equal "0" "$?"

start_test "prompt_info fails outside repo"
(cd "$_testdir/norepo" && prompt_info --color=never >/dev/null 2>&1)
assert_equal "1" "$?"

start_test "vcs status succeeds in git repo"
(cd "$_realgit" && vcs status >/dev/null 2>&1)
assert_equal "0" "$?"

# The `st` alias (wired by the command dispatch loop) should exit 0 in
# a clean real repo.
start_test "st alias succeeds in git repo"
(cd "$_realgit" && st >/dev/null 2>&1)
assert_equal "0" "$?"

# projectroot and project work off a real repo too.
start_test "projectroot works on real git repo"
result=$(cd "$_realgit" && projectroot)
assert_equal "$_realgit" "$result"
result=$(cd "$_realgit" && project)
start_test "project works on real git repo"
assert_equal "realgit" "$result"

###############
# Performance: binary vcs detection should be fast. With a 200ms
# budget we catch ~10x regressions without flaking on slow CI.
# VCS_PERF_BUDGET_MS=0 disables the check for manual profiling.

# Warmup: exclude first-call variance (binary load, cache file creation)
# from the timed loop.
        start_test "vcs detect within ${_vcs_perf_budget_ms}ms budget"
(cd "$_testdir/gitrepo" && vcs >/dev/null 2>&1)
_start=$(_now_ns)
_i=0
while test $_i -lt 10; do
    (cd "$_testdir/gitrepo" && vcs >/dev/null 2>&1)
    _i=$((_i + 1))
done
_end=$(_now_ns)
_vcs_perf_budget_ms="${VCS_PERF_BUDGET_MS:-200}"
if test "$_start" != "0" && test "$_end" != "0"; then
    _elapsed_ms=$(( (_end - _start) / 1000000 ))
    echo "  10 x vcs detect: ${_elapsed_ms}ms (budget ${_vcs_perf_budget_ms}ms)"
    if test "$_vcs_perf_budget_ms" -gt 0; then
        assert_true \
            test "$_elapsed_ms" -le "$_vcs_perf_budget_ms"
    fi
else
    skip_block "vcs detect perf check: date +%s%N unavailable"
fi

test_summary "shrc_vcs"
