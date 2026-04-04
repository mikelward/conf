#!/usr/bin/env elvish
#
# Tests for elvish shell configuration.
#
# Run with: XDG_CONFIG_HOME=config elvish rc_elv_test.elv

use path
use str

var failures = 0
var passes = 0

fn assert-equal {|label expected actual|
  # Compare as strings to handle number/string mismatches
  if (eq (to-string $expected) (to-string $actual)) {
    set passes = (+ $passes 1)
  } else {
    echo "FAIL:" $label
    echo "  expected:" $expected
    echo "  actual:  " $actual
    set failures = (+ $failures 1)
  }
}

fn assert-contains {|label needle haystack|
  if (str:contains $haystack $needle) {
    set passes = (+ $passes 1)
  } else {
    echo "FAIL:" $label
    echo "  expected to contain:" $needle
    echo "  actual:             " $haystack
    set failures = (+ $failures 1)
  }
}

fn assert-not-contains {|label needle haystack|
  if (not (str:contains $haystack $needle)) {
    set passes = (+ $passes 1)
  } else {
    echo "FAIL:" $label
    echo "  expected not to contain:" $needle
    echo "  actual:                 " $haystack
    set failures = (+ $failures 1)
  }
}

fn test-summary {
  echo ""
  if (== $failures 0) {
    echo "rc_elv_test: all" $passes "tests passed."
  } else {
    echo "rc_elv_test:" $failures "test(s) failed," $passes "passed."
    exit 1
  }
}

# Prevent interactive editor from opening
set-env EDITOR "sh -c 'printf \"edited by test\n\" > \"$1\"' --"
set-env VISUAL (get-env EDITOR)
set-env GIT_EDITOR (get-env EDITOR)

# Create temp directory for testing
var testdir = (mktemp -d)

# Empty directory to disable hooks
var nohooks = $testdir/nohooks
mkdir $nohooks

# Source the shrc module via the elvish module system.
# XDG_CONFIG_HOME must be set to config/ so that use finds lib/shrc.elv.
use shrc

# Clear git environment that may leak in
unset-env GIT_DIR
unset-env GIT_INDEX_FILE
unset-env GIT_WORK_TREE
unset-env GIT_PREFIX

###############
# Setup: create a "remote" bare repo and a local clone

var git-remote = $testdir/git_remote.git
var git-local = $testdir/git_local

git init --bare $git-remote >/dev/null 2>&1
git clone $git-remote $git-local >/dev/null 2>&1

# Disable commit signing and hooks in test repos
git -C $git-local config commit.gpgsign false
git -C $git-local config core.hooksPath $nohooks

# Create an initial commit
git -C $git-local commit --allow-empty -m "initial commit" >/dev/null 2>&1
git -C $git-local push -u origin HEAD >/dev/null 2>&1

###############
# Test VCS detection in a git repo

echo "--- VCS detection ---"

# Save and restore pwd for tests that need cd
var saved-pwd = $pwd

cd $git-local
var detected-vcs = (shrc:vcs)
assert-equal "vcs detects git" git $detected-vcs

var detected-root = (shrc:rootdir)
assert-equal "rootdir returns git root" $git-local $detected-root

cd /tmp
var no-vcs = (shrc:vcs)
assert-equal "vcs returns empty outside repo" "" $no-vcs

var no-root = (shrc:rootdir)
assert-equal "rootdir returns empty outside repo" "" $no-root

cd $saved-pwd

###############
# Test VCS branch

echo "--- VCS branch ---"

var initial-branch = (git -C $git-local rev-parse --abbrev-ref HEAD)

cd $git-local
var branch = (shrc:vcs-branch)
assert-equal "vcs-branch returns current branch" $initial-branch $branch
cd $saved-pwd

# Test branch after creating a new branch
git -C $git-local checkout -b test-branch >/dev/null 2>&1

cd $git-local
var new-branch = (shrc:vcs-branch)
assert-equal "vcs-branch returns new branch" test-branch $new-branch
cd $saved-pwd

# Switch back
git -C $git-local checkout $initial-branch >/dev/null 2>&1

###############
# Test status chars

echo "--- Status chars ---"

# Clean repo should have no status chars
cd $git-local
var clean-status = (shrc:status-chars)
assert-equal "status-chars clean repo" "" $clean-status
cd $saved-pwd

# Add an untracked file
echo "untracked" > $git-local/untracked.txt
cd $git-local
var untracked-status = (shrc:status-chars)
assert-contains "status-chars with untracked file" "??" $untracked-status
cd $saved-pwd

