#!/bin/bash
#
# End-to-end tests that exercise shrc under a real `bash -i` subshell.
# Only the bash-specific behaviour (DEBUG-trap autocd hook, inherited
# aliases, stty guard) lives here; the sh-portable shrc function tests
# live in shrc_test.sh and are driven under both dash and bash.
#
# Run from the Makefile via `bash shrc_bash_test.sh`.

. "$(dirname "$0")/shrc_test_lib.sh"

# Set up a temp directory tree for cd tests
_autocd_root="$_testdir/autocd"
mkdir -p "$_autocd_root/sub"

# End-to-end: bash -i with shrc should autocd into a trailing-slash dir
# via the DEBUG trap hook. (Without the hook, bash would error with
# "Is a directory" since command_not_found_handle doesn't fire for
# paths containing `/` that happen to resolve to a directory.)
#
# Terminal-title escapes from the prompt machinery land on the same
# line as our marker, so match anywhere on the line, not just ^.
# `--norc --noprofile` skips the invoking user's rc files (e.g. a
# distro default `alias l='ls -CF'` that would clash with shrc's
# `l() { ... }` function definition via bash parse-time alias
# expansion); we only want to exercise shrc itself here.
# run_interactive_with_timeout prefixes `setsid` so bash -i starts in
# a new session with no controlling tty; without that, tcsetattr calls
# from the prompt / readline / shrc's `stty start undef stop undef`
# guard fire SIGTTOU against a non-foreground pgrp and suspend the
# subshell ("Suspended (tty output)"), hanging `make test` whenever it
# is run under a real pty (CI terminal, `script -c`, etc.). </dev/null
# is kept for the same reason against older toolchains that lack
# setsid -- and the timeout -k fallback in run_with_timeout bounds any
# residual hang to ~N+2s.
start_test "bash -i autocds on trailing slash via DEBUG trap"
result=$(cd "$_autocd_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    install_precommand_trap
    ./sub/
    printf "\nPWDMARK=%s\n" "$PWD"
' </dev/null 2>/dev/null | sed -n 's/.*PWDMARK=//p')
assert_equal "$_autocd_root/sub" "$result"

# Tilde-expanded form: user types `~/sub/` and expects to land in
# $HOME/sub, not see "Is a directory". Mirrors the zsh ~/scripts/
# regression this fix addresses.
start_test "bash -i autocds on ~/foo/ via DEBUG trap"
result=$(HOME="$_autocd_root" run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    install_precommand_trap
    ~/sub/
    printf "\nPWDMARK=%s\n" "$PWD"
' </dev/null 2>/dev/null | sed -n 's/.*PWDMARK=//p')
assert_equal "$_autocd_root/sub" "$result"

# Regression: sourcing shrc under an interactive bash that inherits
# aliases with the same names as shrc's function definitions (e.g.
# Ubuntu's default `alias l='ls -CF'` from /etc/bash.bashrc or
# ~/.bashrc) must not break parsing. Bash expands aliases at parse
# time, so without the pre-block `unalias -a`, `l() { ... }` would
# parse as `ls -CF() { ... }` and raise a syntax error, leaving
# install_precommand_trap undefined.
start_test "shrc sources cleanly despite inherited l/ll/la aliases"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    alias l="ls -CF"
    alias ll="ls -alF"
    alias la="ls -A"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    if type install_precommand_trap >/dev/null 2>&1; then
        printf "OK"
    else
        printf "MISSING"
    fi
' </dev/null 2>/dev/null)
assert_equal "OK" "$result"

# Regression: sourcing shrc in a non-tty interactive bash must not
# SIGTTOU-hang on `stty start undef stop undef`. Pre-fix, the stty
# call fired tcsetattr from a non-foreground pgrp under `make -j`
# and suspended the process ("Suspended (tty output)") -- `make
# test` hung forever. A `test -t 0` guard around stty makes this
# safe. The run_with_timeout wrapper adds a short timeout(1)
# fence so a future regression surfaces as a test failure, not a
# hung CI run. When timeout(1) isn't installed the wrapper runs
# the command unfenced; this matches the prior skip-with-timeout
# behaviour while still giving coverage on boxes with timeout.
start_test "shrc stty guard: sources cleanly with stdin=/dev/null (no SIGTTOU hang)"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    printf "DONE"
' </dev/null 2>/dev/null)
assert_equal "DONE" "$result"

# The prompt leaves the bold attribute on so typed input stands out
# (see input_attribute in shrc). readline emits no reset of its own
# when it prints a completion listing, so the matches would inherit the
# bold; colored-stats makes it colour each match and reset afterwards.
# `bind -v` warns "line editing not enabled" on a non-tty stdin but
# still reports the variable, hence the stderr redirect.
start_test "shrc enables readline colored-stats"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    bind -v 2>/dev/null | sed -n "s/^set colored-stats //p"
' </dev/null 2>/dev/null)
assert_equal "on" "$result"

# inputrc carries the same setting for readline users that never source
# shrc (other readline programs, a login shell without it).
start_test "inputrc sets colored-stats"
assert_true grep -qx 'set colored-stats on' "$_srcdir/inputrc"

# bash restores the DEBUG trap after the handler returns, so the trap's
# own `trap - DEBUG` doesn't stick and it keeps firing for every command
# the prompt hooks run. install_precommand_trap arms a flag as its last
# step, and only the first command after that -- the one the user typed
# -- reaches precommand. Without the flag, every prompt hook would be
# recorded as a command: the wrong title, the wrong timing, and a bogus
# atuin history entry, with the real command then going unrecorded.
start_test "the DEBUG trap passes only the user's command to precommand"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    precommand() { printf "SAW[%s]\n" "$*"; }
    __fake_prompt_hook() { :; }
    install_precommand_trap
    echo the-user-command >/dev/null
    # Everything below stands in for the rest of a prompt cycle, which
    # runs with the trap still armed but the flag cleared.
    preprompt >/dev/null 2>&1
    __fake_prompt_hook
' </dev/null 2>/dev/null | grep '^SAW\[')
assert_equal "SAW[echo the-user-command > /dev/null]" "$result"

# A `bind -x` widget -- atuin's and fzf's Ctrl-R handlers, zoxide's zi --
# runs as a command and would otherwise consume the armed flag, so the
# command the user then accepts would go unrecorded and the widget's own
# name would be filed in its place. bash sets READLINE_LINE only while a
# widget runs, which is what distinguishes them.
start_test "the DEBUG trap ignores commands run by readline widgets"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    precommand() { printf "SAW[%s]\n" "$*"; }
    __fake_widget() { :; }
    install_precommand_trap
    # bash sets this for the duration of a bind -x command.
    READLINE_LINE=
    __fake_widget
    unset READLINE_LINE
    echo the-user-command >/dev/null
' </dev/null 2>/dev/null | grep '^SAW\[')
assert_not_contains "__fake_widget" "$result"

# When nothing runs -- an empty line, Ctrl-C at the prompt, a line that
# won't parse -- the arm from the previous prompt is still in place, and
# the next thing to fire the trap is the prompt's own first hook. It must
# be dropped rather than filed as a command: an empty Enter was otherwise
# recorded as `preprompt`, with its title and timing to match.
start_test "the DEBUG trap drops the arm when the prompt hooks run first"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    precommand() { printf "SAW[%s]\n" "$*"; }
    install_precommand_trap
    # No user command in between: this stands in for a prompt cycle that
    # follows an empty line, starting with the cycle marker as a real one
    # does.
    _prompt_cycle_start
    preprompt >/dev/null 2>&1
    __after_hooks() { :; }
    __after_hooks
' </dev/null 2>/dev/null | grep "^SAW\[")
assert_equal "" "$result"

# The marker is what identifies a prompt cycle, not the names of the
# functions it runs -- so someone who types `preprompt` at the prompt gets
# it recorded like any other command.
start_test "the DEBUG trap records a prompt-hook name the user typed"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    precommand() { printf "SAW[%s]\n" "$*"; }
    preprompt() { :; }
    install_precommand_trap
    preprompt
' </dev/null 2>/dev/null | grep "^SAW\[")
assert_equal "SAW[preprompt]" "$result"

# End-to-end: the whole PROMPT_COMMAND chain has to carry the exit status
# of the command the user ran through to preprompt, which reads $? for the
# prompt colour, the job report, and atuin's `history end --exit`. The
# cycle marker runs first, so a marker that returned its own status would
# make every failure look like a success.
start_test "the prompt cycle carries the exit status through to preprompt"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    preprompt() { printf "\nSTATUS[%s]\n" "$?"; }
    (exit 3)
    eval "$PROMPT_COMMAND"
' </dev/null 2>/dev/null | sed -n 's/.*STATUS\[\([0-9]*\)\].*/\1/p')
assert_equal "3" "$result"

###############
# Fuzzy completion (bashrc.fuzzycomplete). Unlike the readline widget
# this replaced, these run the completion the way bash does: set
# COMP_WORDS/COMP_CWORD and call the registered function. That is the
# whole point of the design -- bash splits the line, so there is no line
# parsing to test, and none to get wrong.
#
# fzf is stubbed: the real one is interactive, and the stub picks the
# first candidate whose characters appear in order, which is what fzf's
# own --select-1 --exit-0 would return for these inputs.
_fzc_bin="$_testdir/fzcbin"
mkdir -p "$_fzc_bin"
cat > "$_fzc_bin/fzf" << 'STUB'
#!/bin/bash
# Reads NUL-delimited, like the --read0 the caller passes, so a candidate
# containing a newline stays one candidate here too.
_query=
_icase=
for _arg in "$@"; do
    case "$_arg" in
    --query=*) _query="${_arg#--query=}" ;;
    --ignore-case) _icase=yes ;;
    --case-sensitive) _icase=off ;;
    esac
done
# Smart-case, like the real fzf: an uppercase letter in the query makes
# matching case-sensitive unless --ignore-case says otherwise.
case "$_query" in
*[A-Z]*) test -n "$_icase" || _icase=off ;;
esac
_items=()
mapfile -d '' -t _items
for _item in ${_items[@]+"${_items[@]}"}; do
    if test "$_icase" = off; then
        _rest="$_item"
        _q="$_query"
    else
        _rest="${_item,,}"
        _q="${_query,,}"
    fi
    _ok=yes
    while test -n "$_q"; do
        _c="${_q%"${_q#?}"}"
        _q="${_q#?}"
        case "$_rest" in
        *"$_c"*) _rest="${_rest#*"$_c"}" ;;
        *) _ok=; break ;;
        esac
    done
    if test -n "$_ok"; then
        printf '%s\n' "$_item"
        exit 0
    fi
