#!/bin/bash
#
# Tests for jj VCS implementation functions.
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
# Configure a test user so commits can be pushed
(cd "$_jj_repo" && jj config set --repo user.name "Test User")
(cd "$_jj_repo" && jj config set --repo user.email "test@example.com")

###############
# Test jj base

# jj_base on a fresh repo returns something (the root commit), * prefix, no @ prefix
result=$(cd "$_jj_repo" && jj_base 2>&1)
assert_true "jj_base fresh repo returns something" test -n "$result"
assert_false "jj_base fresh repo has no @ prefix" grep -q '^@ ' <<< "$result"
assert_true "jj_base fresh repo has * prefix" grep -q '^\* ' <<< "$result"

# jj_base changes after a commit — shows parent with * prefix, no @ line (wc has no description)
(
    cd "$_jj_repo"
    echo "base-test" > basefile.txt
    jj commit -m "jj base test commit" >/dev/null 2>&1
)
result=$(cd "$_jj_repo" && jj_base)
assert_true "jj_base after commit shows parent description" grep -q 'jj base test commit' <<< "$result"
assert_false "jj_base has no @ prefix when wc undescribed" grep -q '^@ ' <<< "$result"
assert_true "jj_base has * prefix for parent" grep -q '^\* ' <<< "$result"

# jj_base shows both @ (wc) and * (parent) when working copy has a description
(cd "$_jj_repo" && jj describe -m "wc description" >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj_base)
assert_true "jj_base shows parent when wc described" grep -q 'jj base test commit' <<< "$result"
assert_true "jj_base shows wc description with @ prefix" grep -q '^@ .*wc description' <<< "$result"
assert_true "jj_base shows parent with * prefix" grep -q '^\* .*jj base test commit' <<< "$result"
# Clean up: remove the description
(cd "$_jj_repo" && jj describe -m "" >/dev/null 2>&1)

# jj_base changes after a second commit
(
    cd "$_jj_repo"
    echo "second" > secondfile.txt
    jj commit -m "jj second base commit" >/dev/null 2>&1
)
result=$(cd "$_jj_repo" && jj_base)
assert_true "jj_base shows second commit" grep -q 'jj second base commit' <<< "$result"

# jj prev creates a new branch point so @ still has no children - at-tip behavior
(cd "$_jj_repo" && jj prev >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj_base)
assert_true "jj_base after prev shows earlier commit" grep -q 'jj base test commit' <<< "$result"

# Restore to tip for subsequent tests
(cd "$_jj_repo" && jj next >/dev/null 2>&1)
(cd "$_jj_repo" && jj new >/dev/null 2>&1)

###############
# Test jj graph

_jj_graph_wc=$(cd "$_jj_repo" && jj log --no-graph -r @ -T 'change_id.shortest()')
_jj_graph_parent=$(cd "$_jj_repo" && jj log --no-graph -r @- -T 'change_id.shortest()')
_jj_graph_parent_desc=$(cd "$_jj_repo" && jj log --no-graph -r @- -T 'if(description, description.first_line(), "(no description set)")')
result=$(cd "$_jj_repo" && jj_graph -r '@|@-')
assert_equal "jj_graph two commits" \
"@  $_jj_graph_wc (no description set)
○  $_jj_graph_parent $_jj_graph_parent_desc
│
~" \
"$result"

###############
# Test jj outgoing and incoming

# Push existing commits so they become immutable and don't appear in outgoing
_jj_git_remote="$_testdir/jj_git_remote"
git init --bare "$_jj_git_remote" >/dev/null 2>&1
(cd "$_jj_repo" && jj git remote add origin "$_jj_git_remote" >/dev/null 2>&1)
# Point main at the latest non-empty mutable commit (not an empty WC intermediate)
(cd "$_jj_repo" && jj bookmark create main -r "latest(mutable() ~ empty())" >/dev/null 2>&1)
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

###############
# Test jj drop

# jj_drop abandons a commit
(
    cd "$_jj_repo"
    echo "drop-content" > jj_dropfile.txt
    jj commit -m "jj drop target" >/dev/null 2>&1
)
_jj_drop_id=$(cd "$_jj_repo" && jj log --no-graph -r '@-' -T 'change_id.shortest()')
(cd "$_jj_repo" && jj_drop "$_jj_drop_id" >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj log --no-graph -r 'all()' -T 'description')
assert_false "jj_drop abandons commit" grep -q 'jj drop target' <<< "$result"

###############
# Test jj describe

