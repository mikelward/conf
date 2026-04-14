#!/bin/sh
#
# Shared test library for shrc tests.
# Provides assertion helpers, shell stubs, and a temp directory.
# Compatible with dash, bash, and zsh.
#
# Strictness note: we do NOT `set -u` globally. shrc functions rely on
# `local _where=$2` style argument access (implicit-empty on missing
# args), so inheriting -u aborts them on optional arguments. Instead,
# assertion helpers use `${n?}` strict references on each positional
# argument, which catches the typo class that -u is meant to catch
# (e.g. `assert_equal "label" "$expcted" "$actual"` with a misspelled
# var name would previously pass silently when $actual was also empty;
# it now aborts the test script with a clear "positional: missing"
# error). `set -e` is also deliberately avoided: the helpers' whole
# job is to observe non-zero exits.

failures=0
passes=0
_skipped=0

# The ${n?missing ...} strict references below make the test script
# abort with a clear error if an assertion is called with too few
# arguments. The `$#` check additionally catches the common typo class
# where an unset variable expanded to empty AND collapsed a trailing
# argument. E.g. `assert_equal "label" "$expcted" "$actual"` --
# previously $expcted silently expanded to "" and the helper received
# three args ("label", "", "<actual>") with a false match when $actual
# was also empty. We can't detect that under word-split arg passing
# (the empty string IS a valid argument), but we CAN flag call sites
# that forgot an argument entirely, and missing args are the most
# common typo in practice.
# Intentionally NOT using `set -u` globally: shrc functions rely on
# `local _where=$2` style implicit-empty on missing args, so inheriting
# -u would abort them. `set -e` is also avoided: the helpers' job is
# to observe non-zero exits.
assert_equal() {
    local label="${1?assert_equal: missing label}"
    local expected="${2?assert_equal: missing expected value}"
    local actual="${3?assert_equal: missing actual value}"
    if test $# -ne 3; then
        echo "FAIL: $label (assert_equal: expected 3 args, got $#)" >&2
        failures=$((failures + 1))
        return 1
    fi
    if test "$expected" = "$actual"; then
        passes=$((passes + 1))
    else
        echo "FAIL: $label"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        failures=$((failures + 1))
    fi
}

assert_true() {
    local label="${1?assert_true: missing label}"
    shift
    if test $# -eq 0; then
        echo "FAIL: $label (assert_true: no command given)" >&2
        failures=$((failures + 1))
        return 1
    fi
    if "$@"; then
        passes=$((passes + 1))
    else
        echo "FAIL: $label"
        echo "  expected command to succeed: $*"
        failures=$((failures + 1))
    fi
}

assert_false() {
    local label="${1?assert_false: missing label}"
    shift
    if test $# -eq 0; then
        echo "FAIL: $label (assert_false: no command given)" >&2
        failures=$((failures + 1))
        return 1
    fi
    if "$@"; then
        echo "FAIL: $label"
        echo "  expected command to fail: $*"
        failures=$((failures + 1))
    else
        passes=$((passes + 1))
    fi
}

assert_contains() {
    local label="${1?assert_contains: missing label}"
    local needle="${2?assert_contains: missing needle}"
    local haystack="${3?assert_contains: missing haystack}"
    if test $# -ne 3; then
        echo "FAIL: $label (assert_contains: expected 3 args, got $#)" >&2
        failures=$((failures + 1))
        return 1
    fi
    # Reject an empty needle: the case pattern *""* matches any
    # haystack, so `assert_contains "label" "$unset" "$actual"` would
    # silently pass. That's a wiring-bug trap, not a useful assertion.
    if test -z "$needle"; then
        echo "FAIL: $label (assert_contains: empty needle; use assert_equal for empty-string checks)" >&2
        failures=$((failures + 1))
        return 1
    fi
    case "$haystack" in
    *"$needle"*)
        passes=$((passes + 1))
        ;;
    *)
        echo "FAIL: $label"
        echo "  expected to contain: $(printf '%s' "$needle" | cat -v)"
        echo "  actual:              $(printf '%s' "$haystack" | cat -v)"
        failures=$((failures + 1))
        ;;
    esac
}

