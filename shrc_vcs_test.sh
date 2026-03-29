#!/bin/bash
#
# Tests for shrc.vcs core functions and cross-VCS consistency.
# Implementation-specific tests are in shrc_vcs_{git,hg,jj}_test.sh.
# Requires bash or zsh (uses here-strings).
#

source "$(dirname "$0")/shrc_test_lib.sh"

# Source shrc.vcs (provides target_relative_to and other functions)
# shellcheck source=shrc.vcs
source "$_srcdir/shrc.vcs" >/dev/null 2>&1

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
# Test vcs_backend and vcs_hosting

# git repo should have git backend
rm -f "$_testdir/gitrepo/.vcs_cache"
result=$(cd "$_testdir/gitrepo" && vcs_backend)
assert_equal "vcs_backend returns git for git repo" "git" "$result"

# hg repo has no backend
rm -f "$_testdir/hgrepo/.vcs_cache"
result=$(cd "$_testdir/hgrepo" && vcs_backend)
assert_equal "vcs_backend returns empty for hg repo" "" "$result"

# jj repo with git backend
mkdir -p "$_testdir/jjrepo/.jj/repo/store/git"
echo "git" > "$_testdir/jjrepo/.jj/repo/store/type"
rm -f "$_testdir/jjrepo/.vcs_cache"
# Stub git to return a github remote URL
git() {
    if test "$1" = "-C" && test "$3" = "remote"; then
        echo "https://github.com/user/repo.git"
        return 0
    fi
    command git "$@"
}
result=$(cd "$_testdir/jjrepo" && vcs_backend)
assert_equal "vcs_backend returns git for jj-git repo" "git" "$result"
result=$(cd "$_testdir/jjrepo" && vcs_hosting)
assert_equal "vcs_hosting returns github for github remote" "github" "$result"
unset -f git

# jj repo with gerrit remote
mkdir -p "$_testdir/jjrepo_gerrit/.jj/repo/store/git"
echo "git" > "$_testdir/jjrepo_gerrit/.jj/repo/store/type"
git() {
    if test "$1" = "-C" && test "$3" = "remote"; then
        echo "https://chromium.googlesource.com/foo/bar"
        return 0
    fi
    command git "$@"
}
result=$(cd "$_testdir/jjrepo_gerrit" && vcs_hosting)
assert_equal "vcs_hosting returns gerrit for googlesource remote" "gerrit" "$result"
unset -f git

# jj repo with no origin remote
mkdir -p "$_testdir/jjrepo_noremote/.jj/repo/store/git"
echo "git" > "$_testdir/jjrepo_noremote/.jj/repo/store/type"
git() {
    if test "$1" = "-C" && test "$3" = "remote"; then
        return 2
    fi
    command git "$@"
}
result=$(cd "$_testdir/jjrepo_noremote" && vcs_hosting)
assert_equal "vcs_hosting returns empty for no remote" "" "$result"
unset -f git

# jj repo with non-git backend
mkdir -p "$_testdir/jjrepo_piper/.jj/repo/store"
echo "piper" > "$_testdir/jjrepo_piper/.jj/repo/store/type"
result=$(cd "$_testdir/jjrepo_piper" && vcs_backend)
assert_equal "vcs_backend returns piper for piper backend" "piper" "$result"
result=$(cd "$_testdir/jjrepo_piper" && vcs_hosting)
assert_equal "vcs_hosting returns empty for non-git backend" "" "$result"

# Verify cache has 4 fields
rm -f "$_testdir/jjrepo/.vcs_cache"
git() {
    if test "$1" = "-C" && test "$3" = "remote"; then
        echo "https://github.com/user/repo.git"
        return 0
    fi
    command git "$@"
}
(cd "$_testdir/jjrepo" && vcs >/dev/null)
_cache_content=$(cat "$_testdir/jjrepo/.vcs_cache")
assert_contains "vcs_cache contains backend" "git" "$_cache_content"
assert_contains "vcs_cache contains hosting" "github" "$_cache_content"
unset -f git

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

# clone just dispatches based on URL pattern, stub out git/hg/jj
_clone_log=""
have_command() { return 0; }
jj() { _clone_log="jj $*"; }
hg() { _clone_log="hg $*"; }

clone https://github.com/foo/bar.git
assert_equal "clone dispatches .git to jj git clone" "jj git clone https://github.com/foo/bar.git" "$_clone_log"

_clone_log=""
clone https://hg.example.com/hg/repo
assert_equal "clone dispatches /hg/ to hg" "hg clone https://hg.example.com/hg/repo" "$_clone_log"

# Test fallback to git when jj is unavailable
unset -f jj
have_command() { test "$1" != "jj"; }
confirm() { return 0; }
git() { _clone_log="git $*"; }
_clone_log=""
clone https://github.com/foo/bar.git
assert_equal "clone falls back to git when jj unavailable" "git clone https://github.com/foo/bar.git" "$_clone_log"