# jj_describe edits the commit description
(cd "$_jj_repo" && jj_describe -m "jj describe test" >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj log --no-graph -r @ -T 'description')
assert_true "jj_describe changes description" grep -q 'jj describe test' <<< "$result"

###############
# Test jj rename

(
    cd "$_jj_repo"
    echo "rename-me" > jj_renamefile.txt
    jj commit -m "add renamefile" >/dev/null 2>&1
)
(cd "$_jj_repo" && jj_rename jj_renamefile.txt jj_renamed.txt >/dev/null 2>&1)
assert_true "jj_rename moves file" test -f "$_jj_repo/jj_renamed.txt"
assert_false "jj_rename removes original" test -f "$_jj_repo/jj_renamefile.txt"
result=$(cd "$_jj_repo" && jj diff --summary)
assert_true "jj_rename shows rename in diff" test -n "$result"
(cd "$_jj_repo" && jj commit -m "rename test" >/dev/null 2>&1)

# jj_rename with wrong number of args fails
result=$(cd "$_jj_repo" && jj_rename only_one_arg 2>&1)
assert_equal "jj_rename wrong args returns 1" "1" "$?"
assert_true "jj_rename wrong args shows usage" grep -q 'usage' <<< "$result"

###############
# Test jj remove

(
    cd "$_jj_repo"
    echo "remove-me" > jj_removefile.txt
    jj commit -m "add removefile" >/dev/null 2>&1
)
(cd "$_jj_repo" && jj_remove jj_removefile.txt >/dev/null 2>&1)
assert_false "jj_remove deletes file" test -f "$_jj_repo/jj_removefile.txt"
result=$(cd "$_jj_repo" && jj diff --summary)
assert_true "jj_remove untracks file" grep -q 'jj_removefile.txt' <<< "$result"
(cd "$_jj_repo" && jj commit -m "remove test" >/dev/null 2>&1)

###############
# Test jj cp

(
    cd "$_jj_repo"
    echo "cp-me" > jj_copyfile.txt
    jj commit -m "add cpfile" >/dev/null 2>&1
)
(cd "$_jj_repo" && jj_copy jj_copyfile.txt jj_copyd.txt >/dev/null 2>&1)
assert_true "jj_copy creates copy" test -f "$_jj_repo/jj_copyd.txt"
assert_true "jj_copy keeps original" test -f "$_jj_repo/jj_copyfile.txt"
(cd "$_jj_repo" && jj commit -m "cp test" >/dev/null 2>&1)

###############
# Test jj mv and rm

(
    cd "$_jj_repo"
    echo "mv-me" > jj_mvfile.txt
    jj commit -m "add mvfile" >/dev/null 2>&1
)
(cd "$_jj_repo" && jj_mv jj_mvfile.txt jj_mvd.txt >/dev/null 2>&1)
assert_true "jj_mv moves file" test -f "$_jj_repo/jj_mvd.txt"
assert_false "jj_mv removes original" test -f "$_jj_repo/jj_mvfile.txt"
(cd "$_jj_repo" && jj commit -m "mv test" >/dev/null 2>&1)

(
    cd "$_jj_repo"
    echo "rm-me" > jj_rmfile.txt
    jj commit -m "add rmfile" >/dev/null 2>&1
)
(cd "$_jj_repo" && jj_rm jj_rmfile.txt >/dev/null 2>&1)
assert_false "jj_rm deletes file" test -f "$_jj_repo/jj_rmfile.txt"
(cd "$_jj_repo" && jj commit -m "rm test" >/dev/null 2>&1)

###############
# Test jj prev and next

# Create a chain of commits to navigate; capture nav C's id for reliable cleanup
(
    cd "$_jj_repo"
    echo "nav-a" > jj_nav_a.txt
    jj commit -m "jj nav A" >/dev/null 2>&1
    echo "nav-b" > jj_nav_b.txt
    jj commit -m "jj nav B" >/dev/null 2>&1
)
_jj_nav_c_id=$(cd "$_jj_repo" && jj log --no-graph -r @ -T 'change_id')
(
    cd "$_jj_repo"
    echo "nav-c" > jj_nav_c.txt
    jj commit -m "jj nav C" >/dev/null 2>&1
)

# jj_prev positions @ as a new child of the parent (from empty @ on top of C)
(cd "$_jj_repo" && jj_prev >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj log --no-graph -r @- -T 'description')
assert_true "jj_prev new @ is child of C's parent" grep -q 'jj nav B' <<< "$result"