assert_not_contains() {
    local label="${1?assert_not_contains: missing label}"
    local needle="${2?assert_not_contains: missing needle}"
    local haystack="${3?assert_not_contains: missing haystack}"
    if test $# -ne 3; then
        echo "FAIL: $label (assert_not_contains: expected 3 args, got $#)" >&2
        failures=$((failures + 1))
        return 1
    fi
    # Reject an empty needle: *""* matches any haystack, so
    # `assert_not_contains "label" "$unset" "$actual"` would always
    # fail -- making the test look red for the wrong reason.
    if test -z "$needle"; then
        echo "FAIL: $label (assert_not_contains: empty needle; use assert_equal for empty-string checks)" >&2
        failures=$((failures + 1))
        return 1
    fi
    case "$haystack" in
    *"$needle"*)
        echo "FAIL: $label"
        echo "  expected not to contain: $(printf '%s' "$needle" | cat -v)"
        echo "  actual:                  $(printf '%s' "$haystack" | cat -v)"
        failures=$((failures + 1))
        ;;
    *)
        passes=$((passes + 1))
        ;;
    esac
}

# Mark the current test script as wholly skipped (e.g. required tool is
# missing). test_summary then reports SKIP rather than a misleading
# "all 0 tests passed." Callers should typically `exit 0` after the
# final test_summary, which returns 0 in this case.
skip_all() {
    _skipped=1
    local _reason="${1:-}"
    if test -n "$_reason"; then
        echo "SKIP: $_reason"
    fi
}

# Record that a conditional block inside a test script was skipped.
# The summary line tallies these so a reader can tell at a glance
# that not every code path ran.
skip_block() {
    _skipped=$((_skipped + 1))
    local _reason="${1:-}"
    if test -n "$_reason"; then
        echo "SKIP: $_reason"
    fi
}

# Print summary and exit with appropriate code.
# Fails (exit 1) when:
#   - any assertion failed, OR
#   - no assertions ran AND nothing was explicitly skipped (catches
#     "silently green 0-pass" outputs caused by typos / wiring bugs).
test_summary() {
    local name="${1:-tests}"
    echo
    if test "$failures" -gt 0; then
        echo "$name: $failures test(s) failed, $passes passed."
        exit 1
    fi
    if test "$passes" -eq 0 && test "$_skipped" -eq 0; then
        echo "$name: FAIL - no tests ran and none were explicitly skipped"
        exit 1
    fi
    if test "$passes" -eq 0; then
        echo "$name: SKIPPED"
        return 0
    fi
    if test "$_skipped" -gt 0; then
        echo "$name: all $passes tests passed ($_skipped skipped)."
    else
        echo "$name: all $passes tests passed."
    fi
}

# Stub out shell detection
BASH_VERSION="${BASH_VERSION:-fake}"
ZSH_VERSION=
is_zsh() { false; }
is_bash() { true; }
is_dash() { false; }
is_sh() { false; }

# We need puts, gets, warn, and trim_prefix for shrc.vcs and prompt functions
puts() {
    printf '%s\n' "$*"
}
gets() {
    read -r "$@"
}
warn() {
    printf '%s\n' "$*" >&2
}
error() {
    printf '%s\n' "$*" >&2
}
trim_prefix() {
    local _prefix="$1"
    local _target="$2"
    puts "${_target#$_prefix}"
}

# Prevent any test from opening an interactive editor
export EDITOR="sh -c 'printf \"edited by test\n\" > \"\$1\"' --"
export VISUAL="$EDITOR"
export GIT_EDITOR="$EDITOR"
export HGEDITOR="$EDITOR"
export JJ_EDITOR="$EDITOR"

# Run a command with a timeout if `timeout(1)` is installed, else run
# it directly. Prevents a regression in any of the shell-invocation
# tests (bash -i, zsh -i, fish -i, dash -c) from hanging `make test`
# forever when a non-foreground-pgrp tcsetattr or similar trap suspends
# the subshell ("Suspended (tty output)"). A failed-to-complete command
# surfaces as a test failure with a non-zero exit (124 on timeout),
# not an infinite wait.
#
# Uses `timeout -k 2 N` (SIGKILL fallback 2s after SIGTERM): a subshell
# that SIGTTOU-stopped won't respond to SIGTERM (queued while T-stopped
# but not delivered until SIGCONT), so without -k the stopped process
# sits forever and timeout(1) waits with it. -k guarantees a SIGKILL
# fires after the grace period and the test terminates.
#
# Usage: run_with_timeout SECONDS command [args...]
# The default timeout is intentionally short-ish (10s is plenty for any
# real shrc sourcing); override per call when a test is known to do
# more work.
run_with_timeout() {
    local _secs="${1?run_with_timeout: missing seconds}"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout -k 2 "$_secs" "$@"
    else
        "$@"
    fi
}