done
exit 0
STUB
chmod +x "$_fzc_bin/fzf"

_fzc_root="$_testdir/fzc"
mkdir -p "$_fzc_root/My Pictures/holiday" "$_fzc_root/Music"

# A $HOME for the test that goes through shrc, since shrc looks for
# ~/.bashrc.fuzzycomplete -- the name confinst links this file to --
# rather than for the file in the checkout.
_fzc_home="$_testdir/fzchome"
mkdir -p "$_fzc_home"
cp "$_srcdir/bashrc.fuzzycomplete" "$_fzc_home/.bashrc.fuzzycomplete"

# And one whose .shrc.local registers a compspec, for the ordering: a
# local override is sourced after the rest of shrc, so wrapping has to
# happen after it or what it registers is never wrapped.
_fzc_localhome="$_testdir/fzclocalhome"
mkdir -p "$_fzc_localhome"
cp "$_srcdir/bashrc.fuzzycomplete" "$_fzc_localhome/.bashrc.fuzzycomplete"
cat > "$_fzc_localhome/.shrc.local" << 'LOCAL'
_fzclocal() { COMPREPLY=(checkout commit rebase); }
complete -F _fzclocal __fzclocal
LOCAL

# Drives a compspec exactly as bash would, honouring a 124 retry.
_fzc_driver='
    drive() {
        local _line="$1" _spec _fn _rc
        read -r -a COMP_WORDS <<< "$_line"
        case "$_line" in *" ") COMP_WORDS+=("") ;; esac
        COMP_CWORD=$(( ${#COMP_WORDS[@]} - 1 ))
        COMP_LINE="$_line"; COMP_POINT=${#_line}
        local _cmd="${COMP_WORDS[0]}"
        local _cur="${COMP_WORDS[COMP_CWORD]}"
        local _prev="${COMP_WORDS[COMP_CWORD-1]}"
        _fzcspec "$_cmd"
        _fn="${_spec#*-F }"; _fn="${_fn%% *}"
        COMPREPLY=(); "$_fn" "$_cmd" "$_cur" "$_prev"; _rc=$?
        if test "$_rc" -eq 124; then
            _fzcspec "$_cmd"
            _fn="${_spec#*-F }"; _fn="${_fn%% *}"
            COMPREPLY=(); "$_fn" "$_cmd" "$_cur" "$_prev"
        fi
    }
    # The compspec bash would pick: the whole command word first, then
    # the part after the last slash, then the default one. The function
    # is still called with the word as typed.
    _fzcspec() {
        _spec="$(complete -p "$1" 2>/dev/null)" && return 0
        case "$1" in
        */*) _spec="$(complete -p "${1##*/}" 2>/dev/null)" && return 0 ;;
        esac
        _spec="$(complete -p -D)"
    }
'

# The headline case: a command with its own completion still generates
# its own candidates, and they are matched on a subsequence rather than
# a prefix. This is what the widget could never do without standing in
# for bash'"'"'s completion machinery.
start_test "completion fuzzy-matches a command's own candidates"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcgit() { COMPREPLY=(checkout commit cherry-pick rebase); }
    complete -F _fzcgit __fzcgit
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcgit ckout"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "checkout" "$result"

# What real completions actually do: they end in `compgen -W ... -- "$cur"`
# and hand back an already prefix-filtered list, so when the prefix fails
# there is nothing left to match on. Asking again with the word blanked
# gets the whole list, which is the one worth matching against. Without
# this, fuzzy matching would work against a stub and against almost
# nothing installed on a real machine.
start_test "completion retries a prefix-filtering command with the word blanked"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcfilter() {
        COMPREPLY=($(compgen -W "checkout commit rebase" -- "$2"))
    }
    complete -F _fzcfilter __fzcfilter
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcfilter rbse"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "rebase" "$result"

# The retry has to put COMP_WORDS, COMP_LINE and COMP_POINT back: a
# completion that reads any of them after us would otherwise see a line
# with a word missing.
start_test "completion restores the completion variables after a blanked retry"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcfilter() { COMPREPLY=($(compgen -W "rebase" -- "$2")); }
    complete -F _fzcfilter __fzcvars
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcvars rbse"
    printf "\nOUT=[%s|%s|%s]\n" \
        "${COMP_WORDS[COMP_CWORD]}" "$COMP_LINE" "$COMP_POINT"
' </dev/null 2>/dev/null | sed -n 's/.*OUT=\[\(.*\)\]/\1/p')
assert_equal "rbse|__fzcvars rbse|14" "$result"

# The other half, working at the same time: a command with no completion
# of its own gets filenames, matched the same way.
start_test "completion fuzzy-matches filenames for an unknown command"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcnospec mp"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# The bare name: readline quotes it and adds the slash, because it is
# the layer that knows whether the word sits inside an open quote.
assert_equal "My Pictures" "$result"

# A completion that deliberately returns nothing means "there is nothing
# valid here". Without -o default, offering a filename would hand the
# command an argument it does not accept.
start_test "completion offers no files when the spec asks for no fallback"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcempty() { COMPREPLY=(); }
    complete -F _fzcempty __fzcempty
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcempty mp"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "" "$result"

# ... and with -o default it falls through to files, because that is
# what the spec asked for.
start_test "completion offers files when the spec asks for the fallback"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcempty() { COMPREPLY=(); }
    complete -o default -F _fzcempty __fzcdef
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcdef mp"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "My Pictures" "$result"

# The blanked retry asks a different question, so a completion that
# branches on the word can answer about a different kind of thing --
# options for `--x`, positional values for the empty word. A value must
# never be matched in where an option was being typed.
start_test "completion keeps the retry to the kind of word being completed"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    # Options for a dash word, positional values otherwise -- and the
    # value is a subsequence of the misspelled option.
    _fzckind() {
        case "$2" in
        -*) COMPREPLY=($(compgen -W "--verbose --version" -- "$2")) ;;
        *)  COMPREPLY=(vvverboseee) ;;
        esac
    }
    complete -F _fzckind __fzckind
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzckind --verbse"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# `--ver` still says "an option", so the shortened retry stays in the
# right domain and the misspelling is actually rescued.
assert_equal "--verbose" "$result"

# And when the retry does reach the empty word -- past the cap, or on a
# word too short to shorten usefully -- the domain can change, so what
# comes back is filtered to the kind being completed. Forced here by
# taking the shortening attempts away.
start_test "completion drops wrong-kind candidates from an empty-word retry"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzckind2() {
        case "$2" in
        -*) COMPREPLY=($(compgen -W "--verbose --version" -- "$2")) ;;
        *)  COMPREPLY=(vvverboseee) ;;
        esac
    }
    complete -F _fzckind2 __fzckind2
    source '"$_srcdir"'/bashrc.fuzzycomplete
    _FUZZY_COMPLETE_MAX_RETRIES=0
    '"$_fzc_driver"'
    drive "__fzckind2 --verbse"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# The typed word does fuzzy-match `vvverboseee`, so without the guard a
# half-typed option would be replaced by a positional value.
assert_equal "" "$result"

# A prior -D that deliberately generates nothing has to keep doing that:
# taking its options away and substituting `-o default` would turn its
# silence into filename completion.
start_test "completion keeps a prior -D spec's own options"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcquiet() { COMPREPLY=(); }
    complete -D -F _fzcquiet
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcquiet mp"
    printf "\nREPLY=[%s] SPEC=[%s]\n" "${COMPREPLY[*]}" "$(complete -p -D)"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\] SPEC=\[\(.*\)\]/\1|\2/p')
assert_equal "|complete -F _fuzzy_complete -D" "$result"

# ... while a -D carrying options keeps them across the wrap.
start_test "completion carries a prior -D spec's options onto the wrapper"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcopt() { COMPREPLY=(); }
    complete -D -o nospace -o default -F _fzcopt
    source '"$_srcdir"'/bashrc.fuzzycomplete
    printf "\nSPEC=[%s]\n" "$(complete -p -D)"
' </dev/null 2>/dev/null | sed -n 's/.*SPEC=\[\(.*\)\]/\1/p')
assert_equal "complete -o default -o nospace -F _fuzzy_complete -D" "$result"

# Dismissing the picker means "leave it alone", which an empty COMPREPLY
# does not achieve: `-o default` would hand the word to readline's own
# filename completion and it could still be replaced.
start_test "completion leaves the line alone when the picker is dismissed"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    _cancelbin="$(mktemp -d)"
    printf "#!/bin/sh\nexit 130\n" > "$_cancelbin/fzf"
    chmod +x "$_cancelbin/fzf"
    export PATH="$_cancelbin:$PATH"
    _fzccancel() { COMPREPLY=(checkout commit); }
    complete -o default -F _fzccancel __fzccancel
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzccancel mp"
    rm -rf "$_cancelbin"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "mp" "$result"

# ... while fzf simply matching nothing is a different answer: the
# command's own candidates go back for readline to match, which is
# exactly what bash does with them. Bash never prefix-filters COMPREPLY,
# so `checkout`/`commit` for the word `mp` completes to their common
# prefix `c` unwrapped -- measured -- and clearing here took that away.
start_test "completion hands back its candidates when the picker matches nothing"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    _nobin="$(mktemp -d)"
    printf "#!/bin/sh\nexit 1\n" > "$_nobin/fzf"
    chmod +x "$_nobin/fzf"
    export PATH="$_nobin:$PATH"
    _fzcnomatch() { COMPREPLY=(checkout commit); }
    complete -o default -F _fzcnomatch __fzcnomatch
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcnomatch mp"
    rm -rf "$_nobin"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "checkout commit" "$result"

# Re-sourcing .shrc is an ordinary thing to do, and by then -D is
# already ours: clearing the saved generator would drop the lazy loader
# with nothing to reinstate it until a new shell started.
start_test "completion keeps the saved -D generator across a re-source"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcprior2() { COMPREPLY=(alpha beta gamma); }
    complete -D -F _fzcprior2
    source '"$_srcdir"'/bashrc.fuzzycomplete
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcresourced gma"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "gamma" "$result"

