#!/bin/bash
#
# Tests for git VCS implementation functions.
#

source "$(dirname "$0")/shrc_test_lib.sh"

# shellcheck source=shrc.vcs
source "$_srcdir/shrc.vcs" >/dev/null 2>&1
source "$_srcdir/shrc.vcs.git"

# Clear git environment that leaks in when run from a git hook
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

###############
# Test git drop

# git_drop removes a commit and rebases descendants
(
    cd "$_git_local"
    echo "drop-base" > dropbase.txt
    git add dropbase.txt
    git commit -m "drop base commit" >/dev/null 2>&1
    echo "drop-target" > droptarget.txt
    git add droptarget.txt
    git commit -m "drop this commit" >/dev/null 2>&1
    echo "drop-child" > dropchild.txt
    git add dropchild.txt
    git commit -m "drop child commit" >/dev/null 2>&1
)
_drop_rev=$(cd "$_git_local" && git log --oneline | grep 'drop this commit' | awk '{print $1}')
(cd "$_git_local" && git_drop "$_drop_rev" >/dev/null 2>&1)
result=$(cd "$_git_local" && git log --oneline)
assert_false "git_drop removes target commit" grep -q 'drop this commit' <<< "$result"
assert_true "git_drop keeps child commit" grep -q 'drop child commit' <<< "$result"
assert_true "git_drop keeps base commit" grep -q 'drop base commit' <<< "$result"
assert_false "git_drop target file is gone" test -f "$_git_local/droptarget.txt"
assert_true "git_drop child file remains" test -f "$_git_local/dropchild.txt"

###############
# Test git fetch_time

# git_fetchtime returns empty when FETCH_HEAD doesn't exist
(cd "$_git_local" && rm -f "$(git rev-parse --git-dir)/FETCH_HEAD")
result=$(cd "$_git_local" && git_fetchtime)
assert_equal "git_fetchtime no FETCH_HEAD" "" "$result"

# git_fetchtime returns a timestamp after fetch
(cd "$_git_local" && git fetch >/dev/null 2>&1)
result=$(cd "$_git_local" && git_fetchtime)
assert_true "git_fetchtime after fetch is non-empty" test -n "$result"
assert_true "git_fetchtime returns a number" test "$result" -gt 0 2>/dev/null

# git_fetchtime updates after a new fetch
old_time=$result
sleep 1
(cd "$_git_local" && git fetch >/dev/null 2>&1)
new_time=$(cd "$_git_local" && git_fetchtime)
assert_true "git_fetchtime updates after fetch" test "$new_time" -ge "$old_time"

###############
# Test git describe

# git_describe edits the commit message (like reword)
(cd "$_git_local" && git_describe >/dev/null 2>&1)
result=$(cd "$_git_local" && git log -1 --format=%s)
assert_equal "git_describe changes message" "edited by test" "$result"

###############
# Test git rename

(
    cd "$_git_local"
    echo "rename-me" > git_renamefile.txt
    git add git_renamefile.txt
    git commit -m "add renamefile" >/dev/null 2>&1
)
(cd "$_git_local" && git_rename git_renamefile.txt git_renamed.txt >/dev/null 2>&1)
assert_true "git_rename moves file" test -f "$_git_local/git_renamed.txt"
assert_false "git_rename removes original" test -f "$_git_local/git_renamefile.txt"
result=$(cd "$_git_local" && git status --short)
assert_true "git_rename stages rename" grep -q 'R.*git_renamed.txt' <<< "$result"
(cd "$_git_local" && git commit -m "rename test" >/dev/null 2>&1)

###############
# Test git remove

(
    cd "$_git_local"
    echo "remove-me" > git_removefile.txt
    git add git_removefile.txt
    git commit -m "add removefile" >/dev/null 2>&1
)
(cd "$_git_local" && git_remove git_removefile.txt >/dev/null 2>&1)
assert_false "git_remove deletes file" test -f "$_git_local/git_removefile.txt"
result=$(cd "$_git_local" && git status --short)
assert_true "git_remove stages deletion" grep -q '^D.*git_removefile.txt' <<< "$result"
(cd "$_git_local" && git commit -m "remove test" >/dev/null 2>&1)

