#!/bin/bash
#
# Tests for shrc.vcs core functions. The per-VCS subcommand behaviour
# lives in the `vcs` Go binary (the mikelward/vcs submodule) and is
# tested there.
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

# hg repo has no backend (cache uses - sentinel)
rm -f "$_testdir/hgrepo/.vcs_cache"
result=$(cd "$_testdir/hgrepo" && vcs_backend)
assert_equal "vcs_backend returns empty for hg repo" "" "$result"
# Verify the sentinel is written to line 1 of cache
_cache_line1=$(head -1 "$_testdir/hgrepo/.vcs_cache")
assert_contains "hg cache uses - sentinel for backend" " - " "$_cache_line1"

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
_write_jj_origin "$_testdir/jjrepo" "https://github.com/user/repo.git"
rm -f "$_testdir/jjrepo/.vcs_cache"
result=$(cd "$_testdir/jjrepo" && vcs_backend)
assert_equal "vcs_backend returns git for jj-git repo" "git" "$result"
result=$(cd "$_testdir/jjrepo" && vcs_hosting)
assert_equal "vcs_hosting returns github for github remote" "github" "$result"

# jj repo with gerrit remote
_write_jj_origin "$_testdir/jjrepo_gerrit" "https://chromium.googlesource.com/foo/bar"
result=$(cd "$_testdir/jjrepo_gerrit" && vcs_hosting)
assert_equal "vcs_hosting returns gerrit for googlesource remote" "gerrit" "$result"

# jj repo with gitlab remote
_write_jj_origin "$_testdir/jjrepo_gitlab" "https://gitlab.com/user/repo.git"
result=$(cd "$_testdir/jjrepo_gitlab" && vcs_hosting)
assert_equal "vcs_hosting returns gitlab for gitlab.com remote" "gitlab" "$result"

# self-hosted gitlab
_write_jj_origin "$_testdir/jjrepo_gitlab_self" "https://gitlab.mycompany.com/group/repo.git"
result=$(cd "$_testdir/jjrepo_gitlab_self" && vcs_hosting)
assert_equal "vcs_hosting returns gitlab for self-hosted gitlab" "gitlab" "$result"

# jj repo with bitbucket remote
_write_jj_origin "$_testdir/jjrepo_bitbucket" "https://bitbucket.org/user/repo.git"
result=$(cd "$_testdir/jjrepo_bitbucket" && vcs_hosting)
assert_equal "vcs_hosting returns bitbucket for bitbucket remote" "bitbucket" "$result"

# jj repo with sourcehut remote
_write_jj_origin "$_testdir/jjrepo_srht" "https://git.sr.ht/~user/repo"
result=$(cd "$_testdir/jjrepo_srht" && vcs_hosting)
assert_equal "vcs_hosting returns sourcehut for sr.ht remote" "sourcehut" "$result"

# jj repo with no origin remote
_write_jj_origin "$_testdir/jjrepo_noremote" ""
result=$(cd "$_testdir/jjrepo_noremote" && vcs_hosting)
assert_equal "vcs_hosting returns empty for no remote" "" "$result"

# jj repo with non-git backend
mkdir -p "$_testdir/jjrepo_piper/.jj/repo/store"
echo "piper" > "$_testdir/jjrepo_piper/.jj/repo/store/type"
result=$(cd "$_testdir/jjrepo_piper" && vcs_backend)
assert_equal "vcs_backend returns piper for piper backend" "piper" "$result"
result=$(cd "$_testdir/jjrepo_piper" && vcs_hosting)
assert_equal "vcs_hosting returns empty for non-git backend" "" "$result"

# Verify cache format: line 1 has 3 fields, line 2 has rootdir
rm -f "$_testdir/jjrepo/.vcs_cache"
(cd "$_testdir/jjrepo" && vcs >/dev/null)
_cache_line1=$(head -1 "$_testdir/jjrepo/.vcs_cache")
_cache_line2=$(sed -n '2p' "$_testdir/jjrepo/.vcs_cache")
assert_contains "vcs_cache line 1 contains backend" "git" "$_cache_line1"
assert_contains "vcs_cache line 1 contains hosting" "github" "$_cache_line1"
_field_count=$(echo "$_cache_line1" | awk '{print NF}')
assert_equal "vcs_cache line 1 has 3 fields (all set)" "3" "$_field_count"
assert_equal "vcs_cache line 2 is rootdir" "$_testdir/jjrepo" "$_cache_line2"

# Verify cache has 3 fields on line 1 even when backend and hosting are empty
rm -f "$_testdir/hgrepo/.vcs_cache"
(cd "$_testdir/hgrepo" && vcs >/dev/null)
_cache_line1=$(head -1 "$_testdir/hgrepo/.vcs_cache")
_field_count=$(echo "$_cache_line1" | awk '{print NF}')
assert_equal "vcs_cache line 1 has 3 fields (sentinels)" "3" "$_field_count"
assert_contains "hg cache line 1 ends with - -" "- -" "$_cache_line1"

# Verify cache has 3 fields on line 1 when only hosting is empty
rm -f "$_testdir/jjrepo_noremote/.vcs_cache"
(cd "$_testdir/jjrepo_noremote" && vcs >/dev/null)
_cache_line1=$(head -1 "$_testdir/jjrepo_noremote/.vcs_cache")
_field_count=$(echo "$_cache_line1" | awk '{print NF}')
assert_equal "vcs_cache line 1 has 3 fields (hosting sentinel)" "3" "$_field_count"
assert_contains "git backend with no hosting ends with -" "git -" "$_cache_line1"

# Test paths with spaces
mkdir -p "$_testdir/path with spaces/subdir"
mkdir "$_testdir/path with spaces/.git"
result=$(cd "$_testdir/path with spaces" && vcs)
assert_equal "vcs detects git in path with spaces" "git" "$result"
result=$(cd "$_testdir/path with spaces" && rootdir)
assert_equal "rootdir works with spaces in path" "$_testdir/path with spaces" "$result"
result=$(cd "$_testdir/path with spaces" && vcs_backend)
assert_equal "vcs_backend works with spaces in path" "git" "$result"
result=$(cd "$_testdir/path with spaces/subdir" && rootdir)
assert_equal "rootdir from subdir works with spaces" "$_testdir/path with spaces" "$result"
result=$(cd "$_testdir/path with spaces/subdir" && rootdir "file.txt")
assert_equal "rootdir with arg works with spaces" "$_testdir/path with spaces/file.txt" "$result"

# Test paths with backslashes (read -r prevents mangling)
mkdir -p "$_testdir/back\\slash"
mkdir "$_testdir/back\\slash/.git"
result=$(cd "$_testdir/back\\slash" && vcs)
assert_equal "vcs detects git in path with backslash" "git" "$result"
result=$(cd "$_testdir/back\\slash" && rootdir)
assert_equal "rootdir works with backslash in path" "$_testdir/back\\slash" "$result"

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

test_summary "core"