# The same for the per-command map: a second source must not forget what
# each wrapped command's original completion was.
start_test "completion keeps its wrapped compspecs across a re-source"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcgit2() { COMPREPLY=(checkout commit rebase); }
    complete -F _fzcgit2 __fzcagain
    source '"$_srcdir"'/bashrc.fuzzycomplete
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcagain ckout"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "checkout" "$result"

# The opt-out has to work in the shell that is already running, not only
# in a fresh one: someone setting it has just hit a completion they want
# out of.
start_test "completion uninstalls itself when turned off and re-sourced"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcorig() { COMPREPLY=(checkout); }
    complete -o default -F _fzcorig __fzcoff2
    source '"$_srcdir"'/bashrc.fuzzycomplete
    WANT_FUZZY_COMPLETE=0
    source '"$_srcdir"'/bashrc.fuzzycomplete
    # The -D message names an internal command and varies by version,
    # so ask whether one is registered rather than what it says.
    complete -p -D >/dev/null 2>&1 && _d=present || _d=gone
    printf "\nSPEC=[%s] D=[%s]\n" "$(complete -p __fzcoff2)" "$_d"
' </dev/null 2>/dev/null | sed -n 's/.*SPEC=\[\(.*\)\] D=\[\(.*\)\]/\1|\2/p')
assert_equal "complete -o default -F _fzcorig __fzcoff2|gone" "$result"

# `complete -r cmd` has to take effect: the command reaches the -D
# wrapper afterwards, and the saved generator must not still be called.
start_test "completion forgets a generator after its compspec is removed"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcgone() { COMPREPLY=(zzgonecandidate); }
    complete -F _fzcgone __fzcgone
    source '"$_srcdir"'/bashrc.fuzzycomplete
    complete -r __fzcgone
    '"$_fzc_driver"'
    drive "__fzcgone zzgone"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# The removed generator was the only source of that candidate, so an
# empty result is the proof it is no longer being called.
assert_equal "" "$result"

# fzf failing to run is a broken install, not an empty match, and
# falling back quietly on every Tab would hide it.
start_test "completion reports an fzf that cannot run"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    _badbin="$(mktemp -d)"
    printf "#!/bin/sh\nexit 127\n" > "$_badbin/fzf"
    chmod +x "$_badbin/fzf"
    export PATH="$_badbin:$PATH"
    _fzcbad() { COMPREPLY=(checkout commit); }
    complete -F _fzcbad __fzcbad
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcbad ck" 2>&1
    rm -rf "$_badbin"
' </dev/null 2>&1 | grep -c "fzf exited 127")
assert_equal "1" "$result"

# ... but only once, or the report would bury the line being edited.
start_test "completion reports a broken fzf only once"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    _badbin="$(mktemp -d)"
    printf "#!/bin/sh\nexit 127\n" > "$_badbin/fzf"
    chmod +x "$_badbin/fzf"
    export PATH="$_badbin:$PATH"
    _fzcbad2() { COMPREPLY=(checkout commit); }
    complete -F _fzcbad2 __fzcbad2
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcbad2 ck"
    drive "__fzcbad2 co"
    drive "__fzcbad2 ch"
    rm -rf "$_badbin"
' </dev/null 2>&1 | grep -c "fzf exited 127")
assert_equal "1" "$result"

# Reporting it is not enough: the candidates the command already
# generated have to survive the picker that couldn't run. A function-only
# spec has no `-o default` to fall through to, so clearing them would
# leave every wrapped command completing to nothing at all -- worse than
# the prefix matching this replaced.
start_test "completion keeps the candidates when fzf cannot run"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    _badbin="$(mktemp -d)"
    printf "#!/bin/sh\nexit 127\n" > "$_badbin/fzf"
    chmod +x "$_badbin/fzf"
    export PATH="$_badbin:$PATH"
    _fzcbad3() { COMPREPLY=(checkout checkpoint); }
    complete -F _fzcbad3 __fzcbad3
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcbad3 check" 2>/dev/null
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
    rm -rf "$_badbin"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "checkout checkpoint" "$result"

# And a picker that writes something *before* dying. Reading the output
# without checking the status took whatever it managed to print as the
# choice, so a truncated write went on the line as text no generator
# ever offered -- while the warning said bash's completion was being
# used instead.
start_test "completion refuses partial output from a picker that died"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    _partbin="$(mktemp -d)"
    printf "#!/bin/sh\ncat >/dev/null\nprintf partial\nexit 2\n" > "$_partbin/fzf"
    chmod +x "$_partbin/fzf"
    export PATH="$_partbin:$PATH"
    _fzcpart() { COMPREPLY=(checkout checkpoint); }
    complete -F _fzcpart __fzcpart
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcpart check" 2>/dev/null
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
    rm -rf "$_partbin"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# Not "partial": the command's own candidates, as for any broken picker.
assert_equal "checkout checkpoint" "$result"

# The same for a dismissal that somehow left output behind: ESC means
# the user chose nothing, whatever bytes arrived with it.
start_test "completion refuses partial output from a dismissed picker"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    _canbin="$(mktemp -d)"
    printf "#!/bin/sh\ncat >/dev/null\nprintf partial\nexit 130\n" > "$_canbin/fzf"
    chmod +x "$_canbin/fzf"
    export PATH="$_canbin:$PATH"
    _fzccanp() { COMPREPLY=(checkout checkpoint); }
    complete -F _fzccanp __fzccanp
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzccanp check" 2>/dev/null
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
    rm -rf "$_canbin"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# The dismissal sentinel, not "partial".
assert_equal "check" "$result"

# A candidate may contain a newline, and a newline-delimited handover
# would offer each half as a choice of its own -- so picking one would
# insert text the command never offered.
start_test "completion keeps a candidate containing a newline whole"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcnl() { COMPREPLY=($'"'"'alpha\nbeta'"'"' zzz); }
    complete -F _fzcnl __fzcnl
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcnl beta"
    printf "\nN=[%s] REPLY=[%s]\n" "${#COMPREPLY[@]}" "${COMPREPLY[0]}"
' </dev/null 2>/dev/null | tr "\n" "~" | sed -n 's/.*N=\[\([0-9]*\)\] REPLY=\[\(.*\)\]~.*/\1|\2/p')
# One candidate, both of its lines -- not the `beta` half on its own.
assert_equal "1|alpha~beta" "$result"

# The candidate's own trailing newline is part of it. Command
# substitution strips every trailing newline rather than only the one
# fzf adds, so without the sentinel `alpha\n` comes back as `alpha` --
# again a value the generator never offered.
start_test "completion keeps a candidate's own trailing newline"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzctn() { COMPREPLY=($'"'"'alpha\n'"'"' zzz); }
    complete -F _fzctn __fzctn
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzctn alp"
    printf "\nREPLY=[%q]\n" "${COMPREPLY[0]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "\$'alpha\\n'" "$result"

# 130 is fzf's documented status for a dismissed picker. A crash or an
# external kill is not the user declining, and reading it as one would
# hold the line silently rather than reporting a broken picker.
start_test "completion treats a killed picker as broken, not dismissed"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    _killbin="$(mktemp -d)"
    printf "#!/bin/sh\nexit 137\n" > "$_killbin/fzf"
    chmod +x "$_killbin/fzf"
    export PATH="$_killbin:$PATH"
    _fzckill() { COMPREPLY=(alpha beta); }
    complete -F _fzckill __fzckill
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzckill al" 2>/dev/null
    rm -rf "$_killbin"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# The generator's candidates, not the typed word held in place.
assert_equal "alpha beta" "$result"

# Filename candidates come back unescaped, since readline is the layer
# that quotes them, while the word off the line still carries the
# escapes the user typed. Matching one against the other rejects the
# candidate and loses a completion bash makes today -- `cd My\ P` is an
# ordinary thing to type.
start_test "completion matches filename candidates on the decoded word"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    source '"$_srcdir"'/bashrc.fuzzycomplete
    # bash-completion sets -o filenames with compopt from inside its
    # helpers, so the saved spec never shows it and only a live reading
    # can. compopt is valid only in a real completion, so it is shadowed.
    compopt() { test -n "${1-}" || printf "compopt -o filenames cmd\n"; }
    _fzcfn() { COMPREPLY=("My Pictures"); }
    complete -F _fzcfn __fzcfn
    _fuzzy_complete_install __fzcfn
    COMP_WORDS=(__fzcfn "My\\ P"); COMP_CWORD=1
    COMP_LINE="__fzcfn My\\ P"; COMP_POINT=${#COMP_LINE}
    COMPREPLY=(); _fuzzy_complete __fzcfn "My\\ P" __fzcfn
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "My Pictures" "$result"

# The sentinel is the word as typed, escapes and all. Under -o filenames
# readline would quote it again and turn `My\ Pic` into a literal, so a
# dismissal would edit the line it was asked to leave alone.
start_test "completion turns filename quoting off for the cancel sentinel"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    _cancelbin="$(mktemp -d)"
    printf "#!/bin/sh\nexit 130\n" > "$_cancelbin/fzf"
    chmod +x "$_cancelbin/fzf"
    export PATH="$_cancelbin:$PATH"
    source '"$_srcdir"'/bashrc.fuzzycomplete
    _fzcasked=
    compopt() {
        if test -z "${1-}"; then printf "compopt -o filenames cmd\n"
        else _fzcasked="$_fzcasked $*"; fi
    }
    _fzccq() { COMPREPLY=("My Pictures"); }
    complete -F _fzccq __fzccq
    _fuzzy_complete_install __fzccq
    COMP_WORDS=(__fzccq "My\\ P"); COMP_CWORD=1
    COMP_LINE="__fzccq My\\ P"; COMP_POINT=${#COMP_LINE}
    COMPREPLY=(); _fuzzy_complete __fzccq "My\\ P" __fzccq
    rm -rf "$_cancelbin"
    case "$_fzcasked" in *"+o filenames"*) printf "\nASKED=[yes]\n" ;;
    *) printf "\nASKED=[no]\n" ;; esac