# jj_prev again positions @ as child of B's parent
(cd "$_jj_repo" && jj_prev >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj log --no-graph -r @- -T 'description')
assert_true "jj_prev again moves one step back" grep -q 'jj nav A' <<< "$result"

# jj_next moves forward one step
(cd "$_jj_repo" && jj_next >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj log --no-graph -r @- -T 'description')
assert_true "jj_next moves to child" grep -q 'jj nav B' <<< "$result"

# clean up: restore to a direct child of nav C (not via jj next which creates an intermediate WC)
(cd "$_jj_repo" && jj new "$_jj_nav_c_id" >/dev/null 2>&1)

###############
# Test jj goto

# jj_goto creates new @ as child of target revision
_jj_goto_target=$(cd "$_jj_repo" && jj log --no-graph -r '@--' -T 'change_id.shortest()')
(cd "$_jj_repo" && jj_goto "$_jj_goto_target" >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj log --no-graph -r @- -T 'description')
assert_true "jj_goto new @ is child of target" grep -q 'jj nav B' <<< "$result"

# jj_goto back to the tip (latest non-empty mutable commit = jj nav C)
_jj_goto_tip=$(cd "$_jj_repo" && jj log --no-graph -r 'latest(mutable() ~ empty())' -T 'change_id.shortest()')
(cd "$_jj_repo" && jj_goto "$_jj_goto_tip" >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj log --no-graph -r @- -T 'description')
assert_true "jj_goto back to tip" grep -q 'jj nav C' <<< "$result"

# clean up: create a new working copy on top
(cd "$_jj_repo" && jj new >/dev/null 2>&1)

###############
# Test jj uncommit

# jj_uncommit moves changes from parent into the working copy
(
    cd "$_jj_repo"
    echo "uncommit-content" > jj_uncommitfile.txt
    jj commit -m "jj uncommit test" >/dev/null 2>&1
)
assert_true "jj before uncommit file in parent" \
    bash -c "cd '$_jj_repo' && jj file show jj_uncommitfile.txt -r @- 2>/dev/null | grep -q uncommit-content"
(cd "$_jj_repo" && jj_uncommit >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj diff --summary)
assert_true "jj_uncommit moves changes to working copy" grep -q 'jj_uncommitfile.txt' <<< "$result"
# clean up
(cd "$_jj_repo" && jj commit -m "re-commit after uncommit" >/dev/null 2>&1)

###############
# Test jj absorb

# jj_absorb automatically amends changes into the correct prior commits
(
    cd "$_jj_repo"
    echo "absorb-line1" > jj_absorbfile.txt
    jj commit -m "jj absorb base commit" >/dev/null 2>&1
    echo "absorb-line2" > jj_absorbfile2.txt
    jj commit -m "jj absorb second commit" >/dev/null 2>&1
    # Modify a file from the first commit
    echo "absorb-line1-modified" > jj_absorbfile.txt
)
(cd "$_jj_repo" && jj_absorb >/dev/null 2>&1)
result=$(cd "$_jj_repo" && jj file show jj_absorbfile.txt -r @-- 2>/dev/null)
assert_equal "jj_absorb absorbed change into base" "absorb-line1-modified" "$result"
# The second commit should be unchanged
result=$(cd "$_jj_repo" && jj log --no-graph -r @- -T 'description')
assert_true "jj_absorb keeps second commit" grep -q 'jj absorb second commit' <<< "$result"

###############
# Test backend-dependent dispatch

# Ensure cache exists with backend info
rm -f "$_jj_repo/.vcs_cache"
(cd "$_jj_repo" && vcs >/dev/null)

# The test repo was created with jj git init, so backend should be git
result=$(cd "$_jj_repo" && vcs_backend)
assert_equal "jj test repo has git backend" "git" "$result"

# Stub jj to capture commands dispatched by each function
_jj_cmd_log="$_testdir/jj_cmd_log"

jj() { echo "$*" >> "$_jj_cmd_log"; }

: > "$_jj_cmd_log"
(cd "$_jj_repo" && jj_push --bookmark main 2>/dev/null)
result=$(cat "$_jj_cmd_log")
assert_contains "jj_push uses git push for git backend" "git push" "$result"

: > "$_jj_cmd_log"
(cd "$_jj_repo" && jj_pull 2>/dev/null)
result=$(cat "$_jj_cmd_log")
assert_contains "jj_pull uses git fetch for git backend" "git fetch" "$result"

: > "$_jj_cmd_log"
(cd "$_jj_repo" && jj_fastforward 2>/dev/null)
result=$(cat "$_jj_cmd_log")
assert_contains "jj_fastforward uses git fetch for git backend" "git fetch" "$result"

