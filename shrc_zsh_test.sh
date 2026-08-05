#!/bin/zsh
#
# End-to-end tests that exercise shrc under a real `zsh` subshell.
# Cross-shell behaviour is verified in shrc_test.sh; only zsh-specific
# regression tests live here.
#
# Run from the Makefile via `zsh shrc_zsh_test.sh` (skipped when zsh
# isn't installed).

. "$(dirname "$0")/shrc_test_lib.sh"

# Regression: shrc must enable AUTO_CD under interactive zsh so typing
# `Downloads<ENTER>` from any directory cds into $HOME/Downloads via
# CDPATH. The flag is set in the `is_interactive` block of shrc, which
# only runs under `zsh -i`.
start_test "shrc enables AUTO_CD under interactive zsh"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    if [[ -o AUTO_CD ]]; then print -r "ON"; else print -r "OFF"; fi
' </dev/null 2>/dev/null | grep -E '^(ON|OFF)$' | tail -1)
assert_equal "ON" "$result"

# Regression: the interactive-only zsh setopts (history/completion/prompt)
# were split out of setup_shell_compat_common into setup_shell_compat_interactive,
# which the interactive block runs only after the session handoff. Under an
# interactive zsh the block runs, so SHARE_HISTORY is enabled...
start_test "shrc enables SHARE_HISTORY under interactive zsh"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    if [[ -o SHARE_HISTORY ]]; then print -r "ON"; else print -r "OFF"; fi
' </dev/null 2>/dev/null | grep -E '^(ON|OFF)$' | tail -1)
assert_equal "ON" "$result"

# ...but loading only the function defs + essential compat
# (SHRC_LOAD_FUNCTIONS_ONLY skips the interactive block) leaves it OFF,
# proving the setopt was deferred out of setup_shell_compat_common rather than
# run on every source -- so a launcher that re-execs or hands off skips it.
start_test "shrc defers SHARE_HISTORY out of essential setup_shell_compat_common"
result=$(zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/shrc >/dev/null 2>&1
    if [[ -o SHARE_HISTORY ]]; then print -r "ON"; else print -r "OFF"; fi
' </dev/null 2>/dev/null | grep -E '^(ON|OFF)$' | tail -1)
assert_equal "OFF" "$result"

test_summary "shrc_zsh_test"
