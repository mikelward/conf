#!/bin/bash
#
# Tests for shrc.vcs when the vcs binary is available.
# Verifies that shrc.vcs delegates to the binary instead of the shell fallback.
#

source "$(dirname "$0")/shrc_test_lib.sh"

# Skip if vcs binary is not installed.
if ! command -v vcs >/dev/null 2>&1; then
    echo "SKIP: vcs binary not installed"
    exit 0
fi

# have_command must see the real binary.
have_command() {
    command -v "$1" >/dev/null 2>&1
}

# shellcheck source=shrc.vcs
source "$_srcdir/shrc.vcs" >/dev/null 2>&1

###############
# Test that binary path is taken (vcs function calls the binary)

# Verify vcs() is the thin wrapper, not the shell fallback.
# The shell fallback contains "vcs_cache"; the binary wrapper does not.
_vcs_body="$(type vcs)"
assert_not_contains "vcs() uses binary path (no vcs_cache reference)" "vcs_cache" "$_vcs_body"
assert_contains "vcs() uses binary path (calls command vcs)" "command vcs" "$_vcs_body"

###############
# Test vcs detection via binary

mkdir -p "$_testdir/gitrepo/subdir"
git init "$_testdir/gitrepo" >/dev/null 2>&1

result=$(cd "$_testdir/gitrepo" && vcs)
assert_equal "vcs detects git repo via binary" "git" "$result"

result=$(cd "$_testdir/gitrepo/subdir" && vcs)
assert_equal "vcs detects git from subdir via binary" "git" "$result"

# Test no vcs
mkdir -p "$_testdir/norepo"
result=$(cd "$_testdir/norepo" && vcs)
assert_equal "vcs returns empty for no repo via binary" "" "$result"
(cd "$_testdir/norepo" && vcs)
assert_equal "vcs returns false for no repo via binary" "1" "$?"

###############
# Test rootdir via binary

result=$(cd "$_testdir/gitrepo/subdir" && rootdir)
assert_equal "rootdir returns repo root via binary" "$_testdir/gitrepo" "$result"

###############
# Test vcs_backend via binary

result=$(cd "$_testdir/gitrepo" && vcs_backend)
assert_equal "vcs_backend returns git via binary" "git" "$result"

###############
# Test cv (clearcache) via binary

# Create a .vcs_cache manually
echo "test" > "$_testdir/gitrepo/.vcs_cache"
(cd "$_testdir/gitrepo" && cv)
assert_false "cv removes .vcs_cache via binary" test -f "$_testdir/gitrepo/.vcs_cache"

###############
# Test vcs command dispatch

# Verify the dispatch loop created wrappers that call vcs
_status_body="$(type status)"
assert_contains "status() calls vcs" "vcs" "$_status_body"

# Verify actual command execution (vcs status in a git repo)
(cd "$_testdir/gitrepo" && git -c user.email=test@test.com -c user.name=Test commit --allow-empty -m "test" >/dev/null 2>&1)
result=$(cd "$_testdir/gitrepo" && vcs status 2>&1)
# status should succeed (exit 0) in a clean repo
(cd "$_testdir/gitrepo" && vcs status >/dev/null 2>&1)
assert_equal "vcs status succeeds in git repo" "0" "$?"

###############
# Test cp/mv/rm fallback outside VCS

mkdir -p "$_testdir/norepo2"
echo "content" > "$_testdir/norepo2/file.txt"
(cd "$_testdir/norepo2" && cp file.txt copy.txt)
assert_true "cp falls back to command cp outside VCS" test -f "$_testdir/norepo2/copy.txt"

echo "moveme" > "$_testdir/norepo2/mv_src.txt"
(cd "$_testdir/norepo2" && mv mv_src.txt mv_dst.txt)
assert_true "mv falls back to command mv outside VCS" test -f "$_testdir/norepo2/mv_dst.txt"
assert_false "mv removes source outside VCS" test -f "$_testdir/norepo2/mv_src.txt"

echo "rmme" > "$_testdir/norepo2/rm_file.txt"
(cd "$_testdir/norepo2" && rm rm_file.txt)
assert_false "rm falls back to command rm outside VCS" test -f "$_testdir/norepo2/rm_file.txt"

###############
# Test that shrc.vcs.* files are NOT sourced when binary is available

# If the shell fallback functions like git_status were sourced, they'd be defined.
# With the binary path, they should not be.
assert_false "git_status not defined (binary replaces shell impls)" \
    type git_status >/dev/null 2>&1

###############
# Test subdir still works (shared code, not in if/else split)

result=$(cd "$_testdir/gitrepo/subdir" && subdir)
assert_equal "subdir works with binary" "subdir" "$result"

###############
# Test projectroot and project work

result=$(cd "$_testdir/gitrepo/subdir" && projectroot)
assert_equal "projectroot works with binary" "$_testdir/gitrepo" "$result"

result=$(cd "$_testdir/gitrepo/subdir" && project)
assert_equal "project works with binary" "gitrepo" "$result"

###############
# Test aliases work with binary

result=$(cd "$_testdir/gitrepo" && st 2>&1; echo $?)
assert_contains "st alias works with binary" "0" "$result"

###############
# Performance: binary vcs detection should be fast
_start=$(date +%s%N 2>/dev/null || echo "0")
for _i in $(seq 1 10); do
    (cd "$_testdir/gitrepo" && vcs >/dev/null 2>&1)
done
_end=$(date +%s%N 2>/dev/null || echo "0")
if test "$_start" != "0" && test "$_end" != "0"; then
    _elapsed_ms=$(( (_end - _start) / 1000000 ))
    echo "  10 x vcs detect: ${_elapsed_ms}ms"
fi

test_summary "vcs-binary"