' </dev/null 2>/dev/null | sed -n 's/.*ASKED=\[\(.*\)\]/\1/p')
assert_equal "yes" "$result"

# The sentinel is a *unique* match, and inside an open quote that is
# readline's cue to close it -- so dismissing the picker on
# `Base/"My Pic` finished the word, where bash with two candidates to
# choose from leaves the quote open. Nothing generated at all is the
# only thing that means "leave this alone" there.
start_test "completion leaves a quoted word alone when the picker is dismissed"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    _cancelbin="$(mktemp -d)"
    printf "#!/bin/sh\nexit 130\n" > "$_cancelbin/fzf"
    chmod +x "$_cancelbin/fzf"
    export PATH="$_cancelbin:$PATH"
    source '"$_srcdir"'/bashrc.fuzzycomplete
    _fzcqc() { COMPREPLY=("My Pictures" "My Picnic"); }
    complete -F _fzcqc __fzcqc
    _fuzzy_complete_install __fzcqc
    COMP_WORDS=(__fzcqc "Base/\"My Pic"); COMP_CWORD=1
    COMP_LINE="__fzcqc Base/\"My Pic"; COMP_POINT=${#COMP_LINE}
    COMPREPLY=(); _fuzzy_complete __fzcqc "My Pic" __fzcqc
    rm -rf "$_cancelbin"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "" "$result"

# And its pair: unquoted, the sentinel is still what holds the line, so
# the empty reply above is the quoting rule rather than the dismissal
# having stopped working.
start_test "completion still returns the cancel sentinel for an unquoted word"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    _cancelbin="$(mktemp -d)"
    printf "#!/bin/sh\nexit 130\n" > "$_cancelbin/fzf"
    chmod +x "$_cancelbin/fzf"
    export PATH="$_cancelbin:$PATH"
    source '"$_srcdir"'/bashrc.fuzzycomplete
    _fzcqu() { COMPREPLY=("My Pictures" "My Picnic"); }
    complete -F _fzcqu __fzcqu
    _fuzzy_complete_install __fzcqu
    COMP_WORDS=(__fzcqu Pic); COMP_CWORD=1
    COMP_LINE="__fzcqu Pic"; COMP_POINT=${#COMP_LINE}
    COMPREPLY=(); _fuzzy_complete __fzcqu Pic __fzcqu
    rm -rf "$_cancelbin"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "Pic" "$result"

# A generator can change which *kind* of fallback bash will offer, not
# just whether there is one: `compopt +o default -o dirnames` narrows it
# to directories, and the saved spec cannot show that.
start_test "completion takes the fallback kind from the live options"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    : > "Mystery File"
    source '"$_srcdir"'/bashrc.fuzzycomplete
    compopt() { test -n "${1-}" || printf "compopt +o default -o dirnames cmd\n"; }
    _fzclk() { COMPREPLY=(); }
    complete -o default -F _fzclk __fzclk
    _fuzzy_complete_install __fzclk
    '"$_fzc_driver"'
    drive "__fzclk myf"
    rm -f "Mystery File"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# `Mystery File` is the only thing matching, and it is not a directory.
assert_equal "" "$result"

# COMPREPLY holds logical names -- `-o filenames` has readline quote
# what goes back. Returning the prefix as the user spelled it gets the
# escapes quoted a second time, so `My\ Pictures/` becomes a directory
# with a real backslash in its name.
start_test "completion hands back a decoded path prefix"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    source '"$_srcdir"'/bashrc.fuzzycomplete
    COMP_WORDS=(cat "My\\ Pictures/hol"); COMP_CWORD=1
    COMP_LINE="cat My\\ Pictures/hol"; COMP_POINT=${#COMP_LINE}
    COMPREPLY=(); _fuzzy_complete cat "My\\ Pictures/hol" cat
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "My Pictures/holiday" "$result"

# The filename fallback is for unquoted words only. Inside quotes a
# backslash means an escape, nothing, or something in between depending
# on which quote it is, and $2 arrives identical in all three -- and a
# quote after some path text truncates $2 to the part after it, losing
# the directory entirely. Each of those was a separate bug; the line is
# drawn at the whole class instead.
# The same line, drawn in the other place it matters: a command's own
# filename candidates. Decoding a quoted word there builds a query for a
# name nobody typed -- but not decoding it is no better, since the word
# arrives in an alphabet the candidates are not in. `"Slash\\D` reaches
# us with both backslashes where the candidate holds one, so the query
# matches nothing and clears a completion bash already made. Neither
# alphabet is the right one, so the picker stands aside and the
# generator's candidates go back for readline to match as it always did.
# `-o dirnames` is not `-o filenames`. It says what to do when the
# compspec generates *nothing*, and leaves what it did generate alone --
# measured: a returned `My Pictures` inserts verbatim under dirnames and
# as `My\ Pictures` under filenames. So a dirnames spec's candidates are
# raw text, and decoding the word before matching them builds a query
# their own spelling never contained.
start_test "completion does not decode the word for a dirnames spec"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcdnq() { COMPREPLY=(ab '"'"'a\b'"'"'); }
    complete -o dirnames -F _fzcdnq __fzcdnq
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcdnq a\\b"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# Decoding would query `ab` and take the other candidate.
assert_equal 'a\b' "$result"

# The pair, so the above is the option rather than decoding having
# stopped altogether: under `-o filenames` the candidates really are
# logical names, the word is decoded, and `ab` is the match.
start_test "completion decodes the word for a filenames spec"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcfnq() { COMPREPLY=(ab '"'"'a\b'"'"'); }
    complete -o filenames -F _fzcfnq __fzcfnq
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcfnq a\\b"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "ab" "$result"

start_test "completion leaves a quoted word's filename candidates alone"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    source '"$_srcdir"'/bashrc.fuzzycomplete
    compopt() { test -n "${1-}" || printf "compopt -o filenames cmd\n"; }
    _fzcqq() { COMPREPLY=(ab '"'"'a\b'"'"'); }
    complete -F _fzcqq __fzcqq
    _fuzzy_complete_install __fzcqq
    COMP_WORDS=(__fzcqq "'"'"'a\b"); COMP_CWORD=1
    COMP_LINE="__fzcqq '"'"'a\b"; COMP_POINT=${#COMP_LINE}
    COMPREPLY=(); _fuzzy_complete __fzcqq "a\b" __fzcqq
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# Both candidates, untouched. Querying at all -- decoded or not -- picks
# one of them, and which one is an artefact of the alphabet mismatch.
assert_equal 'ab a\b' "$result"

# The regression that shows: inside double quotes bash doubles a
# backslash, so `"Slash\\D` arrives with two against a candidate holding
# one. The query matches nothing, and clearing on no-match takes away a
# completion bash performs correctly on its own -- `"Slash\\Dir"`.
start_test "completion keeps a quoted candidate its query could not match"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    source '"$_srcdir"'/bashrc.fuzzycomplete
    compopt() { test -n "${1-}" || printf "compopt -o filenames cmd\n"; }
    _fzcsq() { COMPREPLY=('"'"'Slash\Dir'"'"'); }
    complete -F _fzcsq __fzcsq
    _fuzzy_complete_install __fzcsq
    COMP_WORDS=(__fzcsq "\"Slash\\\\D"); COMP_CWORD=1
    COMP_LINE="__fzcsq \"Slash\\\\D"; COMP_POINT=${#COMP_LINE}
    COMPREPLY=(); _fuzzy_complete __fzcsq "Slash\\\\D" __fzcsq
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal 'Slash\Dir' "$result"

start_test "completion declines a word opened with a single quote"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _qroot="$(mktemp -d)"
    mkdir -p "$_qroot/My Pictures"
    cd "$_qroot" || exit 1
    source '"$_srcdir"'/bashrc.fuzzycomplete
    COMP_WORDS=(cat "'"'"'mp"); COMP_CWORD=1
    COMP_LINE="cat '"'"'mp"; COMP_POINT=${#COMP_LINE}
    COMPREPLY=(); _fuzzy_complete cat "mp" cat
    cd / && rm -rf "$_qroot"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# `My Pictures` is right there and matches `mp` when unquoted.
assert_equal "" "$result"

start_test "completion declines a word opened with a double quote"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _qroot="$(mktemp -d)"
    mkdir -p "$_qroot/My Pictures"
    cd "$_qroot" || exit 1
    source '"$_srcdir"'/bashrc.fuzzycomplete
    COMP_WORDS=(cat "\"mp"); COMP_CWORD=1
    COMP_LINE="cat \"mp"; COMP_POINT=${#COMP_LINE}
    COMPREPLY=(); _fuzzy_complete cat "mp" cat
    cd / && rm -rf "$_qroot"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "" "$result"

# The same for a quote after some path text, where bash has already
# dropped the directory from $2 before the function is called.
start_test "completion declines a word with a quote after the path"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _qroot2="$(mktemp -d)"
    mkdir -p "$_qroot2/SlashDir"
    : > "$_qroot2/SlashDir/My Pictures"
    cd "$_qroot2" || exit 1
    source '"$_srcdir"'/bashrc.fuzzycomplete
    COMP_WORDS=(cat "Base/'"'"'Slash\\Dir/mp"); COMP_CWORD=1
    COMP_LINE="cat Base/'"'"'Slash\\Dir/mp"; COMP_POINT=${#COMP_LINE}
    COMPREPLY=(); _fuzzy_complete cat "Slash\\Dir/mp" cat
    cd / && rm -rf "$_qroot2"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# Without the decline this returns SlashDir/'s contents wearing the
# prefix that was typed -- a path that does not exist.
assert_equal "" "$result"

# `complete -p` prints reusable shell input, so a command name needing
# quotes comes back quoted -- bash prints `'\''['\''` for `[`. Slicing the
# text keeps the quotes and wraps a command that does not exist.
start_test "completion wraps a command whose name needs quoting"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcbrack() { COMPREPLY=(); }
    complete -F _fzcbrack "["
    source '"$_srcdir"'/bashrc.fuzzycomplete
    printf "\nSPEC=[%s]\n" "$(complete -p "[")"
' </dev/null 2>/dev/null | sed -n 's/.*SPEC=\[\(.*\)\]/\1/p')
assert_equal "complete -F _fuzzy_complete '['" "$result"

# Readline is configured case-insensitive here, and fzf matches
# smart-case -- so an uppercase query would reject a candidate bash
# accepts, taking a completion away rather than adding one.
start_test "completion follows readline's case-insensitive setting"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    bind "set completion-ignore-case on" 2>/dev/null
    _fzcci() { COMPREPLY=("My Pictures"); }
    complete -F _fzcci __fzcci
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcci MY"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "My Pictures" "$result"

# The other direction is deliberately not symmetric, and this pins it.
# With the setting off -- readline's default -- smart-case still matches
# `mp` against `My Pictures`, which readline would not, and passing
# `--case-sensitive` to follow readline would take away the example this
# whole file exists for. Adding a match readline could not find is the
# point; the rule is never removing one.
#
# Driven through the filename fallback rather than a command's own
# candidates, because that is where a no-match is observable: a wrapped
# command hands its candidates back when nothing matches, so the answer
# would be the same either way and the test would prove nothing.
start_test "completion keeps fuzzy matching when readline is case-sensitive"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    bind "set completion-ignore-case off" 2>/dev/null
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzccasenospec mp"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "My Pictures" "$result"

# Bash resolves a compspec by the whole command word and then by the
# basename, but calls the function with the word as typed -- so a
# command run by path arrives under a name the saved maps never held.
start_test "completion finds a saved compspec for a command run by path"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcpath() { COMPREPLY=(checkout commit rebase); }
    complete -F _fzcpath __fzcpath
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "./__fzcpath ckout"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "checkout" "$result"

# A spec removed or replaced after it was wrapped must not be put back
# by the uninstall: that would undo the removal.
start_test "completion does not restore a spec that is no longer its own"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcold() { COMPREPLY=(old); }
    _fzcnew() { COMPREPLY=(new); }
    complete -F _fzcold __fzcreplaced
    source '"$_srcdir"'/bashrc.fuzzycomplete
    complete -F _fzcnew __fzcreplaced
    WANT_FUZZY_COMPLETE=0
    source '"$_srcdir"'/bashrc.fuzzycomplete
    printf "\nSPEC=[%s]\n" "$(complete -p __fzcreplaced)"
' </dev/null 2>/dev/null | sed -n 's/.*SPEC=\[\(.*\)\]/\1/p')
assert_equal "complete -F _fzcnew __fzcreplaced" "$result"

# Readline has to be told these are filenames: that is what makes it
# quote for the current context -- an open quote included -- and append
# the slash that lets the next Tab descend. compopt is only valid inside
# a real completion, so the test shadows it (a function wins over the
# builtin) and records what would have been asked for.
start_test "completion asks readline to treat file candidates as filenames"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    source '"$_srcdir"'/bashrc.fuzzycomplete
    compopt() { printf "COMPOPT[%s]\n" "$*" >> "$_fzc_log"; }
    export _fzc_log="$(mktemp)"
    '"$_fzc_driver"'
    drive "__fzcslash mp"
    printf "\nREPLY=[%s] FILENAMES=[%s]\n" "${COMPREPLY[*]}" \
        "$(grep -c -- "-o filenames" "$_fzc_log")"
    rm -f "$_fzc_log"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\] FILENAMES=\[\([0-9]*\)\]/\1|\2/p')
assert_equal "My Pictures|1" "$result"

# `-P` and `-S` are applied after the function returns, so the word on
# the line carries an affix the candidates don't: `PREgma` would be
# matched against a bare `gamma` and find nothing. Left unwrapped, the
# same as every other action bash applies for itself.
start_test "completion leaves a -P/-S spec unwrapped"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcwrap() { COMPREPLY=(gamma); }
    complete -P PRE -S SUF -o default -F _fzcwrap __fzcwrap
    source '"$_srcdir"'/bashrc.fuzzycomplete
    printf "\nSPEC=[%s]\n" "$(complete -p __fzcwrap)"
' </dev/null 2>/dev/null | sed -n 's/.*SPEC=\[\(.*\)\]/\1/p')
assert_equal "complete -o default -P 'PRE' -S 'SUF' -F _fzcwrap __fzcwrap" "$result"

# A -D taken over by something else after installation must not be
# overwritten by the saved one when disabling.
start_test "completion does not restore a -D that is no longer its own"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcfirst() { COMPREPLY=(); }
    _fzclater() { COMPREPLY=(); }
    complete -D -F _fzcfirst
    source '"$_srcdir"'/bashrc.fuzzycomplete
    complete -D -F _fzclater
    WANT_FUZZY_COMPLETE=0
    source '"$_srcdir"'/bashrc.fuzzycomplete
    printf "\nSPEC=[%s]\n" "$(complete -p -D)"
' </dev/null 2>/dev/null | sed -n 's/.*SPEC=\[\(.*\)\]/\1/p')
assert_equal "complete -F _fzclater -D" "$result"

# The saved -D is deliberately kept across a re-source, but only while
# there is still a -D to keep. Once `complete -r -D` has taken it away
# there is no live spec to overwrite the saved one with, so it has to be
# cleared outright: an unknown command completing from a generator bash
# would no longer call is the removal quietly undone.
start_test "completion forgets a -D that was removed before a re-source"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcgone() { COMPREPLY=(zzunique); }
    complete -D -F _fzcgone
    source '"$_srcdir"'/bashrc.fuzzycomplete
    complete -r -D
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcnospec zzu"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# The removed generator was the only source of that candidate, and no
# file here matches the query, so empty is the proof it is not called.
assert_equal "" "$result"

# bash 3.2 -- still /bin/bash on macOS -- has no associative arrays, and
# `declare -A` there fails at run time rather than being skipped. The
# version check has to come before any of that is reached, or the file
# prints an error on every shell start while claiming to decline
# cleanly. BASH_VERSION is an ordinary variable, so the check can be
# driven without a 3.2 to hand.
start_test "fuzzy completion defines nothing on a bash too old for it"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    BASH_VERSION=3.2.57
    _out="$( . '"$_srcdir"'/bashrc.fuzzycomplete 2>&1 )"
    printf "\nOUT=[%s] FN=[%s]\n" "$_out" "$(type -t _fuzzy_complete)"
' </dev/null 2>/dev/null | sed -n 's/.*OUT=\[\(.*\)\] FN=\[\(.*\)\]/\1|\2/p')
# Nothing said, and nothing defined.
assert_equal "|" "$result"

# A spec may legitimately carry `-P -F`, and reading that argument as
# the flag would take the prefix for the generator -- completion then
# fails with `-F: command not found`.
start_test "completion steps over an option argument that looks like -F"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcdashf() { COMPREPLY=(alpha); }
    complete -F _fzcdashf -P "-F" __fzcdashf
    source '"$_srcdir"'/bashrc.fuzzycomplete
    # The parser directly: such a spec is declined for its -P, so the
    # only place the step-over is visible is what the parse produced.
    _fuzzy_complete_parse "$(complete -p __fzcdashf)" cmd
    printf "\nFN=[%s] FLAGS=[%s]\n" "$_fuzzy_complete_fnname" \
        "$_fuzzy_complete_flagstr"
' </dev/null 2>/dev/null | sed -n 's/.*FN=\[\(.*\)\] FLAGS=\[\(.*\)\]/\1|\2/p')
# Taking the -P argument for the generator would leave the command
# completing with `-F: command not found`.
assert_equal "_fzcdashf| -P" "$result"

# Reaching the retry cap has to stop, not jump to the empty word. The
# empty word is the widest question and the one most likely to be
# answered from a different domain, so skipping ahead to it is the worst
# move at the point where care was given up.
start_test "completion stops at the retry cap instead of asking the empty word"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    # Records every word it is asked about, and only ever answers the
    # empty one -- so a candidate proves the empty word was reached.
    _fzccap() {
        printf "ASKED[%s]\n" "$2" >> "$_fzc_log"
        test -n "$2" || COMPREPLY=(zzemptydomain)
    }
    complete -F _fzccap __fzccap
    source '"$_srcdir"'/bashrc.fuzzycomplete
    export _fzc_log="$(mktemp)"
    '"$_fzc_driver"'
    drive "__fzccap abcdefghij"
    printf "\nREPLY=[%s] EMPTY=[%s]\n" "${COMPREPLY[*]}" \
        "$(grep -c -- "ASKED\[\]" "$_fzc_log")"
    rm -f "$_fzc_log"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\] EMPTY=\[\([0-9]*\)\]/\1|\2/p')
# Never asked about the empty word, so nothing from that domain.
assert_equal "|0" "$result"

# ... while a word short enough to shrink into it still gets there, one
# character at a time, which is the only way it should be reached.
start_test "completion still reaches the empty word by shrinking a short one"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcshort() { test -n "$2" || COMPREPLY=(zzreached); }
    complete -F _fzcshort __fzcshort
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcshort zzr"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "zzreached" "$result"

# Bash strips the opening quote from $2 but leaves it in COMP_WORDS, so
# slicing the array word by the length of $2 takes the quote for a
# character of the word and leaves the last one looking like text past
# the cursor.
start_test "completion keeps an open quote out of the word it retries with"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcquote() { printf "WORD[%s]\n" "${COMP_WORDS[COMP_CWORD]}" >> "$_fzc_log"; }
    source '"$_srcdir"'/bashrc.fuzzycomplete
    export _fzc_log="$(mktemp)"
    # As bash presents it inside an open double quote: the array keeps
    # the quote, $2 does not.
    COMP_WORDS=(cmd "\"My Pic"); COMP_CWORD=1
    COMP_LINE="cmd \"My Pic"; COMP_POINT=11
    _fuzzy_complete_call_bare _fzcquote cmd "My Pic" cmd
    printf "\nFIRST=[%s]\n" "$(head -1 "$_fzc_log")"
    rm -f "$_fzc_log"
' </dev/null 2>/dev/null | sed -n 's/.*FIRST=\[WORD\[\(.*\)\]\]/\1/p')
# One character off the word, quote kept, nothing left over past it.
assert_equal '"My Pi' "$result"

# `-o plusdirs` is a second generator bash runs after the function, and
# after this has already picked. Reproducing it would mean two quoting
# conventions meeting in one list, so the spec is left alone.
start_test "completion leaves an -o plusdirs spec unwrapped"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcplus() { COMPREPLY=(alpha); }
    complete -o plusdirs -F _fzcplus __fzcplus
    source '"$_srcdir"'/bashrc.fuzzycomplete
    printf "\nSPEC=[%s]\n" "$(complete -p __fzcplus)"
' </dev/null 2>/dev/null | sed -n 's/.*SPEC=\[\(.*\)\]/\1/p')
assert_equal "complete -o plusdirs -F _fzcplus __fzcplus" "$result"

# .shrc sources this from inside init_fuzzy_complete, and `declare` in a
# function is local to it. Without -g the saved compspecs would go out of
# scope the moment initialisation returned, while every command stayed
# registered to the wrapper -- so every Tab would find no generator and
# offer nothing the command knows about. Sourcing at the top level, which
# every other test here does, hides it completely.
start_test "completion survives being sourced from inside a function"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcscope() { COMPREPLY=(checkout commit rebase); }
    complete -F _fzcscope __fzcscope
    # Exactly how .shrc loads it.
    _init_it() { . '"$_srcdir"'/bashrc.fuzzycomplete; }
    _init_it
    '"$_fzc_driver"'
    drive "__fzcscope ckout"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "checkout" "$result"

# A spec naming a second generator beside the function is left alone:
# bash applies every action, so the -W list would be merged in after the
# pick, outside fzf and unmatchable.
start_test "completion leaves a mixed-generator spec unwrapped"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcmixed() { COMPREPLY=(alpha); }
    complete -F _fzcmixed -W "beta gamma" __fzcmixed
    source '"$_srcdir"'/bashrc.fuzzycomplete
    printf "\nSPEC=[%s]\n" "$(complete -p __fzcmixed)"
' </dev/null 2>/dev/null | sed -n 's/.*SPEC=\[\(.*\)\]/\1/p')
assert_equal "complete -W 'beta gamma' -F _fzcmixed __fzcmixed" "$result"

# Declining a -D this cannot reproduce is a decision, not a failure: a
# non-zero status here is what .shrc reports on, and would warn on every
# shell start about a supported case.
start_test "completion succeeds when it declines an unsupported -D"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    complete -D -W "alpha beta"
    if . '"$_srcdir"'/bashrc.fuzzycomplete; then _r=ok; else _r=failed; fi
    printf "\nSTATUS=[%s] D=[%s]\n" "$_r" "$(complete -p -D)"
' </dev/null 2>/dev/null | sed -n 's/.*STATUS=\[\(.*\)\] D=\[\(.*\)\]/\1|\2/p')
assert_equal "ok|complete -W 'alpha beta' -D" "$result"

# Every action beside -F is refused, in both spellings. bash applies
# each one and merges its results in after this has already picked, so
# those candidates never reach fzf and put the ambiguity back.
start_test "completion refuses every generator action beside -F"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcact() { COMPREPLY=(alpha); }
    # One per shape: a lowercase action, the -A form, a filter, and the
    # directory option.
    complete -d -F _fzcact __fzcact1
    complete -A hostname -F _fzcact __fzcact2
    complete -X "bad*" -F _fzcact __fzcact3
    complete -o plusdirs -F _fzcact __fzcact4
    # ... and one that names nothing else, which must still be wrapped.
    complete -o nospace -F _fzcact __fzcact5
    source '"$_srcdir"'/bashrc.fuzzycomplete
    _r=
    for _c in __fzcact1 __fzcact2 __fzcact3 __fzcact4; do
        case "$(complete -p $_c)" in
        *_fuzzy_complete*) _r="${_r}W" ;;
        *) _r="${_r}." ;;
        esac
    done
    case "$(complete -p __fzcact5)" in
    *_fuzzy_complete*) _r="${_r}W" ;;
    *) _r="${_r}." ;;
    esac
    printf "\nOUT=[%s]\n" "$_r"
' </dev/null 2>/dev/null | sed -n 's/.*OUT=\[\(.*\)\]/\1/p')
# Four left alone, the plain one wrapped.
assert_equal "....W" "$result"

# The same guard on the -D path, where a second action would apply to
# every command without a spec of its own.
start_test "completion refuses a -D naming another action"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcdact() { COMPREPLY=(alpha); }
    complete -D -F _fzcdact -W "beta gamma"
    source '"$_srcdir"'/bashrc.fuzzycomplete
    printf "\nSPEC=[%s]\n" "$(complete -p -D)"
' </dev/null 2>/dev/null | sed -n 's/.*SPEC=\[\(.*\)\]/\1/p')
assert_equal "complete -W 'beta gamma' -F _fzcdact -D" "$result"

# `compopt` with no name changes the completion currently executing, so
# a retry can undo what the generator said about the word actually
# typed. The veto has to be read before any retry runs.
start_test "completion keeps the fallback veto made for the typed word"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    source '"$_srcdir"'/bashrc.fuzzycomplete
    # compopt is only valid inside a real completion, so it is shadowed
    # here -- a function wins over the builtin -- with just enough state
    # to answer what the live options are.
    _fzcstate="-o default"
    compopt() {
        case "${1-}" in
        "") printf "complete %s cmd\n" "$_fzcstate" ;;
        +o) _fzcstate= ;;
        -o) _fzcstate="-o default" ;;
        esac
    }
    # Forbids filenames for the word as typed, allows them for anything
    # shorter -- and never generates, so a retry always happens.
    _fzcveto() {
        if test "$2" = mp; then compopt +o default; else compopt -o default; fi
        COMPREPLY=()
    }
    complete -o default -F _fzcveto __fzcveto
    _fuzzy_complete_install __fzcveto
    '"$_fzc_driver"'
    drive "__fzcveto mp"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# `My Pictures` is sitting right there; the veto made for `mp` has to
