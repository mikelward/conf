#!/bin/sh
#
# Tests for scripts/check-rule-size.sh, and that the rule files it guards
# fit under the cap.

. "$(dirname "$0")/shrc_test_lib.sh"

_check="$_srcdir/scripts/check-rule-size.sh"
_ci="$_srcdir/.github/workflows/ci.yml"

# shrc_test_lib.sh made $_testdir and removes it on exit.
_tmp="$_testdir"

# Where the failing cases' messages go, out of the suite's output.
_err="$_tmp/err"

# A file of exactly $1 bytes.
make_file() {
    head -c "$1" /dev/zero | tr '\0' x > "$2"
}

# Run the check with its messages in $_err.
sh_quiet() {
    sh "$@" 2>"$_err"
}

start_test "a file under 24,000 bytes passes"
make_file 23999 "$_tmp/under.md"
assert_true sh "$_check" "$_tmp/under.md"

start_test "a file of exactly 24,000 bytes fails, since Antigravity's cap is 24 KB"
make_file 24000 "$_tmp/at.md"
assert_false sh_quiet "$_check" "$_tmp/at.md"

start_test "an oversized file is named, with its size"
make_file 24001 "$_tmp/over.md"
_out=$(sh "$_check" "$_tmp/over.md" 2>&1)
assert_contains "over.md is 24001 bytes" "$_out"

start_test "one oversized file among several fails the run"
assert_false sh_quiet "$_check" "$_tmp/under.md" "$_tmp/over.md"

start_test "a missing file fails rather than passing unchecked"
assert_false sh_quiet "$_check" "$_tmp/missing.md"

start_test "with no arguments it checks both AGENTS.md files, which fit"
assert_true sh -c 'cd "$1" && sh scripts/check-rule-size.sh' sh "$_srcdir"

start_test "CI runs it in the lanes job, which docs-only pull requests still get"
_lanes=$(sed -n '/^  lanes:/,$p' "$_ci")
assert_contains "scripts/check-rule-size.sh" "$_lanes"

test_summary "check-rule-size"