# Run an interactive shell (bash -i, zsh -i, fish -i, etc.) detached
# from the controlling terminal, with a timeout fence. Interactive
# shells call tcsetattr to configure the tty (prompt rendering,
# readline init, shrc's `stty start undef stop undef` guard, etc.).
# When the caller is not in the foreground process group of its
# controlling tty -- which is the common case under `make -j`,
# `script -c`, or any shell test harness whose pty isn't directly
# owned by the test -- tcsetattr fires SIGTTOU at the subshell,
# stopping it ("Suspended (tty output)") and taking the whole pipeline
# with it. `setsid` places the subshell in a brand-new session with no
# controlling tty, so there is nothing to SIGTTOU from. Falls back to
# plain run_with_timeout when setsid isn't installed.
#
# Usage: run_interactive_with_timeout SECONDS command [args...]
run_interactive_with_timeout() {
    local _secs="${1?run_interactive_with_timeout: missing seconds}"
    shift
    if command -v setsid >/dev/null 2>&1; then
        run_with_timeout "$_secs" setsid "$@"
    else
        run_with_timeout "$_secs" "$@"
    fi
}

# Create a temp directory for testing
_testdir=$(mktemp -d)
trap 'rm -rf "$_testdir"' EXIT

# Empty directory to use as core.hooksPath to disable hooks without
# modifying template hook files (which may be hardlinked)
_nohooks="$_testdir/nohooks"
mkdir "$_nohooks"

# Source directory (where the test file lives). Absolute so tests that
# spawn subshells with a different cwd (e.g. the bash -i autocd test)
# can still refer to $_srcdir/shrc reliably.
_srcdir="$(cd "$(dirname "$0")" && pwd)"

# Extract a shell function definition from a file and eval it.
# Assumes the function starts at column 0 and ends with } at column 0.
# Usage: extract_func funcname [filepath]
# filepath defaults to $_srcdir/shrc
# Fails loudly if the function is not found, so a rename in shrc
# doesn't silently fall through to a system command (or nothing).
# Also fails if the extracted block doesn't end with a column-0 `}`,
# which would mean sed ran to EOF without finding the closing brace
# (e.g. the function ends with `}` indented, or the file was truncated
# mid-function). Without that check we'd eval a syntactically invalid
# fragment and the first assertion against the missing function would
# be the failure signal, far from the real cause.
extract_func() {
    local _fn="$1"
    local _file="${2:-$_srcdir/shrc}"
    local _def
    _def=$(sed -n "/^$_fn()/,/^}/p" "$_file")
    if test -z "$_def"; then
        echo "FAIL: extract_func could not find '$_fn' in $_file" >&2
        failures=$((failures + 1))
        return 1
    fi
    # `sed '/pattern/,/end/p'` prints through EOF if /end/ never matches.
    # Require the extracted block's last line to be a column-0 `}` so we
    # don't eval a half-function that silently stops matching the real
    # body.
    _last=$(printf '%s\n' "$_def" | tail -n 1)
    if test "$_last" != "}"; then
        echo "FAIL: extract_func found '$_fn' in $_file but block does not end with a column-0 '}'" >&2
        failures=$((failures + 1))
        return 1
    fi
    eval "$_def"
}

# Like extract_func, but applies a sed substitution to the extracted
# body before eval'ing it. Useful for testing branches that key off
# readonly shell variables (e.g. $UID). Example:
#   extract_func_subst ps1_character 's/\$UID/$_test_uid/g'
# Fails loudly if the function is not found or the extracted block does
# not end with a column-0 `}` (see extract_func above).
extract_func_subst() {
    local _fn="$1"
    local _sed="$2"
    local _file="${3:-$_srcdir/shrc}"
    local _def
    _def=$(sed -n "/^$_fn()/,/^}/p" "$_file" | sed "$_sed")
    if test -z "$_def"; then
        echo "FAIL: extract_func_subst could not find '$_fn' in $_file" >&2
        failures=$((failures + 1))
        return 1
    fi
    _last=$(printf '%s\n' "$_def" | tail -n 1)
    if test "$_last" != "}"; then
        echo "FAIL: extract_func_subst found '$_fn' in $_file but block does not end with a column-0 '}'" >&2
        failures=$((failures + 1))
        return 1
    fi
    eval "$_def"
}