###############
# Test git cp

(
    cd "$_git_local"
    echo "cp-me" > git_copyfile.txt
    git add git_copyfile.txt
    git commit -m "add cpfile" >/dev/null 2>&1
)
(cd "$_git_local" && git_copy git_copyfile.txt git_copyd.txt >/dev/null 2>&1)
assert_true "git_copy creates copy" test -f "$_git_local/git_copyd.txt"
assert_true "git_copy keeps original" test -f "$_git_local/git_copyfile.txt"
result=$(cd "$_git_local" && git status --short)
assert_true "git_copy stages new file" grep -q 'A.*git_copyd.txt' <<< "$result"
(cd "$_git_local" && git commit -m "cp test" >/dev/null 2>&1)

###############
# Test git mv and rm

(
    cd "$_git_local"
    echo "mv-me" > git_mvfile.txt
    git add git_mvfile.txt
    git commit -m "add mvfile" >/dev/null 2>&1
)
(cd "$_git_local" && git_mv git_mvfile.txt git_mvd.txt >/dev/null 2>&1)
assert_true "git_mv moves file" test -f "$_git_local/git_mvd.txt"
assert_false "git_mv removes original" test -f "$_git_local/git_mvfile.txt"
(cd "$_git_local" && git commit -m "mv test" >/dev/null 2>&1)

(
    cd "$_git_local"
    echo "rm-me" > git_rmfile.txt
    git add git_rmfile.txt
    git commit -m "add rmfile" >/dev/null 2>&1
)
(cd "$_git_local" && git_rm git_rmfile.txt >/dev/null 2>&1)
assert_false "git_rm deletes file" test -f "$_git_local/git_rmfile.txt"
result=$(cd "$_git_local" && git status --short)
assert_true "git_rm stages deletion" grep -q '^D.*git_rmfile.txt' <<< "$result"
(cd "$_git_local" && git commit -m "rm test" >/dev/null 2>&1)

###############
# Test git prev and next

# git_prev moves to the parent commit
_head_before=$(cd "$_git_local" && git rev-parse HEAD)
_parent=$(cd "$_git_local" && git rev-parse HEAD~)
(cd "$_git_local" && git_prev 2>/dev/null)
_head_after=$(cd "$_git_local" && git rev-parse HEAD)
assert_equal "git_prev moves to parent" "$_parent" "$_head_after"

# git_next moves back to the child commit
(cd "$_git_local" && git_next 2>/dev/null)
_head_after=$(cd "$_git_local" && git rev-parse HEAD)
assert_equal "git_next moves to child" "$_head_before" "$_head_after"

# git_next at tip returns error
(cd "$_git_local" && git checkout "$_default_branch" >/dev/null 2>&1)
(cd "$_git_local" && git_next 2>/dev/null)
assert_equal "git_next at tip fails" "1" "$?"

# clean up: ensure we're on the branch
(cd "$_git_local" && git checkout "$_default_branch" >/dev/null 2>&1)

###############
# Test git goto

# git_goto switches to a specific revision
_git_goto_target=$(cd "$_git_local" && git rev-parse HEAD~2)
(cd "$_git_local" && git_goto "$_git_goto_target" >/dev/null 2>&1)
_git_goto_head=$(cd "$_git_local" && git rev-parse HEAD)
assert_equal "git_goto switches to target revision" "$_git_goto_target" "$_git_goto_head"

# git_goto switches to a branch
(cd "$_git_local" && git_goto "$_default_branch" >/dev/null 2>&1)
result=$(cd "$_git_local" && git rev-parse --abbrev-ref HEAD)
assert_equal "git_goto switches to branch" "$_default_branch" "$result"

###############
# Test git uncommit

# git_uncommit moves HEAD back and leaves changes staged
(
    cd "$_git_local"
    echo "uncommit-content" > uncommitfile.txt
    git add uncommitfile.txt
    git commit -m "uncommit test commit" >/dev/null 2>&1
)
_before_uncommit=$(cd "$_git_local" && git rev-parse HEAD~)
(cd "$_git_local" && git_uncommit >/dev/null 2>&1)
_after_uncommit=$(cd "$_git_local" && git rev-parse HEAD)
assert_equal "git_uncommit moves HEAD back" "$_before_uncommit" "$_after_uncommit"
assert_true "git_uncommit keeps file" test -f "$_git_local/uncommitfile.txt"
result=$(cd "$_git_local" && git status --short)
assert_true "git_uncommit leaves changes staged" grep -q '^A.*uncommitfile.txt' <<< "$result"
# clean up
(cd "$_git_local" && git commit -m "re-commit after uncommit" >/dev/null 2>&1)

