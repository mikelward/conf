#!/bin/bash
#
# Tests for hg VCS backend functions.
#

source "$(dirname "$0")/shrc_vcs_test_helpers.sh"
source "$_srcdir/shrc.vcs.hg"

if ! command -v hg >/dev/null 2>&1; then
    echo "SKIP: hg not installed"
    exit 0
fi

# Use chg (persistent command server) if available for faster tests
if command -v chg >/dev/null 2>&1; then
    hg() { command chg "$@"; }
fi

###############
# Setup: create a "remote" hg repo and a local clone

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

###############
# Test hg outgoing and incoming

# Test hg_outgoing with no unpushed commits
result=$(cd "$_hg_local" && hg_outgoing 2>&1)
assert_equal "hg_outgoing no unpushed commits" "" "$result"

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

###############
# Test hg commit, amend, recommit, reword

# hg_commit creates a new changeset
(
    cd "$_hg_local"
    echo "commit-test" > commitfile.txt
    hg add commitfile.txt
)
(cd "$_hg_local" && hg_commit -m "hg commit test" -u "test <test@test.com>" >/dev/null 2>&1)
result=$(cd "$_hg_local" && hg log -r . --template '{desc}')
assert_equal "hg_commit with -m" "hg commit test" "$result"

# hg_recommit amends with new message
(cd "$_hg_local" && hg_recommit -m "hg recommit msg" -u "test <test@test.com>" >/dev/null 2>&1)
result=$(cd "$_hg_local" && hg log -r . --template '{desc}')
assert_equal "hg_recommit changes message" "hg recommit msg" "$result"

# hg_recommit can also add files (commit --amend)
(
    cd "$_hg_local"
    echo "amend-content" > amendfile.txt
    hg add amendfile.txt
)
(cd "$_hg_local" && hg_recommit -m "hg recommit msg" -u "test <test@test.com>" >/dev/null 2>&1)
assert_true "hg_recommit includes new file" \
    bash -c "cd '$_hg_local' && hg log -r . --template '{file_adds}' | grep -q amendfile.txt"

###############
# Test hg branch, revert, undo

# hg_branch returns the current branch
result=$(cd "$_hg_local" && hg_branch)
assert_equal "hg_branch returns current branch" "default" "$result"

# hg_revert restores a modified file
(
    cd "$_hg_local"
    echo "clean-content" > hg_revertfile.txt
    hg add hg_revertfile.txt
    hg commit -m "add revertfile" -u "test <test@test.com>"
    echo "dirty-content" > hg_revertfile.txt
)
(cd "$_hg_local" && hg_revert hg_revertfile.txt >/dev/null 2>&1)
result=$(cd "$_hg_local" && cat hg_revertfile.txt)
assert_equal "hg_revert restores file" "clean-content" "$result"

# hg_revert only reverts the named file
(
    cd "$_hg_local"
    echo "dirty-a" > hg_revertfile.txt
    echo "dirty-b" > commitfile.txt
)
(cd "$_hg_local" && hg_revert hg_revertfile.txt >/dev/null 2>&1)
result=$(cd "$_hg_local" && cat hg_revertfile.txt)
assert_equal "hg_revert reverts named file" "clean-content" "$result"
result=$(cd "$_hg_local" && cat commitfile.txt)
assert_equal "hg_revert keeps other changes" "dirty-b" "$result"
# clean up
(cd "$_hg_local" && hg revert --all >/dev/null 2>&1 && find . -name '*.orig' -delete)

###############
# Test hg status

# hg_status shows modified files
(cd "$_hg_local" && echo "dirty" > hg_statusfile.txt && hg add hg_statusfile.txt)
result=$(cd "$_hg_local" && hg_status)
assert_true "hg_status shows added file" grep -q 'hg_statusfile.txt' <<< "$result"
assert_true "hg_status shows A prefix" grep -q '^A' <<< "$result"

# hg_status clean repo
(cd "$_hg_local" && hg commit -m "status test" -u "test <test@test.com>" >/dev/null 2>&1)
result=$(cd "$_hg_local" && hg_status)
assert_equal "hg_status clean repo" "" "$result"

# hg_status shows unknown files
(cd "$_hg_local" && echo "unknown" > hg_unknownfile.txt)
result=$(cd "$_hg_local" && hg_status)
assert_true "hg_status shows unknown file" grep -q 'hg_unknownfile.txt' <<< "$result"
# clean up
rm "$_hg_local/hg_unknownfile.txt"

###############
# Test hg show

result=$(cd "$_hg_local" && hg_show)
assert_true "hg_show displays changeset" grep -q 'statusfile' <<< "$result"

###############
# Test hg diffstat

(
    cd "$_hg_local"
    echo "diffstat-content" > hg_diffstatfile.txt
    hg add hg_diffstatfile.txt
)
result=$(cd "$_hg_local" && hg_diffstat)
assert_true "hg_diffstat shows changed file" grep -q 'hg_diffstatfile.txt' <<< "$result"
assert_true "hg_diffstat shows insertion count" grep -q 'insertion' <<< "$result"
(cd "$_hg_local" && hg commit -m "diffstat test" -u "test <test@test.com>" >/dev/null 2>&1)

###############
# Test hg addremove

# hg_addremove adds untracked and removes missing files
(
    cd "$_hg_local"
    echo "newfile" > hg_addremove_new.txt
    rm -f hg_statusfile.txt
)
(cd "$_hg_local" && hg_addremove >/dev/null 2>&1)
result=$(cd "$_hg_local" && hg status)
assert_true "hg_addremove adds new file" grep -q '^A hg_addremove_new.txt' <<< "$result"
assert_true "hg_addremove removes missing file" grep -q '^R hg_statusfile.txt' <<< "$result"
# clean up
(cd "$_hg_local" && hg commit -m "addremove test" -u "test <test@test.com>" >/dev/null 2>&1)

test_summary "hg"
