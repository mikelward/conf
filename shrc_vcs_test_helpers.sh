#!/bin/bash
#
# Shared test helpers for shrc.vcs tests.
# Requires bash or zsh (uses here-strings).
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

# We need trim_prefix for shrc.vcs functions
trim_prefix() {
    local _prefix="$1"
    local _target="$2"
    echo "${_target#$_prefix}"
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

# Source shrc.vcs (provides target_relative_to and other functions)
_srcdir="$(dirname "$0")"
# shellcheck source=shrc.vcs
source "$_srcdir/shrc.vcs"
