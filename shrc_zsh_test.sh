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

# Opt-in history preview: without WANT_HISTORY_PREVIEW the pick function isn't
# even defined, so the line-pre-redraw hook and its per-keystroke history scan
# stay off by default.
start_test "the history preview is off (function undefined) without WANT_HISTORY_PREVIEW"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    if (( ${+functions[_shrc_history_preview_pick]} )); then
        print -r -- "pick:defined"
    else
        print -r -- "pick:absent"
    fi
' </dev/null 2>/dev/null)
assert_contains "pick:absent" "$result"

# Opted in but the hook mechanism is unavailable (zsh < 5.3, no
# add-zle-hook-widget): the feature can't install and there's no fallback, so it
# must warn rather than skip silently. Simulate the missing widget by emptying
# fpath, then re-run the deferred installer and check for the warning.
start_test "the history preview warns when add-zle-hook-widget is unavailable"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    WANT_HISTORY_PREVIEW=1
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    fpath=()
    init_history_preview 2>&1
' </dev/null 2>&1)
assert_contains "needs add-zle-hook-widget" "$result"

# With WANT_HISTORY_PREVIEW=1 the pick function finds the newest history entry
# that *contains* the buffer -- a substring anywhere, not just a prefix (the
# ghost handles prefixes). A unique marker seeded newest is found first
# regardless of the developer's real history, and the query lands mid-command
# to prove it isn't prefix-only.
# The cases below add fixture commands with `print -s`. shrc sets
# HISTFILE=~/.zsh_history with SHARE_HISTORY/SAVEHIST, so an isolated HOME keeps
# `make test` from writing those markers into the developer's real history.
_hppollhome="$_testdir/hp-poll-home"
mkdir -p "$_hppollhome"
start_test "the history preview picks a mid-command substring match with WANT_HISTORY_PREVIEW"
result=$(HOME="$_hppollhome" run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    WANT_HISTORY_PREVIEW=1
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    if (( ${+functions[_shrc_history_preview_pick]} )); then
        print -s -- "qwrtp_marker echo hello world"
        print -s -- "an unrelated newer line"
        _shrc_history_preview_pick "marker echo"
        print -r -- "match:$_shrc_preview_text"
    else
        print -r -- "pick:absent"
    fi
' </dev/null 2>/dev/null)
assert_contains "match:qwrtp_marker echo hello world" "$result"
assert_not_contains "pick:absent" "$result"

# An entry equal to what is typed is skipped: once the command is fully typed
# there is nothing to preview (and the ghost, not this, extends a prefix).
start_test "the history preview skips an entry equal to the buffer"
result=$(HOME="$_hppollhome" run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    WANT_HISTORY_PREVIEW=1
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    print -s -- "qwrtp_exact_marker"
    _shrc_history_preview_pick "qwrtp_exact_marker"
    print -r -- "match:[$_shrc_preview_text]"
' </dev/null 2>/dev/null)
assert_contains "match:[]" "$result"

# A query that matches nothing leaves the preview empty rather than showing a
# stale or unrelated command.
start_test "the history preview is empty when nothing matches"
result=$(HOME="$_hppollhome" run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    WANT_HISTORY_PREVIEW=1
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    print -s -- "qwrtp_marker echo hello world"
    _shrc_history_preview_pick "no_such_zzq_sentinel"
    print -r -- "match:[$_shrc_preview_text]"
' </dev/null 2>/dev/null)
assert_contains "match:[]" "$result"

# Regression: zle -M takes everything after -M as its message, so `zle -M --
# "$msg"` renders a literal "--" ahead of the text rather than treating -- as
# an option terminator. The display widget must pass the message directly; a
# message starting with - is already safe as the -M operand.
start_test "the history preview passes its message to zle -M without a -- terminator"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    WANT_HISTORY_PREVIEW=1
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    print -r -- "${functions[_shrc_history_preview]}"
' </dev/null 2>/dev/null)
assert_contains 'zle -M "$_shrc_preview_text"' "$result"
assert_not_contains "zle -M --" "$result"

# A multi-line command is retrieved and collapsed to one preview line: ${(V)}
# renders each embedded newline as a visible \n escape rather than injecting a
# real newline into the zle -M area. (Direct event-number indexing surfaces
# multi-line entries reliably; the earlier ${(nOk)history} scan did not.)
start_test "the history preview collapses a multi-line command to one line"
result=$(HOME="$_hppollhome" run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    WANT_HISTORY_PREVIEW=1
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    print -s -- $'\''grep foo\nbar baz\nqux'\''
    _shrc_history_preview_pick "bar baz"
    print -r -- "match:$_shrc_preview_text"
' </dev/null 2>/dev/null)
assert_contains 'match:grep foo\nbar baz\nqux' "$result"

# Opt-out path: enabling the preview registers a line-pre-redraw hook, so
# flipping WANT_HISTORY_PREVIEW off and re-sourcing (rerc) must unregister it --
# otherwise the preview couldn't be turned off without a fresh shell. Enable,
# re-source with it off, and assert the hook and its functions are gone while
# the unrelated bold-input hook on the same line-pre-redraw survives.
start_test "flipping WANT_HISTORY_PREVIEW off and re-sourcing removes the preview hook"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    WANT_HISTORY_PREVIEW=1
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    WANT_HISTORY_PREVIEW=0
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    typeset -a out; zstyle -g out zle-line-pre-redraw widgets 2>/dev/null
    case "${out[*]}" in
        *_shrc_history_preview*) print -r -- "hook:present" ;;
        *)                       print -r -- "hook:removed" ;;
    esac
    case "${out[*]}" in
        *_shrc_bold_input*) print -r -- "bold:present" ;;
        *)                  print -r -- "bold:removed" ;;
    esac
    print -r -- "pickfn:${+functions[_shrc_history_preview_pick]}"