: > "$_jj_cmd_log"
(cd "$_jj_repo" && jj_submit 2>/dev/null)
result=$(cat "$_jj_cmd_log")
assert_contains "jj_submit uses git push for git backend" "git push" "$result"

: > "$_jj_cmd_log"
(cd "$_jj_repo" && jj_review 2>/dev/null)
result=$(cat "$_jj_cmd_log")
assert_contains "jj_review uses git push for git backend" "git push" "$result"

: > "$_jj_cmd_log"
(cd "$_jj_repo" && jj_upload 2>/dev/null)
result=$(cat "$_jj_cmd_log")
assert_contains "jj_upload uses git push for git backend" "git push" "$result"

: > "$_jj_cmd_log"
(cd "$_jj_repo" && jj_uploadchain 2>/dev/null)
result=$(cat "$_jj_cmd_log")
assert_contains "jj_uploadchain uses git push for git backend" "git push" "$result"

: > "$_jj_cmd_log"
(cd "$_jj_repo" && jj_presubmit 2>/dev/null)
result=$(cat "$_jj_cmd_log")
assert_equal "jj_presubmit no-ops for git backend" "" "$result"

###############
# Test GitHub review/upload with gh integration

vcs_hosting() { echo "github"; }
have_command() { test "$1" = "gh" || command -v "$1" >/dev/null 2>&1; }

_gh_cmd_log="$_testdir/gh_cmd_log"

# Create a gh stub script on PATH so "command gh" finds it
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

: > "$_jj_cmd_log"
: > "$_gh_cmd_log"
(cd "$_jj_repo" && jj_review 2>/dev/null)
result=$(cat "$_jj_cmd_log")
assert_contains "jj_review github pushes" "git push" "$result"
result=$(cat "$_gh_cmd_log")
assert_contains "jj_review github creates PR" "pr create" "$result"
assert_contains "jj_review github creates draft PR" "--draft" "$result"

: > "$_jj_cmd_log"
: > "$_gh_cmd_log"
(cd "$_jj_repo" && jj_review -r someone 2>/dev/null)
result=$(cat "$_jj_cmd_log")
assert_contains "jj_review -r github pushes" "git push" "$result"
result=$(cat "$_gh_cmd_log")
assert_contains "jj_review -r github creates PR" "pr create" "$result"
assert_contains "jj_review -r adds reviewer" "--reviewer someone" "$result"
assert_not_contains "jj_review -r not draft" "--draft" "$result"

: > "$_jj_cmd_log"
: > "$_gh_cmd_log"
(cd "$_jj_repo" && jj_review -m mailme 2>/dev/null)
result=$(cat "$_gh_cmd_log")
assert_contains "jj_review -m creates PR" "pr create" "$result"
assert_contains "jj_review -m adds reviewer" "--reviewer mailme" "$result"
assert_not_contains "jj_review -m not draft" "--draft" "$result"

: > "$_jj_cmd_log"
: > "$_gh_cmd_log"
(cd "$_jj_repo" && jj_review --reviewer someone 2>/dev/null)
result=$(cat "$_gh_cmd_log")
assert_contains "jj_review --reviewer adds reviewer" "--reviewer someone" "$result"
assert_not_contains "jj_review --reviewer not draft" "--draft" "$result"

: > "$_jj_cmd_log"
: > "$_gh_cmd_log"
(cd "$_jj_repo" && jj_review --reviewer=eqsign 2>/dev/null)
result=$(cat "$_gh_cmd_log")
assert_contains "jj_review --reviewer= adds reviewer" "--reviewer eqsign" "$result"
assert_not_contains "jj_review --reviewer= not draft" "--draft" "$result"

: > "$_jj_cmd_log"
: > "$_gh_cmd_log"
(cd "$_jj_repo" && jj_upload 2>/dev/null)
result=$(cat "$_gh_cmd_log")
assert_contains "jj_upload github creates PR" "pr create" "$result"

: > "$_jj_cmd_log"
: > "$_gh_cmd_log"
(cd "$_jj_repo" && jj_uploadchain 2>/dev/null)
result=$(cat "$_gh_cmd_log")
assert_contains "jj_uploadchain github creates PR" "pr create" "$result"

PATH="${PATH#$_gh_stub_dir:}"
unset -f jj vcs_hosting have_command
rm -f "$_jj_cmd_log" "$_gh_cmd_log"

test_summary "jj"
