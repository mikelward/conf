#!/bin/zsh
#
# End-to-end tests that exercise shrc under a real `zsh` subshell.
# Only the zsh-specific behaviour (accept-line widget autocd, widget
# registration, CDPATH splitting under `emulate -L zsh`) lives here;
# the sh-portable shrc function tests live in shrc_test.sh.
#
# Run from the Makefile via `zsh shrc_zsh_test.sh` (skipped when zsh
# isn't installed).

. "$(dirname "$0")/shrc_test_lib.sh"

# Set up a temp directory tree for cd tests.
_autocd_root="$_testdir/autocd"
mkdir -p "$_autocd_root/sub"
_cdpath_parent="$_testdir/autocd_cdpath"
mkdir -p "$_cdpath_parent/elsewhere"

# zsh's accept-line widget rewrites a trailing-slash dir buffer to
# `cd -- foo/`. We can't drive ZLE non-interactively, so source the
# real shrc under `zsh -i` (so its `if is_interactive` block actually
# defines _autocd_accept_line and registers the widget) and stub out
# `zle` so the widget's trailing `zle .accept-line` call is a no-op.
# This exercises shrc's ACTUAL implementations -- a regression in
# either `_autocd_accept_line` or `resolve_cdpath_dir` would surface
# here, unlike an inline copy.
result=$(cd "$_autocd_root" && run_interactive_with_timeout 10 zsh -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    zle() { : }   # shadow the builtin so `zle .accept-line` is inert
    BUFFER="./sub/"
    _autocd_accept_line
    print -r -- "$BUFFER"
' </dev/null 2>/dev/null)
assert_equal "zsh accept-line widget rewrites trailing-slash dir" \
    "cd -- ./sub/" "$result"

# Non-dir / multi-word / no-slash inputs are passed through unchanged.
result=$(cd "$_autocd_root" && run_interactive_with_timeout 10 zsh -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    zle() { : }
    BUFFER="./sub/ arg"
    _autocd_accept_line
    print -r -- "$BUFFER"
' </dev/null 2>/dev/null)
assert_equal "zsh accept-line widget leaves multi-word buffers alone" \
    "./sub/ arg" "$result"

# End-to-end: under the real shrc, a `~/foo/` buffer must rewrite
# to the tilde-expanded absolute path so .accept-line cd`s into it
# instead of trying to exec $HOME/foo/ and dying on permission
# denied. This is the bug users hit with `~/scripts/`.
result=$(HOME="$_autocd_root" run_interactive_with_timeout 10 zsh -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    zle() { : }
    BUFFER="~/sub/"
    _autocd_accept_line
    print -r -- "$BUFFER"
' </dev/null 2>/dev/null)
assert_equal "zsh accept-line widget expands ~/foo/ to absolute cd" \
    "cd -- $_autocd_root/sub/" "$result"

# Verify shrc actually registers the widget.
result=$(run_interactive_with_timeout 10 zsh -i -c 'source '"$_srcdir"'/shrc >/dev/null 2>&1; \
    if typeset -f _autocd_accept_line >/dev/null; then \
        print -r "REGMARK"; \
    fi' </dev/null 2>/dev/null | sed -n 's/.*REGMARK.*/registered/p' | head -1)
assert_equal "shrc registers _autocd_accept_line widget in zsh" \
    "registered" "$result"

# Regression: resolve_cdpath_dir sourced from the real shrc must
# split CDPATH correctly under `emulate -L zsh` (the widget's
# mode). zsh does not honor IFS=: for unquoted param splitting, so
# a naive POSIX implementation iterates once with the whole
# colon-joined string and fails to find anything in CDPATH.
result=$(run_interactive_with_timeout 10 zsh -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    # shrc sets CDPATH=".:$HOME", so override after sourcing.
    CDPATH=".:'"$_cdpath_parent"'"
    cd '"$_autocd_root/sub"' || exit 1
    widget_probe() {
        emulate -L zsh
        if resolve_cdpath_dir "elsewhere/"; then
            print -r "FOUND"
        else
            print -r "MISSING"
        fi
    }
    widget_probe
' 2>/dev/null | tail -1)
assert_equal "resolve_cdpath_dir walks CDPATH under emulate -L zsh" \
    "FOUND" "$result"

test_summary "shrc_zsh_test"
