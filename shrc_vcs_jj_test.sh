#!/bin/bash
#
# Tests for jj VCS backend functions.
#

source "$(dirname "$0")/shrc_vcs_test_helpers.sh"
source "$_srcdir/shrc.vcs.jj"

if ! command -v jj >/dev/null 2>&1; then
    echo "SKIP: jj not installed"
    exit 0
fi

###############
# Setup: create a jj repo

_jj_repo="$_testdir/jj_repo"
jj git init "$_jj_repo" >/dev/null 2>&1

###############
# Test jj outgoing and incoming

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

###############
# Test jj commit, amend, recommit, reword

# jj_commit creates a new commit
(
    cd "$_jj_repo"
    echo "commit-test" > jj_commitfile.txt
)
(cd "$_jj_repo" && jj_commit -m "jj commit test" >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj log --no-graph -r @- -T 'description')
assert_true "jj_commit with -m" grep -q 'jj commit test' <<< "$result"

# jj_amend squashes working copy into parent
(
    cd "$_jj_repo"
    echo "amend-content" > jj_amendfile.txt
)
(cd "$_jj_repo" && jj_amend >/dev/null 2>&1)
assert_true "jj_amend squashes into parent" \
    bash -c "cd '$_jj_repo' && jj file show jj_amendfile.txt -r @- 2>/dev/null | grep -q amend-content"

# jj_recommit updates the description
(cd "$_jj_repo" && jj_recommit -m "jj recommit msg" >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj log --no-graph -r @ -T 'description')
assert_true "jj_recommit changes description" grep -q 'jj recommit msg' <<< "$result"

# jj_reword with args uses -m
(cd "$_jj_repo" && jj_reword "jj reword msg" >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj log --no-graph -r @ -T 'description')
assert_true "jj_reword with args" grep -q 'jj reword msg' <<< "$result"

###############
# Test jj branch, revert, undo

# jj_branch is a no-op (no current bookmark concept)
result=$(cd "$_jj_repo" && jj_branch)
assert_equal "jj_branch returns empty" "" "$result"

# jj_revert creates a commit that reverses changes
(
    cd "$_jj_repo"
    echo "original-jj" > jj_revertfile.txt
    jj commit -m "add revertfile" >/dev/null 2>&1
    echo "modified-jj" > jj_revertfile.txt
    jj commit -m "modify revertfile" >/dev/null 2>&1
)
(cd "$_jj_repo" && jj_revert -r @- --destination @ >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj log --no-graph -r 'children(@)' -T 'description')
assert_true "jj_revert creates revert commit" grep -q 'Revert' <<< "$result"

# jj_undo reverses the last operation
(cd "$_jj_repo" && jj_undo >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj log --no-graph -r 'all()' -T 'description')
assert_false "jj_undo removes revert commit" grep -q 'Revert' <<< "$result"

###############
# Test jj status

# jj_status shows modified files with short format
(cd "$_jj_repo" && echo "new-jj" > jj_statusfile.txt)
result=$(cd "$_jj_repo" && jj_status)
assert_true "jj_status shows added file" grep -q 'jj_statusfile.txt' <<< "$result"
assert_true "jj_status shows A prefix" grep -q '^A' <<< "$result"

# jj_status after commit shows empty output
(cd "$_jj_repo" && jj commit -m "status test" >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj_status)
assert_equal "jj_status clean after commit" "" "$result"

test_summary "jj"