# hold even though a shorter retry said the opposite afterwards.
assert_equal "" "$result"

# The fallback veto was one option among several. Everything else a
# retry does to the live options is in force too when readline inserts
# the result, so the honest call's whole option state has to go back --
# here a `-o nospace` the typed word asked for and a shorter retry
# turned off.
start_test "completion restores the options the honest call left"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    source '"$_srcdir"'/bashrc.fuzzycomplete
    # Shadowed the same way as the veto test above, tracking one option.
    _fzcopts=
    compopt() {
        case "${1-}" in
        "") printf "compopt %s cmd\n" "$_fzcopts" ;;
        -o) _fzcopts="-o $2" ;;
        +o) _fzcopts= ;;
        esac
    }
    # nospace for the word as typed, off for anything shorter -- and
    # generates only for the shorter one, so a retry always happens.
    _fzcns() {
        if test "$2" = mp; then
            compopt -o nospace
            COMPREPLY=()
        else
            compopt +o nospace
            COMPREPLY=(mypick)
        fi
    }
    complete -F _fzcns __fzcns
    _fuzzy_complete_install __fzcns
    '"$_fzc_driver"'
    drive "__fzcns mp"
    printf "\nOPTS=[%s]\n" "$_fzcopts"
' </dev/null 2>/dev/null | sed -n 's/.*OPTS=\[\(.*\)\]/\1/p')
assert_equal "-o nospace" "$result"

