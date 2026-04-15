#!/bin/bash
#
# End-to-end tests that exercise shrc under a real `bash -i` subshell.
# Only the bash-specific behaviour (DEBUG-trap autocd hook, inherited
# aliases, stty guard) lives here; the sh-portable shrc function tests
# live in shrc_test.sh and are driven under both dash and bash.
#
# Run from the Makefile via `bash shrc_bash_test.sh`.

. "$(dirname "$0")/shrc_test_lib.sh"

# Set up a temp directory tree for cd tests
_autocd_root="$_testdir/autocd"
mkdir -p "$_autocd_root/sub"

# End-to-end: bash -i with shrc should autocd into a trailing-slash dir
# via the DEBUG trap hook. (Without the hook, bash would error with
# "Is a directory" since command_not_found_handle doesn't fire for
# paths containing `/` that happen to resolve to a directory.)
#
# Terminal-title escapes from the prompt machinery land on the same
# line as our marker, so match anywhere on the line, not just ^.
# `--norc --noprofile` skips the invoking user's rc files (e.g. a
# distro default `alias l='ls -CF'` that would clash with shrc's
# `l() { ... }` function definition via bash parse-time alias
# expansion); we only want to exercise shrc itself here.
# run_interactive_with_timeout prefixes `setsid` so bash -i starts in
# a new session with no controlling tty; without that, tcsetattr calls
# from the prompt / readline / shrc's `stty start undef stop undef`
# guard fire SIGTTOU against a non-foreground pgrp and suspend the
# subshell ("Suspended (tty output)"), hanging `make test` whenever it
# is run under a real pty (CI terminal, `script -c`, etc.). </dev/null
# is kept for the same reason against older toolchains that lack
# setsid -- and the timeout -k fallback in run_with_timeout bounds any
# residual hang to ~N+2s.
start_test "bash -i autocds on trailing slash via DEBUG trap"
result=$(cd "$_autocd_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    install_precommand_trap
    ./sub/
    printf "\nPWDMARK=%s\n" "$PWD"
' </dev/null 2>/dev/null | sed -n 's/.*PWDMARK=//p')
assert_equal "$_autocd_root/sub" "$result"

# Tilde-expanded form: user types `~/sub/` and expects to land in
# $HOME/sub, not see "Is a directory". Mirrors the zsh ~/scripts/
# regression this fix addresses.
start_test "bash -i autocds on ~/foo/ via DEBUG trap"
result=$(HOME="$_autocd_root" run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    install_precommand_trap
    ~/sub/
    printf "\nPWDMARK=%s\n" "$PWD"
' </dev/null 2>/dev/null | sed -n 's/.*PWDMARK=//p')
assert_equal "$_autocd_root/sub" "$result"

# Regression: sourcing shrc under an interactive bash that inherits
# aliases with the same names as shrc's function definitions (e.g.
# Ubuntu's default `alias l='ls -CF'` from /etc/bash.bashrc or
# ~/.bashrc) must not break parsing. Bash expands aliases at parse
# time, so without the pre-block `unalias -a`, `l() { ... }` would
# parse as `ls -CF() { ... }` and raise a syntax error, leaving
# install_precommand_trap undefined.
start_test "shrc sources cleanly despite inherited l/ll/la aliases"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    alias l="ls -CF"
    alias ll="ls -alF"
    alias la="ls -A"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    if type install_precommand_trap >/dev/null 2>&1; then
        printf "OK"
    else
        printf "MISSING"
    fi
' </dev/null 2>/dev/null)
assert_equal "OK" "$result"

# Regression: sourcing shrc in a non-tty interactive bash must not
# SIGTTOU-hang on `stty start undef stop undef`. Pre-fix, the stty
# call fired tcsetattr from a non-foreground pgrp under `make -j`
# and suspended the process ("Suspended (tty output)") -- `make
# test` hung forever. A `test -t 0` guard around stty makes this
# safe. The run_with_timeout wrapper adds a short timeout(1)
# fence so a future regression surfaces as a test failure, not a
# hung CI run. When timeout(1) isn't installed the wrapper runs
# the command unfenced; this matches the prior skip-with-timeout
# behaviour while still giving coverage on boxes with timeout.
start_test "shrc stty guard: sources cleanly with stdin=/dev/null (no SIGTTOU hang)"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    printf "DONE"
' </dev/null 2>/dev/null)
assert_equal "DONE" "$result"

test_summary "shrc_bash_test"