# Stage the file
git -C $git-local add untracked.txt
cd $git-local
var staged-status = (shrc:status-chars)
assert-contains "status-chars with staged file" "A" $staged-status
cd $saved-pwd

# Modify a tracked file
git -C $git-local commit -m "add file" >/dev/null 2>&1
echo "modified" > $git-local/untracked.txt
cd $git-local
var modified-status = (shrc:status-chars)
assert-contains "status-chars with modified file" "M" $modified-status
cd $saved-pwd

# Clean up
git -C $git-local checkout -- . 2>/dev/null

###############
# Test unique function

echo "--- unique ---"

var unique-result = [(shrc:unique a b a c b c)]
assert-equal "unique count" 3 (count $unique-result)
assert-equal "unique first" a $unique-result[0]
assert-equal "unique second" b $unique-result[1]
assert-equal "unique third" c $unique-result[2]

var unique-empty = [(shrc:unique)]
assert-equal "unique empty" 0 (count $unique-empty)

var unique-single = [(shrc:unique x)]
assert-equal "unique single" 1 (count $unique-single)

###############
# Test color functions

echo "--- Colors ---"

# Test that color-print wraps text in escape sequences
var blue-output = (shrc:blue hello)
assert-contains "blue contains text" hello $blue-output

var green-output = (shrc:green world)
assert-contains "green contains text" world $green-output

var yellow-output = (shrc:yellow warning)
assert-contains "yellow contains text" warning $yellow-output

var red-output = (shrc:red error)
assert-contains "red contains text" error $red-output

###############
# Test dir-info

echo "--- dir-info ---"

# In a git repo, dir-info should show the project name
cd $git-local
var dir-output = (shrc:dir-info)
assert-contains "dir-info shows project name" git_local $dir-output
cd $saved-pwd

# In a subdirectory, should show subdir
mkdir -p $git-local/sub/dir
cd $git-local/sub/dir
var subdir-output = (shrc:dir-info)
assert-contains "dir-info in subdir shows project" git_local $subdir-output
assert-contains "dir-info in subdir shows subdir" sub/dir $subdir-output
cd $saved-pwd

# Outside a repo, should show tilde directory
cd /tmp
var home-output = (shrc:dir-info)
assert-contains "dir-info outside repo shows path" tmp $home-output
cd $saved-pwd

###############
# Test host-info

echo "--- host-info ---"

var host-output = (shrc:host-info)
var expected-host = (hostname -s)
assert-contains "host-info shows hostname" $expected-host $host-output

###############
# Test trim-prefix

echo "--- trim-prefix ---"

assert-equal "trim-prefix basic" "/sub/dir" (shrc:trim-prefix "/home/user" "/home/user/sub/dir")
assert-equal "trim-prefix no match" "/other/path" (shrc:trim-prefix "/home/user" "/other/path")
assert-equal "trim-prefix exact" "" (shrc:trim-prefix "/home/user" "/home/user")

###############
# Test tilde-directory

echo "--- tilde-directory ---"

cd (get-env HOME)
var tilde = (shrc:tilde-directory)
assert-equal "tilde-directory home" "~" $tilde
cd $saved-pwd

###############
# Test bar

echo "--- bar ---"

var bar-output = (shrc:bar)
assert-contains "bar produces output" "―" $bar-output

###############
# Test map (git)

echo "--- map ---"

cd $git-local
var map-output = (shrc:map)
# Should show the latest commit message
assert-contains "map shows commit info" "add file" $map-output
cd $saved-pwd

###############
# Test fetch-info

echo "--- fetch-info ---"

# Fresh clone with recent FETCH_HEAD should not warn (produces no output)
cd $git-local
shrc:fetch-info
cd $saved-pwd

###############
# Test path functions

echo "--- path functions ---"

var old-paths = $paths
shrc:prepend-path $testdir
assert-equal "prepend-path adds to front" $testdir $paths[0]

# Restore paths
set paths = $old-paths

shrc:append-path $testdir
assert-equal "append-path adds to end" $testdir $paths[(- (count $paths) 1)]

# Restore paths
set paths = $old-paths

###############
# Test vcs_cache usage

echo "--- vcs_cache ---"

# Create a directory with a .vcs_cache file
var cache-dir = $testdir/cached_repo
mkdir -p $cache-dir
printf "git - github\n%s\n" $cache-dir > $cache-dir/.vcs_cache

cd $cache-dir
var cached-vcs = (shrc:vcs)
assert-equal "vcs reads cache" git $cached-vcs

var cached-root = (shrc:rootdir)
assert-equal "rootdir reads cache" $cache-dir $cached-root
cd $saved-pwd

###############
# Cleanup

rm -rf $testdir

test-summary