# Bash serializes a compspec with its arguments quoted, so a `-P` prefix
# whose text happens to read like an option is still just text. Matching
# the serialized string can not tell the two apart, which is why the
# option queries read the parsed flags instead.
start_test "completion does not read option text out of a quoted prefix"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcpfx() { COMPREPLY=(); }
    complete -P " -o default " -F _fzcpfx __fzcpfx
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcpfx mp"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# The spec asked for no fallback at all, so `My Pictures` must not be
# offered however much the prefix looks like `-o default`.
assert_equal "" "$result"

# `-o dirnames` asks for directory completion, not filename completion.
# A regular file here would be a candidate bash would never have offered.
start_test "completion offers only directories for an -o dirnames spec"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    : > "Mystery File"
    _fzcempty() { COMPREPLY=(); }
    complete -o dirnames -F _fzcempty __fzcdirs
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcdirs myf"
    rm -f "Mystery File"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "" "$result"

# Bash passes the text from the start of the word to the cursor as $2,
# which is not the whole word when Tab is pressed in the middle of one.
# Querying with the untyped suffix would reject the very candidate the
# user is reaching for.
start_test "completion queries on the cursor prefix, not the whole word"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcmid() { COMPREPLY=(checkout commit rebase); }
    complete -F _fzcmid __fzcmid
    source '"$_srcdir"'/bashrc.fuzzycomplete
    COMP_WORDS=(__fzcmid ckoutZZZ); COMP_CWORD=1
    COMP_LINE="__fzcmid ckoutZZZ"; COMP_POINT=14
    COMPREPLY=()
    # Bash would pass the text up to the cursor, not the whole word.
    _fuzzy_complete __fzcmid ckout __fzcmid
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "checkout" "$result"

# The blanked retry takes off only the typed prefix: whatever follows
# the cursor is still on the line and still part of the word.
start_test "completion's retry leaves the line alone with the cursor mid-word"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcsaw() { printf "\nSAW=[%s|%s]\n" "$COMP_LINE" "$COMP_POINT" >&2; COMPREPLY=(); }
    source '"$_srcdir"'/bashrc.fuzzycomplete
    COMP_WORDS=(cmd abcdef); COMP_CWORD=1
    COMP_LINE="cmd abcdef"; COMP_POINT=7
    _fuzzy_complete_call_bare _fzcsaw cmd abc cmd
' </dev/null 2>&1 | sed -n 's/.*SAW=\[\(.*\)\]/\1/p' | tr "\n" " ")
# The word cannot be located in the line when the cursor is inside it,
# so the line is left exactly as bash set it and only $2 varies. A true
# line the generator can trust beats one spliced together from two
# alphabets.
assert_equal "cmd abcdef|7 cmd abcdef|7 cmd abcdef|7 " "$result"

# With the cursor at the end of the word -- the ordinary Tab -- the word
# is found in the line and both shrink together.
start_test "completion's retry shortens the line with the cursor at the end"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcsaw2() { printf "\nSAW=[%s|%s]\n" "$COMP_LINE" "$COMP_POINT" >&2; COMPREPLY=(); }
    source '"$_srcdir"'/bashrc.fuzzycomplete
    COMP_WORDS=(cmd abc); COMP_CWORD=1
    COMP_LINE="cmd abc"; COMP_POINT=7
    _fuzzy_complete_call_bare _fzcsaw2 cmd abc cmd
