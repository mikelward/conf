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
_skipped_all=0

# Capture the real interpreter before we stub BASH_VERSION / ZSH_VERSION
# below. Tests pass this to test_summary so the summary header reflects
# the actual shell under test, not whatever the stubs make it look like.
# Fallback chain: prefer $BASH_VERSION / $ZSH_VERSION, then /proc on Linux,
# then ps(1), finally a plain "sh". /proc/$$/exe alone is not portable
# (macOS / *BSD have no /proc), which would previously collapse to the
# literal fallback string and mislabel the summary.
if test -n "${BASH_VERSION:-}"; then
    _real_shell=bash
elif test -n "${ZSH_VERSION:-}"; then
    _real_shell=zsh
else
    _real_shell=$(basename "$(readlink -f /proc/$$/exe 2>/dev/null)" 2>/dev/null)
    if test -z "$_real_shell" || test "$_real_shell" = "exe"; then
        _real_shell=$(ps -p $$ -o comm= 2>/dev/null | sed 's/^-//;s/[[:space:]]//g')
    fi
    test -n "$_real_shell" || _real_shell=sh
fi

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
    # The ${n?} refs above already abort on missing args. The $# check
    # only fires on 4+ args (a call that looks right but leaks extras).
    if test $# -gt 3; then
        echo "FAIL: $label (assert_equal: too many args, got $#)" >&2
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
    if test $# -gt 3; then
        echo "FAIL: $label (assert_contains: too many args, got $#)" >&2
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
    if test $# -gt 3; then
        echo "FAIL: $label (assert_not_contains: too many args, got $#)" >&2
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
# "all 0 tests passed." Sets a dedicated flag rather than mutating the
# skip_block counter so the two concepts stay distinct.
skip_all() {
    _skipped_all=1
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
# Always exits (never returns) so callers can't accidentally run code
# after a summary prints.
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
    if test "$passes" -eq 0 \
        && test "$_skipped" -eq 0 \
        && test "$_skipped_all" -eq 0; then
        echo "$name: FAIL - no tests ran and none were explicitly skipped"
        exit 1
    fi
    if test "$_skipped_all" -eq 1 && test "$passes" -eq 0; then
        echo "$name: SKIPPED"
        exit 0
    fi
    if test "$passes" -eq 0; then
        # All tests skipped via skip_block (no skip_all, no passes).
        echo "$name: $_skipped block(s) skipped, 0 tests ran"
        exit 0
    fi
    if test "$_skipped" -gt 0; then
        echo "$name: all $passes tests passed ($_skipped skipped)."
    else
        echo "$name: all $passes tests passed."
    fi
    exit 0
}

# Portable nanosecond clock for perf tests. GNU date +%s%N returns
# digits; BSD date (macOS) does not support %N and returns a literal N
# suffix. Callers test the result against "0" to detect unavailability,
# which the raw `date +%s%N || echo 0` pattern missed when date exits 0
# but emits a non-numeric tail. Always prints "0" when %N is unsupported.
_now_ns() {
    local _ns
    _ns=$(date +%s%N 2>/dev/null)
    case "$_ns" in
        ''|*[!0-9]*) echo 0 ;;
        *) echo "$_ns" ;;
    esac
}

# Shell-detection helpers matching the real shell.
#
# Previously this forced is_bash=true and is_zsh=false regardless of
# the real interpreter, which broke under zsh: extracted functions like
# `what` took the is_bash branch and ran `type -t`, which zsh doesn't
# support. Now the helpers report the truth so extracted functions
# select the branch that actually works in the current shell. dash/sh
# still pretend to be bash because the dash test run is really a
# portability cross-check of shrc's bash-ish code paths.
#
# Under zsh we also replay shrc's setup_shell_compat function so
# `emulate sh` and friends take effect before any extracted function
# runs. Without that, `IFS=:; for dir in $PATH` doesn't word-split
# (zsh doesn't split unquoted vars by default) and path / inpath /
# shift_options / have_command all fail.
case "$_real_shell" in
zsh)
    is_zsh() { true; }
    is_bash() { false; }
    is_dash() { false; }
    is_sh() { false; }
    shell=zsh
    # Pull shrc's setup_shell_compat out with a direct sed so we can
    # invoke it before extract_func itself is defined further down.
    eval "$(sed -n '/^setup_shell_compat()/,/^}/p' \
        "$(cd "$(dirname "$0")" && pwd)/shrc")"
    if type setup_shell_compat >/dev/null 2>&1; then
        setup_shell_compat
    fi
    ;;
bash)
    is_zsh() { false; }
    is_bash() { true; }
    is_dash() { false; }
    is_sh() { false; }
    shell=bash
    ;;
