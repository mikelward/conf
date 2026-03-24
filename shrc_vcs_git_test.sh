#!/bin/bash
#
# Tests for git VCS backend functions.
#

source "$(dirname "$0")/shrc_vcs_test_helpers.sh"
source "$_srcdir/shrc.vcs.git"

# Clear git environment variables that leak in when run from a git hook
unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX

###############
# Setup: create a "remote" bare repo and a local clone

_git_remote="$_testdir/git_remote.git"
_git_local="$_testdir/git_local"

git init --bare "$_git_remote" >/dev/null 2>&1

git clone "$_git_remote" "$_git_local" >/dev/null 2>&1

# Disable commit signing and hooks in test repos
git -C "$_git_local" config commit.gpgsign false
git -C "$_git_local" config core.hooksPath "$_nohooks"

# Create an initial commit on the local clone and push it
(
    cd "$_git_local"
    git commit --allow-empty -m "initial commit" >/dev/null 2>&1
    git push -u origin HEAD >/dev/null 2>&1
)

###############
# Test git base

_initial_branch=$(cd "$_git_local" && git rev-parse --abbrev-ref HEAD)

# git_base on a fresh clone shows the initial commit
result=$(cd "$_git_local" && git_base)
assert_true "git_base fresh clone shows commit" grep -q 'initial commit' <<< "$result"

# git_base shows short hash and subject
_head_hash=$(cd "$_git_local" && git log -1 --format='%h')
assert_true "git_base includes short hash" grep -q "$_head_hash" <<< "$result"

# git_base changes after a new commit
(
    cd "$_git_local"
    echo "base-test" > basefile.txt
    git add basefile.txt
    git commit -m "base test commit" >/dev/null 2>&1
)
result=$(cd "$_git_local" && git_base)
assert_true "git_base after commit shows new commit" grep -q 'base test commit' <<< "$result"

# git_base changes after checkout to a different branch
(
    cd "$_git_local"
    git checkout -b base-branch >/dev/null 2>&1
    echo "branch content" > branchfile.txt
    git add branchfile.txt
    git commit -m "branch commit" >/dev/null 2>&1
)
result=$(cd "$_git_local" && git_base)
assert_true "git_base after checkout shows branch commit" grep -q 'branch commit' <<< "$result"

# git_base changes back after checking out the original branch
(cd "$_git_local" && git checkout "$_initial_branch" >/dev/null 2>&1)
result=$(cd "$_git_local" && git_base)
assert_true "git_base after checkout back shows original" grep -q 'base test commit' <<< "$result"

# clean up: remove the test branch and undo the base test commit
(
    cd "$_git_local"
    git branch -D base-branch >/dev/null 2>&1
    git reset --hard HEAD~ >/dev/null 2>&1
)

###############
# Test git outgoing and incoming

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
(cd "$_git_local" && git fetch >/dev/null 2>&1)
result=$(cd "$_git_local" && git_incoming 2>&1)
assert_equal "git_incoming no new commits" "" "$result"

# Push the local commit, then create a new remote commit from a second clone
_git_local2="$_testdir/git_local2"
(
    cd "$_git_local"
    git push >/dev/null 2>&1
)
git clone "$_git_remote" "$_git_local2" >/dev/null 2>&1
git -C "$_git_local2" config commit.gpgsign false
git -C "$_git_local2" config core.hooksPath "$_nohooks"
(
    cd "$_git_local2"
    echo "remote content" > remotefile.txt
    git add remotefile.txt
    git commit -m "remote commit" >/dev/null 2>&1
    git push >/dev/null 2>&1
)

# Test git_incoming shows the new remote commit
(cd "$_git_local" && git fetch >/dev/null 2>&1)
result=$(cd "$_git_local" && git_incoming 2>&1)
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
# Test git commit, amend, recommit, reword

# git_commit with -m and no files should use --all
(
    cd "$_git_local"
    echo "commit-test" > commitfile.txt
    git add commitfile.txt
)
(cd "$_git_local" && git_commit -m "git commit test" >/dev/null 2>&1)
result=$(cd "$_git_local" && git log -1 --format=%s)
assert_equal "git_commit with -m" "git commit test" "$result"

# git_commit with -m and specific files should not use --all
(
    cd "$_git_local"
    echo "staged" > staged.txt
    echo "unstaged" > unstaged.txt
    git add staged.txt unstaged.txt
    echo "modified-unstaged" > unstaged.txt
)
(cd "$_git_local" && git_commit -m "partial commit" -- staged.txt >/dev/null 2>&1)
result=$(cd "$_git_local" && git diff --name-only)
assert_true "git_commit with files leaves unstaged changes" grep -q 'unstaged.txt' <<< "$result"

# git_commit with no args commits all (--all is added)
(
    cd "$_git_local"
    echo "all-content" > allfile.txt
    git add allfile.txt
)
(cd "$_git_local" && git_commit -m "commit all" >/dev/null 2>&1)
result=$(cd "$_git_local" && git status --short)
assert_equal "git_commit no files commits all" "" "$result"