' </dev/null 2>&1 | sed -n 's/.*SAW=\[\(.*\)\]/\1/p' | tr "\n" " ")
assert_equal "cmd ab|6 cmd a|5 cmd |4 " "$result"

# An escaped space means $2 and the array word are different lengths and
# neither contains the other. Each shrinks in its own alphabet; nothing
# is spliced from both.
start_test "completion's retry shortens an escaped word without splicing"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcesc() { printf "\nSAW=[%s|%s]\n" "${COMP_WORDS[COMP_CWORD]}" "$2" >&2; COMPREPLY=(); }
    source '"$_srcdir"'/bashrc.fuzzycomplete
    COMP_WORDS=(cmd "My\\ Pic"); COMP_CWORD=1
    COMP_LINE="cmd My\\ Pic"; COMP_POINT=11
    # As bash presents it: the backslash is gone from $2 and kept in the
    # array.
    _fuzzy_complete_call_bare _fzcesc cmd "My Pic" cmd
' </dev/null 2>&1 | sed -n 's/.*SAW=\[\(.*\)\]/\1/p' | head -1)
assert_equal 'My\ Pi|My Pi' "$result"

# bash-completion loads most completions on the first Tab, saying so
# with exit 124. The spec it registers has to be wrapped before the
# retry, or every lazily-loaded command stays prefix-matched forever --
# which is to say, almost all of them.
start_test "completion wraps a spec a lazy loader registers"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcloader() {
        _fzcreal() { COMPREPLY=(checkout commit rebase); }
        complete -F _fzcreal __fzclazy
        return 124
    }
    complete -D -F _fzcloader
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzclazy ckout"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "checkout" "$result"

# Taking -D outright would silence whatever held it -- on a distro box
# that is the lazy loader, so nothing would ever load again.
start_test "completion keeps the -D that was there before it"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcprior() { COMPREPLY=(alpha beta gamma); }
    complete -D -F _fzcprior
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcunknown gma"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "gamma" "$result"

# The sharpest form of it: a generator that deliberately answers with
# something the typed word does not contain at all. Bash inserts the
# sole candidate, replacing the word; the picker can never match it, so
# clearing on no-match removed a completion that worked unwrapped.
start_test "completion keeps a candidate that does not contain the word"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcrepl() { COMPREPLY=(replacement); }
    complete -F _fzcrepl __fzcrepl
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcrepl x"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "replacement" "$result"

# Nothing the picker can match, and no fallback either: the command's
# candidates still go back, since bash inserts them without asking
# whether the typed word is a prefix of any of them.
start_test "completion hands back its candidates when neither half matches"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcgit() { COMPREPLY=(checkout commit); }
    complete -F _fzcgit __fzcnone
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcnone zzqqzz"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "checkout commit" "$result"

# WANT_FUZZY_COMPLETE=0 leaves every compspec exactly as it was.
start_test "completion installs nothing when it is turned off"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcgit() { COMPREPLY=(checkout); }
    complete -F _fzcgit __fzcoff
    WANT_FUZZY_COMPLETE=0
    source '"$_srcdir"'/bashrc.fuzzycomplete
    printf "\nSPEC=[%s]\n" "$(complete -p __fzcoff)"
' </dev/null 2>/dev/null | sed -n 's/.*SPEC=\[\(.*\)\]/\1/p')
assert_equal "complete -F _fzcgit __fzcoff" "$result"

