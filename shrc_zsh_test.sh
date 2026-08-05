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

# Regression: x, xa and f all run `command fg`. `emulate sh` turns on
# POSIX_BUILTINS, under which `command` finds builtins; without it `command`
# searches only for an external binary, `fg` becomes "command not found",
# and all three break with no other symptom. Dropping the emulate did
# exactly that and every test still passed.
#
# Job control isn't available in a non-interactive test shell, so assert on
# *which* failure comes back: "no job control" means the builtin was found,
# which is all these functions need. Matching the exact wording would pin a
# zsh version, so this only rules out the lookup failure.
start_test "command fg resolves to the fg builtin under zsh"
result=$(zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/shrc >/dev/null 2>&1
    command fg
' </dev/null 2>&1 | tail -1)
assert_not_contains "command not found" "$result"

# The same lookup, stated directly: `command` must reach builtins at all.
# `command jobs` is the same class as `command fg` without needing a tty.
start_test "command reaches zsh builtins at all"
result=$(zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/shrc >/dev/null 2>&1
    command jobs >/dev/null 2>&1 && print -r "FOUND" || print -r "MISSING"
' </dev/null 2>/dev/null | grep -E '^(FOUND|MISSING)$' | tail -1)
assert_equal "FOUND" "$result"

# The options shrc's own code depends on, asserted as a contract rather than
# left implicit in `emulate sh`. Each has already been lost once, silently,
# and each cost a hand-found bug:
#
#   POSIX_BUILTINS  `command fg` in x / xa / f
#   SH_WORD_SPLIT   psgrep's $ps_args, the IFS=: PATH loops, shift_options,
#                   set_up_ssh_aliases' multi-host Host line
#   KSH_ARRAYS      zle_highlight[0] -- index 0 is invalid without it
#   NOMATCH off     an unmatched glob stays a literal word instead of
#                   aborting the rc mid-source
#
# If the emulate line changes again, this fails immediately and names which
# guarantee went away, rather than surfacing as a broken command weeks later.
start_test "shrc establishes the zsh options its code depends on"
result=$(zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/shrc >/dev/null 2>&1
    for _o in POSIX_BUILTINS SH_WORD_SPLIT KSH_ARRAYS NOMATCH; do
        if [[ -o $_o ]]; then print -r "$_o=on"; else print -r "$_o=off"; fi
    done
' </dev/null 2>/dev/null)
assert_contains "POSIX_BUILTINS=on" "$result"
assert_contains "SH_WORD_SPLIT=on" "$result"
assert_contains "KSH_ARRAYS=on" "$result"
assert_contains "NOMATCH=off" "$result"

# x, xa and f are defined in shrc's interactive block, so nothing above
# reaches them. Check they exist under a real interactive zsh -- a rename or
# an accidental removal would otherwise go unnoticed by the whole suite.
#
# `whence -w`, not `$+functions[...]`: shrc's `emulate sh` turns KSH_ARRAYS
# on, under which `$+functions[x]` expands as `$+functions` followed by a
# literal `[x]` and is always true. The first draft of this test used it and
# reported all three missing.
#
# Match `: function` in the output rather than testing the exit status.
# `whence -w` succeeds for any name it can classify, so on a host with an
# external `x`, `xa` or `f` on PATH it reports `x: command` and exits 0 --
# passing even if the shrc function had been deleted, which is the one thing
# this test exists to notice.
start_test "x, xa and f are defined as functions under interactive zsh"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    for _f in x xa f; do
        case "$(whence -w "$_f" 2>/dev/null)" in
            *": function") print -r "$_f=defined" ;;
            *)             print -r "$_f=missing" ;;
        esac
    done
' </dev/null 2>/dev/null)
assert_contains "x=defined" "$result"
assert_contains "xa=defined" "$result"
assert_contains "f=defined" "$result"

test_summary "shrc_zsh_test"
