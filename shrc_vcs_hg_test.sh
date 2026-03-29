#!/bin/bash
#
# Tests for hg VCS backend functions.
#

source "$(dirname "$0")/shrc_test_lib.sh"

# shellcheck source=shrc.vcs
source "$_srcdir/shrc.vcs" >/dev/null 2>&1
source "$_srcdir/shrc.vcs.hg"

# Clear hg environment that leaks in when run from an hg hook
unset HG_NODE HG_PARENT1 HG_PARENT2 HG_PENDING HG_HOOKTYPE HG_HOOKNAME

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
# Test hg base

# hg_base on a fresh clone shows the initial commit
result=$(cd "$_hg_local" && hg_base)
assert_true "hg_base fresh clone shows commit" grep -q 'initial commit' <<< "$result"

# hg_base changes after a new commit
(
    cd "$_hg_local"
    echo "base-test" > basefile.txt
    hg add basefile.txt
    hg commit -m "hg base test commit" -u "test <test@test.com>"
)
result=$(cd "$_hg_local" && hg_base)
assert_true "hg_base after commit shows new commit" grep -q 'hg base test commit' <<< "$result"

# hg_base changes after update to a different revision
_hg_base_rev=$(cd "$_hg_local" && hg log -r . --template '{rev}')
(cd "$_hg_local" && hg update -r 0 >/dev/null 2>&1)
result=$(cd "$_hg_local" && hg_base)
assert_true "hg_base after update shows earlier commit" grep -q 'initial commit' <<< "$result"

# hg_base changes back after update to the tip
(cd "$_hg_local" && hg update -r "$_hg_base_rev" >/dev/null 2>&1)
result=$(cd "$_hg_local" && hg_base)
assert_true "hg_base after update back shows latest" grep -q 'hg base test commit' <<< "$result"

###############
# Test hg outgoing and incoming

# Push the commit created by the base tests so outgoing starts clean
(cd "$_hg_local" && hg push >/dev/null 2>&1)

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

###############
# Test hg rename

(
    cd "$_hg_local"
    echo "rename-me" > hg_renamefile.txt
    hg add hg_renamefile.txt
    hg commit -m "add renamefile" -u "test <test@test.com>"
)
(cd "$_hg_local" && hg_rename hg_renamefile.txt hg_renamed.txt >/dev/null 2>&1)
assert_true "hg_rename moves file" test -f "$_hg_local/hg_renamed.txt"
assert_false "hg_rename removes original" test -f "$_hg_local/hg_renamefile.txt"
result=$(cd "$_hg_local" && hg status)
assert_true "hg_rename stages add" grep -q '^A hg_renamed.txt' <<< "$result"
assert_true "hg_rename stages remove" grep -q '^R hg_renamefile.txt' <<< "$result"
(cd "$_hg_local" && hg commit -m "rename test" -u "test <test@test.com>" >/dev/null 2>&1)

###############
# Test hg remove

(
    cd "$_hg_local"
    echo "remove-me" > hg_removefile.txt
    hg add hg_removefile.txt
    hg commit -m "add removefile" -u "test <test@test.com>"
)
(cd "$_hg_local" && hg_remove hg_removefile.txt >/dev/null 2>&1)
assert_false "hg_remove deletes file" test -f "$_hg_local/hg_removefile.txt"
result=$(cd "$_hg_local" && hg status)
assert_true "hg_remove stages removal" grep -q '^R hg_removefile.txt' <<< "$result"
(cd "$_hg_local" && hg commit -m "remove test" -u "test <test@test.com>" >/dev/null 2>&1)

###############
# Test hg cp

(
    cd "$_hg_local"
    echo "cp-me" > hg_copyfile.txt
    hg add hg_copyfile.txt
    hg commit -m "add cpfile" -u "test <test@test.com>"
)
(cd "$_hg_local" && hg_copy hg_copyfile.txt hg_copyd.txt >/dev/null 2>&1)
assert_true "hg_copy creates copy" test -f "$_hg_local/hg_copyd.txt"
assert_true "hg_copy keeps original" test -f "$_hg_local/hg_copyfile.txt"
result=$(cd "$_hg_local" && hg status)
assert_true "hg_copy stages new file" grep -q '^A hg_copyd.txt' <<< "$result"
(cd "$_hg_local" && hg commit -m "cp test" -u "test <test@test.com>" >/dev/null 2>&1)

