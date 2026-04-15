#!/bin/dash
#
# End-to-end tests that exercise shrc under a real `dash` subshell.
# Only the dash-specific behaviour (the bash/zsh guard around sourcing
# shrc.vcs, which uses bash-only syntax) lives here; the sh-portable
# shrc function tests live in shrc_test.sh.
#
# Run from the Makefile via `dash shrc_dash_test.sh`.

. "$(dirname "$0")/shrc_test_lib.sh"

# Sanity-check the guard end-to-end: running shrc under dash must not
# emit a syntax error from .shrc.vcs. Drop a symlink at $HOME/.shrc.vcs
# pointing at the repo's shrc.vcs and source shrc in a dash subshell.
# Without the guard this aborts with "Syntax error: '(' unexpected"
# on the declare/array syntax in _github_review.
start_test "shrc sources cleanly under dash despite .shrc.vcs present"
_vcsguard_home="$_testdir/vcsguard_home"
mkdir -p "$_vcsguard_home"
ln -sf "$_srcdir/shrc.vcs" "$_vcsguard_home/.shrc.vcs"
_vcsguard_stderr=$(HOME="$_vcsguard_home" run_with_timeout 10 dash -c '. "$1"' _ "$_srcdir/shrc" 2>&1 >/dev/null)
assert_not_contains "Syntax error" "$_vcsguard_stderr"

test_summary "shrc_dash_test"
