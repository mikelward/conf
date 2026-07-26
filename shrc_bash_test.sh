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
# Fuzzy Tab completion. readline can only match a prefix, so `mp<TAB>`
# can never reach "My Pictures" on its own; the widget gathers the
# candidates -- commands in command position, files elsewhere -- and
# lets fzf match. These drive the widget directly with
# READLINE_LINE/POINT set,
# which is what bash does for a `bind -x` command -- deterministic where
# feeding a real Tab through a pty is not.
#
# fzf is stubbed: the real one is interactive, and the stub picks the
# first candidate whose characters appear in order, which is what fzf's
# own matching would return for these inputs.
_fuzzy_bin="$_testdir/fuzzybin"
mkdir -p "$_fuzzy_bin"
cat > "$_fuzzy_bin/fzf" << 'STUB'
#!/bin/sh
_query=
for _arg in "$@"; do
    case "$_arg" in --query=*) _query="${_arg#--query=}" ;; esac
done
awk -v q="$_query" '
{
    line = $0; i = 1; ok = 1
    for (n = 1; n <= length(q); n++) {
        c = tolower(substr(q, n, 1))
        p = index(tolower(substr(line, i)), c)
        if (p == 0) { ok = 0; break }
        i += p
    }
    if (ok) { print line; exit }
}'
STUB
chmod +x "$_fuzzy_bin/fzf"

_fuzzy_root="$_testdir/fuzzy"
mkdir -p "$_fuzzy_root/My Pictures/holiday" "$_fuzzy_root/Music"

start_test "Tab completes a subsequence into a name with a space"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="cd mp"
    READLINE_POINT=5
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cd My\ Pictures/' "$result"

start_test "Tab leaves the cursor after what it inserted"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="cd mp"
    READLINE_POINT=5
    _fuzzy_tab
    printf "\nPOINT=[%s]\n" "$READLINE_POINT"
' </dev/null 2>/dev/null | sed -n 's/.*POINT=\[\([0-9]*\)\]/\1/p')
assert_equal "16" "$result"

# The rest of the line has to survive: the widget replaces one word, not
# everything from the cursor on.
start_test "Tab keeps what follows the cursor"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="cd mp && ls"
    READLINE_POINT=5
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cd My\ Pictures/ && ls' "$result"

# Completing inside a directory whose name has a space: the escape has to
# be undone to find it, and put back on the way in.
start_test "Tab completes within a directory already typed"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="cd My\\ Pictures/hol"
    READLINE_POINT=21
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cd My\ Pictures/holiday/' "$result"

# The first word is a command, not a file.
start_test "Tab completes a command in the first word"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE="__fzprobe"
    READLINE_POINT=9
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "__fuzzy_probe_command" "$result"

# The deliberate limit: arguments get filenames, whatever completion the
# command has registered. Standing in for bash's completion machinery
# from outside it is the part that kept producing wrong text on the
# line, so it isn't attempted -- see KNOWN LIMITS in bashrc.fuzzytab.
start_test "Tab offers files for an argument to a command with a completion"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    complete -W "start stop restart" __fzsvc
    READLINE_LINE="__fzsvc mp"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal '__fzsvc My\ Pictures/' "$result"