*)
    # dash / sh / ksh: pretend to be bash so extracted functions take
    # their bash-branch code paths (which are the unit under test on
    # this run). BASH_VERSION is stubbed so shrc's own `is_bash`
    # (which checks ${BASH_VERSION:-}) also reports true if any
    # extracted code calls it.
    BASH_VERSION="${BASH_VERSION:-fake}"
    ZSH_VERSION=
    is_zsh() { false; }
    is_bash() { true; }
    is_dash() { false; }
    is_sh() { false; }
    shell=bash
    ;;
esac

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

# Prevent any test from opening an interactive editor.
# The trailing `--` becomes $0 in the wrapped `sh -c`, so the first real
# filename tools like git/hg/jj append (`$EDITOR /path/to/COMMIT_EDITMSG`)
# lands in $1 as expected. Without that trailing sentinel the filename
# would be swallowed by $0 and the stub would write to the wrong place
# (or nothing at all).
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

# Run a fish snippet with config.fish sourced inside an interactive fish.
# Shared by shrc_fish_test.sh and shrc_fish_prompt_test.sh so the fiddly
# invocation (fake HOME, SIGTTOU avoidance, timeout fence, stdin detach)
# only lives in one place.
#
# </dev/null prevents fish -i from inheriting make's controlling terminal:
# otherwise fish enables job control, moves to its own process group, and
# config.fish's `stty start undef stop undef` triggers SIGTTOU (tcsetattr
# from a non-foreground pgrp). With stdin=/dev/null fish can't grab the
# tty and stty fails harmlessly.
#
# Callers pass pre-source and post-source fish preambles so they can seed
# colors before config.fish reads them OR override functions config.fish
# defines. Either preamble may be empty.
#
# Usage: _fish_run_config PRE_SOURCE POST_SOURCE SNIPPET
_fish_run_config() {
    local _pre="$1"
    local _post="$2"
    local _snippet="$3"
    local _fakehome="$_testdir/fakehome"
    mkdir -p "$_fakehome"
    HOME="$_fakehome" \
        TERM=dumb \
        SHPOOL_SESSION_NAME= \
        TMUX= \
        SSH_CONNECTION= \
        run_with_timeout 15 fish --no-config -i -c "
            function tput; return 1; end
            $_pre
            source $_srcdir/config/fish/config.fish
            $_post
            $_snippet
        " </dev/null
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
#
# Usage: extract_func funcname [filepath]
#        extract_func_subst funcname sed_expr [filepath]
#
# filepath defaults to $_srcdir/shrc. extract_func_subst applies a sed
# substitution to the extracted body before eval'ing it -- useful for
# testing branches that key off readonly shell variables (e.g. $UID):
#   extract_func_subst ps1_character 's/\$UID/$_test_uid/g'
#
# Fails loudly if the function is not found, so a rename in shrc
# doesn't silently fall through to a system command (or nothing).
# Also fails if the extracted block doesn't end with a column-0 `}`,
# which would mean sed ran to EOF without finding the closing brace
# (e.g. the function ends with `}` indented, or the file was truncated
# mid-function). Without that check we'd eval a syntactically invalid
# fragment and the first assertion against the missing function would
# be the failure signal, far from the real cause.
_extract_func_impl() {
    local _caller="$1"
    local _fn="$2"
    local _sed="$3"
    local _file="${4:-$_srcdir/shrc}"
    local _def
    local _last
    # Reject anything that isn't a plain identifier. `sed` interprets
    # $_fn as a BRE, so a stray `.` / `[` / etc. in the name would match
    # unintended lines; all shrc function names are identifiers so this
    # is only a safety fence, not a real restriction.
    case "$_fn" in
        ''|*[!A-Za-z0-9_]*)
            echo "FAIL: $_caller invalid function name: '$_fn'" >&2
            failures=$((failures + 1))
            return 1
            ;;
    esac
    if test -n "$_sed"; then
        _def=$(sed -n "/^$_fn()/,/^}/p" "$_file" | sed "$_sed")
    else
        _def=$(sed -n "/^$_fn()/,/^}/p" "$_file")
    fi
    if test -z "$_def"; then
        echo "FAIL: $_caller could not find '$_fn' in $_file" >&2
        failures=$((failures + 1))
        return 1
    fi
    # `sed '/pattern/,/end/p'` prints through EOF if /end/ never matches.
    # Require the extracted block's last line to be a column-0 `}` so we
    # don't eval a half-function that silently stops matching the real
    # body.
    _last=$(printf '%s\n' "$_def" | tail -n 1)
    if test "$_last" != "}"; then
        echo "FAIL: $_caller found '$_fn' in $_file but block does not end with a column-0 '}'" >&2
        failures=$((failures + 1))
        return 1
    fi
    eval "$_def"
}

extract_func() {
    _extract_func_impl extract_func "$1" "" "${2:-}"
}

extract_func_subst() {
    _extract_func_impl extract_func_subst "$1" "$2" "${3:-}"
}
