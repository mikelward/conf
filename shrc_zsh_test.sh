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

# Regression: zsh-autosuggestions is written for native zsh, but shrc runs the
# shell under `emulate sh` (KSH_ARRAYS on). Under KSH_ARRAYS the plugin's
# `(( $#POSTDISPLAY ))` parses as `$#` then `POSTDISPLAY`, so its highlight
# widget floods the terminal with `bad math expression: operator expected at
# POSTDISPLAY`. init_zsh_autosuggestions sources the plugin via `emulate zsh
# -c`, giving its functions sticky zsh emulation so they run clean while the
# shell keeps KSH_ARRAYS on. Drop a stub plugin using that exact construct on
# the plugin search path, source shrc, and check the function both loaded and
# ran without the math error. The `probe:set` assertion guards against a
# vacuous pass where the plugin was never sourced at all.
start_test "zsh-autosuggestions runs in native zsh despite shrc's emulate sh"
_ghosthome="$_testdir/ghost-emulate-home"
mkdir -p "$_ghosthome/.zsh/zsh-autosuggestions"
cat >"$_ghosthome/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" <<'PLUGIN'
_ghost_math_probe() {
    typeset -g _ghost_hl
    if (( $#POSTDISPLAY )); then _ghost_hl="set"; fi
    print -r "probe:${_ghost_hl:-unset}"
}
PLUGIN
result=$(HOME="$_ghosthome" run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    POSTDISPLAY=hello
    _ghost_math_probe
' </dev/null 2>&1)
assert_contains "probe:set" "$result"
assert_not_contains "bad math expression" "$result"

# The ghost renders in a recessive, non-bold gray. shrc bolds only the typed
# buffer (via the _shrc_bold_input region_highlight hook), not the whole zle
# line, so the ghost -- drawn in POSTDISPLAY past $#BUFFER -- is never in the
# bold span. fg=8 is the terminal's gray, readable on light and dark. Assert
# the style is set regardless of whether the plugin itself is installed.
start_test "the ghost's highlight style is set to a non-bold gray under zsh"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    print -r -- "ghost-style:${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE:-unset}"
' </dev/null 2>/dev/null)
assert_contains "ghost-style:fg=8" "$result"

# The typed-input bold is applied to just the buffer (0..$#BUFFER) via a
# region_highlight hook, so the ghost in POSTDISPLAY stays unbolded. Drive the
# hook with a set BUFFER and assert its span ends exactly at $#BUFFER -- never
# reaching into the POSTDISPLAY (ghost) region beyond it.
start_test "the bold-input hook bolds only the typed buffer, not the ghost"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    if (( ${+functions[_shrc_bold_input]} )); then
        region_highlight=(); BUFFER="git commit"; POSTDISPLAY=" --amend"
        _shrc_bold_input
        print -rl -- "${region_highlight[@]}"
    else
        print -r -- "hook:absent"
    fi
' </dev/null 2>/dev/null)
assert_contains "0 10 bold" "$result"          # 0..${#BUFFER}, ${#git commit}=10
assert_not_contains "hook:absent" "$result"

# Re-source path: an older shell had zle_highlight=(default:bold) from the
# prior init; when rerc re-sources shrc, the hook branch must drop that stale
# whole-line bold, or the ghost stays bolded until a fresh shell. Seed the
# stale value, source, and assert it's cleared.
start_test "re-sourcing shrc clears a stale whole-line default:bold"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    typeset -a zle_highlight; zle_highlight=(default:bold)
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    if (( ${+functions[_shrc_bold_input]} )); then
        case "${zle_highlight[*]}" in
            *default:bold*) print -r -- "stale:present" ;;
            *)              print -r -- "stale:clear" ;;
        esac
    else
        print -r -- "hook:absent"
    fi
' </dev/null 2>/dev/null)
assert_contains "stale:clear" "$result"
assert_not_contains "hook:absent" "$result"

# Regression: kitty (and normal-keypad xterm) send Home/End as the CSI forms
# \e[H / \e[F, which terminfo's khome/kend -- the SS3 or \e[1~/\e[4~ forms --
# don't cover, and shrc doesn't switch the keypad into application mode. shrc
# binds the literal forms so Home/End work there; in particular End then
# accepts the zsh-autosuggestions ghost, whose accept fires from end-of-line.
start_test "shrc binds the CSI Home/End forms under interactive zsh"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    print -r -- "end:$(bindkey "^[[F")"
    print -r -- "home:$(bindkey "^[[H")"
' </dev/null 2>/dev/null)
assert_contains "end-of-line" "$result"
assert_contains "beginning-of-line" "$result"
assert_not_contains "undefined-key" "$result"

# Regression: without atuin (as in CI), Up/Down fall back to a native prefix
# history search, bound to the literal arrow forms so kitty's \e[A / \e[B reach
# the widgets -- terminfo cuu1/kcuu1 alone missed kitty, which is how atuin
# used to win the Up key.
start_test "shrc binds Up/Down to the local prefix history search without atuin"
# Hide any real atuin from this subprocess. On a dev box where atuin is
# installed the inherited PATH would make have_command atuin true and bind the
# arrows to the atuin widgets, failing these native-fallback assertions (CI has
# no atuin, so this only bit locally). Drop every PATH entry that holds an atuin
# executable -- cargo/brew/local bin dirs, not the system dirs coreutils are in.
_noatuin_path=""
for _d in ${(s.:.)PATH}; do
    test -x "$_d/atuin" && continue
    _noatuin_path="${_noatuin_path:+$_noatuin_path:}$_d"
done
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    export PATH='"$_noatuin_path"'
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    print -r -- "up:$(bindkey "^[[A")"
    print -r -- "down:$(bindkey "^[[B")"
' </dev/null 2>/dev/null)
assert_contains "up-line-or-local-history" "$result"
assert_contains "down-line-or-local-history" "$result"

# With atuin present, shrc binds BOTH arrows to atuin's fuzzy search
# (up/down-or-atuin-search -> atuin-search) instead of the native fallback:
# atuin's own Up stays off (--disable-up-arrow) and shrc drives the binding, so
# Up and Down open the same atuin search. Stub `atuin` on PATH so `atuin init
# zsh` defines the atuin-search widgets the arrow widgets call, then check the
# arrows bind to them.
start_test "shrc binds Up/Down to atuin's search when atuin is present"
_atuinbin="$_testdir/atuin-arrows-bin"
mkdir -p "$_atuinbin"
cat >"$_atuinbin/atuin" <<'ATUIN'
#!/bin/sh
# Minimal stub of `atuin init zsh`: define the search widgets shrc's arrow
# widgets call, bind only Ctrl-R (no up-arrow, mimicking --disable-up-arrow),
# and -- like real atuin -- define internal _atuin_up_search/_atuin_down_search
# functions, so a regression to those names would collide with shrc's helpers
# (this init is eval'd after shrc's key bindings, so atuin's defs win).
case "$1 $2" in
"init zsh")
    cat <<'ZSH'
_atuin_search_stub() { : }
zle -N atuin-search _atuin_search_stub
zle -N atuin-search-viins _atuin_search_stub
zle -N atuin-search-vicmd _atuin_search_stub
_atuin_up_search() { : }
_atuin_down_search() { : }
bindkey -M emacs '^r' atuin-search
ZSH
    ;;
esac
exit 0
ATUIN
chmod +x "$_atuinbin/atuin"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    export PATH='"$_atuinbin"':$PATH
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    print -r -- "up:$(bindkey "^[[A")"
    print -r -- "down:$(bindkey "^[[B")"
    print -r -- "upfn:${functions[up_or_atuin_search]}"
' </dev/null 2>/dev/null)
assert_contains "up-or-atuin-search" "$result"
assert_contains "down-or-atuin-search" "$result"
# The wrapper must call shrc's own namespaced helper, not atuin's internal
# _atuin_up_search (which atuin defines and which would clobber a shared name).
assert_contains "_shrc_atuin_up" "$result"

test_summary "shrc_zsh_test"