# A tilde is not expanded through a quoted expansion, so the directory
# lookup has to do it -- otherwise `cd ~/x<TAB>` looks in a directory
# literally named "~" and silently offers nothing.
start_test "Tab completes a path under a tilde"
result=$(HOME="$_fuzzy_root" run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="cd ~/mp"
    READLINE_POINT=7
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cd ~/My\ Pictures/' "$result"

# The trailing slash marks a directory, and only filesystem candidates
# can be one. A command that happens to share its name with a directory
# in the current directory must not come out as `name/`.
start_test "Tab doesn't slash a command that shares a directory's name"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    mkdir -p __fzdir
    __fzdir() { :; }
    READLINE_LINE="__fzdir"
    READLINE_POINT=7
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "__fzdir" "$result"

# After a `;`, `&&` or `|` a command starts again. Treating the word as
# an argument to the line's first command would offer files from the
# current directory in place of the command being typed.
start_test "Tab completes a command after a separator"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE="echo done; __fzprobe"
    READLINE_POINT=20
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "echo done; __fuzzy_probe_command" "$result"

# After a reserved word bash expects something to run, so this is a
# command position -- not an argument to a command called `if`.
start_test "Tab completes a command after a keyword"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE="if __fzprobe"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "if __fuzzy_probe_command" "$result"

# A leading assignment doesn't make the next word an argument.
start_test "Tab completes a command after a leading assignment"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE="FOO=1 __fzprobe"
    READLINE_POINT=15
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "FOO=1 __fuzzy_probe_command" "$result"

# ...but only a real assignment. bash runs `A-B=1 ec` as a command
# called A-B=1, so the next word is its argument: offering a command
# name there would put something on the line that can't run.
start_test "Tab doesn't strip a leading word that isn't an assignment"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE="A-B=1 __fzprobe"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "A-B=1 __fzprobe" "$result"

# `NAME+=value` is an assignment too, so what follows is still a command.
start_test "Tab completes a command after an append assignment"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE="PATH+=:/opt __fzprobe"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "PATH+=:/opt __fuzzy_probe_command" "$result"

# `for na` wants the name of a loop variable, not a command. Treating it
# as a command position offers `nawk` as the variable name.
start_test "Tab doesn't offer commands where a loop variable goes"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="for na"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "for na" "$result"

# `time -p pipeline`: the command comes after the option, so this is
# still a command position.
start_test "Tab completes a command after time -p"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE="time -p __fzprobe"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "time -p __fuzzy_probe_command" "$result"

# `--` ends time's options, so what follows is the pipeline's command.
# `My Pictures` matches `mp`, so a regression shows up as a filename
# landing where the command goes.
start_test "Tab completes a command after time --"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE="time -- __fzprobe"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "time -- __fuzzy_probe_command" "$result"

# The & in `>&` belongs to the operator. Split there, the redirection
# target looks like a command position and gets command names.
start_test "Tab declines a >& redirection rather than offering commands"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="echo >& ta"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "echo >& ta" "$result"

# A leading redirection doesn't consume the command: bash still wants
# one after `>out `, so offering files there would put a filename where
# the command goes.
start_test "Tab completes a command after a leading redirection"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE=">out __fzprobe"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal ">out __fuzzy_probe_command" "$result"

# ...and the target of one is a file, not a command. `ou` is a
# subsequence of plenty of command names, so a regression shows up as
# one of them landing on the line.
start_test "Tab doesn't offer commands for a redirection target"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="> ou"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "> ou" "$result"

# The widget needs READLINE_LINE, which a bind -x command only gets from
# bash 4.0. On 3.2 -- macOS's /bin/bash -- Tab must stay readline's.
start_test "Tab isn't bound on a bash too old to set READLINE_LINE"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    # Stands in for running under 3.2, which the test host is not.
    BASH_VERSION="3.2.57(1)-release"
    source '"$_srcdir"'/bashrc.fuzzytab
    bind -X 2>/dev/null | grep -c _fuzzy_tab
' </dev/null 2>/dev/null | tail -1)
assert_equal "0" "$result"

# An assignment whose value has an escaped space is still one word, so
# what follows is still the command.
start_test "Tab completes a command after an assignment with a space in it"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE="FOO=hello\\ world __fzprobe"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "FOO=hello\\ world __fuzzy_probe_command" "$result"

# The escaping this feature adds has to be something it can read back,
# or a directory it just inserted becomes one you can't descend into.
start_test "Tab completes inside a directory whose name it had to escape"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    mkdir -p "Johns dir/holiday"
    READLINE_LINE="cd Johns\\ dir/hol"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    rm -rf "Johns dir"
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cd Johns\ dir/holiday/' "$result"

# `2to3>out` is a command with a redirection, not a redirection: `ec` is
# 2to3's argument, so it gets files rather than command names.
start_test "Tab doesn't read a command name as a redirection descriptor"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="2to3>out zzq"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "2to3>out zzq" "$result"

# The guard has to cover the rest of the word past the cursor, not just
# the head: that part is dropped too. Here the head looks unquoted, and
# dropping the opening `"` while keeping the closing one would turn a
# working line into a syntax error -- the one way this feature could
# damage a line rather than merely fail to help.
start_test "Tab declines when the rest of the word is quoted"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="cd mp\" x\" && echo ok"
    READLINE_POINT=5
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cd mp" x" && echo ok' "$result"

# `coproc NAME compound-command` puts a command after the `{`.
start_test "Tab completes a command in a named coproc"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE="coproc worker { __fzprobe"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "coproc worker { __fuzzy_probe_command" "$result"

# A pasted or quoted-insert tab is whitespace to bash. Without that,
# the whole buffer is one word and completing replaces all of it.
start_test "Tab treats a literal tab in the buffer as a separator"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE=$'"'"'cd\tmp'"'"'
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "${READLINE_LINE//$'"'"'\t'"'"'/|}"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cd|My\ Pictures/' "$result"

# The candidate list is newline-delimited, so a filename containing one
# arrives as two candidates and neither names a real file. Inserting
# either would put a path on the line that doesn't exist.
start_test "Tab offers nothing for a filename with a newline in it"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    touch $'"'"'zzalpha\nzzbeta'"'"'
    READLINE_LINE="cat zzal"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    rm -f $'"'"'zzalpha\nzzbeta'"'"'
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "cat zzal" "$result"

# A command word with a slash in it is a path: `compgen -c` lists bare
# names, so there would be nothing for the query to match.
start_test "Tab completes an explicit command path"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    touch zzrun-local
    chmod +x zzrun-local
    READLINE_LINE="./zzrn"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    rm -f zzrun-local
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "./zzrun-local" "$result"

# `for` is followed by the name of a loop variable, so a path there is
# text bash rejects as an invalid identifier. It's left in the segment
# on purpose -- a command doesn't follow it -- which lands it in the
# file branch unless declined.
start_test "Tab declines the name position after for"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="for mp"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "for mp" "$result"

# ...but the list a `for` iterates over is values, where a filename is
# exactly what's wanted.
start_test "Tab completes a path in the list after for x in"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="for x in mp"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'for x in My\ Pictures/' "$result"

# `printf %q` writes a control character as ANSI-C quoting, which
# nothing here reads back -- so inserting it would make a directory you
# can enter and not leave.
start_test "Tab offers nothing for a name with a control character"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    mkdir -p $'"'"'zzctl\tname'"'"'
    READLINE_LINE="cd zzctl"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    rm -rf $'"'"'zzctl\tname'"'"'
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "cd zzctl" "$result"

# The query is a word typed at a shell prompt, so fzf's extended search
# operators have to be off: `!foo` there means a file called !foo, and
# fzf would read it as "not foo" and auto-select the sole non-match.
start_test "Tab gives fzf the query with extended search off"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    _args="$(mktemp)"
    _bin="$(mktemp -d)"
    printf "#!/bin/sh\nprintf \"%%s\\n\" \"\$@\" > \"$_args\"\n" > "$_bin/fzf"
    chmod +x "$_bin/fzf"
    export PATH="$_bin:$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="cd mp"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nFLAG=[%s]\n" "$(grep -c -- "--no-extended" "$_args")"
    rm -rf "$_bin" "$_args"
' </dev/null 2>/dev/null | sed -n 's/.*FLAG=\[\([0-9]*\)\]/\1/p')
assert_equal "1" "$result"

# `<<-` is the heredoc operator with tab-stripping, so the word after it
# is the delimiter and the command comes after that.
start_test "Tab completes a command after a spaced <<- heredoc"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE="<<- EOF __fzprobe"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "<<- EOF __fuzzy_probe_command" "$result"

# A byte the locale rejects isn't a control character, but `printf %q`
# still renders it as ANSI-C quoting, which is the thing this can't read
# back. Checking what %q produced catches every such name.
start_test "Tab offers nothing for a name with a byte the locale rejects"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    mkdir -p $'zzbad\377name'
    READLINE_LINE="cd zzbad"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    rm -rf $'zzbad\377name'
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "cd zzbad" "$result"

# `)` ends a case pattern, and a command follows it. The widget doesn't
# model that, so it declines rather than offering the wrong list.
start_test "Tab declines a case clause rather than offering files"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="case x in x) mp"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "case x in x) mp" "$result"

# A pasted or quoted-insert newline ends a command, so what follows is
# a command position rather than an argument to whatever came first.
start_test "Tab completes a command after a newline in the buffer"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE=$'"'"'echo done\n__fzprobe'"'"'
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    # The newline would break the marker across two lines, so it is
    # replaced before printing.
    printf "\nLINE=[%s]\n" "${READLINE_LINE//$'"'"'\n'"'"'/|}"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "echo done|__fuzzy_probe_command" "$result"

# `{fd}>out` assigns a descriptor and then runs a command, so this is
# still a command position.
start_test "Tab completes a command after a {fd} redirection"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE="{fd}>out __fzprobe"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "{fd}>out __fuzzy_probe_command" "$result"

# A process substitution is a command position in the middle of a line
# that otherwise reads as arguments, so the filesystem is the wrong
# list. `My Pictures` is right there to be offered wrongly.
start_test "Tab declines a process substitution rather than offering files"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="cat >( mp"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "cat >( mp" "$result"

# `>|` carries a pipe, which the splitter reads as the end of a command
# unless the line is declined first.
start_test "Tab declines a >| redirection rather than offering commands"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="echo >| ta"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "echo >| ta" "$result"

# `set -o vi` later in the session must not find Tab back on readline's
# completion, so the widget goes into both insert keymaps.
start_test "Tab is the widget in vi-insert too"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    bind -m vi-insert -X 2>/dev/null | grep -c _fuzzy_tab
' </dev/null 2>/dev/null | tail -1)
assert_equal "1" "$result"

# .shrc's have_command searches PATH, so it ignores aliases and
# functions. Sourcing this file must not replace it with one that
# accepts either -- every later caller in .shrc would change with it.
start_test "the fuzzy Tab file leaves shrc's have_command alone"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_not_on_path() { :; }
    if have_command __fuzzy_not_on_path; then
        printf "\nSAW=[function]\n"
    else
        printf "\nSAW=[executables]\n"
    fi
' </dev/null 2>/dev/null | sed -n 's/.*SAW=\[\([a-z]*\)\]/\1/p')
assert_equal "executables" "$result"

# The chosen name came off the filesystem, so the trailing-slash check
# has to take it literally. A directory actually called $FZVAR was being
# expanded as a variable -- unset, so the check ran against nothing and
# the slash went missing, and the escaped sigil then makes the next Tab
# decline.
start_test "Tab slashes a directory whose name looks like a variable"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    unset FZVAR
    mkdir -p "\$FZVAR"
    READLINE_LINE="cd fzv"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    rmdir "\$FZVAR"
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cd \$FZVAR/' "$result"

# Tab in the middle of a word replaces the word, rather than inserting
# the candidate and leaving the rest of the old word behind it -- which
# is how readline would produce `git checkoutout`.
start_test "Tab replaces the whole word when the cursor is inside it"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="cd mpzzz"
    READLINE_POINT=5
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cd My\ Pictures/' "$result"

# A variable in the path is expanded to find the directory, and left as
# typed on the line -- the same deal as a tilde.
start_test "Tab completes a path under a variable"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    export FZROOT="'"$_fuzzy_root"'"
    READLINE_LINE="cd \$FZROOT/mp"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cd $FZROOT/My\ Pictures/' "$result"

start_test "Tab offers nothing for a path under an unset variable"
# Expanding it to nothing would list the root, which is not what was
# asked for.
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    unset FZNOSUCH
    READLINE_LINE="cd \$FZNOSUCH/mp"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cd $FZNOSUCH/mp' "$result"

start_test "Tab completes a variable name"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    export FZUNIQUEVAR=x
    READLINE_LINE="echo \$fzuv"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'echo $FZUNIQUEVAR' "$result"

# A bare `$` is the whole variable list, not a filename fragment. In the
# file branch the query would be "$" itself, so a file with a dollar in
# its name could replace it.
start_test "Tab completes a bare dollar into a variable name"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="echo \$"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    # Which variable comes back first is up to compgen -v, so the check
    # is that what landed on the line is one that exists.
    _name="${READLINE_LINE#echo \$}"
    if test -n "$_name" && test -n "${!_name+set}"; then
        printf "\nVAR=[yes]\n"
    else
        printf "\nVAR=[no]\n"
    fi
' </dev/null 2>/dev/null | sed -n 's/.*VAR=\[\([a-z]*\)\]/\1/p')
assert_equal "yes" "$result"

# The guard: a line the widget can't read is left alone rather than
# guessed at.
start_test "Tab declines a quoted word rather than guessing"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="cd \"My Pic"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cd "My Pic' "$result"

start_test "Tab declines a command substitution rather than running it"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    rm -f "'"$_fuzzy_root"'/substitution-ran"
    READLINE_LINE="cd \$(touch '"$_fuzzy_root"'/substitution-ran)/mp"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    if test -e "'"$_fuzzy_root"'/substitution-ran"; then
        printf "\nRAN=[yes]\n"
    else
        printf "\nRAN=[no]\n"
    fi
' </dev/null 2>/dev/null | sed -n 's/.*RAN=\[\([a-z]*\)\]/\1/p')
assert_equal "no" "$result"

# `cd \$HOME/mp` asks about a directory actually named $HOME. HOME here
# does contain a match, so completing it would quietly put a path from
# somewhere else on the line.
start_test "Tab declines an escaped sigil rather than expanding it"
result=$(HOME="$_fuzzy_root" run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="cd \\\$HOME/mp"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cd \$HOME/mp' "$result"

# `ls|gre` with no spaces is grep being typed, not an argument to ls.
start_test "Tab completes a command after an operator with no spaces"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    __fuzzy_probe_command() { :; }
    READLINE_LINE="ls|__fzprobe"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "ls|__fuzzy_probe_command" "$result"

# A widget is all or nothing: with no fzf to pick from, Tab would do
# nothing at all, so it hands the key back to readline instead.
start_test "Tab returns to readline when fzf has gone away"
# Bound at startup with fzf present, then fzf disappears under the
# running shell -- an uninstall, or a bundle that never landed it. The
# widget must give the key up rather than leave Tab doing nothing.
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    printf "\nBEFORE=[%s]\n" "$(bind -X 2>/dev/null | grep -c _fuzzy_tab)"
    have_command() { test "$1" != fzf; }
    READLINE_LINE="cd mp"
    READLINE_POINT=5
    _fuzzy_tab
    printf "\nAFTER=[%s]\n" "$(bind -X 2>/dev/null | grep -c _fuzzy_tab)"
' </dev/null 2>/dev/null | sed -n 's/.*\(BEFORE\|AFTER\)=\[\([0-9]*\)\]/\1=\2/p' | tr '\n' ' ')
assert_equal "BEFORE=1 AFTER=0 " "$result"

# ...and in the other keymap too. Giving the key back in only the
# current one leaves the first Tab in the other dead.
start_test "Tab returns to readline in vi-insert as well"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    have_command() { test "$1" != fzf; }
    READLINE_LINE="cd mp"
    READLINE_POINT=5
    _fuzzy_tab
    bind -m vi-insert -X 2>/dev/null | grep -c _fuzzy_tab
' </dev/null 2>/dev/null | tail -1)
assert_equal "0" "$result"

# An arithmetic command isn't a place for a filename, and `((` carries
# no `)` yet for the paren guard to catch.
start_test "Tab declines an arithmetic command rather than offering files"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="(( mp"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "(( mp" "$result"

# An explicit command path has to name something runnable: inserting a
# file that can't be invoked is a command line that won't run.
start_test "Tab skips a non-executable for an explicit command path"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    touch zzrun-notes
    READLINE_LINE="./zzrn"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    rm -f zzrun-notes
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "./zzrn" "$result"

# `compgen -c` is newline-delimited too, so a command name containing
# one splits into candidates that aren't commands.
start_test "Tab offers nothing for a command name with a newline in it"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    _bin="$(mktemp -d)"
    touch "$_bin/qqxalpha
qqxbeta"
    chmod +x "$_bin/qqxalpha
qqxbeta"
    PATH="$_bin:$PATH"
    READLINE_LINE="qqxal"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    rm -rf "$_bin"
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "qqxal" "$result"

start_test "WANT_FUZZY_TAB=0 leaves Tab alone"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    export WANT_FUZZY_TAB=0
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    bind -X 2>/dev/null | grep -c _fuzzy_tab
' </dev/null 2>/dev/null | tail -1)
assert_equal "0" "$result"

start_test "Tab is the widget when fzf is installed"
result=$(run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    bind -X 2>/dev/null | grep -c _fuzzy_tab
' </dev/null 2>/dev/null | tail -1)
assert_equal "1" "$result"

# The widget lives in its own file, which .shrc sources when it's
# installed as ~/.bashrc.fuzzytab -- the same arrangement as .shrc.vcs.
start_test "shrc picks up the fuzzy Tab file when it's installed"
_fuzzy_home="$_testdir/fuzzyhome"
mkdir -p "$_fuzzy_home"
ln -sf "$_srcdir/bashrc.fuzzytab" "$_fuzzy_home/.bashrc.fuzzytab"
result=$(HOME="$_fuzzy_home" run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    bind -X 2>/dev/null | grep -c _fuzzy_tab
' </dev/null 2>/dev/null | tail -1)
assert_equal "1" "$result"

# The candidates are real names, so a query still carrying the escape
# the user typed matches none of them: `My\ Pic` looks for a backslash
# that isn't in `My Pictures`.
start_test "Tab matches an escaped basename against the real names"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="cat My\\ Pic"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal 'cat My\ Pictures/' "$result"

# `compgen -c` lists the reserved words, and `printf %q` would turn the
# closing brace into `\}` -- an ordinary command name, leaving the group
# unterminated.
start_test "Tab inserts a reserved word unquoted in command position"
result=$(cd "$_fuzzy_root" && run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    source '"$_srcdir"'/bashrc.fuzzytab
    READLINE_LINE="{ echo ok; }"
    READLINE_POINT=${#READLINE_LINE}
    _fuzzy_tab
    printf "\nLINE=[%s]\n" "$READLINE_LINE"
' </dev/null 2>/dev/null | sed -n 's/.*LINE=\[\(.*\)\]/\1/p')
assert_equal "{ echo ok; }" "$result"

# And without it, Tab is readline's, exactly as it was before the
# feature existed -- no error, no missing function, no dead key.
start_test "shrc is fine when the fuzzy Tab file isn't there"
_bare_home="$_testdir/barehome"
mkdir -p "$_bare_home"
result=$(HOME="$_bare_home" run_interactive_with_timeout 10 bash --norc --noprofile -i -c '
    export PATH="'"$_fuzzy_bin"':$PATH"
    source '"$_srcdir"'/shrc >/dev/null 2>&1
    printf "\nWIDGETS=[%s] COMPLETE=[%s]\n" \
        "$(bind -X 2>/dev/null | grep -c _fuzzy_tab)" \
        "$(bind -q complete 2>/dev/null | grep -c "C-i")"
' </dev/null 2>/dev/null | sed -n 's/.*WIDGETS=\[\([0-9]*\)\] COMPLETE=\[\([0-9]*\)\].*/\1 \2/p')
assert_equal "0 1" "$result"

# `bind -x` is bash's. The file is sourced under dash and zsh by the
# other suites for its string helpers, and on a host that has fzf an
# unguarded binding would report `bind: not found` there.
start_test "the fuzzy Tab file binds nothing outside bash"
result=$(cd "$_fuzzy_root" && PATH="$_fuzzy_bin:$PATH" \
    run_with_timeout 10 dash -c ". $_srcdir/bashrc.fuzzytab" 2>&1)
assert_equal "" "$result"

test_summary "shrc_bash_test"