# git_amend updates the last commit without changing the message
(
    cd "$_git_local"
    echo "amend-content" > amendfile.txt
    git add amendfile.txt
)
(cd "$_git_local" && git_amend >/dev/null 2>&1)
result=$(cd "$_git_local" && git log -1 --format=%s)
assert_equal "git_amend preserves message" "commit all" "$result"
assert_true "git_amend includes new file" \
    bash -c "cd '$_git_local' && git show --stat HEAD | grep -q amendfile.txt"

# git_reword changes the commit message (uses GIT_EDITOR set above)
(cd "$_git_local" && git_reword >/dev/null 2>&1)
result=$(cd "$_git_local" && git log -1 --format=%s)
assert_equal "git_reword changes message" "edited by test" "$result"

###############
# Test git branch, revert, undo

# git_branch returns the current branch name
result=$(cd "$_git_local" && git_branch)
_default_branch=$(cd "$_git_local" && git rev-parse --abbrev-ref HEAD)
assert_equal "git_branch returns current branch" "$_default_branch" "$result"

# git_branch works after switching branches
(cd "$_git_local" && git checkout -b test-branch >/dev/null 2>&1)
result=$(cd "$_git_local" && git_branch)
assert_equal "git_branch after switch" "test-branch" "$result"
(cd "$_git_local" && git checkout "$_default_branch" >/dev/null 2>&1)

# git_revert with no args resets all changes
(
    cd "$_git_local"
    echo "dirty" > revertfile.txt
    git add revertfile.txt
)
(cd "$_git_local" && git_revert >/dev/null 2>&1)
result=$(cd "$_git_local" && git status --short)
assert_equal "git_revert no args resets all" "" "$result"

# git_revert with file args reverts only that file
(
    cd "$_git_local"
    echo "keep" > keepfile.txt
    echo "revert-me" > revertme.txt
    git add keepfile.txt revertme.txt
    git commit -m "add two files" >/dev/null 2>&1
    echo "modified-keep" > keepfile.txt
    echo "modified-revert" > revertme.txt
)
(cd "$_git_local" && git_revert revertme.txt >/dev/null 2>&1)
result=$(cd "$_git_local" && cat revertme.txt)
assert_equal "git_revert with file reverts that file" "revert-me" "$result"
result=$(cd "$_git_local" && cat keepfile.txt)
assert_equal "git_revert with file keeps other changes" "modified-keep" "$result"
# clean up
(cd "$_git_local" && git checkout -- keepfile.txt >/dev/null 2>&1)

# git_undo unwraps the last commit, leaving files in working dir
_before_undo=$(cd "$_git_local" && git rev-parse HEAD~)
(cd "$_git_local" && git_undo >/dev/null 2>&1)
_after_undo=$(cd "$_git_local" && git rev-parse HEAD)
assert_equal "git_undo moves HEAD back" "$_before_undo" "$_after_undo"
assert_true "git_undo leaves files in working dir" \
    test -f "$_git_local/keepfile.txt"
# re-commit so later tests have a clean state
(cd "$_git_local" && git add -A && git commit -m "re-commit after undo" >/dev/null 2>&1)

###############
# Test git status

# git_status shows staged files
(cd "$_git_local" && echo "staged" > git_statusfile.txt && git add git_statusfile.txt)
result=$(cd "$_git_local" && git_status)
assert_true "git_status shows staged file" grep -q 'git_statusfile.txt' <<< "$result"
assert_true "git_status shows A prefix" grep -q '^A' <<< "$result"

# git_status shows untracked files
(cd "$_git_local" && echo "untracked" > git_untrackedfile.txt)
result=$(cd "$_git_local" && git_status)
assert_true "git_status shows untracked file" grep -q 'git_untrackedfile.txt' <<< "$result"
assert_true "git_status shows ?? prefix" grep -q '^??' <<< "$result"

# git_status clean repo
(cd "$_git_local" && git add -A && git commit -m "status test" >/dev/null 2>&1)
result=$(cd "$_git_local" && git_status)
assert_equal "git_status clean repo" "" "$result"

###############
# Test git show

result=$(cd "$_git_local" && git_show HEAD)
assert_true "git_show displays commit" grep -q 'status test' <<< "$result"

###############
# Test git diffstat

(
    cd "$_git_local"
    echo "diffstat-content" > git_diffstatfile.txt
    git add git_diffstatfile.txt
)
result=$(cd "$_git_local" && git_diffstat --cached)
assert_true "git_diffstat shows changed file" grep -q 'git_diffstatfile.txt' <<< "$result"
assert_true "git_diffstat shows insertion count" grep -q 'insertion' <<< "$result"
(cd "$_git_local" && git commit -m "diffstat test" >/dev/null 2>&1)

###############
# Test git addremove

# git_addremove stages new files and removals
(
    cd "$_git_local"
    echo "newfile" > addremove_new.txt
    git rm -f git_statusfile.txt >/dev/null 2>&1
    git reset HEAD >/dev/null 2>&1
    rm -f git_statusfile.txt
)
(cd "$_git_local" && git_addremove >/dev/null 2>&1)
result=$(cd "$_git_local" && git status --short)
assert_true "git_addremove stages new file" grep -q '^A.*addremove_new.txt' <<< "$result"
assert_true "git_addremove stages removal" grep -q '^D.*git_statusfile.txt' <<< "$result"
# clean up
(cd "$_git_local" && git commit -m "addremove test" >/dev/null 2>&1)

test_summary "git"
