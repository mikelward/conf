#!/bin/sh
#
# Shared test library for shrc tests.
# Provides assertion helpers, shell stubs, and a temp directory.
# Compatible with dash, bash, and zsh.
#

failures=0
passes=0
_skipped=0

assert_equal() {
    local label="$1"
    local expected="$2"
    local actual="$3"
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
    local label="$1"
    shift
    if "$@"; then
        passes=$((passes + 1))
    else
        echo "FAIL: $label"
        echo "  expected command to succeed: $*"
        failures=$((failures + 1))
    fi
}

assert_false() {
    local label="$1"
    shift
    if "$@"; then
        echo "FAIL: $label"
        echo "  expected command to fail: $*"
        failures=$((failures + 1))
    else
        passes=$((passes + 1))
    fi
}

assert_contains() {
    local label="$1"
    local needle="$2"
    local haystack="$3"
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
    local label="$1"
    local needle="$2"
    local haystack="$3"
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
    eval "$_def"
}

# Like extract_func, but applies a sed substitution to the extracted
# body before eval'ing it. Useful for testing branches that key off
# readonly shell variables (e.g. $UID). Example:
#   extract_func_subst ps1_character 's/\$UID/$_test_uid/g'
# Fails loudly if the function is not found.
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
    eval "$_def"
}