###############
# Test hg mv and rm

(
    cd "$_hg_local"
    echo "mv-me" > hg_mvfile.txt
    hg add hg_mvfile.txt
    hg commit -m "add mvfile" -u "test <test@test.com>"
)
(cd "$_hg_local" && hg_mv hg_mvfile.txt hg_mvd.txt >/dev/null 2>&1)
assert_true "hg_mv moves file" test -f "$_hg_local/hg_mvd.txt"
assert_false "hg_mv removes original" test -f "$_hg_local/hg_mvfile.txt"
(cd "$_hg_local" && hg commit -m "mv test" -u "test <test@test.com>" >/dev/null 2>&1)

(
    cd "$_hg_local"
    echo "rm-me" > hg_rmfile.txt
    hg add hg_rmfile.txt
    hg commit -m "add rmfile" -u "test <test@test.com>"
)
(cd "$_hg_local" && hg_rm hg_rmfile.txt >/dev/null 2>&1)
assert_false "hg_rm deletes file" test -f "$_hg_local/hg_rmfile.txt"
result=$(cd "$_hg_local" && hg status)
assert_true "hg_rm stages removal" grep -q '^R hg_rmfile.txt' <<< "$result"
(cd "$_hg_local" && hg commit -m "rm test" -u "test <test@test.com>" >/dev/null 2>&1)

###############
# Test hg drop

# hg_drop requires the evolve extension; skip if unavailable
if hg help prune >/dev/null 2>&1; then
    (
        cd "$_hg_local"
        echo "drop-content" > hg_dropfile.txt
        hg add hg_dropfile.txt
        hg commit -m "hg drop target" -u "test <test@test.com>"
    )
    _hg_drop_rev=$(cd "$_hg_local" && hg log -r . --template '{rev}')
    (cd "$_hg_local" && hg_drop -r "$_hg_drop_rev" >/dev/null 2>&1)
    result=$(cd "$_hg_local" && hg log -r "not obsolete()" --template '{desc}\n')
    assert_false "hg_drop obsoletes commit" grep -q 'hg drop target' <<< "$result"
else
    echo "SKIP: hg prune not available (evolve extension not installed)"
fi

###############
# Test hg describe

# hg_describe edits the commit message (like reword)
(cd "$_hg_local" && hg_describe >/dev/null 2>&1)
result=$(cd "$_hg_local" && hg log -r . --template '{desc}')
assert_equal "hg_describe changes message" "edited by test" "$result"

###############
# Test hg absorb

# hg_absorb requires the absorb extension; skip if unavailable
if hg help absorb >/dev/null 2>&1; then
    (
        cd "$_hg_local"
        echo "absorb-line1" > hg_absorbfile.txt
        hg add hg_absorbfile.txt
        hg commit -m "hg absorb base commit" -u "test <test@test.com>"
        echo "absorb-line2" > hg_absorbfile2.txt
        hg add hg_absorbfile2.txt
        hg commit -m "hg absorb second commit" -u "test <test@test.com>"
        # Modify a file from the first commit
        echo "absorb-line1-modified" > hg_absorbfile.txt
    )
    (cd "$_hg_local" && hg_absorb >/dev/null 2>&1)
    result=$(cd "$_hg_local" && hg log -r .~ --template '{desc}')
    assert_equal "hg_absorb amends correct commit" "hg absorb base commit" "$result"
    result=$(cd "$_hg_local" && hg cat -r .~ hg_absorbfile.txt)
    assert_true "hg_absorb absorbed change into base" grep -q 'absorb-line1-modified' <<< "$result"
else
    echo "SKIP: hg absorb not available (absorb extension not installed)"
fi

test_summary "hg"
