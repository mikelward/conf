#!/bin/dash
#
# End-to-end test that sourcing shrc under a real dash subshell falls
# into the basic-mode short-circuit cleanly -- no syntax error, no
# bashism blowup. shrc functions aren't expected to work under dash
# (the bash/zsh-only test suite lives in shrc_test.sh), this file only
# guards the "user accidentally invoked sh/dash" path.
#
# Run from the Makefile via `dash shrc_dash_test.sh`.

. "$(dirname "$0")/shrc_test_lib.sh"

# A symlinked .shrc.vcs in $HOME used to surface a syntax-error
# regression here (shrc.vcs uses bash-only declare/array syntax). The
# basic-mode short-circuit at the top of shrc returns long before
# reaching the .shrc.vcs sourcing now, so this test mostly catches
# stray bashisms that slip in *above* the short-circuit.
start_test "shrc sources cleanly under dash despite .shrc.vcs present"
_vcsguard_home="$_testdir/vcsguard_home"
mkdir -p "$_vcsguard_home"
ln -sf "$_srcdir/shrc.vcs" "$_vcsguard_home/.shrc.vcs"
_vcsguard_stderr=$(HOME="$_vcsguard_home" run_with_timeout 10 dash -c '. "$1"' _ "$_srcdir/shrc" 2>&1 >/dev/null)
assert_not_contains "Syntax error" "$_vcsguard_stderr"

test_summary "shrc_dash_test"