###############
# Test git absorb

# git_absorb requires the git-absorb tool; skip if unavailable
if git absorb --help >/dev/null 2>&1; then
    (
        cd "$_git_local"
        echo "absorb-line1" > absorbfile.txt
        git add absorbfile.txt
        git commit -m "absorb base commit" >/dev/null 2>&1
        echo "absorb-line2" > absorbfile2.txt
        git add absorbfile2.txt
        git commit -m "absorb second commit" >/dev/null 2>&1
        # Modify a file from the first commit
        echo "absorb-line1-modified" > absorbfile.txt
        git add absorbfile.txt
    )
    (cd "$_git_local" && git_absorb >/dev/null 2>&1)
    result=$(cd "$_git_local" && git log -1 --format=%s HEAD~)
    assert_equal "git_absorb amends correct commit" "absorb base commit" "$result"
    result=$(cd "$_git_local" && git show HEAD~ -- absorbfile.txt)
    assert_true "git_absorb absorbed change into base" grep -q 'absorb-line1-modified' <<< "$result"
else
    echo "SKIP: git-absorb not installed"
fi

###############
# Test hosting-dependent dispatch

# Ensure cache exists with backend info
rm -f "$_git_local/.vcs_cache"
(cd "$_git_local" && vcs >/dev/null)

# Test repo has git backend
result=$(cd "$_git_local" && vcs_backend)
assert_equal "git test repo has git backend" "git" "$result"

# Stub git to capture commands dispatched by each function
_git_cmd_log="$_testdir/git_cmd_log"

# Override vcs_hosting to return github for testing
vcs_hosting() { echo "github"; }
have_command() { test "$1" = "gh" || command -v "$1" >/dev/null 2>&1; }

# Create a gh stub script on PATH so "command gh" finds it
_gh_cmd_log="$_testdir/gh_cmd_log"
_gh_stub_dir="$_testdir/gh_stub"
mkdir -p "$_gh_stub_dir"
cat > "$_gh_stub_dir/gh" <<GHEOF
#!/bin/sh
echo "\$*" >> "$_gh_cmd_log"
case "\$1 \$2" in
    "pr view") exit 1 ;;
    "repo view") echo "main" ;;
esac
GHEOF
chmod +x "$_gh_stub_dir/gh"
PATH="$_gh_stub_dir:$PATH"

git() {
    echo "$*" >> "$_git_cmd_log"
}