' </dev/null 2>/dev/null)
assert_contains "hook:removed" "$result"
assert_contains "bold:present" "$result"
assert_contains "pickfn:0" "$result"

# Regression: WANT_HISTORY_PREVIEW's natural home is ~/.shrc.local, which shrc
# sources late -- after the interactive zsh block. The install decision is
# deferred (init_history_preview runs after .shrc.local), so a flag set only
# there still installs the preview; deciding in the zsh block would miss it.
# Drop a .shrc.local that sets the flag, source with it unset in the
# environment, and assert the pick function got defined.
start_test "WANT_HISTORY_PREVIEW set in .shrc.local installs the preview"
_hplocal="$_testdir/hp-local-home"
mkdir -p "$_hplocal"
print -r -- "WANT_HISTORY_PREVIEW=1" > "$_hplocal/.shrc.local"
result=$(HOME="$_hplocal" run_interactive_with_timeout 10 env -u ZDOTDIR zsh --no-rcs -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    print -r -- "pickfn:${+functions[_shrc_history_preview_pick]}"
' </dev/null 2>/dev/null)
assert_contains "pickfn:1" "$result"

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

# With atuin present, shrc binds Up to atuin's prefix up-search
# (up-or-atuin-search -> atuin-up-search) and Down to its fuzzy search
# (down-or-atuin-search -> atuin-search), not the native fallback; atuin's own
# Up stays off (--disable-up-arrow) and shrc drives both bindings. Stub `atuin`
# on PATH so `atuin init zsh` defines the search widgets the arrow widgets call,
# then check the arrows bind to them and each picks the right search mode.
start_test "shrc binds Up to atuin's prefix search and Down to fuzzy when atuin is present"
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
zle -N atuin-up-search _atuin_search_stub
zle -N atuin-up-search-viins _atuin_search_stub
zle -N atuin-up-search-vicmd _atuin_search_stub
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
    case "${functions[up_or_atuin_search]}" in
        *atuin-up-search*) print -r -- "up-mode:prefix" ;;
        *)                 print -r -- "up-mode:other" ;;
    esac
    case "${functions[down_or_atuin_search]}" in
        *atuin-up-search*) print -r -- "down-mode:prefix" ;;
        *atuin-search*)    print -r -- "down-mode:fuzzy" ;;
        *)                 print -r -- "down-mode:other" ;;
    esac
' </dev/null 2>/dev/null)
assert_contains "up-or-atuin-search" "$result"
assert_contains "down-or-atuin-search" "$result"
# The wrapper must call shrc's own namespaced helper, not atuin's internal
# _atuin_up_search (which atuin defines and which would clobber a shared name).
assert_contains "_shrc_atuin_up" "$result"
# Up opens atuin's prefix up-search; Down opens the default fuzzy search.
assert_contains "up-mode:prefix" "$result"
assert_contains "down-mode:fuzzy" "$result"

# Regression: when a keymap lacks its per-map variant (atuin-up-search-viins,
# say), the Up wrapper must fall back to the base atuin-up-search (prefix), not
# atuin-search (fuzzy) -- otherwise Up behaves like Down in that keymap. The
# fallback widget is baked into _shrc_atuin_up's body, so assert it names the
# prefix base and never the bare fuzzy widget. Down's fallback is the opposite:
# atuin-search. ("atuin-up-search" does not contain "atuin-search", so the
# not-contains check is exact.)
start_test "the Up wrapper's missing-variant fallback is atuin's prefix search, not fuzzy"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    export PATH='"$_atuinbin"':$PATH
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    print -r -- "${functions[_shrc_atuin_up]}"
' </dev/null 2>/dev/null)
assert_contains "zle atuin-up-search" "$result"
assert_not_contains "zle atuin-search" "$result"

start_test "the Down wrapper's missing-variant fallback is atuin's fuzzy search"
result=$(run_interactive_with_timeout 10 zsh --no-rcs -i -c '
    export PATH='"$_atuinbin"':$PATH
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    print -r -- "${functions[_shrc_atuin_down]}"
' </dev/null 2>/dev/null)
assert_contains "zle atuin-search" "$result"
assert_not_contains "zle atuin-up-search" "$result"

test_summary "shrc_zsh_test"
