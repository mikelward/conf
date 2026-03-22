#!/bin/bash
#
# Tests for shrc.vcs functions.
# Tests VCS detection, subdir, relative_path, status_chars, and clone dispatch.
# Requires bash or zsh (uses here-strings).
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
# Test git outgoing and incoming with real repos

# Source git VCS functions
source "$(dirname "$0")/shrc.vcs.git"

# Create a "remote" bare repo and a local clone
_git_remote="$_testdir/git_remote.git"
_git_local="$_testdir/git_local"

git init --bare "$_git_remote" >/dev/null 2>&1

git clone "$_git_remote" "$_git_local" >/dev/null 2>&1

# Disable commit signing and hooks in test repos
git -C "$_git_local" config commit.gpgsign false
git -C "$_git_local" config core.hooksPath /dev/null

# Create an initial commit on the local clone and push it
(
    cd "$_git_local"
    git commit --allow-empty -m "initial commit" >/dev/null 2>&1
    git push -u origin HEAD >/dev/null 2>&1
)

# Test git_outgoing with no unpushed commits
result=$(cd "$_git_local" && git_outgoing 2>&1)
assert_equal "git_outgoing no unpushed commits" "" "$result"

# Create a local commit that hasn't been pushed
(
    cd "$_git_local"
    echo "new content" > newfile.txt
    git add newfile.txt
    git commit -m "local commit" >/dev/null 2>&1
)

# Test git_outgoing shows the unpushed commit
result=$(cd "$_git_local" && git_outgoing 2>&1)
assert_true "git_outgoing shows unpushed commit" test -n "$result"
assert_true "git_outgoing contains commit message" grep -q 'local commit' <<< "$result"

# Test git_incoming with no new remote commits
result=$(cd "$_git_local" && git fetch 2>&1 && git_incoming 2>&1)
assert_equal "git_incoming no new commits" "" "$result"

# Push the local commit, then create a new remote commit from a second clone
_git_local2="$_testdir/git_local2"
(
    cd "$_git_local"
    git push >/dev/null 2>&1
)
git clone "$_git_remote" "$_git_local2" >/dev/null 2>&1
git -C "$_git_local2" config commit.gpgsign false
(
    cd "$_git_local2"
    echo "remote content" > remotefile.txt
    git add remotefile.txt
    git commit -m "remote commit" >/dev/null 2>&1
    git push >/dev/null 2>&1
)

# Test git_incoming shows the new remote commit
result=$(cd "$_git_local" && git fetch 2>&1 && git_incoming 2>&1)
assert_true "git_incoming shows new remote commit" test -n "$result"
assert_true "git_incoming contains commit message" grep -q 'remote commit' <<< "$result"

# Test git_pending shows unpushed commits
(
    cd "$_git_local"
    echo "pending content" > pendingfile.txt
    git add pendingfile.txt
    git commit -m "pending commit" >/dev/null 2>&1
)
result=$(cd "$_git_local" && git_pending 2>&1)
assert_true "git_pending shows pending commit" test -n "$result"
assert_true "git_pending contains commit message" grep -q 'pending commit' <<< "$result"

###############
# Test hg outgoing and incoming with real repos

# Source hg VCS functions
source "$(dirname "$0")/shrc.vcs.hg"

if command -v hg >/dev/null 2>&1; then

# Create a "remote" hg repo and a local clone
_hg_remote="$_testdir/hg_remote"
_hg_local="$_testdir/hg_local"

hg init "$_hg_remote"
(
    cd "$_hg_remote"
    echo "initial" > file.txt
    hg add file.txt
    hg commit -m "initial commit" -u "test <test@test.com>"
)
hg clone "$_hg_remote" "$_hg_local" >/dev/null 2>&1

# Test hg_outgoing with no unpushed commits (returns exit 1)
result=$(cd "$_hg_local" && hg_outgoing 2>&1)
rc=$?
assert_equal "hg_outgoing no unpushed returns 1" "1" "$rc"

# Create a local commit
(
    cd "$_hg_local"
    echo "local content" > localfile.txt
    hg add localfile.txt
    hg commit -m "hg local commit" -u "test <test@test.com>"
)

