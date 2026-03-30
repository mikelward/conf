#!/bin/sh
#
# Shared test library for shrc tests.
# Provides assertion helpers, shell stubs, and a temp directory.
# Compatible with dash, bash, and zsh.
#

failures=0
passes=0

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

# Print summary and exit with appropriate code
test_summary() {
    local name="${1:-tests}"
    echo
    if test "$failures" -eq 0; then
        echo "$name: all $passes tests passed."
    else
        echo "$name: $failures test(s) failed, $passes passed."
        exit 1
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

# Source directory (where the test file lives)
_srcdir="$(dirname "$0")"

# Extract a shell function definition from a file and eval it.
# Assumes the function starts at column 0 and ends with } at column 0.
# Usage: extract_func funcname [filepath]
# filepath defaults to $_srcdir/shrc
extract_func() {
    eval "$(sed -n "/^$1()/,/^}/p" "${2:-$_srcdir/shrc}")"
}