# Test declining fallback
confirm() { return 1; }
_clone_log=""
clone https://github.com/foo/bar.git
assert_equal "clone aborts when user declines git fallback" "" "$_clone_log"

unset -f git hg jj have_command confirm
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

# Single status code
status() { printf 'M  file1.txt\n'; }
result=$(status_chars)
assert_equal "status_chars single modified file" "M" "$result"

# Only untracked files
status() { printf '?? file1.txt\n?? file2.txt\n'; }
result=$(status_chars)
assert_equal "status_chars only untracked" "??" "$result"

# Two-character status codes (e.g. git staged+unstaged)
status() { printf 'AM file1.txt\nMM file2.txt\n'; }
result=$(status_chars)
assert_equal "status_chars two-char codes" "AM MM" "$result"

# Status codes with ! (e.g. hg missing)
status() { printf '! file1.txt\nM file2.txt\n'; }
result=$(status_chars)
assert_equal "status_chars with ! status" "! M" "$result"

# Ignored files (!!) should be recognized
status() { printf '!! ignored.txt\n?? untracked.txt\n'; }
result=$(status_chars)
assert_equal "status_chars ignored and untracked" "!! ??" "$result"

# Lines with lowercase or non-matching first fields are filtered out
status() { printf 'M  file1.txt\nfoo bar.txt\n123 baz.txt\n'; }
result=$(status_chars)
assert_equal "status_chars filters non-matching lines" "M" "$result"

# Duplicate codes are deduplicated
status() { printf 'A  f1\nA  f2\nA  f3\n'; }
result=$(status_chars)
assert_equal "status_chars deduplicates" "A" "$result"

# Many distinct codes are sorted
status() { printf 'R  f1\nD  f2\nA  f3\nM  f4\n'; }
result=$(status_chars)
assert_equal "status_chars sorts codes" "A D M R" "$result"

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

###############
# Test rm/mv/cp fall back to system commands outside a VCS repo

mkdir -p "$_testdir/norepo2"
echo "rm-me" > "$_testdir/norepo2/rmfile.txt"
(cd "$_testdir/norepo2" && rm rmfile.txt)
assert_false "rm falls back to command rm outside VCS" test -f "$_testdir/norepo2/rmfile.txt"

echo "mv-me" > "$_testdir/norepo2/mvfile.txt"
(cd "$_testdir/norepo2" && mv mvfile.txt mvd.txt)
assert_true "mv falls back to command mv outside VCS" test -f "$_testdir/norepo2/mvd.txt"
assert_false "mv removes original outside VCS" test -f "$_testdir/norepo2/mvfile.txt"

echo "cp-me" > "$_testdir/norepo2/cpfile.txt"
(cd "$_testdir/norepo2" && cp cpfile.txt cpd.txt)
assert_true "cp falls back to command cp outside VCS" test -f "$_testdir/norepo2/cpd.txt"
assert_true "cp keeps original outside VCS" test -f "$_testdir/norepo2/cpfile.txt"

###############
# Test cross-VCS consistency: every command in shrc.vcs dispatch loop
# must have a corresponding function in each implementation.

# Source all implementations for the consistency check
source "$_srcdir/shrc.vcs.git"
source "$_srcdir/shrc.vcs.hg"
source "$_srcdir/shrc.vcs.jj"

# Extract the command list from the dispatch loop in shrc.vcs
_commands=$(
    sed -n '/^for command in/,/; do$/p' "$_srcdir/shrc.vcs" |
    tr ' \\\n' '\n' |
    sed 's/[;]//g' |
    grep -v '^for$\|^command$\|^in$\|^do$\|^$'
)

for _impl in git hg jj; do
    _impl_file="$_srcdir/shrc.vcs.$_impl"
    for _cmd in $_commands; do
        assert_true "${_impl}_${_cmd} defined" \
            grep -q "^${_impl}_${_cmd}()" "$_impl_file"
    done
done

unset _commands _impl _impl_file _cmd

###############
# Run implementation tests in parallel

_outdir="$_testdir/test_output"
mkdir -p "$_outdir"

bash "$_srcdir/shrc_vcs_git_test.sh" > "$_outdir/git" 2>&1 &
_pid_git=$!
bash "$_srcdir/shrc_vcs_hg_test.sh"  > "$_outdir/hg"  2>&1 &
_pid_hg=$!
bash "$_srcdir/shrc_vcs_jj_test.sh"  > "$_outdir/jj"  2>&1 &
_pid_jj=$!

_impl_failures=0
for _impl in git hg jj; do
    eval "wait \$_pid_$_impl"
    _rc=$?
    cat "$_outdir/$_impl"
    if test "$_rc" -ne 0; then
        _impl_failures=$((_impl_failures + 1))
    fi
done

test_summary "core"

if test "$_impl_failures" -gt 0; then
    echo "$_impl_failures implementation suite(s) failed."
    exit 1
fi
