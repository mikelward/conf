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

# shrc used to run `emulate sh` under zsh, which turned SH_WORD_SPLIT on
# and made unquoted parameters split the way they do in sh. It no longer
# does, so zsh keeps its own semantics: an unquoted parameter stays one
# word.
start_test "shrc leaves SH_WORD_SPLIT off (zsh semantics, not sh)"
result=$(zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/shrc >/dev/null 2>&1
    if [[ -o SH_WORD_SPLIT ]]; then print -r "ON"; else print -r "OFF"; fi
' </dev/null 2>/dev/null | grep -E '^(ON|OFF)$' | tail -1)
assert_equal "OFF" "$result"

# `emulate sh` also turned GLOB_SUBST on, which made the *result* of an
# unquoted expansion get treated as a glob pattern. Dropping the emulate
# leaves it off, so a parameter holding `*` stays literal.
start_test "shrc leaves GLOB_SUBST off"
result=$(zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/shrc >/dev/null 2>&1
    if [[ -o GLOB_SUBST ]]; then print -r "ON"; else print -r "OFF"; fi
' </dev/null 2>/dev/null | grep -E '^(ON|OFF)$' | tail -1)
assert_equal "OFF" "$result"

# NOMATCH stays off deliberately: under zsh's default an unmatched glob is
# a fatal error, which would abort the rc partway through sourcing rather
# than leaving the pattern as a literal word the way sh does.
start_test "shrc leaves NO_NOMATCH set so an unmatched glob doesn't abort"
result=$(zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/shrc >/dev/null 2>&1
    print -r -- /nonexistent-'"$$"'/*.nothing
    print -r "SURVIVED"
' </dev/null 2>/dev/null | grep -E '^SURVIVED$' | tail -1)
assert_equal "SURVIVED" "$result"

# The functions that still need sh word splitting opt in with
# `emulate -L sh`, whose LOCAL_OPTIONS scope is the function. Calling one
# must not leave splitting on for the caller.
start_test "emulate -L sh in inpath does not leak splitting to the caller"
result=$(zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/shrc >/dev/null 2>&1
    inpath /usr/bin >/dev/null 2>&1
    if [[ -o SH_WORD_SPLIT ]]; then print -r "LEAKED"; else print -r "CONTAINED"; fi
' </dev/null 2>/dev/null | grep -E '^(LEAKED|CONTAINED)$' | tail -1)
assert_equal "CONTAINED" "$result"

# zshrc is a real file rather than a symlink to shrc, and holds the
# options wanted because zsh is better than sh. shrc no longer sets them,
# so sourcing shrc alone must leave them at zsh's defaults...
start_test "shrc alone does not set the zsh improvement options"
result=$(zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/shrc >/dev/null 2>&1
    if [[ -o KSH_GLOB ]]; then print -r "ON"; else print -r "OFF"; fi
' </dev/null 2>/dev/null | grep -E '^(ON|OFF)$' | tail -1)
assert_equal "OFF" "$result"

# ...and sourcing zshrc must set them, then reach shrc through its own
# directory so the functions still load.
start_test "zshrc sets the zsh improvement options and sources shrc"
result=$(zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/zshrc >/dev/null 2>&1
    for _o in KSH_GLOB BARE_GLOB_QUAL KSH_AUTOLOAD SH_GLOB POSIX_ALIASES; do
        if [[ -o $_o ]]; then print -r "$_o=on"; else print -r "$_o=off"; fi
    done
    is_function have_command && print -r "shrc=loaded"
' </dev/null 2>/dev/null)
assert_contains "KSH_GLOB=on" "$result"
assert_contains "BARE_GLOB_QUAL=off" "$result"
assert_contains "KSH_AUTOLOAD=off" "$result"
assert_contains "SH_GLOB=off" "$result"
assert_contains "POSIX_ALIASES=off" "$result"
assert_contains "shrc=loaded" "$result"

# The improvements are set before shrc is sourced, so shrc's own compat
# block must not clobber them. This is what `emulate sh` used to break:
# it reset every option set before it.
start_test "shrc's compat block does not clobber zshrc's improvements"
result=$(zsh --no-rcs -c '
    setopt KSH_GLOB
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/shrc >/dev/null 2>&1
    if [[ -o KSH_GLOB ]]; then print -r "KEPT"; else print -r "CLOBBERED"; fi
' </dev/null 2>/dev/null | grep -E '^(KEPT|CLOBBERED)$' | tail -1)
assert_equal "KEPT" "$result"

# Regression: when zsh reads ~/.zshrc as a *startup file*, $0 is the shell
# name rather than the rc file, so `${0:A:h}` expands to the current
# directory and zshrc sources nothing -- silently skipping every function,
# the prompt, and session startup. Only `%x` names the file being read.
# This has to exercise the real startup path: `source /path/to/zshrc` sets
# $0 to the file and hides the bug completely.
start_test "zshrc loads shrc when zsh reads it as a real ~/.zshrc"
_zdot=$(mktemp -d)
ln -s "$_srcdir/zshrc" "$_zdot/.zshrc"
result=$(
    cd /    # a wrong resolution would land here, not on the checkout
    export HOME="$_zdot" ZDOTDIR="$_zdot" SHRC_LOAD_FUNCTIONS_ONLY=1
    run_interactive_with_timeout 15 zsh -d -i -c 'is_function have_command && print -r "loaded"' </dev/null 2>/dev/null | grep -E '^loaded$' | tail -1
)
rm -rf "$_zdot"
assert_equal "loaded" "$result"

# Regression: an earlier startup file can enable these, and /etc/zshenv is
# read before ~/.zshenv can turn GLOBAL_RCS off, so it cannot be opted out
# of. POSIX_ALIASES is the one that bites: shrc's `+` / `-` aliases still
# define under it but fail to expand. zshrc must reset all three rather than
# trusting zsh's defaults.
start_test "zshrc resets options an earlier startup file enabled"
result=$(zsh --no-rcs -c '
    setopt POSIX_ALIASES SH_GLOB KSH_AUTOLOAD
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/zshrc >/dev/null 2>&1
    for _o in POSIX_ALIASES SH_GLOB KSH_AUTOLOAD; do
        if [[ -o $_o ]]; then print -r "$_o=leaked"; else print -r "$_o=reset"; fi
    done
' </dev/null 2>/dev/null)
assert_contains "POSIX_ALIASES=reset" "$result"
assert_contains "SH_GLOB=reset" "$result"
assert_contains "KSH_AUTOLOAD=reset" "$result"

# The resets have to survive failsafe too -- they move the shell toward
# stock zsh, which is what failsafe wants. Only the deviations are skipped.
start_test "zshrc resets POSIX_ALIASES even in failsafe mode"
result=$(FAILSAFE=1 zsh --no-rcs -c '
    setopt POSIX_ALIASES
    source '"$_srcdir"'/zshrc >/dev/null 2>&1
    if [[ -o POSIX_ALIASES ]]; then print -r "leaked"; else print -r "reset"; fi
' </dev/null 2>/dev/null | grep -E '^(leaked|reset)$' | tail -1)
assert_equal "reset" "$result"

# Regression: failsafe mode is meant to be a minimal recovery shell, and shrc
# returns before any of its setup for FAILSAFE / LC_FAILSAFE / ~/.failsafe.
# While zshrc was a symlink to shrc that guard came before every zsh option;
# once zshrc set its own options ahead of the source, failsafe still altered
# globbing -- the config the escape hatch exists to escape.
start_test "zshrc applies no options in failsafe mode"
result=$(FAILSAFE=1 zsh --no-rcs -c '
    source '"$_srcdir"'/zshrc >/dev/null 2>&1
    if [[ -o KSH_GLOB ]]; then print -r "APPLIED"; else print -r "SKIPPED"; fi
' </dev/null 2>/dev/null | grep -E '^(APPLIED|SKIPPED)$' | tail -1)
assert_equal "SKIPPED" "$result"

# ...while a normal startup still gets them.
start_test "zshrc applies its options when failsafe is off"
result=$(zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/zshrc >/dev/null 2>&1
    if [[ -o KSH_GLOB ]]; then print -r "APPLIED"; else print -r "SKIPPED"; fi
' </dev/null 2>/dev/null | grep -E '^(APPLIED|SKIPPED)$' | tail -1)
assert_equal "APPLIED" "$result"

# FAILSAFE=0 means failsafe is *off*, so the options must still apply -- the
# guard keys off shrc having loaded rather than the variable merely being set.
start_test "zshrc applies its options when FAILSAFE=0"
result=$(FAILSAFE=0 zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/zshrc >/dev/null 2>&1
    if [[ -o KSH_GLOB ]]; then print -r "APPLIED"; else print -r "SKIPPED"; fi
' </dev/null 2>/dev/null | grep -E '^(APPLIED|SKIPPED)$' | tail -1)
assert_equal "APPLIED" "$result"

# Regression: shrc's rerc re-reads ~/.shrc, which was the whole config while
# zshrc was a symlink to shrc. Now it isn't, so reloading only shrc would
# leave this file's options at whatever a plugin last set them to. zshrc
# overrides rerc to re-read itself; unset a zshrc-owned option, reload, and
# it must come back.
start_test "rerc under zsh restores options owned by zshrc"
result=$(zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/zshrc >/dev/null 2>&1
    unsetopt KSH_GLOB
    rerc >/dev/null 2>&1
    if [[ -o KSH_GLOB ]]; then print -r "RESTORED"; else print -r "LOST"; fi
' </dev/null 2>/dev/null | grep -E '^(RESTORED|LOST)$' | tail -1)
assert_equal "RESTORED" "$result"

# zshrc must find shrc through its own resolved directory, not $PWD or a
# hard-coded $HOME path, so it works from a checkout and through the
# installed ~/.zshrc symlink alike.
start_test "zshrc locates shrc independently of the working directory"
result=$(cd / && zsh --no-rcs -c '
    SHRC_LOAD_FUNCTIONS_ONLY=1 source '"$_srcdir"'/zshrc >/dev/null 2>&1
    is_function have_command && print -r "loaded"
' </dev/null 2>/dev/null | grep -E '^loaded$' | tail -1)
assert_equal "loaded" "$result"

test_summary "shrc_zsh_test"
