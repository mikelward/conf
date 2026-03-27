#!/bin/bash
#
# Tests for jj VCS backend functions.
#

source "$(dirname "$0")/shrc_test_lib.sh"

# shellcheck source=shrc.vcs
source "$_srcdir/shrc.vcs" >/dev/null 2>&1
source "$_srcdir/shrc.vcs.jj"

# Clear jj environment that leaks in when run from a jj hook
unset JJ_OP_ID

if ! command -v jj >/dev/null 2>&1; then
    echo "SKIP: jj not installed"
    exit 0
fi

###############
# Setup: create a jj repo

_jj_repo="$_testdir/jj_repo"
jj git init "$_jj_repo" >/dev/null 2>&1

###############
# Test jj base

# jj_base on a fresh repo shows the root commit
result=$(cd "$_jj_repo" && jj_base 2>&1)
assert_true "jj_base fresh repo returns something" test -n "$result"

# jj_base changes after a commit
(
    cd "$_jj_repo"
    echo "base-test" > basefile.txt
    jj commit -m "jj base test commit" >/dev/null 2>&1
)
result=$(cd "$_jj_repo" && jj_base)
assert_true "jj_base after commit shows parent" grep -q 'jj base test commit' <<< "$result"

# jj_base changes after jj prev (edit parent)
(
    cd "$_jj_repo"
    echo "second" > secondfile.txt
    jj commit -m "jj second base commit" >/dev/null 2>&1
)
_jj_second_base=$(cd "$_jj_repo" && jj_base)
assert_true "jj_base shows second commit" grep -q 'jj second base commit' <<< "$_jj_second_base"

# Use jj prev to move working copy to the parent
(cd "$_jj_repo" && jj prev --edit >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj_base)
assert_true "jj_base after prev shows earlier commit" grep -q 'jj base test commit' <<< "$result"

# Create a new working copy change on top (prev --edit abandoned the old one)
(cd "$_jj_repo" && jj new >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj_base)
assert_true "jj_base after new shows current commit" grep -q 'jj second base commit' <<< "$result"

###############
# Test jj outgoing and incoming

# Push existing commits so they become immutable and don't appear in outgoing
_jj_git_remote="$_testdir/jj_git_remote"
git init --bare "$_jj_git_remote" >/dev/null 2>&1
(cd "$_jj_repo" && jj git remote add origin "$_jj_git_remote" >/dev/null 2>&1)
(cd "$_jj_repo" && jj bookmark create main -r @- >/dev/null 2>&1)
(cd "$_jj_repo" && jj git push --bookmark main --allow-new >/dev/null 2>&1)

# Test jj_outgoing with no unpushed commits
result=$(cd "$_jj_repo" && jj_outgoing 2>&1)
assert_equal "jj_outgoing no unpushed commits" "" "$result"

# Create a commit
(
    cd "$_jj_repo"
    echo "jj content" > jjfile.txt
    jj commit -m "jj test commit" >/dev/null 2>&1
)

# Test jj_outgoing shows the commit with prefix
result=$(cd "$_jj_repo" && jj_outgoing 2>&1)
assert_true "jj_outgoing shows mutable commit" test -n "$result"
assert_true "jj_outgoing contains commit message" grep -q 'jj test commit' <<< "$result"
assert_true "jj_outgoing has @ or * prefix" grep -q '^[*@] ' <<< "$result"

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
assert_true "jj_outgoing current base has @ prefix" grep -q '^@ .*jj second commit' <<< "$result"
assert_true "jj_outgoing other commit has * prefix" grep -q '^\* .*jj test commit' <<< "$result"

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

# jj_status after commit shows empty output (new @ is undescribed but empty)
(cd "$_jj_repo" && jj commit -m "status test" >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj_status)
assert_equal "jj_status clean after commit" "" "$result"

# jj_status hides changes in described commits
(cd "$_jj_repo" && echo "described-content" > jj_describedfile.txt)
(cd "$_jj_repo" && jj describe -m "already described" >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj_status)
assert_equal "jj_status empty for described commit" "" "$result"
# Clean up: commit so @ is fresh again
(cd "$_jj_repo" && jj commit -m "cleanup described" >/dev/null 2>&1)

###############
# Test jj show

result=$(cd "$_jj_repo" && jj_show @-)
assert_true "jj_show displays commit" grep -q 'cleanup described' <<< "$result"

###############
# Test jj diffstat

(cd "$_jj_repo" && echo "diffstat-content" > jj_diffstatfile.txt)
result=$(cd "$_jj_repo" && jj_diffstat)
assert_true "jj_diffstat shows changed file" grep -q 'jj_diffstatfile.txt' <<< "$result"
(cd "$_jj_repo" && jj commit -m "diffstat test" >/dev/null 2>&1)

###############
# Test jj addremove

# jj_addremove is a no-op (jj auto-tracks), should succeed without error
(cd "$_jj_repo" && echo "auto-tracked" > jj_addremove.txt)
(cd "$_jj_repo" && jj_addremove >/dev/null 2>&1)
assert_equal "jj_addremove succeeds" "0" "$?"
# file should already be tracked by jj
result=$(cd "$_jj_repo" && jj_status)
assert_true "jj auto-tracks new file" grep -q 'jj_addremove.txt' <<< "$result"

test_summary "jj"