# Test hg_outgoing shows the unpushed commit
result=$(cd "$_hg_local" && hg_outgoing 2>&1)
rc=$?
assert_equal "hg_outgoing with unpushed returns 0" "0" "$rc"
assert_true "hg_outgoing produces output" test -n "$result"

# Test hg_incoming with no new remote commits (returns exit 1)
result=$(cd "$_hg_local" && hg_incoming 2>&1)
rc=$?
assert_equal "hg_incoming no new returns 1" "1" "$rc"

# Create a remote commit
(
    cd "$_hg_remote"
    echo "remote content" > remotefile.txt
    hg add remotefile.txt
    hg commit -m "hg remote commit" -u "test <test@test.com>"
)

# Test hg_incoming shows the new remote commit
result=$(cd "$_hg_local" && hg_incoming 2>&1)
rc=$?
assert_equal "hg_incoming with new returns 0" "0" "$rc"
assert_true "hg_incoming produces output" test -n "$result"

# Test hg_pending shows status
(
    cd "$_hg_local"
    echo "modified" >> file.txt
)
result=$(cd "$_hg_local" && hg_pending 2>&1)
assert_true "hg_pending shows modified files" test -n "$result"

else
echo "SKIP: hg not installed, skipping hg integration tests"
fi

###############
# Test jj outgoing and incoming with real repos

# Source jj VCS functions
source "$(dirname "$0")/shrc.vcs.jj"

if command -v jj >/dev/null 2>&1; then

# Create a jj repo
_jj_repo="$_testdir/jj_repo"
jj git init "$_jj_repo" >/dev/null 2>&1

# Test jj_outgoing with no commits (empty repo)
result=$(cd "$_jj_repo" && jj_outgoing 2>&1)
assert_equal "jj_outgoing empty repo" "" "$result"

# Create a commit
(
    cd "$_jj_repo"
    echo "jj content" > jjfile.txt
    jj commit -m "jj test commit" >/dev/null 2>&1
)

# Test jj_outgoing shows the commit
result=$(cd "$_jj_repo" && jj_outgoing 2>&1)
assert_true "jj_outgoing shows mutable commit" test -n "$result"
assert_true "jj_outgoing contains commit message" grep -q 'jj test commit' <<< "$result"

# Test jj_incoming shows operation log
result=$(cd "$_jj_repo" && jj_incoming 2>&1)
assert_true "jj_incoming shows op log" test -n "$result"
assert_true "jj_incoming contains commit operation" grep -q 'commit' <<< "$result"

# Test jj_pending shows mutable commits
result=$(cd "$_jj_repo" && jj_pending 2>&1)
assert_true "jj_pending shows pending commits" test -n "$result"
assert_true "jj_pending contains commit message" grep -q 'jj test commit' <<< "$result"

# Create a second commit and verify both show up
(
    cd "$_jj_repo"
    echo "more jj content" > jjfile2.txt
    jj commit -m "jj second commit" >/dev/null 2>&1
)

result=$(cd "$_jj_repo" && jj_outgoing 2>&1)
assert_true "jj_outgoing shows first commit" grep -q 'jj test commit' <<< "$result"
assert_true "jj_outgoing shows second commit" grep -q 'jj second commit' <<< "$result"

else
echo "SKIP: jj not installed, skipping jj integration tests"
fi

###############
# Test cross-VCS consistency: every command in shrc.vcs dispatch loop
# must have a corresponding function in each backend.

_shrc_vcs="$(dirname "$0")/shrc.vcs"

# Extract the command list from the dispatch loop in shrc.vcs
_commands=$(
    sed -n '/^for command in/,/; do$/p' "$_shrc_vcs" |
    tr ' \\\n' '\n' |
    sed 's/[;]//g' |
    grep -v '^for$\|^command$\|^in$\|^do$\|^$'
)

for _backend in git hg jj; do
    _backend_file="$(dirname "$0")/shrc.vcs.$_backend"
    for _cmd in $_commands; do
        assert_true "${_backend}_${_cmd} defined" \
            grep -q "^${_backend}_${_cmd}()" "$_backend_file"
    done
done

unset _shrc_vcs _commands _backend _backend_file _cmd

echo
if test "$failures" -eq 0; then
    echo "All tests passed."
else
    echo "$failures test(s) failed."
    exit 1
fi
