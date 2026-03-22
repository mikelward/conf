#!/bin/bash
#
# Tests for shrc.vcs functions.
# Tests VCS detection, subdir, relative_path, status_chars, and clone dispatch.
#

failures=0

assert_equal() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if test "$expected" = "$actual"; then
        echo "PASS: $label"
    else
        echo "FAIL: $label"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        failures=$((failures + 1))
    fi
}

assert_true() {
    local label="$1"
    shift
    if "$@"; then
        echo "PASS: $label"
    else
        echo "FAIL: $label"
        echo "  expected command to succeed: $*"
        failures=$((failures + 1))
    fi
}

assert_false() {
    local label="$1"
    shift
    if "$@"; then
        echo "FAIL: $label"
        echo "  expected command to fail: $*"
        failures=$((failures + 1))
    else
        echo "PASS: $label"
    fi
}

# Stub out shell detection
BASH_VERSION="${BASH_VERSION:-fake}"
ZSH_VERSION=
is_zsh() { false; }
is_bash() { true; }
is_dash() { false; }
is_sh() { false; }

# We need trim_prefix for shrc.vcs functions
trim_prefix() {
    local _prefix="$1"
    local _target="$2"
    echo "${_target#$_prefix}"
}

# Source shrc.vcs (provides target_relative_to and other functions)
# shellcheck source=shrc.vcs
source "$(dirname "$0")/shrc.vcs"

# Create a temp directory for testing
_testdir=$(mktemp -d)
trap 'rm -rf "$_testdir"' EXIT

###############
# Test vcs detection

# Test git detection
mkdir -p "$_testdir/gitrepo/subdir"
mkdir "$_testdir/gitrepo/.git"
result=$(cd "$_testdir/gitrepo" && vcs)
assert_equal "vcs detects git repo" "git" "$result"

# Test hg detection
mkdir -p "$_testdir/hgrepo"
mkdir "$_testdir/hgrepo/.hg"
result=$(cd "$_testdir/hgrepo" && vcs)
assert_equal "vcs detects hg repo" "hg" "$result"

# Test jj detection
mkdir -p "$_testdir/jjrepo"
mkdir "$_testdir/jjrepo/.jj"
result=$(cd "$_testdir/jjrepo" && vcs)
assert_equal "vcs detects jj repo" "jj" "$result"

# Test no vcs
mkdir -p "$_testdir/norepo"
result=$(cd "$_testdir/norepo" && vcs)
assert_equal "vcs returns empty for no repo" "" "$result"
(cd "$_testdir/norepo" && vcs)
assert_equal "vcs returns false for no repo" "1" "$?"

# Test vcs detection from subdirectory
result=$(cd "$_testdir/gitrepo/subdir" && vcs)
assert_equal "vcs detects git from subdir" "git" "$result"

# Test .vcs_cache is created
assert_true "vcs creates .vcs_cache" test -f "$_testdir/gitrepo/.vcs_cache"

# Test .vcs_cache is used on second call
result=$(cd "$_testdir/gitrepo" && vcs)
assert_equal "vcs uses cache on second call" "git" "$result"

###############
# Test cv (clear vcs cache)

(cd "$_testdir/gitrepo" && cv)
assert_false "cv removes .vcs_cache" test -f "$_testdir/gitrepo/.vcs_cache"

###############
# Test rootdir

# Re-detect to create cache
(cd "$_testdir/gitrepo/subdir" && vcs >/dev/null)
result=$(cd "$_testdir/gitrepo/subdir" && rootdir)
assert_equal "rootdir returns repo root" "$_testdir/gitrepo" "$result"

# Test rootdir with arguments
result=$(cd "$_testdir/gitrepo/subdir" && rootdir "file.txt")
assert_equal "rootdir with arg returns full path" "$_testdir/gitrepo/file.txt" "$result"

result=$(cd "$_testdir/gitrepo/subdir" && rootdir "a.txt" "b.txt")
expected="$_testdir/gitrepo/a.txt
$_testdir/gitrepo/b.txt"
assert_equal "rootdir with multiple args" "$expected" "$result"

###############
# Test subdir

result=$(cd "$_testdir/gitrepo/subdir" && subdir)
assert_equal "subdir returns path under root" "subdir" "$result"

result=$(cd "$_testdir/gitrepo" && subdir)
assert_equal "subdir at root returns empty" "" "$result"

###############
# Test clone dispatch

# clone just dispatches based on URL pattern, stub out git/hg
_clone_log=""
git() { _clone_log="git $*"; }
hg() { _clone_log="hg $*"; }

clone https://github.com/foo/bar.git
assert_equal "clone dispatches .git to git" "git clone https://github.com/foo/bar.git" "$_clone_log"

_clone_log=""
clone https://hg.example.com/hg/repo
assert_equal "clone dispatches /hg/ to hg" "hg clone https://hg.example.com/hg/repo" "$_clone_log"

unset -f git hg
unset _clone_log

###############
# Test status_chars

# Stub status to return known output
status() {
    printf 'M  file1.txt\nA  file2.txt\n?? file3.txt\nM  file4.txt\n'
}
result=$(status_chars)
assert_equal "status_chars extracts unique sorted chars" "?? A M" "$result"

# Stub status returning clean
status() { :; }
result=$(status_chars)
assert_equal "status_chars returns empty for clean" "" "$result"

unset -f status

###############
# Test allknown

# Stub unknown to return something
unknown() { echo "untracked.txt"; }
result=$(allknown)
assert_equal "allknown prints unknown files" "untracked.txt" "$result"
allknown >/dev/null
assert_equal "allknown returns false when files unknown" "1" "$?"

# Stub unknown to return nothing
unknown() { :; }
allknown >/dev/null
assert_equal "allknown returns true when no unknown files" "0" "$?"

unset -f unknown

###############
# Test target_relative_to

result=$(target_relative_to "src/foo.txt" "src")
assert_equal "target_relative_to same parent" "foo.txt" "$result"

result=$(target_relative_to "src/foo.txt" "lib")
assert_equal "target_relative_to sibling dir" "../src/foo.txt" "$result"

result=$(target_relative_to "foo.txt" ".")
assert_equal "target_relative_to from dot" "foo.txt" "$result"

result=$(target_relative_to "a/b/c" "a")
assert_equal "target_relative_to nested" "b/c" "$result"

###############
# Test project

# Stub projectroot
projectroot() { echo "/home/user/repos/myproject"; }
result=$(project)
assert_equal "project returns basename of projectroot" "myproject" "$result"
unset -f projectroot

echo
if test "$failures" -eq 0; then
    echo "All tests passed."
else
    echo "$failures test(s) failed."
    exit 1
fi