: > "$_git_cmd_log"
(cd "$_git_local" && git_review 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_review uses git push for github" "push" "$result"
assert_not_contains "git_review does not use refs/for for github" "refs/for" "$result"

: > "$_git_cmd_log"
(cd "$_git_local" && git_upload 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_upload uses git push for github" "push" "$result"
assert_not_contains "git_upload does not use refs/for for github" "refs/for" "$result"

: > "$_git_cmd_log"
(cd "$_git_local" && git_uploadchain 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_uploadchain uses git push for github" "push" "$result"
assert_not_contains "git_uploadchain does not use refs/for for github" "refs/for" "$result"

# Test gerrit dispatch
vcs_hosting() { echo "gerrit"; }

# Stub git_branch so the Gerrit ref can be constructed
git_branch() { echo "testbranch"; }

: > "$_git_cmd_log"
(cd "$_git_local" && git_review 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_review uses refs/for for gerrit" "refs/for" "$result"

: > "$_git_cmd_log"
(cd "$_git_local" && git_upload 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_upload uses refs/for for gerrit" "refs/for" "$result"

: > "$_git_cmd_log"
(cd "$_git_local" && git_uploadchain 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_uploadchain uses refs/for for gerrit" "refs/for" "$result"

###############
# Test GitHub review/upload with gh integration

vcs_hosting() { echo "github"; }

: > "$_git_cmd_log"
: > "$_gh_cmd_log"
(cd "$_git_local" && git_review 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_review github pushes" "push" "$result"
result=$(cat "$_gh_cmd_log")
assert_contains "git_review github creates PR" "pr create" "$result"
assert_contains "git_review github creates draft PR" "--draft" "$result"

: > "$_git_cmd_log"
: > "$_gh_cmd_log"
(cd "$_git_local" && git_review -r someone 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_review -r github pushes" "push" "$result"
result=$(cat "$_gh_cmd_log")
assert_contains "git_review -r github creates PR" "pr create" "$result"
assert_contains "git_review -r adds reviewer" "--reviewer someone" "$result"
assert_not_contains "git_review -r not draft" "--draft" "$result"

: > "$_git_cmd_log"
: > "$_gh_cmd_log"
(cd "$_git_local" && git_review -m mailme 2>/dev/null)
result=$(cat "$_gh_cmd_log")
assert_contains "git_review -m creates PR" "pr create" "$result"
assert_contains "git_review -m adds reviewer" "--reviewer mailme" "$result"
assert_not_contains "git_review -m not draft" "--draft" "$result"

: > "$_git_cmd_log"
: > "$_gh_cmd_log"
(cd "$_git_local" && git_review --reviewer someone 2>/dev/null)
result=$(cat "$_gh_cmd_log")
assert_contains "git_review --reviewer adds reviewer" "--reviewer someone" "$result"
assert_not_contains "git_review --reviewer not draft" "--draft" "$result"

: > "$_git_cmd_log"
: > "$_gh_cmd_log"
(cd "$_git_local" && git_review --reviewer=eqsign 2>/dev/null)
result=$(cat "$_gh_cmd_log")
assert_contains "git_review --reviewer= adds reviewer" "--reviewer eqsign" "$result"
assert_not_contains "git_review --reviewer= not draft" "--draft" "$result"

: > "$_git_cmd_log"
: > "$_gh_cmd_log"
(cd "$_git_local" && git_upload 2>/dev/null)
result=$(cat "$_gh_cmd_log")
assert_contains "git_upload github creates PR" "pr create" "$result"

: > "$_git_cmd_log"
: > "$_gh_cmd_log"
(cd "$_git_local" && git_uploadchain 2>/dev/null)
result=$(cat "$_gh_cmd_log")
assert_contains "git_uploadchain github creates PR" "pr create" "$result"

###############
# Test Gerrit review with -r flag

vcs_hosting() { echo "gerrit"; }
git_branch() { echo "testbranch"; }

: > "$_git_cmd_log"
(cd "$_git_local" && git_review 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_review uses refs/for for gerrit" "refs/for" "$result"

: > "$_git_cmd_log"
(cd "$_git_local" && git_review -r someone 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_review -r uses refs/for for gerrit" "refs/for" "$result"
assert_contains "git_review -r adds gerrit reviewer" "%r=someone" "$result"

: > "$_git_cmd_log"
(cd "$_git_local" && git_review -m mailme 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_review -m uses refs/for for gerrit" "refs/for" "$result"
assert_contains "git_review -m adds gerrit reviewer" "%r=mailme" "$result"

: > "$_git_cmd_log"
(cd "$_git_local" && git_review --reviewer someone 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_review --reviewer adds gerrit reviewer" "%r=someone" "$result"

: > "$_git_cmd_log"
(cd "$_git_local" && git_review --reviewer=eqsign 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_review --reviewer= adds gerrit reviewer" "%r=eqsign" "$result"

: > "$_git_cmd_log"
(cd "$_git_local" && git_upload 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_upload uses refs/for for gerrit" "refs/for" "$result"

: > "$_git_cmd_log"
(cd "$_git_local" && git_uploadchain 2>/dev/null)
result=$(cat "$_git_cmd_log")
assert_contains "git_uploadchain uses refs/for for gerrit" "refs/for" "$result"

PATH="${PATH#$_gh_stub_dir:}"
unset -f git vcs_hosting git_branch have_command
rm -f "$_git_cmd_log" "$_gh_cmd_log"

test_summary "git"
