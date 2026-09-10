#!/bin/mksh
#
# End-to-end test that sourcing shrc under a real ksh subshell falls
# into the failsafe-mode short-circuit cleanly -- no syntax error, no
# bashism blowup. shrc functions aren't expected to work under ksh
# (the bash/zsh-only test suite lives in shrc_test.sh); ksh is
# bottom-tier alongside dash, so this file only guards the "shell isn't
# a feature target" path. mksh is the proxy: the most-shipped, most
# POSIX-strict member of the ksh family (Android's /bin/sh, embedded),
# so passing under it covers OpenBSD ksh and ksh93 in practice.
#
# Run from the Makefile via `mksh shrc_ksh_test.sh`.

. "$(dirname "$0")/shrc_test_lib.sh"

# A symlinked .shrc.vcs in $HOME used to surface a syntax-error
# regression under non-bash shells (shrc.vcs uses bash-only
# declare/array syntax). The failsafe-mode short-circuit at the top of
# shrc returns long before reaching the .shrc.vcs sourcing, so this
# test mostly catches stray bashisms that slip in *above* the
# short-circuit.
start_test "shrc sources cleanly under ksh despite .shrc.vcs present"
_vcsguard_home="$_testdir/vcsguard_home"
mkdir -p "$_vcsguard_home"
ln -sf "$_srcdir/shrc.vcs" "$_vcsguard_home/.shrc.vcs"
_vcsguard_stderr=$(HOME="$_vcsguard_home" run_with_timeout 10 mksh -c '. "$1"' _ "$_srcdir/shrc" 2>&1 >/dev/null)
assert_not_contains "Syntax error" "$_vcsguard_stderr"

# ksh sets KSH_VERSION and slips past the sh/dash $0 check, so the
# is_ksh branch of the failsafe condition is what routes it here.
# Assert the short-circuit actually fired rather than the rich config
# running silently.
start_test "shrc reaches failsafe mode under ksh"
_failsafe_stderr=$(HOME="$_vcsguard_home" run_with_timeout 10 mksh -c '. "$1"' _ "$_srcdir/shrc" 2>&1 >/dev/null)
assert_contains "failsafe mode" "$_failsafe_stderr"

test_summary "shrc_ksh_test"