# Every test above sources bashrc.fuzzycomplete itself, so all of them
# would still pass with the feature never reaching a real shell: shrc
# could stop calling init_fuzzy_complete, look for the wrong path, or
# gate on the wrong shell, and nothing here would notice. That is not a
# hypothetical -- sourcing it from inside a function is exactly how the
# maps came to be function-local while every test stayed green.
#
# So this one drives it the way the user does: register a compspec,
# source shrc, and complete. Nothing between the file and bash is
# stubbed except fzf, which has to be.
start_test "shrc loads the fuzzy completion and wraps a compspec"
result=$(cd "$_fzc_root" && HOME="$_fzc_home" \
    run_interactive_with_timeout 20 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcshrc() { COMPREPLY=(checkout commit rebase); }
    complete -F _fzcshrc __fzcshrc
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    '"$_fzc_driver"'
    drive "__fzcshrc ckout"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "checkout" "$result"

# .shrc.local is the file a host is customised in, and shrc sources it
# after everything else -- so a compspec registered there is only
# wrapped if the wrapping happens later still.
start_test "shrc wraps a compspec registered by .shrc.local"
result=$(cd "$_fzc_root" && HOME="$_fzc_localhome" \
    run_interactive_with_timeout 20 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    '"$_fzc_driver"'
    drive "__fzclocal ckout"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "checkout" "$result"

# This file is bash's alone -- associative arrays, `complete`, COMPREPLY
# -- so unlike shrc it must never be sourced by another shell. shrc
# guards it; this asserts the guard, since a dash login would otherwise
# report a syntax error on every shell start.
start_test "shrc does not source the fuzzy completion file outside bash"
result=$(cd "$_fzc_root" && run_with_timeout 10 dash -c "
    HOME='$_fzc_root'
    cp $_srcdir/bashrc.fuzzycomplete \$HOME/.bashrc.fuzzycomplete
    . $_srcdir/shrc" 2>&1 | grep -c "fuzzycomplete")
assert_equal "0" "$result"

# The string helpers, which is all of it that isn't bash-specific.
start_test "fuzzy completion splits a word into directory and base"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/bashrc.fuzzycomplete
    printf "\nOUT=[%s|%s|%s|%s]\n" \
        "$(fuzzy_complete_dir docs/mp)" "$(fuzzy_complete_base docs/mp)" \
        "$(fuzzy_complete_dir mp)" "$(fuzzy_complete_base mp)"
' </dev/null 2>/dev/null | sed -n 's/.*OUT=\[\(.*\)\]/\1/p')
assert_equal "docs/|mp||mp" "$result"

start_test "fuzzy completion unescapes a word for the filesystem"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/bashrc.fuzzycomplete
    printf "\nOUT=[%s]\n" "$(fuzzy_complete_unescape "My\\ Pictures/")"
' </dev/null 2>/dev/null | sed -n 's/.*OUT=\[\(.*\)\]/\1/p')
assert_equal "My Pictures/" "$result"

# `printf %q` renders a name it cannot escape with backslashes as
# $'...', which nothing here reads back -- so it is refused rather than
# inserted as a path you could enter and not leave.
start_test "fuzzy completion refuses a name needing ANSI-C quoting"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/bashrc.fuzzycomplete
    fuzzy_complete_quote "$(printf "tab\there")" >/dev/null && echo BAD || echo OK
' </dev/null 2>/dev/null | grep -c "^OK")
assert_equal "1" "$result"

start_test "fuzzy completion reads the filename flags off a spec"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/bashrc.fuzzycomplete
    _r=
    for _o in filenames dirnames plusdirs default; do
        fuzzy_complete_wants_filenames "complete -o $_o -F f c" &&
            _r="${_r}1" || _r="${_r}0"
    done
    printf "\nOUT=[%s]\n" "$_r"
' </dev/null 2>/dev/null | sed -n 's/.*OUT=\[\(.*\)\]/\1/p')
# Only -o filenames marks what the function generated. dirnames and
# plusdirs say what to do when it generates nothing, and measurably
# leave a returned `My Pictures` unquoted, exactly as a bare spec does.
assert_equal "1000" "$result"

# Eligibility for the file fallback is the *live* options, not the saved
# flags: a generator can move between the two. `compopt +o dirnames
# -o bashdefault` leaves a stored `-o dirnames` spec asking for nothing
# that names a file, and reading the saved flags offered regular files
# where bash offers none at all.
start_test "completion offers no files when the generator switches to bashdefault"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _lroot="$(mktemp -d)"
    : > "$_lroot/plain.txt"
    cd "$_lroot" || exit 1
    _fzclive() { COMPREPLY=(); }
    complete -o dirnames -F _fzclive __fzclive
    source '"$_srcdir"'/bashrc.fuzzycomplete
    compopt() { test -n "${1-}" || printf "compopt +o dirnames -o bashdefault cmd\n"; }
    '"$_fzc_driver"'
    drive "__fzclive pln"
    cd / && rm -rf "$_lroot"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "" "$result"

# The pair: the same stored spec whose generator leaves `-o dirnames`
# alone still gets directories, so the above is the live reading rather
# than the fallback having stopped working.
start_test "completion still offers directories when the live options keep dirnames"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _lroot2="$(mktemp -d)"
    mkdir -p "$_lroot2/Dir1"
    cd "$_lroot2" || exit 1
    _fzclive2() { COMPREPLY=(); }
    complete -o dirnames -F _fzclive2 __fzclive2
    source '"$_srcdir"'/bashrc.fuzzycomplete
    compopt() { test -n "${1-}" || printf "compopt -o dirnames cmd\n"; }
    '"$_fzc_driver"'
    drive "__fzclive2 D1"
    cd / && rm -rf "$_lroot2"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "Dir1" "$result"

# Ownership is the -F value, not the text of the printed spec. A `-P`
# prefix containing the wrapper name would otherwise claim a spec
# somebody else installed, and the uninstall would then restore the
# obsolete saved one over their newer completion.
start_test "fuzzy completion reads ownership from the -F value"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/bashrc.fuzzycomplete
    _r=
    fuzzy_complete_is_ours "complete -o nospace -F _fuzzy_complete demo" &&
        _r="${_r}1" || _r="${_r}0"
    fuzzy_complete_is_ours "complete -P '"'"' -F _fuzzy_complete '"'"' -F other demo" &&
        _r="${_r}1" || _r="${_r}0"
    fuzzy_complete_is_ours "complete -F other demo" && _r="${_r}1" || _r="${_r}0"
    printf "\nOUT=[%s]\n" "$_r"
' </dev/null 2>/dev/null | sed -n 's/.*OUT=\[\(.*\)\]/\1/p')
assert_equal "100" "$result"

# FIGNORE is readline's, and it runs *after* this file has picked one
# candidate out of the list. A sole candidate readline then rejects is
# discarded rather than replaced, so picking `alpha.o` under `FIGNORE=.o`
# completes to nothing -- where bash alone would have dropped it from the
# list first and completed the name beside it. The picker never sees the
# ignored names now.
#
# The query matches only the ignored name, so the answer does not depend
# on what order the directory is read in.
start_test "completion drops FIGNORE candidates before the picker"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _figroot="$(mktemp -d)"
    : > "$_figroot/alpha.o"
    : > "$_figroot/alpine.txt"
    cd "$_figroot" || exit 1
    FIGNORE=.o
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcnospec ph"
    cd / && rm -rf "$_figroot"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "" "$result"

# The pair that makes the one above mean something: the same word and the
# same file, ignored by a suffix that does not match, comes back.
start_test "completion keeps a candidate FIGNORE does not name"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _figroot="$(mktemp -d)"
    : > "$_figroot/alpha.o"
    : > "$_figroot/alpine.txt"
    cd "$_figroot" || exit 1
    FIGNORE=.zzz
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcnospec ph"
    cd / && rm -rf "$_figroot"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "alpha.o" "$result"

start_test "completion drops FIGNORE candidates from a wrapped command"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    FIGNORE=.o
    _fzcfig() { COMPREPLY=(alpha.o alpine.txt); }
    complete -o filenames -F _fzcfig __fzcfig
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcfig ph"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# Both back for readline, which drops `alpha.o` itself and completes
# `alpine.txt` -- what bash does unwrapped. Without the filter the
# picker settles on `alpha.o` alone and readline discards it, so this
# still tells the two apart.
assert_equal "alpha.o alpine.txt" "$result"

# And its pair, which is the reason the filter is not simply run on every
# list: without `-o filenames` readline never applies FIGNORE, so these
# are not filenames and dropping one would take away a completion bash
# makes today. Same suffix, same word, opposite answer.
start_test "completion keeps FIGNORE candidates where readline would not filter"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    FIGNORE=.o
    _fzcfig2() { COMPREPLY=(alpha.o alpine.txt); }
    complete -F _fzcfig2 __fzcfig2
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcfig2 ph"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "alpha.o" "$result"

# Every candidate ignored is not the same as no candidates: readline
# would have dropped the lot and left the line alone, which is what
# offering the whole list gets. Returning nothing instead would let a
# spec with -o default fall through to something else entirely.
start_test "completion offers the whole list when FIGNORE would empty it"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    FIGNORE=.o
    _fzcfig3() { COMPREPLY=(alpha.o beta.o); }
    complete -o filenames -F _fzcfig3 __fzcfig3
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcfig3 ph"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "alpha.o" "$result"

# bash's own suffix rule: colon-separated, empty entries skipped, and the
# name has to be strictly longer than the suffix -- `FIGNORE=alpha.o`
# does not hide `alpha.o`.
start_test "fuzzy completion applies bash's FIGNORE suffix rule"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/bashrc.fuzzycomplete
    FIGNORE=":.o::.log:"
    fuzzy_complete_ignore_fignore a.o b.log c.txt d.orig
    _r="${_fuzzy_complete_kept[*]}"
    FIGNORE="alpha.o"
    fuzzy_complete_ignore_fignore alpha.o
    printf "\nOUT=[%s|%s]\n" "$_r" "${_fuzzy_complete_kept[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*OUT=\[\(.*\)\]/\1/p')
assert_equal "c.txt d.orig|alpha.o" "$result"

# Which options readline filters under -- measured, since `-o dirnames`
# reads like it should and does not.
start_test "fuzzy completion reads the FIGNORE filter option off a spec"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/bashrc.fuzzycomplete
    _r=
    for _o in filenames plusdirs dirnames default; do
        fuzzy_complete_filters_fignore "complete -o $_o -F f c" &&
            _r="${_r}1" || _r="${_r}0"
    done
    printf "\nOUT=[%s]\n" "$_r"
' </dev/null 2>/dev/null | sed -n 's/.*OUT=\[\(.*\)\]/\1/p')
assert_equal "1100" "$result"

# A spec carrying -o plusdirs is never wrapped, but a generator can turn
# it on for one call with compopt, and then bash merges matching
# directories in after this returns -- so the candidate the picker
# settled on is one of several again and choosing it inserts nothing.
# Bash's own merge is the whole answer, so the picker stands aside.
start_test "completion declines the picker when plusdirs is turned on live"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcpd() { COMPREPLY=(alpha beta); }
    complete -F _fzcpd __fzcpd
    source '"$_srcdir"'/bashrc.fuzzycomplete
    compopt() { test -n "${1-}" || printf "compopt -o plusdirs cmd\n"; }
    '"$_fzc_driver"'
    drive "__fzcpd alp"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
# Not "alpha": the picker would have reduced it to one.
assert_equal "alpha beta" "$result"

# And the pair, so the above is plusdirs rather than the picker being
# broken: the same generator without it still gets fuzzy-matched.
start_test "completion still picks when plusdirs is off"
result=$(cd "$_fzc_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _fzcpd2() { COMPREPLY=(alpha beta); }
    complete -F _fzcpd2 __fzcpd2
    source '"$_srcdir"'/bashrc.fuzzycomplete
    compopt() { test -n "${1-}" || printf "compopt +o plusdirs cmd\n"; }
    '"$_fzc_driver"'
    drive "__fzcpd2 alp"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "alpha" "$result"

# compopt prints every option with an explicit sign, so `+o plusdirs`
# says it is off and must not read as on.
start_test "fuzzy completion reads plusdirs off the live options"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/bashrc.fuzzycomplete
    _r=
    for _s in "compopt -o plusdirs cmd" "compopt +o plusdirs cmd" \
            "compopt -o filenames cmd"; do
        fuzzy_complete_has_plusdirs "$_s" && _r="${_r}1" || _r="${_r}0"
    done
    printf "\nOUT=[%s]\n" "$_r"
' </dev/null 2>/dev/null | sed -n 's/.*OUT=\[\(.*\)\]/\1/p')
assert_equal "100" "$result"

# `-o bashdefault` is not filename completion. bash draws the line
# between it and `-o default`: default is readline's filename
# completion, bashdefault is "the rest of bash's completions", which
# depend on the context and usually name no file at all. Measured
# against bash 5.2: a `-o bashdefault` spec generating nothing completes
# nothing for `My` with `My Pictures` right there.
start_test "completion offers no files for a bashdefault-only spec"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _bdroot="$(mktemp -d)"
    mkdir -p "$_bdroot/My Pictures"
    cd "$_bdroot" || exit 1
    _fzcbd() { COMPREPLY=(); }
    complete -o bashdefault -F _fzcbd __fzcbd
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcbd mp"
    cd / && rm -rf "$_bdroot"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "" "$result"

# The pair: the same generator and the same word under `-o default`,
# which does ask for filenames.
start_test "completion still offers files for a default spec"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _bdroot="$(mktemp -d)"
    mkdir -p "$_bdroot/My Pictures"
    cd "$_bdroot" || exit 1
    _fzcdf() { COMPREPLY=(); }
    complete -o default -F _fzcdf __fzcdf
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcdf mp"
    cd / && rm -rf "$_bdroot"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "My Pictures" "$result"

# A word bash expands rather than reads as a path. A file literally
# named `$HOME` is a subsequence match for `$HME`, so without the
# decline the picker offers a filename where bash offers a variable --
# and this one bites under `-o default` too, not just bashdefault.
start_test "completion declines a word naming a variable"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _vroot="$(mktemp -d)"
    : > "$_vroot/\$HOME"
    cd "$_vroot" || exit 1
    _fzcvar() { COMPREPLY=(); }
    complete -o default -F _fzcvar __fzcvar
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzcvar \$HME"
    cd / && rm -rf "$_vroot"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "" "$result"

# And a leading tilde, which bash completes as a user name.
start_test "completion declines a word naming a user"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fzc_bin"':$PATH"
    _troot="$(mktemp -d)"
    : > "$_troot/~rocket"
    cd "$_troot" || exit 1
    _fzctil() { COMPREPLY=(); }
    complete -o default -F _fzctil __fzctil
    source '"$_srcdir"'/bashrc.fuzzycomplete
    '"$_fzc_driver"'
    drive "__fzctil ~rkt"
    cd / && rm -rf "$_troot"
    printf "\nREPLY=[%s]\n" "${COMPREPLY[*]}"
' </dev/null 2>/dev/null | sed -n 's/.*REPLY=\[\(.*\)\]/\1/p')
assert_equal "" "$result"

start_test "fuzzy completion reads the file-naming fallbacks off a spec"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/bashrc.fuzzycomplete
    _r=
    for _o in default dirnames bashdefault nospace; do
        fuzzy_complete_wants_files "complete -o $_o -F f c" &&
            _r="${_r}1" || _r="${_r}0"
    done
    # bashdefault beside dirnames must not widen it to regular files:
    # measured, bash offers none for that pair either.
    fuzzy_complete_dirs_only "complete -o bashdefault -o dirnames -F f c" &&
        _r="${_r}1" || _r="${_r}0"
    fuzzy_complete_dirs_only "complete -o default -o dirnames -F f c" &&
        _r="${_r}1" || _r="${_r}0"
    printf "\nOUT=[%s]\n" "$_r"
' </dev/null 2>/dev/null | sed -n 's/.*OUT=\[\(.*\)\]/\1/p')
assert_equal "110010" "$result"

# bash 3.2 is still /bin/bash on macOS, and has neither `complete -D`
# nor associative arrays. Half-installing there would be worse than
# staying out of the way.
start_test "fuzzy completion declines a bash too old for it"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    source '"$_srcdir"'/bashrc.fuzzycomplete
    _r=
    for _v in "3.2.57(1)-release" "4.1.2(1)-release" "4.2.53(1)-release" "5.2.15(1)-release"; do
        fuzzy_complete_bash_version_ok "$_v" && _r="${_r}1" || _r="${_r}0"
    done
    printf "\nOUT=[%s]\n" "$_r"
' </dev/null 2>/dev/null | sed -n 's/.*OUT=\[\(.*\)\]/\1/p')
assert_equal "0011" "$result"  # 3.2 and 4.1 out, 4.2 and 5.2 in

test_summary "shrc_bash_test"
