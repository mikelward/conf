#!/bin/bash
#
# Tests for config/mesh/env.mesh and config/mesh/rc.mesh.
# Mirrors fish_test.sh but exercises the mesh implementation via `mesh -c`.
# Skips gracefully when mesh is not installed.
#
# Both files are sourced for every snippet: mesh reads env.mesh on every
# invocation and rc.mesh only for interactive shells, and rc.mesh is written
# so that everything above its interactive section is definitions only. That
# is what lets a non-interactive `mesh -c` source it and call into it.
#

. "$(dirname "$0")/shrc_test_lib.sh"

if ! command -v mesh >/dev/null 2>&1; then
    skip_all "mesh not installed"
    test_summary "mesh_test"
    exit 0
fi

_env_mesh="$_srcdir/config/mesh/env.mesh"
_rc_mesh="$_srcdir/config/mesh/rc.mesh"
_fakehome="$_testdir/fakehome"
mkdir -p "$_fakehome"

# Run a mesh snippet with both config files sourced. A fake HOME keeps the
# real one out of reach (the ~/.failsafe probe, ~/.workstation, the history
# file, the local overrides). NO_COLOR would not actually strip anything here
# -- mesh writes no escapes when stdout is not a terminal -- but it is set for
# the same reason the fish harness sets it: so a future assertion doesn't
# depend on that.
#
# $1 is a preamble evaluated after the source (so it can replace a function
# the config defines), $2 the snippet under test. Either may be empty.
_mesh_run_config() {
    local _post="$1"
    local _snippet="$2"
    HOME="$_fakehome" \
        TERM=dumb \
        NO_COLOR=1 \
        SHPOOL_SESSION_NAME= \
        TMUX= \
        SSH_CONNECTION= \
        run_with_timeout 15 mesh -c "
            source $_env_mesh
            source $_rc_mesh
            $_post
            $_snippet
        " </dev/null
}

# Same, but leaving stdin connected to the caller's. The default closes it, so
# the helpers that read stdin -- each, each0, with-address-records -- need this
# one to be given anything to read.
_mesh_run_stdin() {
    local _post="$1"
    local _snippet="$2"
    HOME="$_fakehome" \
        TERM=dumb \
        NO_COLOR=1 \
        SHPOOL_SESSION_NAME= \
        TMUX= \
        SSH_CONNECTION= \
        run_with_timeout 15 mesh -c "
            source $_env_mesh
            source $_rc_mesh
            $_post
            $_snippet
        "
}

# The common case: stub the commands a test host may or may not have, so
# session-backend and the want-* gates are deterministic. have-command is
# replaced rather than PATH-stubbed because it is the single choke point the
# config asks through.
_mesh_run() {
    _mesh_run_config '
        status func have-command(name) {
            match $name {
                shpool | autoshpool | tmux | autotmux | brew | fnm => { return false }
                _ => {
                    if type -P --quiet $name { return true }
                    return false
                }
            }
        }
    ' "$1"
}

###############
# TEST: failsafe short-circuits rc.mesh

start_test "mesh FAILSAFE=1 bails out of rc.mesh"
result="$(HOME="$_fakehome" FAILSAFE=1 run_with_timeout 15 mesh -c "
    source $_rc_mesh
    if type --quiet tilde-pwd { puts defined } else { puts undefined }
" 2>&1 </dev/null)"
assert_contains "failsafe mode" "$result"
assert_contains "undefined" "$result"

start_test "mesh LC_FAILSAFE=1 bails out of rc.mesh"
result="$(HOME="$_fakehome" LC_FAILSAFE=1 run_with_timeout 15 mesh -c "
    source $_rc_mesh
    puts done
" 2>&1 </dev/null)"
assert_contains "failsafe mode" "$result"

# `:bool` reads 1/true as on and 0/false as off. Anything else is reported on
# stderr rather than read as off in silence, so `FAILSAFE=yes` -- which the
# old `== "1"` comparison swallowed -- now tells the person who typed it.
start_test "mesh FAILSAFE=true bails out of rc.mesh"
result="$(HOME="$_fakehome" FAILSAFE=true run_with_timeout 15 mesh -c "
    source $_rc_mesh
    puts done
" 2>&1 </dev/null)"
assert_contains "failsafe mode" "$result"

start_test "mesh LC_FAILSAFE=true bails out of rc.mesh"
result="$(HOME="$_fakehome" LC_FAILSAFE=true run_with_timeout 15 mesh -c "
    source $_rc_mesh
    puts done
" 2>&1 </dev/null)"
assert_contains "failsafe mode" "$result"

for _failsafe_off in 0 false; do
    start_test "mesh FAILSAFE=$_failsafe_off loads rc.mesh and says nothing"
    result="$(HOME="$_fakehome" FAILSAFE="$_failsafe_off" run_with_timeout 15 mesh -c "
        source $_rc_mesh
        puts done
    " 2>&1 </dev/null)"
    assert_not_contains "failsafe mode" "$result"
    assert_not_contains "is not 1/0/true/false" "$result"
    assert_contains "done" "$result"
done

start_test "mesh FAILSAFE=yes is reported and read as off"
result="$(HOME="$_fakehome" FAILSAFE=yes run_with_timeout 15 mesh -c "
    source $_rc_mesh
    puts done
" 2>&1 </dev/null)"
assert_contains "is not 1/0/true/false" "$result"
assert_not_contains "failsafe mode" "$result"
assert_contains "done" "$result"

start_test "mesh ~/.failsafe bails out of rc.mesh"
touch "$_fakehome/.failsafe"
result="$(HOME="$_fakehome" run_with_timeout 15 mesh -c "
    source $_rc_mesh
    puts done
" 2>&1 </dev/null)"
rm -f "$_fakehome/.failsafe"
assert_contains "failsafe mode" "$result"

start_test "mesh no failsafe flag defines the config"
result="$(_mesh_run 'if type --quiet tilde-pwd { puts defined }')"
assert_equal "defined" "$result"

# env-on is the shared reader behind the FAILSAFE checks: unset means off, so
# the default lives in the helper rather than at each call site. The tests above
# go through rc.mesh's standalone copy of the rule; these exercise env.mesh's
# `want-failsafe`, which is the half that calls env-on.
start_test "mesh env-on reads an unset flag as off"
result="$(HOME="$_fakehome" run_with_timeout 15 mesh -c "
    source $_env_mesh
    puts env-on(FAILSAFE)
" 2>&1 </dev/null)"
assert_equal "false" "$result"

for _on in 1 true; do
    start_test "mesh env-on reads $_on as on"
    result="$(HOME="$_fakehome" FAILSAFE="$_on" run_with_timeout 15 mesh -c "
        source $_env_mesh
        puts env-on(FAILSAFE)
    " 2>&1 </dev/null | tail -1)"
    assert_equal "true" "$result"
done

for _off in 0 false; do
    start_test "mesh env-on reads $_off as off"
    result="$(HOME="$_fakehome" FAILSAFE="$_off" run_with_timeout 15 mesh -c "
        source $_env_mesh
        puts env-on(FAILSAFE)
    " 2>&1 </dev/null)"
    assert_equal "false" "$result"
    assert_not_contains "is not 1/0/true/false" "$result"
done

start_test "mesh env-on reports a value that is neither"
result="$(HOME="$_fakehome" FAILSAFE=yes run_with_timeout 15 mesh -c "
    source $_env_mesh
    puts env-on(FAILSAFE)
" 2>&1 </dev/null)"
assert_contains "is not 1/0/true/false" "$result"

start_test "mesh want-failsafe answers for LC_FAILSAFE too"
result="$(HOME="$_fakehome" LC_FAILSAFE=1 run_with_timeout 15 mesh -c "
    source $_env_mesh
    puts want-failsafe()
" 2>&1 </dev/null | tail -1)"
assert_equal "true" "$result"

start_test "mesh want-failsafe is false with no flag and no ~/.failsafe"
result="$(HOME="$_fakehome" run_with_timeout 15 mesh -c "
    source $_env_mesh
    puts want-failsafe()
" 2>&1 </dev/null)"
assert_equal "false" "$result"

###############
# TEST: local environment overrides

# env.local.mesh is read by env.mesh before rc.mesh's session handoff, so
# WANT_SHPOOL and friends set there take effect. rc.local.mesh runs after the
# handoff and is too late for those.
###############
# TEST: CDPATH

# Set in env.mesh, not rc.mesh: a non-interactive `mesh script.mesh` resolves
# `cd` the same way, and a login-shell mesh has no POSIX parent to inherit it
# from. mesh reads it as a list, like PATH.
start_test "mesh sets CDPATH to . and \$HOME"
result="$(_mesh_run 'puts $env.CDPATH:join(",")')"
assert_equal ".,$_fakehome" "$result"

# `cd` echoes the directory it resolved through CDPATH. bash does the same, so
# this is the behavior a user switching over already sees -- asserted rather
# than left to surprise whoever next reads an mcd test.
start_test "mesh cd echoes a directory resolved through CDPATH"
mkdir -p "$_testdir/cdpath-target"
result="$(_mesh_run "
    cd $_testdir
    cd cdpath-target
")"
assert_equal "$_testdir/cdpath-target" "$result"

start_test "mesh CDPATH reaches a non-interactive script"
printf 'puts $env.CDPATH:join(",")\n' > "$_testdir/cdpath.mesh"
result="$(HOME="$_fakehome" run_with_timeout 15 mesh -c "
    source $_env_mesh
    puts \$env.CDPATH:join(\",\")
" </dev/null 2>&1)"
assert_equal ".,$_fakehome" "$result"

###############
# TEST: the completion bell

# Gated on xterm and its variants, as shrc:1635 gates it: that is what turns a
# bell into a window-manager urgency hint rather than a beep.
# Run mesh directly rather than through _mesh_run_config: that helper pins
# TERM=dumb, which is exactly the variable under test here.
_flash_run() {
    HOME="$_fakehome" TERM="$1" run_with_timeout 15 mesh -c "
        source $_env_mesh
        source $_rc_mesh
        flash-terminal
    " </dev/null 2>&1 | od -c | head -1
}

start_test "mesh flash-terminal rings the bell on an xterm"
assert_contains '\a' "$(_flash_run xterm)"

start_test "mesh flash-terminal rings the bell on an xterm variant"
assert_contains '\a' "$(_flash_run xterm-256color)"

start_test "mesh flash-terminal stays quiet on other terminals"
assert_not_contains '\a' "$(_flash_run dumb)"

start_test "mesh flash-terminal stays quiet with no TERM"
assert_not_contains '\a' "$(_flash_run "")"

# `xtermfoo` is not an xterm variant -- the gate is an exact name or an
# `xterm-` prefix, as shrc's `xterm|xterm-*` case is.
start_test "mesh flash-terminal is not fooled by a name starting with xterm"
assert_not_contains '\a' "$(_flash_run xtermfoo)"

# The prompt is what rings it, so the call has to be in preprompt rather than
# left for the user.
start_test "mesh preprompt rings the bell last"
result="$(HOME="$_fakehome" TERM=xterm run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    int func terminal-width() { return 1 }
    str func auth-info() { return \"\" }
    func maybe-background-fetch(auth = \"\") { return }
    func publish-jobs() { return }
    str func dir-info() { return \"dir\" }
    func unmerged() { return }
    preprompt
" </dev/null 2>/dev/null | od -c | tail -3)"
assert_contains '\a' "$result"

###############
# TEST: local environment overrides

start_test "mesh env.local.mesh is read and can set the session gating"
mkdir -p "$_fakehome/.config/mesh"
printf 'export WANT_SHPOOL = "0"\nexport MESH_ENV_LOCAL_RAN = "yes"\n' \
    > "$_fakehome/.config/mesh/env.local.mesh"
result="$(_mesh_run 'puts $env:get(MESH_ENV_LOCAL_RAN, "no") $env:get(WANT_SHPOOL, "unset")')"
assert_equal "yes 0" "$result"

start_test "mesh env.local.mesh can add to PATH"
printf 'add-path /etc start\n' > "$_fakehome/.config/mesh/env.local.mesh"
result="$(_mesh_run 'puts inpath("/etc")')"
assert_equal "true" "$result"

# The point of a machine-local override: what it prepends has to beat the
# standard list, which means it is read *after* that list is built. shrc gets
# the same precedence by sourcing ~/.env.local right after ~/.env.
start_test "mesh env.local.mesh PATH additions land in front of the standard ones"
mkdir -p "$_fakehome/usr-local-bin-stand-in" "$_fakehome/bin"
printf 'add-path %s start\n' "$_fakehome/usr-local-bin-stand-in" \
    > "$_fakehome/.config/mesh/env.local.mesh"
result="$(_mesh_run 'puts $env.PATH[0]')"
assert_equal "$_fakehome/usr-local-bin-stand-in" "$result"

# ...but the globs still go in front of the local file, as in shrc: they are
# the most specific thing on the list.
start_test "mesh scripts.* still leads the local PATH additions"
mkdir -p "$_fakehome/scripts.test"
result="$(_mesh_run 'puts $env.PATH[0]')"
assert_equal "$_fakehome/scripts.test" "$result"
rmdir "$_fakehome/scripts.test"

# $GOPATH/bin is ~/bin already when GOPATH is the default; prepending it
# unconditionally would put ~/bin in front of ~/scripts. shrc:1193 guards it.
start_test "mesh adds \$GOPATH/bin only when GOPATH is not \$HOME"
printf 'export GOPATH = "%s/elsewhere"\n' "$_fakehome" \
    > "$_fakehome/.config/mesh/env.local.mesh"
mkdir -p "$_fakehome/elsewhere/bin"
result="$(_mesh_run 'puts $env.PATH[0]')"
assert_equal "$_fakehome/elsewhere/bin" "$result"

start_test "mesh leaves ~/scripts ahead of ~/bin with the default GOPATH"
printf '' > "$_fakehome/.config/mesh/env.local.mesh"
mkdir -p "$_fakehome/scripts"
result="$(_mesh_run 'puts $env.PATH[0]')"
assert_equal "$_fakehome/scripts" "$result"

# A file's status is that of its last statement, so a failure here would be
# overwritten by every assignment below it and rerc's guard would see success
# over a half-applied local config. Reported at the point of failure instead.
start_test "mesh reports a failing env.local.mesh"
printf 'this is not( valid mesh\n' > "$_fakehome/.config/mesh/env.local.mesh"
result="$(_mesh_run 'puts reached-the-end' 2>&1)"
assert_contains "env.local.mesh failed" "$result"

# Reported, not fatal: a login shell whose PATH was never set up is worse than
# one whose local overrides half-applied, and shrc's `.` of ~/.env.local
# carries on the same way.
start_test "mesh sets up the rest of the environment after a failing env.local.mesh"
assert_contains "reached-the-end" "$result"

start_test "mesh still builds PATH after a failing env.local.mesh"
result="$(_mesh_run 'puts $env.PATH[0]' 2>/dev/null)"
assert_equal "$_fakehome/scripts" "$result"

start_test "mesh is fine with no env.local.mesh"
rm -f "$_fakehome/.config/mesh/env.local.mesh"
result="$(_mesh_run 'puts ok')"
assert_equal "ok" "$result"

# Same rule for the interactive half's local file. Pulled out as a named
# function precisely so it is reachable from here: nothing past rc.mesh's
# `return unless $sh.interactive` can be driven without a pty.
start_test "mesh read-local-rc reports a failing rc.local.mesh"
printf 'this is not( valid mesh\n' > "$_fakehome/.config/mesh/rc.local.mesh"
result="$(_mesh_run 'read-local-rc
puts after' 2>&1)"
assert_contains "rc.local.mesh failed" "$result"
assert_contains "after" "$result"

start_test "mesh read-local-rc is quiet when rc.local.mesh is fine"
printf 'export RC_LOCAL_MARKER = "seen"\n' > "$_fakehome/.config/mesh/rc.local.mesh"
result="$(_mesh_run 'read-local-rc
puts $env.RC_LOCAL_MARKER' 2>&1)"
assert_equal "seen" "$result"

start_test "mesh read-local-rc is fine with no rc.local.mesh"
rm -f "$_fakehome/.config/mesh/rc.local.mesh"
result="$(_mesh_run 'read-local-rc
puts ok' 2>&1)"
assert_equal "ok" "$result"

###############
# TEST: the command shortcuts forward flags

# The whole point of the alias/wrapper conversion: a plain `func l(...args)`
# rejected an undeclared long flag before ...args could collect it, so
# `l --color=never` was `unknown flag --color` and `l --help` printed mesh's
# generated help instead of reaching ls.
_fake_l_bin="$_testdir/fakelbin"
mkdir -p "$_fake_l_bin"
printf '#!/bin/sh\necho "ls got: $@"\n' > "$_fake_l_bin/ls"
chmod +x "$_fake_l_bin/ls"

start_test "mesh an alias shortcut forwards an undeclared long flag"
result="$(PATH="$_fake_l_bin:$PATH" _mesh_run_config '' 'l --color=never somefile')"
assert_contains "color=never" "$result"
assert_contains "somefile" "$result"

start_test "mesh an alias shortcut forwards --help rather than answering it"
result="$(PATH="$_fake_l_bin:$PATH" _mesh_run_config '' 'l --help')"
assert_contains "ls got: " "$result"
assert_contains "help" "$result"
assert_not_contains "Usage:" "$result"

start_test "mesh the shortcuts are wrapper funcs"
result="$(_mesh_run 'type g')"
assert_contains "wrapper func g(...args)" "$result"

###############
# TEST: the delegating helpers forward flags to their command

# retry/recent/body each read one leading option of their own and forward the
# rest. Declaring it as a mesh flag would scan the *whole* argument list, so a
# flag belonging to the delegated command was rejected -- `retry curl --fail`
# was `unknown flag --fail`. shrc reads them as leading options too.
_fake_delegate_bin="$_testdir/fakedelegatebin"
mkdir -p "$_fake_delegate_bin"
printf '#!/bin/sh\necho "curl got: $@"\n' > "$_fake_delegate_bin/curl"
chmod +x "$_fake_delegate_bin/curl"

start_test "mesh retry forwards a long flag to the retried command"
result="$(PATH="$_fake_delegate_bin:$PATH" _mesh_run_config 'func bell() { }' 'retry curl --fail URL')"
assert_equal "curl got: --fail URL" "$result"

start_test "mesh retry still reads its own --sleep in both forms"
result="$(PATH="$_fake_delegate_bin:$PATH" _mesh_run_config 'func bell() { }' 'retry --sleep=0 curl --fail A
retry --sleep 0 curl --fail B')"
assert_equal "curl got: --fail A
curl got: --fail B" "$result"

start_test "mesh setx forwards a long flag to the traced command"
result="$(PATH="$_fake_delegate_bin:$PATH" _mesh_run_config '' 'setx curl --location URL' 2>/dev/null)"
assert_equal "curl got: --location URL" "$result"

start_test "mesh with-agent forwards a long flag"
result="$(PATH="$_fake_delegate_bin:$PATH" _mesh_run_config '' 'with-agent curl --fail X')"
assert_equal "curl got: --fail X" "$result"

start_test "mesh first-arg-last forwards a long flag"
result="$(PATH="$_fake_delegate_bin:$PATH" _mesh_run_config '' 'first-arg-last curl LAST --ignore-case')"
assert_equal "curl got: --ignore-case LAST" "$result"

start_test "mesh shift-options collects the documented --file=value form"
result="$(PATH="$_fake_delegate_bin:$PATH" _mesh_run_config '' 'shift-options curl target --file=value')"
assert_equal "curl got: --file=value target" "$result"

# Not a delegated command's flag -- data that merely looks like one. A plain
# func scans it just the same, so the message helpers are wrappers too.
start_test "mesh warn and error accept text that starts with a dash"
result="$(_mesh_run '
    warn "--x is unset"
    error "--y is unset"
' 2>&1)"
assert_equal "--x is unset
--y is unset" "$result"

start_test "mesh run forwards a long flag to the delegated command"
result="$(PATH="$_fake_delegate_bin:$PATH" _mesh_run_config 'func logger(...a) { }' 'run curl --location URL')"
assert_equal "curl got: --location URL" "$result"

start_test "mesh body forwards a long flag and prints the header"
result="$(printf 'HEADER\naaa\nbbb\n' | HOME="$_fakehome" TERM=dumb NO_COLOR=1 run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    body grep --invert-match aaa
")"
assert_equal "HEADER
bbb" "$result"

# shrc:662 and shrc:954 spell the count as a leading -<number>, which is the
# form both are documented with. A bare `-2` reaches a wrapper as the *integer*
# -2, not a string, so the head is interpolated to text before parsing.
start_test "mesh body accepts the -N shorthand"
result="$(printf 'H1\nH2\nxxx\n' | HOME="$_fakehome" TERM=dumb NO_COLOR=1 run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    body -2 cat
")"
assert_equal "H1
H2
xxx" "$result"

start_test "mesh recent accepts the -N shorthand"
# Counts lines rather than inspecting a value: `recent` prints, and `-2` would
# otherwise reach `ls`, which rejects it with `invalid option -- '2'`.
result="$(_mesh_run '
    cd /etc
    recent -2 | wc -l
' 2>/dev/null | tail -1 | tr -d " ")"
assert_equal "2" "$result"

start_test "mesh body reads its own --lines"
result="$(printf 'H1\nH2\nxxx\n' | HOME="$_fakehome" TERM=dumb NO_COLOR=1 run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    body --lines=2 cat
")"
assert_equal "H1
H2
xxx" "$result"

# starts-with takes data, and a value call scans an argument whose runtime
# value begins with `--` as a flag unless the callee is a wrapper.
start_test "mesh starts-with accepts an argument that looks like a flag"
result="$(_mesh_run 'puts starts-with("--sleep=5", "--sleep=")')"
assert_equal "true" "$result"

###############
# TEST: bak/unbak round-trip, and the flag-shaped name a wrapper exists for

_bak_dir="$_testdir/bakdir"
start_test "mesh bak and unbak round-trip a file"
rm -rf "$_bak_dir"
mkdir -p "$_bak_dir"
printf 'contents\n' > "$_bak_dir/note"
_mesh_run "
    cd $_bak_dir
    bak note
" >/dev/null 2>&1
assert_true test -f "$_bak_dir/note.bak"
_mesh_run "
    cd $_bak_dir
    unbak note.bak
" >/dev/null 2>&1
assert_true test -f "$_bak_dir/note"

# Two things have to hold for a name beginning with `--`: it reaches a wrapper
# as mesh's Flag value, so the reader inside unbak has to read it as text
# (`~` takes a string), and `mv` has to be given the option terminator, or it
# reads the name as an option of its own and refuses the rename.
start_test "mesh bak backs up a file whose name looks like a flag"
rm -rf "$_bak_dir"
mkdir -p "$_bak_dir"
touch "$_bak_dir/--weird"
_mesh_run "
    cd $_bak_dir
    bak --weird
" >/dev/null 2>&1
assert_true test -f "$_bak_dir/--weird.bak"

start_test "mesh unbak restores a file whose name looks like a flag"
result="$(_mesh_run "
    cd $_bak_dir
    unbak --weird.bak
" 2>&1)"
assert_true test -f "$_bak_dir/--weird"
# Neither the shell's reader nor `mv` may object on the way through.
assert_equal "" "$result"

###############
# TEST: rerc reloads both halves

start_test "mesh rerc re-reads env.mesh as well as rc.mesh"
mkdir -p "$_fakehome/.config/mesh"
ln -sf "$_env_mesh" "$_fakehome/.config/mesh/env.mesh"
ln -sf "$_rc_mesh" "$_fakehome/.config/mesh/rc.mesh"
printf 'export MESH_RELOAD_MARKER = "seen"\n' > "$_fakehome/.config/mesh/env.local.mesh"
result="$(_mesh_run '
    $env.MESH_RELOAD_MARKER = ""
    rerc
    puts $env:get(MESH_RELOAD_MARKER, "unset")
' 2>/dev/null | tail -1)"
assert_equal "seen" "$result"
rm -f "$_fakehome/.config/mesh/env.local.mesh" "$_fakehome/.config/mesh/env.mesh" "$_fakehome/.config/mesh/rc.mesh"

###############
# TEST: the vcs shortcuts

# The long-form shortcuts are generated from `vcs --list-commands` at
# interactive start, so the list lives in vcs/commands.go rather than being
# restated here -- see the generator tests further down. What this file still
# hand-picks is the short forms, which have no subcommand of their own name,
# and those are file-scope definitions like the other shells'.
#
# `status` is deliberately absent, and is the one shortcut mesh cannot have:
# it is a mesh builtin, so `alias status` is refused. `st` is the spelling that
# survives here; the other shells keep both.
start_test "mesh defines the short vcs shortcuts the other shells define"
result="$(_mesh_run '
    missing = []
    for name in [am ci di gr lg ma st] {
        if not is-runnable($name) { missing += [$name] }
    }
    puts $missing:repr
')"
assert_equal "[]" "$result"

###############
# TEST: startup auth is gated on a terminal

# `ssh-add` prompts, so a forced-interactive session with stdin redirected
# cannot answer it. config.fish:2044 gates on stdin_is_tty for the same reason.
start_test "mesh startup auth is gated on stdin being a tty"
result="$(_mesh_run_config '
    bool func stdin-is-tty() { return false }
    bool func in-shpool() { return false }
    bool func need-auth() { return true }
    func auth() { puts "PROMPTED" }
' '
    if stdin-is-tty() and not in-shpool() and need-auth() { auth }
    puts done
')"
assert_equal "done" "$result"

start_test "mesh startup auth runs with a tty"
result="$(_mesh_run_config '
    bool func stdin-is-tty() { return true }
    bool func in-shpool() { return false }
    bool func need-auth() { return true }
    func auth() { puts "PROMPTED" }
' '
    if stdin-is-tty() and not in-shpool() and need-auth() { auth }
')"
assert_equal "PROMPTED" "$result"

###############
# TEST: confirm

# An argument-taking modifier cannot be written inside a string, so the join
# has to be bound first -- without that, confirm failed before reaching `gets`
# and the prompt could not be answered at all.
# `confirm` reads a reply, so these bypass _mesh_run's `</dev/null`.
#
# The answer is read as an exit **status**, which is the contract callers use:
# `clone` asks `if confirm(…)`, and a boolean's status view is 0 for true. That
# keeps these three tests independent of how the prompt is worded, which stream
# it goes to, and whether it ends in a newline -- the prompt has its own test
# below, and it should be the only one that breaks when the wording changes.
_confirm_status() {
    printf '%s' "$1" | HOME="$_fakehome" TERM=dumb NO_COLOR=1 run_with_timeout 15 mesh -c "
        source $_env_mesh
        source $_rc_mesh
        confirm are you sure
    " >/dev/null 2>&1
    echo "$?"
}

start_test "mesh confirm takes yes"
assert_equal "0" "$(_confirm_status 'y
')"

start_test "mesh confirm takes a bare Enter as yes"
assert_equal "0" "$(_confirm_status '
')"

start_test "mesh confirm takes no"
assert_equal "1" "$(_confirm_status 'n
')"

# End of input is a decline, not a crash. The `gets reply` command form left
# `reply` unchanged at end of input -- unbound, here -- so `confirm x` with
# nothing to read died on "reply: unbound variable" and reported failure for
# the wrong reason. `gets()` yields false there, which the match reads as no.
# rc.elv answers false at end of input too.
start_test "mesh confirm declines at end of input"
assert_equal "1" "$(_confirm_status '')"

start_test "mesh confirm says nothing about an unbound variable at end of input"
printf '' | HOME="$_fakehome" TERM=dumb NO_COLOR=1 run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    confirm are you sure
" >/dev/null 2>"$_testdir/confirm-eof.err"
assert_not_contains "unbound variable" "$(cat "$_testdir/confirm-eof.err")"

# The prompt itself, asserted once, on stderr. mesh used to swallow a
# function's earlier stdout when its last statement was a `match` and it was
# called for its value, so the prompt never appeared at all; mikelward/mesh
# 77dca06 fixed that, which is what made the stream worth choosing.
_confirm_streams() {
    printf 'y\n' | HOME="$_fakehome" TERM=dumb NO_COLOR=1 run_with_timeout 15 mesh -c "
        source $_env_mesh
        source $_rc_mesh
        confirm are you sure
    " 2>"$_testdir/confirm.err" >"$_testdir/confirm.out"
}

start_test "mesh confirm prompts with the joined question"
_confirm_streams
assert_contains "are you sure? [Y/n]" "$(cat "$_testdir/confirm.err")"

# The point of the split: a caller reading stdout gets nothing but what it
# asked for, so `confirm x > file` still asks rather than writing the question
# into the file.
start_test "mesh confirm keeps the prompt off stdout"
_confirm_streams
assert_equal "" "$(cat "$_testdir/confirm.out")"

###############
# TEST: PATH helpers

start_test "mesh prepend-path puts an existing dir first"
result="$(_mesh_run '
    prepend-path /etc
    puts $env.PATH[0]
')"
assert_equal "/etc" "$result"

start_test "mesh prepend-path ignores a dir that does not exist"
result="$(_mesh_run '
    before = $env.PATH[0]
    prepend-path /no-such-dir-here
    if $env.PATH[0] == $before { puts unchanged }
')"
assert_equal "unchanged" "$result"

start_test "mesh append-path puts an existing dir last"
result="$(_mesh_run '
    append-path /etc
    puts $env.PATH:last
')"
assert_equal "/etc" "$result"

start_test "mesh prepend-path does not duplicate an entry"
result="$(_mesh_run '
    prepend-path /etc
    prepend-path /etc
    count = 0
    for d in $env.PATH {
        if $d == "/etc" { count = $count + 1 }
    }
    puts $count
')"
assert_equal "1" "$result"

# The move-to-front half of `prepend-path`, which `:prepend(...):dedup` now
# does in one statement: an entry already further down comes to the front
# rather than being left where it was or landing twice.
start_test "mesh prepend-path moves an entry already on PATH to the front"
result="$(_mesh_run '
    append-path /etc
    prepend-path /etc
    count = 0
    for d in $env.PATH {
        if $d == "/etc" { count = $count + 1 }
    }
    puts $env.PATH[0] $count
')"
assert_equal "/etc 1" "$result"

# The move-to-end half of `append-path`, the mirror of the test above.
# `without(...):append(...)` is one chain rather than a delete statement and an
# append, and `:dedup` cannot stand in for it here -- it keeps the *first*
# occurrence, so an entry already on the front would win over the copy being
# appended and the dir would never reach the end.
start_test "mesh append-path moves an entry already on PATH to the end"
result="$(_mesh_run '
    prepend-path /etc
    append-path /etc
    count = 0
    for d in $env.PATH {
        if $d == "/etc" { count = $count + 1 }
    }
    puts $env.PATH:last $count
')"
assert_equal "/etc 1" "$result"

# `:dedup` collapses the duplicates the inherited PATH arrived with, not just
# the one being added -- what keeps a `rerc` from growing the list. config.nu's
# `uniq` does the same; bash, fish and Elvish have no one-statement equivalent
# and still delete only the entry being moved.
start_test "mesh prepend-path collapses a duplicate already on the inherited PATH"
result="$(_mesh_run '
    $env.PATH = ["/tmp" "/etc" "/tmp"]
    prepend-path /usr
    puts $env.PATH:join(",")
')"
assert_equal "/usr,/tmp,/etc" "$result"

start_test "mesh delete-path removes an entry"
result="$(_mesh_run '
    prepend-path /etc
    delete-path /etc
    if ("/etc" in $env.PATH) { puts present } else { puts absent }
')"
assert_equal "absent" "$result"

start_test "mesh inpath reports membership"
result="$(_mesh_run '
    prepend-path /etc
    puts inpath("/etc") inpath("/no-such-dir-here")
')"
assert_equal "true false" "$result"

start_test "mesh add-path with no position appends only when missing"
result="$(_mesh_run '
    add-path /etc
    first = $env.PATH:last
    add-path /etc
    puts $first $env.PATH:last
')"
assert_equal "/etc /etc" "$result"

###############
# TEST: command-lookup helpers

start_test "mesh have-command finds a real command and misses a fake one"
result="$(_mesh_run_config '' '
    if have-command("sh") { puts found } else { puts missing }
    if have-command("no-such-command-xyz") { puts found } else { puts missing }
')"
assert_equal "found
missing" "$result"

start_test "mesh have-command ignores functions, unlike is-runnable"
result="$(_mesh_run_config '
    func only-a-function() { puts hi }
' '
    if have-command("only-a-function") { puts found } else { puts missing }
    if is-runnable("only-a-function") { puts found } else { puts missing }
')"
assert_equal "missing
found" "$result"

# These answer with the lookup's own status rather than a bool, so branching on
# them is unchanged but printing one shows `0` / `1`. Pinned because it is the
# visible half of the contract: a caller who puts the answer somewhere a person
# reads needs to know it is a status, and 0-is-yes reads backwards if you were
# expecting a bool.
start_test "mesh have-command answers with a status, not a bool"
result="$(_mesh_run_config '' '
    puts have-command("sh") have-command("no-such-command-xyz")
')"
assert_equal "0 1" "$result"

start_test "mesh path prints the full path to a command"
result="$(_mesh_run_config '' 'puts path("sh")')"
assert_contains "/sh" "$result"

###############
# TEST: shellenv-entry, the KEY=VALUE reader brew/fnm output goes through

start_test "mesh shellenv-entry splits an export line"
result="$(_mesh_run '
    e = shellenv-entry("export FNM_DIR=\"/home/user/.fnm\";")
    puts ...$e
')"
assert_equal "FNM_DIR /home/user/.fnm" "$result"

start_test "mesh shellenv-entry ignores comments and blank lines"
result="$(_mesh_run '
    puts shellenv-entry(""):len shellenv-entry("# a comment"):len shellenv-entry("not an assignment"):len
')"
assert_equal "0 0 0" "$result"

start_test "mesh shellenv-entry takes the quoted run, not everything up to the last quote"
# `fnm env --shell bash` writes PATH as `"<shim>":$PATH` -- the closing quote
# is in the middle -- so trimming quotes off both ends left a stray one behind.
result="$(_mesh_run '
    e = shellenv-entry("export PATH=\"/opt/fnm/bin\":\$PATH")
    puts ...$e
')"
assert_equal "PATH /opt/fnm/bin" "$result"

start_test "mesh shellenv-entry handles a single-quoted value"
result="$(_mesh_run "
    e = shellenv-entry(\"export FNM_ARCH='x64'\")
    puts ...\$e
")"
assert_equal "FNM_ARCH x64" "$result"

start_test "mesh shellenv-entry leaves an unquoted value alone"
result="$(_mesh_run '
    e = shellenv-entry("export FNM_LOGLEVEL=info")
    puts ...$e
')"
assert_equal "FNM_LOGLEVEL info" "$result"

start_test "mesh unquoted-head passes through an unquoted word"
result="$(_mesh_run 'puts unquoted-head("plain") unquoted-head("\"quoted\":tail")')"
assert_equal "plain quoted" "$result"

###############
# TEST: setup-fnm does not accumulate shim directories across reloads

# A fake `fnm` that mints a new multishell directory on every call, the way the
# real one does -- the shim path is per-invocation, so the value setup-fnm is
# about to overwrite is the only handle on the entry already sitting in PATH.
_fake_fnm_bin="$_testdir/fakefnmbin"
mkdir -p "$_fake_fnm_bin"
cat > "$_fake_fnm_bin/fnm" <<EOF
#!/bin/sh
n=\$(cat "$_testdir/fnm-calls" 2>/dev/null || echo 0)
n=\$((n + 1))
echo "\$n" > "$_testdir/fnm-calls"
echo "export FNM_MULTISHELL_PATH=\"$_testdir/fnm-shell-\$n\";"
echo "export FNM_DIR=\"$_testdir/fnm\";"
echo "export PATH=\"$_testdir/fnm-shell-\$n/bin\":\\\$PATH"
EOF
chmod +x "$_fake_fnm_bin/fnm"

# `rerc` re-reads env.mesh, so setup-fnm runs again in a live session. The
# cleanup below the loop deletes the shim named by FNM_MULTISHELL_PATH, so
# overwriting that variable first left every earlier shim on PATH.
# A failing `fnm env` yields no assignments, and the cleanup below would then
# re-prepend the *previous* shim -- deliberately putting a stale node back at
# the front of PATH on every reload. Report and leave PATH alone instead.
start_test "mesh setup-fnm reports a failing fnm env and leaves PATH alone"
_failing_fnm_bin="$_testdir/failingfnmbin"
mkdir -p "$_failing_fnm_bin"
printf '#!/bin/sh\nexit 3\n' > "$_failing_fnm_bin/fnm"
chmod +x "$_failing_fnm_bin/fnm"
mkdir -p "$_testdir/stale-shim/bin"
result="$(PATH="$_failing_fnm_bin:$PATH" FNM_MULTISHELL_PATH="$_testdir/stale-shim" \
    HOME="$_fakehome" run_with_timeout 15 mesh -c "
    source $_env_mesh
    puts \"first=\$env.PATH[0]\"
" </dev/null 2>&1)"
assert_contains "could not read the node environment" "$result"
assert_not_contains "first=$_testdir/stale-shim/bin" "$result"

start_test "mesh setup-fnm leaves one shim on PATH across reloads"
rm -f "$_testdir/fnm-calls"
result="$(PATH="$_fake_fnm_bin:$PATH" _mesh_run_config '' '
    setup-fnm
    setup-fnm
    setup-fnm
    puts $env.PATH:join(",")
')"
# env.mesh runs setup-fnm once as it is sourced, so the three above are calls
# two through four and only the fourth shim should have survived.
assert_equal "1" "$(printf '%s\n' "$result" | tr ',' '\n' | grep -c 'fnm-shell-')"
assert_contains "$_testdir/fnm-shell-4/bin" "$result"

# Every name `fnm env` publishes is applied through `$env[$name]`, so one this
# file has never heard of arrives on its own -- which is what shrc and fish get
# from eval'ing the snippet, and what the per-name match here used to trade
# away.
start_test "mesh setup-fnm applies a variable it does not know by name"
_new_fnm_bin="$_testdir/newvarfnmbin"
mkdir -p "$_new_fnm_bin"
cat > "$_new_fnm_bin/fnm" <<EOF
#!/bin/sh
echo "export FNM_DIR=\"$_testdir/fnm\";"
echo "export FNM_SOMETHING_NEW=\"whatever\";"
EOF
chmod +x "$_new_fnm_bin/fnm"
result="$(PATH="$_new_fnm_bin:$PATH" _mesh_run_config '' '
    setup-fnm
    puts $env.FNM_SOMETHING_NEW
' 2>&1)"
assert_contains "whatever" "$result"

# Nothing expands a value here, so one still naming another variable would be
# exported with the `$` in it. Say which one and leave it unset -- a path a
# child cannot use is worse than a missing one.
start_test "mesh setup-fnm reports a value it cannot expand and leaves it unset"
_ref_fnm_bin="$_testdir/reffnmbin"
mkdir -p "$_ref_fnm_bin"
cat > "$_ref_fnm_bin/fnm" <<'EOF'
#!/bin/sh
echo 'export FNM_LATER_DIR="$HOME/elsewhere";'
EOF
chmod +x "$_ref_fnm_bin/fnm"
result="$(PATH="$_ref_fnm_bin:$PATH" _mesh_run_config '' '
    setup-fnm
    later = $env:get(FNM_LATER_DIR, "unset")
    puts "later=$later"
' 2>&1)"
assert_contains "FNM_LATER_DIR refers to another variable" "$result"
assert_contains "later=unset" "$result"

# `\$` is bash's *literal* dollar inside double quotes, which is how a home
# directory with a `$` in its name arrives. Rejecting it as a reference would
# drop FNM_MULTISHELL_PATH and with it the node shim.
_dollar_fnm_bin="$_testdir/dollarfnmbin"
mkdir -p "$_dollar_fnm_bin"
cat > "$_dollar_fnm_bin/fnm" <<'EOF'
#!/bin/sh
echo 'export FNM_DIR="/home/user/we\$rd/fnm";'
EOF
chmod +x "$_dollar_fnm_bin/fnm"

start_test "mesh setup-fnm keeps an escaped dollar as a literal"
result="$(PATH="$_dollar_fnm_bin:$PATH" _mesh_run_config '' '
    setup-fnm
    dir = $env:get(FNM_DIR, "unset")
    puts "dir=$dir"
' 2>&1)"
assert_contains 'dir=/home/user/we$rd/fnm' "$result"
assert_not_contains "refers to another variable" "$result"

###############
# TEST: setup-brew derives what `brew shellenv` would export

# A fake brew tree: $prefix/bin/brew, plus $prefix/Homebrew when the layout
# under test is the Linuxbrew / Intel-macOS one.
_make_fake_brew() {
    local _prefix="$1"
    local _with_repo="$2"
    rm -rf "$_prefix"
    mkdir -p "$_prefix/bin" "$_prefix/sbin" "$_prefix/share/man" "$_prefix/share/info"
    # Cellar is what tells a real prefix from a shim's grandparent, and Homebrew
    # creates it at install time, so a realistic tree has one. The stub answers
    # `--prefix` with a wrong path on purpose: any test that still reads the
    # derived prefix proves brew was never asked.
    mkdir -p "$_prefix/Cellar"
    printf '#!/bin/sh\ntest "$1" = --prefix && echo /wrong/prefix\nexit 0\n' > "$_prefix/bin/brew"
    chmod +x "$_prefix/bin/brew"
    test "$_with_repo" = "repo" && mkdir -p "$_prefix/Homebrew"
    return 0
}

# `rerc` re-reads env.mesh, so setup-brew runs more than once per session: a
# plain prepend would put the same brew dir on the front again each time and
# grow MANPATH/INFOPATH without bound, along with an extra trailing empty.
start_test "mesh setup-brew is idempotent across reloads"
_make_fake_brew "$_testdir/brew-idem" norepo
result="$(_mesh_run "
    \$env.BREW = \"$_testdir/brew-idem/bin/brew\"
    setup-brew
    setup-brew
    setup-brew
    puts \$env.MANPATH:join(\",\")
    puts \$env.INFOPATH:join(\",\")
")"
assert_equal "$_testdir/brew-idem/share/man,
$_testdir/brew-idem/share/info," "$result"

start_test "mesh setup-brew reload keeps an inherited MANPATH entry once"
result="$(HOME="$_fakehome" MANPATH=/usr/share/man run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    \$env.BREW = \"$_testdir/brew-idem/bin/brew\"
    setup-brew
    setup-brew
    puts \$env.MANPATH:join(\",\")
" </dev/null)"
assert_equal "$_testdir/brew-idem/share/man,/usr/share/man," "$result"

# An empty component in a man/info path means "and the system defaults here",
# so deduplicating must not take it with the Homebrew entry.
start_test "mesh setup-brew keeps an inherited INFOPATH sentinel"
result="$(HOME="$_fakehome" INFOPATH="/custom:" run_with_timeout 15 mesh -c "
    source $_env_mesh
    \$env.BREW = \"$_testdir/brew-idem/bin/brew\"
    setup-brew
    setup-brew
    puts \$env.INFOPATH:join(\",\")
" </dev/null)"
assert_equal "$_testdir/brew-idem/share/info,/custom," "$result"

start_test "mesh setup-brew keeps an interior MANPATH empty"
result="$(HOME="$_fakehome" MANPATH="/a::/b" run_with_timeout 15 mesh -c "
    source $_env_mesh
    \$env.BREW = \"$_testdir/brew-idem/bin/brew\"
    setup-brew
    setup-brew
    puts \$env.MANPATH:join(\",\")
" </dev/null)"
assert_equal "$_testdir/brew-idem/share/man,/a,,/b," "$result"

start_test "mesh setup-brew exports the prefix and cellar"
_make_fake_brew "$_testdir/brew-arm" norepo
result="$(_mesh_run "
    \$env.BREW = \"$_testdir/brew-arm/bin/brew\"
    setup-brew
    puts \$env.HOMEBREW_PREFIX \$env.HOMEBREW_CELLAR
")"
assert_equal "$_testdir/brew-arm $_testdir/brew-arm/Cellar" "$result"

# The grandparent of `bin/brew` is the prefix for every real layout, and the
# stub would answer a wrong one, so reading the derived value proves brew was
# not forked on the ordinary path -- where shrc pays a `brew shellenv` every
# time.
start_test "mesh setup-brew does not ask brew when the tree looks real"
result="$(_mesh_run "
    \$env.BREW = \"$_testdir/brew-arm/bin/brew\"
    setup-brew
    puts \$env.HOMEBREW_PREFIX
")"
assert_equal "$_testdir/brew-arm" "$result"

# Reached through a shim outside its own tree, the grandparent is whatever
# holds the shim -- \$HOME, typically -- so brew is asked for the real answer.
start_test "mesh setup-brew asks brew when reached through a shim"
mkdir -p "$_testdir/shimbin"
printf '#!/bin/sh\ntest "$1" = --prefix && echo %s\nexit 0\n' "$_testdir/brew-arm" \
    > "$_testdir/shimbin/brew"
chmod +x "$_testdir/shimbin/brew"
result="$(_mesh_run "
    \$env.BREW = \"$_testdir/shimbin/brew\"
    setup-brew
    puts \$env.HOMEBREW_PREFIX \$env.HOMEBREW_CELLAR
")"
assert_equal "$_testdir/brew-arm $_testdir/brew-arm/Cellar" "$result"

# The derived prefix is already known wrong by the time brew is asked, so a
# failed query leaves nothing usable to fall back to -- exporting the shim's
# grandparent would put an unrelated tree's bin/sbin on PATH.
start_test "mesh setup-brew gives up when brew cannot name its prefix"
mkdir -p "$_testdir/badshimbin"
printf '#!/bin/sh\nexit 1\n' > "$_testdir/badshimbin/brew"
chmod +x "$_testdir/badshimbin/brew"
result="$(_mesh_run "
    \$env.BREW = \"$_testdir/badshimbin/brew\"
    setup-brew
    p = \$env:get(HOMEBREW_PREFIX, \"unset\")
    puts \"prefix=\$p\"
" 2>&1)"
assert_contains "cannot determine the install prefix" "$result"
assert_contains "prefix=unset" "$result"

start_test "mesh setup-brew leaves PATH alone when brew cannot name its prefix"
result="$(_mesh_run "
    before = \$env.PATH:join(\",\")
    \$env.BREW = \"$_testdir/badshimbin/brew\"
    setup-brew
    if \$env.PATH:join(\",\") == \$before { puts unchanged } else { puts changed }
" 2>/dev/null)"
assert_equal "unchanged" "$result"

# `bin/brew` points into $prefix/Homebrew on Linuxbrew and Intel macOS, so
# resolving the symlink would name the *repo* as the prefix. It is deliberately
# not resolved.
start_test "mesh setup-brew does not follow bin/brew into the Homebrew repo"
_make_fake_brew "$_testdir/brew-symlink" repo
mkdir -p "$_testdir/brew-symlink/Homebrew/bin"
mv "$_testdir/brew-symlink/bin/brew" "$_testdir/brew-symlink/Homebrew/bin/brew"
ln -s "$_testdir/brew-symlink/Homebrew/bin/brew" "$_testdir/brew-symlink/bin/brew"
result="$(_mesh_run "
    \$env.BREW = \"$_testdir/brew-symlink/bin/brew\"
    setup-brew
    puts \$env.HOMEBREW_PREFIX
")"
assert_equal "$_testdir/brew-symlink" "$result"

start_test "mesh setup-brew points HOMEBREW_REPOSITORY at the prefix on Apple silicon"
result="$(_mesh_run "
    \$env.BREW = \"$_testdir/brew-arm/bin/brew\"
    setup-brew
    puts \$env.HOMEBREW_REPOSITORY
")"
assert_equal "$_testdir/brew-arm" "$result"

start_test "mesh setup-brew points HOMEBREW_REPOSITORY at \$prefix/Homebrew when it exists"
_make_fake_brew "$_testdir/brew-linux" repo
result="$(_mesh_run "
    \$env.BREW = \"$_testdir/brew-linux/bin/brew\"
    setup-brew
    puts \$env.HOMEBREW_REPOSITORY
")"
assert_equal "$_testdir/brew-linux/Homebrew" "$result"

start_test "mesh setup-brew puts brew's bin ahead of its sbin on PATH"
result="$(_mesh_run "
    \$env.BREW = \"$_testdir/brew-arm/bin/brew\"
    setup-brew
    puts \$env.PATH[0] \$env.PATH[1]
")"
assert_equal "$_testdir/brew-arm/bin $_testdir/brew-arm/sbin" "$result"

start_test "mesh setup-brew sets MANPATH with an unset MANPATH"
result="$(HOME="$_fakehome" run_with_timeout 15 env -u MANPATH mesh -c "
    source $_env_mesh
    source $_rc_mesh
    \$env.BREW = \"$_testdir/brew-arm/bin/brew\"
    setup-brew
    puts \$env.MANPATH:join(\",\")
" </dev/null)"
assert_equal "$_testdir/brew-arm/share/man," "$result"

start_test "mesh setup-brew keeps an existing MANPATH and its trailing component"
result="$(HOME="$_fakehome" MANPATH=/usr/share/man run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    \$env.BREW = \"$_testdir/brew-arm/bin/brew\"
    setup-brew
    puts \$env.MANPATH:join(\",\")
" </dev/null)"
assert_equal "$_testdir/brew-arm/share/man,/usr/share/man," "$result"

start_test "mesh setup-brew sets INFOPATH with an unset INFOPATH"
result="$(HOME="$_fakehome" run_with_timeout 15 env -u INFOPATH mesh -c "
    source $_env_mesh
    source $_rc_mesh
    \$env.BREW = \"$_testdir/brew-arm/bin/brew\"
    setup-brew
    puts \$env.INFOPATH:join(\",\")
" </dev/null)"
assert_equal "$_testdir/brew-arm/share/info," "$result"

start_test "mesh setup-brew keeps an existing INFOPATH"
result="$(HOME="$_fakehome" INFOPATH=/usr/share/info run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    \$env.BREW = \"$_testdir/brew-arm/bin/brew\"
    setup-brew
    puts \$env.INFOPATH:join(\",\")
" </dev/null)"
assert_equal "$_testdir/brew-arm/share/info,/usr/share/info" "$result"

start_test "mesh env.mesh completes its setup with brew installed and no MANPATH"
result="$(HOME="$_fakehome" run_with_timeout 15 env -u MANPATH -u INFOPATH \
    BREW="$_testdir/brew-arm/bin/brew" mesh -c "
    source $_env_mesh
    puts \$env.GREP_COLORS
" 2>&1 </dev/null)"
assert_equal "mt=4" "$result"

###############
# TEST: string and path helpers

start_test "mesh starts-with tests a computed prefix"
result="$(_mesh_run 'puts starts-with("abcdef", "abc") starts-with("abcdef", "xyz") starts-with("abc", "")')"
assert_equal "true false false" "$result"

# `without` is a `:filter` over a lambda that names `$entry` in its `with (…)`
# list, and mesh capture is explicit: a lambda that failed to name it would see
# an unbound name rather than quietly keeping or dropping everything. Every
# occurrence goes, not just the first -- that is what makes a reload idempotent
# however many copies the inherited list arrived with.
start_test "mesh without drops every occurrence"
result="$(_mesh_run '
    kept = without(["/a" "/b" "/a" "/c" "/a"], "/a")
    puts $kept:join(",")
')"
assert_equal "/b,/c" "$result"

# An empty component in a man/info path names the system defaults at that
# position, so it is data rather than padding -- `without` keeps it, and only
# `drop-trailing-empty` takes the one at the end.
# A `--`-leading element is *data*, and `:filter` never reads it as a flag: a
# callable applied per element binds with flag scanning off, so the `wrapper`
# that `without` itself needs at its written call site has no counterpart to
# want on the lambda inside it. PATH is the live case -- `append-path /sbin`
# runs at startup and goes through `without`, so a relative `--tools` component
# on an inherited PATH would break every shell if this were not so.
start_test "mesh without keeps a flag-shaped element"
result="$(_mesh_run '
    kept = without(["--tools" "/usr/bin" "--sleep=0" "-n"], "/usr/bin")
    puts $kept:join(",")
')"
assert_equal "--tools,--sleep=0,-n" "$result"

start_test "mesh without keeps empty elements"
result="$(_mesh_run '
    kept = without(["" "/a" "" "/b" ""], "/b")
    puts $kept:len $kept:join(",")
')"
assert_equal "4 ,/a,," "$result"

start_test "mesh tilde-pwd shortens \$HOME"
result="$(_mesh_run '
    cd $env.HOME
    puts tilde-pwd()
')"
assert_equal "~" "$result"

start_test "mesh tilde-pwd shortens a directory under \$HOME"
mkdir -p "$_fakehome/sub"
result="$(_mesh_run '
    cd "$env.HOME/sub"
    puts tilde-pwd()
')"
assert_equal "~/sub" "$result"

start_test "mesh tilde-pwd leaves a directory outside \$HOME alone"
result="$(_mesh_run '
    cd /etc
    puts tilde-pwd()
')"
assert_equal "/etc" "$result"

# `:tilde` ignores a $HOME of `/`, so the exact-home test in front of it is
# what keeps the root directory rendering as `~` -- which is what shrc, fish
# and nushell each answer from an exact-home branch of their own.
start_test "mesh tilde-pwd shortens a \$HOME of /"
result="$(HOME=/ TERM=dumb NO_COLOR=1 SHPOOL_SESSION_NAME= TMUX= SSH_CONNECTION= \
    run_with_timeout 15 mesh -c "
        source $_env_mesh
        source $_rc_mesh
        cd /
        puts tilde-pwd()
    " </dev/null)"
assert_equal "~" "$result"

# A sibling whose name merely starts with $HOME's is not under it. Both the
# old prefix compare and `:tilde` match whole components; this pins that across
# the handover.
start_test "mesh tilde-pwd leaves a sibling of \$HOME alone"
mkdir -p "${_fakehome}extra"
result="$(_mesh_run "
    cd ${_fakehome}extra
    puts tilde-pwd()
")"
assert_equal "${_fakehome}extra" "$result"

start_test "mesh short-hostname drops the domain and the user prefix"
result="$(_mesh_run '
    $env.HOSTNAME = "someuser-host1.example.com"
    $env.USERNAME = "someuser"
    puts short-hostname()
')"
assert_equal "host1" "$result"

start_test "mesh short-hostname is empty with no hostname"
result="$(_mesh_run '
    $env.HOSTNAME = ""
    puts "[$(puts short-hostname())]"
')"
assert_equal "[]" "$result"

###############
# TEST: mcd does not cd after a failed mkdir

# assert_contains, not assert_equal: `cd` echoes the resolved directory when it
# came from CDPATH, which bash does too (POSIX requires it for a non-`.` entry,
# and bash prints for `.` as well). So the output is the echo *and* the pwd.
start_test "mesh mcd makes the directory and moves into it"
result="$(_mesh_run "
    cd $_testdir
    mcd made-by-mcd
    puts \$(pwd)
")"
assert_contains "$_testdir/made-by-mcd" "$result"

start_test "mesh mcd says so when the directory already exists"
result="$(_mesh_run "
    cd $_testdir
    mcd made-by-mcd
")"
assert_equal "made-by-mcd already exists" "$result"

# A plain file standing where a parent directory should be, rather than a
# read-only directory: permission bits don't stop root, and these tests run as
# root in CI. mkdir fails either way, and the cd must not run after it --
# otherwise mkdir's real diagnostic is followed by a second one for the same
# cause, which is what the `&&` is there to prevent.
start_test "mesh mcd does not cd when mkdir fails"
touch "$_testdir/not-a-dir"
result="$(_mesh_run "mcd $_testdir/not-a-dir/nope" 2>&1)"
assert_contains "mkdir: cannot create directory" "$result"
assert_not_contains "mesh: cd:" "$result"

start_test "mesh find-up finds a file in a parent directory"
mkdir -p "$_testdir/up/a/b"
touch "$_testdir/up/marker"
result="$(_mesh_run "
    cd $_testdir/up/a/b
    puts find-up(\"marker\")
")"
assert_equal "$_testdir/up/marker" "$result"

# The walk starts at the working directory rather than its parent, which is
# where shrc:1011 and config.fish:557 start too. `:ancestors` includes the path
# it was given, so this is the first element of the list the loop walks.
start_test "mesh find-up finds a file in the working directory"
result="$(_mesh_run "
    cd $_testdir/up
    puts find-up(\"marker\")
")"
assert_equal "$_testdir/up/marker" "$result"

# The other end of the walk. `/` is the last ancestor rather than the stop
# condition, so a search that reaches it still looks there; the miss is the
# list running out, not a `$dir == "/"` test the loop no longer has.
start_test "mesh find-up is empty when nothing matches"
result="$(_mesh_run '
    cd /
    puts "[$(puts find-up("no-such-marker-xyz"))]"
')"
assert_equal "[]" "$result"

# shrc and fish signal the miss with exit status 1. A mesh value function has
# no status to carry that in -- in command position it prints nothing and
# captures nothing -- so the miss is signalled by an empty return. mesh has no
# truthy values, so the caller asks with an explicit `!= ""`; that is the
# contract, so it is asserted rather than left to happen to work.
start_test "mesh find-up answers empty on a miss and a path on a hit"
result="$(_mesh_run "
    cd $_testdir/up/a/b
    if find-up(\"no-such-marker-xyz\") != \"\" { puts miss-found } else { puts miss-empty }
    if find-up(\"marker\") != \"\" { puts hit-found } else { puts hit-empty }
")"
assert_equal "miss-empty
hit-found" "$result"

start_test "mesh find-test-file names the sibling test file"
touch "$_testdir/thing.sh" "$_testdir/thing_test.sh"
result="$(_mesh_run "puts find-test-file(\"$_testdir/thing.sh\")")"
assert_equal "$_testdir/thing_test.sh" "$result"

start_test "mesh find-test-file is empty when there is no test file"
touch "$_testdir/lonely.sh"
result="$(_mesh_run "puts \"[\$(puts find-test-file(\\\"$_testdir/lonely.sh\\\"))]\"")"
assert_equal "[]" "$result"

###############
# TEST: shift-options moves leading options past the target argument

start_test "mesh shift-options moves leading options past target"
result="$(_mesh_run '
    func fake-ssh(...args) { puts ...$args }
    shift-options fake-ssh target -t -v hostname
')"
assert_equal "-t -v target hostname" "$result"

start_test "mesh shift-options stops scanning at the first operand"
result="$(_mesh_run '
    func fake-ssh(...args) { puts ...$args }
    shift-options fake-ssh target uptime -l
')"
assert_equal "target uptime -l" "$result"

# `-5` arrives as the integer -5, which `~` refuses as a left operand -- the
# whole call failed rather than the option being collected.
start_test "mesh shift-options classifies a bare numeric short option"
result="$(_mesh_run '
    func fake-head(...args) { puts ...$args }
    shift-options fake-head file -5
' 2>&1)"
assert_equal "-5 file" "$result"

###############
# TEST: tz2tz stops when the source conversion fails

_fake_date_bin="$_testdir/fakedatebin"
mkdir -p "$_fake_date_bin"
cat > "$_fake_date_bin/date" <<'EOF'
#!/bin/sh
# Stand in for GNU date, which macOS doesn't have. Reject the one spec the
# tests pass as unparsable; otherwise answer a fixed epoch for the `+%s` leg
# and echo the timezone for the other, so both legs are visible.
case "$2" in
    unparsable) echo "date: invalid date 'unparsable'" >&2; exit 1 ;;
esac
case "$3" in
    +%s) echo 1577836800 ;;
    *)   echo "converted $2 in $TZ" ;;
esac
EOF
chmod +x "$_fake_date_bin/date"

start_test "mesh tz2tz does not run the target leg after a failed source leg"
result="$(PATH="$_fake_date_bin:$PATH" _mesh_run 'tz2tz UTC UTC unparsable' 2>&1)"
assert_equal "date: invalid date 'unparsable'" "$result"

start_test "mesh tz2tz reports the failed source leg to the caller"
PATH="$_fake_date_bin:$PATH" _mesh_run 'tz2tz UTC UTC unparsable
exit $sh.status' > /dev/null 2>&1
assert_equal "1" "$?"

start_test "mesh tz2tz converts through both timezones when the spec parses"
result="$(PATH="$_fake_date_bin:$PATH" _mesh_run 'tz2tz UTC EST 2020-01-01 00:00' 2>&1)"
assert_equal "converted @1577836800 in EST" "$result"

###############
# TEST: daemon restarts a background program detached

_fake_daemon_bin="$_testdir/fakedaemonbin"
mkdir -p "$_fake_daemon_bin"
printf '#!/bin/sh\necho "pkill: $*"\n' > "$_fake_daemon_bin/pkill"
printf '#!/bin/sh\necho "setsid: $*"\n' > "$_fake_daemon_bin/setsid"
chmod +x "$_fake_daemon_bin/pkill" "$_fake_daemon_bin/setsid"

start_test "mesh daemon kills the old copy and starts a detached one"
result="$(PATH="$_fake_daemon_bin:$PATH" _mesh_run 'daemon xbindkeys')"
assert_equal "pkill: xbindkeys
setsid: xbindkeys" "$result"

# The `&` runs inside a `fork`, so the parent keeps no job -- otherwise
# safe-exit would refuse to leave a shell that had ever started a daemon.
start_test "mesh daemon leaves no job behind in the parent"
result="$(PATH="$_fake_daemon_bin:$PATH" _mesh_run 'daemon xbindkeys > /dev/null
puts "jobs=$sh.jobs:len"')"
assert_equal "jobs=0" "$result"

start_test "mesh bindkeys passes its arguments through to xbindkeys"
result="$(PATH="$_fake_daemon_bin:$PATH" _mesh_run 'bindkeys --poll-rc')"
assert_equal "pkill: xbindkeys
setsid: xbindkeys --poll-rc" "$result"

###############
# TEST: session backend preference

start_test "mesh session-backend prefers shpool when both are available"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
' 'puts session-backend()')"
assert_equal "shpool" "$result"

start_test "mesh SESSION_BACKEND=tmux flips the preference"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
' '
    $env.SESSION_BACKEND = "tmux"
    puts session-backend()
')"
assert_equal "tmux" "$result"

start_test "mesh WANT_SHPOOL=0 falls back to tmux"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
' '
    $env.WANT_SHPOOL = "0"
    puts session-backend()
')"
assert_equal "tmux" "$result"

start_test "mesh SESSION_BACKEND=tmux with WANT_TMUX=0 falls back to shpool"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
' '
    $env.SESSION_BACKEND = "tmux"
    $env.WANT_TMUX = "0"
    puts session-backend()
')"
assert_equal "shpool" "$result"

start_test "mesh session-backend is empty when neither backend is installed"
result="$(_mesh_run 'puts "[$(puts session-backend())]"')"
assert_equal "[]" "$result"

start_test "mesh session-backend needs the autoshpool helper, not just shpool"
result="$(_mesh_run_config '
    status func have-command(name) {
        match $name {
            shpool => { return true }
            _ => { return false }
        }
    }
' 'puts "[$(puts session-backend())]"')"
assert_equal "[]" "$result"

###############
# TEST: the session launchers only replace this shell when they succeed

start_test "mesh maybe-start-session-and-exit keeps the shell when autoshpool fails"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
    bool func stdin-is-tty() { return true }
    bool func inside-project() { return true }
    func autoshpool(...args) {
        puts "autoshpool ran"
        fail
    }
' '
    maybe-start-session-and-exit
    puts "still here"
')"
assert_contains "autoshpool ran" "$result"
assert_contains "still here" "$result"

start_test "mesh maybe-start-session-and-exit keeps the shell when autotmux fails"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
    bool func stdin-is-tty() { return true }
    bool func inside-project() { return true }
    func autotmux(...args) { fail }
' '
    $env.SESSION_BACKEND = "tmux"
    maybe-start-session-and-exit
    puts "still here"
')"
assert_equal "still here" "$result"

start_test "mesh maybe-start-session-and-exit exits when autoshpool succeeds"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
    bool func stdin-is-tty() { return true }
    bool func inside-project() { return true }
    func autoshpool(...args) { return true }
' '
    maybe-start-session-and-exit
    puts "should not print"
')"
assert_equal "" "$result"

start_test "mesh switchshpool keeps the shell when the switch fails"
result="$(_mesh_run_config '
    func autoshpool(...args) { fail }
' '
    switchshpool other
    puts "still here"
')"
assert_equal "still here" "$result"

start_test "mesh switchshpool exits when the switch succeeds"
result="$(_mesh_run_config '
    func autoshpool(...args) { return true }
' '
    switchshpool other
    puts "should not print"
')"
assert_equal "" "$result"

###############
# TEST: want-shpool / want-tmux gating

start_test "mesh want-shpool is false without a tty"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
    bool func stdin-is-tty() { return false }
    bool func inside-project() { return true }
' 'puts want-shpool()')"
assert_equal "false" "$result"

start_test "mesh want-shpool is true on a tty inside a project"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
    bool func stdin-is-tty() { return true }
    bool func inside-project() { return true }
' 'puts want-shpool()')"
assert_equal "true" "$result"

start_test "mesh want-shpool is false when already in shpool"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
    bool func stdin-is-tty() { return true }
    bool func inside-project() { return true }
' '
    $env.SHPOOL_SESSION_NAME = "already"
    puts want-shpool()
')"
assert_equal "false" "$result"

start_test "mesh want-shpool is true when connected remotely, outside a project"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
    bool func stdin-is-tty() { return true }
    bool func inside-project() { return false }
' '
    $env.SSH_CONNECTION = "10.0.0.1 1 10.0.0.2 22"
    puts want-shpool()
')"
assert_equal "true" "$result"

start_test "mesh WANT_SHPOOL=0 turns want-shpool off"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
    bool func stdin-is-tty() { return true }
    bool func inside-project() { return true }
' '
    $env.WANT_SHPOOL = "0"
    puts want-shpool()
')"
assert_equal "false" "$result"

start_test "mesh want-tmux is false inside tmux"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
    bool func stdin-is-tty() { return true }
    bool func inside-project() { return true }
' '
    $env.TMUX = "/tmp/tmux-0/default,1,0"
    puts want-tmux()
')"
assert_equal "false" "$result"

###############
# TEST: session-shell prints the explicitly started shell for autoshpool's
# session creation, gated on SHLVL showing a parent shell; the handoff sets
# it for the launcher and restores it when the launcher fails.

start_test "mesh session-shell prints a nested shell's own binary"
result="$(_mesh_run_config '' '
    $env.SESSION_SHELL = ""
    $env.SHLVL = "2"
    exe = $(type -P mesh)
    got = session-shell()
    if $got == "$exe -l" { puts yes } else { puts "no: $got" }
')"
assert_equal "yes" "$result"

start_test "mesh session-shell empty for the first (login) shell"
result="$(_mesh_run_config '' '
    $env.SESSION_SHELL = ""
    $env.SHLVL = "1"
    got = session-shell()
    puts "[$got]"
')"
assert_equal "[]" "$result"

start_test "mesh session-shell prefers an inherited value"
result="$(_mesh_run_config '' '
    $env.SESSION_SHELL = "/opt/other-shell -l"
    $env.SHLVL = "2"
    puts session-shell()
')"
assert_equal "/opt/other-shell -l" "$result"

start_test "mesh session-shell empty for a non-numeric SHLVL"
result="$(_mesh_run_config '' '
    $env.SESSION_SHELL = ""
    $env.SHLVL = "banana"
    got = session-shell()
    puts "[$got]"
')"
assert_equal "[]" "$result"

start_test "mesh failed handoff passes SESSION_SHELL then restores it"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
    bool func stdin-is-tty() { return true }
    bool func inside-project() { return true }
    func autoshpool(...args) {
        v = $env:get(SESSION_SHELL, "")
        puts "launcher saw [$v]"
        fail
    }
' '
    $env.SESSION_SHELL = ""
    $env.SHLVL = "2"
    maybe-start-session-and-exit
    after = $env:get(SESSION_SHELL, "")
    puts "after [$after]"
')"
assert_contains "launcher saw [" "$result"
assert_contains " -l]" "$result"
assert_contains "after []" "$result"

###############
# TEST: applydiff only replaces the file when the command succeeded

start_test "mesh applydiff replaces the file when the command succeeds"
printf 'original\n' > "$_testdir/apply-ok.txt"
result="$(_mesh_run "
    func formatter(f) { puts formatted }
    applydiff formatter $_testdir/apply-ok.txt
    cat $_testdir/apply-ok.txt
")"
assert_equal "formatted" "$result"

start_test "mesh applydiff leaves the file alone when the command fails"
printf 'original\n' > "$_testdir/apply-fail.txt"
result="$(_mesh_run "
    func formatter(f) { fail }
    applydiff formatter $_testdir/apply-fail.txt
    cat $_testdir/apply-fail.txt
" 2>/dev/null)"
assert_equal "original" "$result"

start_test "mesh applydiff removes the staged file when the command fails"
printf 'original\n' > "$_testdir/apply-staged.txt"
_mesh_run "
    func formatter(f) { fail }
    applydiff formatter $_testdir/apply-staged.txt
" >/dev/null 2>&1
assert_false test -e "$_testdir/apply-staged.txt.new"

start_test "mesh applydiff reports the failure and returns nonzero"
printf 'original\n' > "$_testdir/apply-report.txt"
result="$(_mesh_run "
    func formatter(f) { fail }
    applydiff formatter $_testdir/apply-report.txt
    puts \"status=\$sh.status\"
" 2>&1)"
assert_contains "is unchanged" "$result"
assert_contains "status=1" "$result"

###############
# TEST: the ls lister is probed, not assumed
#
# The arm is chosen while rc.mesh is sourced, so the fake `ls` has to be on PATH
# for the whole run -- and it has to be a real executable, since both the probe
# and the wrapper go through `command ls`, which steps past a mesh function.

_gnu_ls_bin="$_testdir/gnulsbin"
mkdir -p "$_gnu_ls_bin"
printf '#!/bin/sh\necho "ls: $*"\n' > "$_gnu_ls_bin/ls"
chmod +x "$_gnu_ls_bin/ls"

# A BSD/macOS-style ls: rejects --color=auto outright.
_bsd_ls_bin="$_testdir/bsdlsbin"
mkdir -p "$_bsd_ls_bin"
{
    printf '#!/bin/sh\n'
    printf 'for a in "$@"; do\n'
    printf '  case "$a" in --color=*) echo "ls: illegal option" >&2; exit 1 ;; esac\n'
    printf 'done\n'
    printf 'echo "ls: $*"\n'
} > "$_bsd_ls_bin/ls"
chmod +x "$_bsd_ls_bin/ls"

_no_l_stub='
    status func have-command(name) {
        match $name {
            l => { return false }
            _ => {
                if type -P --quiet $name { return true }
                return false
            }
        }
    }
'

start_test "mesh l uses the GNU flags when this ls takes them"
result="$(PATH="$_gnu_ls_bin:$PATH" _mesh_run_config "$_no_l_stub" 'l somefile')"
assert_equal "ls: --color=auto -v -b -x somefile" "$result"

start_test "mesh l falls back to plain ls when --color=auto is rejected"
result="$(PATH="$_bsd_ls_bin:$PATH" _mesh_run_config "$_no_l_stub" 'l somefile' 2>/dev/null)"
assert_equal "ls: -v -b -x somefile" "$result"

start_test "mesh ll builds on whichever lister was picked"
result="$(PATH="$_bsd_ls_bin:$PATH" _mesh_run_config "$_no_l_stub" 'll somefile' 2>/dev/null)"
assert_equal "ls: -v -b -x -l somefile" "$result"

start_test "mesh l prefers the separate l program when the host has one"
_l_bin="$_testdir/lbin"
mkdir -p "$_l_bin"
printf '#!/bin/sh\necho "l: $*"\n' > "$_l_bin/l"
chmod +x "$_l_bin/l"
result="$(PATH="$_l_bin:$PATH" _mesh_run_config '' 'l somefile')"
assert_equal "l: -K -v -e -x somefile" "$result"

###############
# TEST: the package shortcuts delegate to the `package` script

# A fake `package` on PATH rather than a mesh function: the aliases name the
# script directly, and `info`/`files` shadow real programs, so only a PATH
# stub proves which one the shortcut reached.
_fake_package_bin="$_testdir/fakepackagebin"
mkdir -p "$_fake_package_bin"
printf '#!/bin/sh\necho "package: $@"\n' > "$_fake_package_bin/package"
chmod +x "$_fake_package_bin/package"

# shrc:2802, config.fish:1310 and config.nu:1486 all define `info`; the port
# had every other verb in the list but not it, so `info` reached the GNU reader
# instead of the package manager.
start_test "mesh info reaches the package script"
result="$(PATH="$_fake_package_bin:$PATH" _mesh_run_config '' 'info somepkg')"
assert_equal "package: info somepkg" "$result"

# The sibling `files` shortcut has no mesh spelling: `files` is a reserved
# value-call name, so binding it is a syntax error rather than a shadowing.
# This asserts the reason, so the shortcut isn't "restored" into a broken file.
start_test "mesh reserves files, so the shortcut cannot be defined"
result="$(_mesh_run_config '' 'wrapper func files(...args) { puts $args:len }' 2>&1)"
assert_contains "files" "$result"
assert_contains "cannot be a function name" "$result"

start_test "mesh listfiles reaches the package script"
result="$(PATH="$_fake_package_bin:$PATH" _mesh_run_config '' 'listfiles somepkg')"
assert_equal "package: listfiles somepkg" "$result"

###############
# TEST: download does not fetch into the wrong directory

# A fake `wget` on PATH, not a mesh function: `download` calls `command wget`,
# which deliberately steps past any function of that name -- so a function stub
# is bypassed and the real wget would go to the network.
_fake_wget_bin="$_testdir/fakewgetbin"
mkdir -p "$_fake_wget_bin"
printf '#!/bin/sh\necho "wget in $PWD"\n' > "$_fake_wget_bin/wget"
chmod +x "$_fake_wget_bin/wget"

start_test "mesh download fetches after a successful cd"
mkdir -p "$_fakehome/Downloads"
result="$(PATH="$_fake_wget_bin:$PATH" _mesh_run 'download http://example.invalid/f')"
assert_equal "wget in $_fakehome/Downloads" "$result"

start_test "mesh download does not fetch when the cd fails"
rm -rf "$_fakehome/Downloads"
result="$(PATH="$_fake_wget_bin:$PATH" _mesh_run '
    cd /etc
    download http://example.invalid/f
    puts "status=$sh.status"
' 2>/dev/null)"
assert_not_contains "wget in" "$result"
assert_contains "status=1" "$result"
mkdir -p "$_fakehome/Downloads"

###############
# TEST: a failing capture still yields its output
#
# This config's lookups whose *miss* is routine -- getent exiting 2, dig 9,
# pgrep 1 -- read a plain `$(...)` and test the result for emptiness. That only
# works on a mesh where a capture yields its bytes whatever the command exited
# with; an older one left the name unbound and the next line died with
# `unbound variable`. Asserted directly so an old mesh fails here, by name,
# rather than somewhere downstream.

start_test "mesh a failing capture is empty rather than unbound"
result="$(_mesh_run '
    out = $(sh -c "exit 2")
    puts "[$out]"
')"
assert_equal "[]" "$result"

start_test "mesh a failing capture keeps output the command did produce"
result="$(_mesh_run '
    out = $(sh -c "echo kept; exit 3")
    st = $sh.status
    puts "[$out] $st"
')"
assert_equal "[kept] 3" "$result"

###############
# TEST: :words tokenizes on whitespace runs, not literal spaces
#
# A mesh modifier now; this config carried a `fields()` helper for it before
# mesh grew one. The cases below are the ones the config actually meets, so they
# stay here rather than relying on mesh's own tests alone.

start_test "mesh :words collapses runs of spaces and tabs"
result="$(_mesh_run '
    f = "  a   b\tc  ":words
    puts $f:len
    puts ...$f
')"
assert_equal "3
a b c" "$result"

start_test "mesh :words is empty for a blank line"
result="$(_mesh_run '
    f = "":words
    puts $f:len
')"
assert_equal "0" "$result"

start_test "mesh :words picks the hostname out of column-padded getent output"
# `getent hosts` pads the address column, so a literal-space split puts empty
# strings in the middle and the hostname is not element 1.
result="$(_mesh_run '
    f = "127.0.0.1       localhost localhost.localdomain":words
    puts $f:get(1, "(none)")
')"
assert_equal "localhost" "$result"

start_test "mesh :words picks the family and address out of column-padded ip output"
result="$(_mesh_run '
    f = "2: eth0    inet 10.0.0.5/24 brd 10.0.0.255 scope global eth0":words
    puts $f[1] $f[2] $f[3]
')"
assert_equal "eth0 inet 10.0.0.5/24" "$result"

start_test "mesh ssh-client-host reads the padded getent hostname"
result="$(_mesh_run_config '
    status func have-command(name) {
        match $name {
            getent => { return true }
            _ => { return false }
        }
    }
    func getent(...args) { puts "10.0.0.1       host1.example.com host1" }
' '
    $env.SSH_CONNECTION = "10.0.0.1 4321 10.0.0.2 22"
    puts ssh-client-host()
')"
assert_equal "host1" "$result"

start_test "mesh ssh-client-host falls back to the raw IP with no lookup"
result="$(_mesh_run_config '
    bool func have-command(name) { return false }
' '
    $env.SSH_CONNECTION = "10.0.0.1 4321 10.0.0.2 22"
    puts ssh-client-host()
')"
assert_equal "10.0.0.1" "$result"

# A miss is the ordinary outcome of both lookups -- getent exits 2 for an
# address with no entry -- and a plain capture leaves the name unbound, so the
# `dig` fallback below it was never reached.
start_test "mesh ssh-client-host falls back to dig when getent has no entry"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
    func getent(...args) { fail 2 }
    func dig(...args) { puts "host2.example.com." }
' '
    $env.SSH_CONNECTION = "10.0.0.1 4321 10.0.0.2 22"
    puts ssh-client-host()
' 2>&1)"
assert_equal "host2" "$result"

start_test "mesh ssh-client-host answers the raw IP when both lookups miss"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
    func getent(...args) { fail 2 }
    func dig(...args) { fail 9 }
' '
    $env.SSH_CONNECTION = "10.0.0.1 4321 10.0.0.2 22"
    puts ssh-client-host()
' 2>&1)"
assert_equal "10.0.0.1" "$result"

start_test "mesh ssh-client-host prefers LC_CLIENT_HOST"
result="$(_mesh_run '
    $env.LC_CLIENT_HOST = "laptop1"
    $env.SSH_CONNECTION = "10.0.0.1 4321 10.0.0.2 22"
    puts ssh-client-host()
')"
assert_equal "laptop1" "$result"

start_test "mesh ssh-client-host is empty outside an ssh session"
result="$(_mesh_run 'puts "[$(puts ssh-client-host())]"')"
assert_equal "[]" "$result"

###############
# TEST: psgrep reports a pattern that matches nothing

# `pgrep` exits 1 on no match, which is what the empty-result branch is for. A
# plain capture left `pids` unbound, so that test failed with `unbound variable`
# and the miss was never reported.
start_test "mesh psgrep reports a pattern matching no processes"
result="$(_mesh_run_config '
    func pgrep(...args) { fail }
' 'psgrep no-such-process
puts "status=$sh.status"' 2>&1)"
assert_equal "No processes matching no-such-process
status=1" "$result"

start_test "mesh psgrep passes the matched pids to ps"
result="$(_mesh_run_config '
    func pgrep(...args) { puts "11,22" }
    wrapper func psc(...args) { puts psc: ...$args }
' 'psgrep -w pattern' 2>&1)"
assert_equal "psc: -p 11,22 -w" "$result"

###############
# TEST: age answers a failing status for a file it cannot read

# `stat` has already reported why. Without the guard its diagnostic was
# followed by an unbound-variable error for the capture and another for the
# subtraction -- three messages for one cause.
#
# The miss is `stat`'s own status, which is what makes `if age($f)` the way to
# ask. shrc:767 and config.fish:330 end up nonzero on the same file too, their
# `expr` / `math` failing on the empty capture.
start_test "mesh age is falsy for a missing file"
result="$(_mesh_run "
    if age(\"$_testdir/no-such-file-xyz\") { puts found } else { puts missing }
" 2>/dev/null)"
assert_equal "missing" "$result"

# The code itself, not just its truthiness: it is stat's, forwarded rather than
# replaced with a status of this function's own choosing.
start_test "mesh age forwards stat's exit code on a miss"
result="$(_mesh_run "puts age(\"$_testdir/no-such-file-xyz\")" 2>/dev/null)"
assert_equal "1" "$result"

# Why `fail` rather than a returned status, pinned in the one place the two
# differ: in command position the *status* is the condition, so a hit reads as
# true. A returned status would answer the miss and then raise "an int is not a
# condition" on the hit, which is the shape this asserts against.
start_test "mesh age reads as a condition on a hit and a miss alike"
touch "$_testdir/aged-cond"
result="$(_mesh_run "
    if age $_testdir/aged-cond { puts hit } else { puts \"no hit\" }
    if age $_testdir/no-such-file-xyz { puts \"no miss\" } else { puts miss }
" 2>/dev/null)"
assert_equal "hit
miss" "$result"

start_test "mesh age reports the seconds since a file changed"
touch "$_testdir/aged"
result="$(_mesh_run "
    n = age(\"$_testdir/aged\")
    if \$n < 60 { puts recent } else { puts \"stale: \$n\" }
" 2>&1)"
assert_equal "recent" "$result"

###############
# TEST: return types are declared where there is a value, and only there

# mesh narrowed a func's value channel to the type it declares: an undeclared
# `func` hands back its status whatever the body produced, so `str func` is what
# makes tilde-pwd() a path rather than a `0`. That makes the declaration a
# contract rather than documentation, and one an edit can silently drop -- the
# function keeps parsing and starts answering `0` -- so it is asserted here.
start_test "mesh a value function declares the type it answers with"
result="$(_mesh_run 'type tilde-pwd' 2>&1)"
assert_contains "str func tilde-pwd()" "$result"

# The other half of the split, and the reason it isn't "declare one everywhere":
# preprompt draws a prompt and answers nothing, so it declares nothing.
start_test "mesh an effect-only function declares no return type"
result="$(_mesh_run 'type preprompt' 2>&1)"
assert_contains "    func preprompt()" "$result"

# read-local-rc reports whether the local file loaded, which is a status and not
# the `bool` it briefly claimed: the success arm returned `true` only because
# `fail 0` is refused, while the no-local-file path is a bare `return` and hands
# back a status. `status(0)` for the success arm puts all three exits in one
# type, which is what makes the declaration true rather than half true.
start_test "mesh read-local-rc declares the status it reports"
result="$(_mesh_run 'type read-local-rc' 2>&1)"
assert_contains "status func read-local-rc()" "$result"

# Each of the three exits, since the declaration is only as good as its worst
# arm and the middle one is the arm that was wrong.
start_test "mesh read-local-rc succeeds with no rc.local.mesh"
rm -f "$_fakehome/.config/mesh/rc.local.mesh"
result="$(_mesh_run 'if read-local-rc { puts ok } else { puts failed }' 2>&1)"
assert_equal "ok" "$result"

start_test "mesh read-local-rc succeeds on a clean rc.local.mesh"
printf 'export RC_LOCAL_MARKER = "seen"\n' > "$_fakehome/.config/mesh/rc.local.mesh"
result="$(_mesh_run 'if read-local-rc { puts ok } else { puts failed }' 2>&1)"
assert_equal "ok" "$result"

start_test "mesh read-local-rc fails on a broken rc.local.mesh"
printf 'this is not( valid mesh\n' > "$_fakehome/.config/mesh/rc.local.mesh"
result="$(_mesh_run 'if read-local-rc { puts ok } else { puts failed }' 2>&1 | tail -n 1)"
assert_equal "failed" "$result"
rm -f "$_fakehome/.config/mesh/rc.local.mesh"

###############
# TEST: no function answers with a type it did not declare

# Built here rather than beside the is-ssh-valid tests that also use it: the
# audit below is the first thing that needs an ssh-add which cannot block.
_fake_ssh_add_bin="$_testdir/fakesshaddbin"
mkdir -p "$_fake_ssh_add_bin"
printf '#!/bin/sh\nexit "${FAKE_SSH_ADD_STATUS:-0}"\n' > "$_fake_ssh_add_bin/ssh-add"
chmod +x "$_fake_ssh_add_bin/ssh-add"

#
# mesh warns when a call's value disagrees with its declaration, which turns
# every declaration in the two config files into something checkable rather
# than something asserted. This drives each value channel once and fails on any
# such warning -- that is how read-local-rc's wrong `bool` was found.
#
# The name list is checked against the config below rather than trusted, so a
# value function added later cannot quietly escape the sweep.
_typed_audit='
a = connected-remotely(); a = connected-via-ssh(); a = env-on("NOPE")
a = i-am-root(); a = in-shpool(); a = inpath("/usr/bin"); a = inside-project()
a = inside-tmux(); a = is-function("blue"); a = is-shell-name("puts")
a = need-auth(); a = on-dev-host(); a = on-my-laptop(); a = on-my-machine()
a = on-my-workstation(); a = on-production-host(); a = on-test-host()
a = session-script-wanted(); a = show-hostname-in-title(); a = shpool-available()
a = stdin-is-tty(); a = tmux-available(); a = want-failsafe(); a = want-shpool()
a = want-tmux(); a = starts-with("abc", "a")
b = terminal-width()
c = shellenv-entry("export A=1"); c = drop-trailing-empty(["a" ""])
c = without(["a" "b"], "a")
d = have-command("sh"); d = have-command("no-such-program-xyz")
d = is-runnable("sh"); d = is-runnable("no-such-program-xyz")
d = quiet(true); d = is-ssh-valid()
d = read-local-rc()
e = auth-info(); e = blue("x"); e = bounded-auth-info(); e = builddir()
e = buildroot(); e = check-limit("NOPE", "2"); e = dir-info()
e = find-test-file("/etc/hostname"); e = find-up("hostname")
e = format-duration(5000); e = green("x"); e = host-info(); e = job-info()
e = one-line("a  b"); e = projectname(); e = projectroot(); e = prompt-line("")
e = prompt-project-name(); e = prompt-session-name(); e = publish-jobs-file()
e = red("x"); e = rootdir(); e = session-backend(); e = session-name()
e = session-shell(); e = short-hostname(); e = ssh-client-host(); e = tilde-pwd()
e = title-text(); e = unquoted-head("\"x\""); e = workstation(); e = yellow("x")
f = age("/etc/hostname")
'

# trydiff stages its output *beside* the input (`${file}.trydiff.$pid`), so it
# needs a fixture in a writable directory -- pointed at /etc/hostname it cannot
# stage on any runner that isn't root, and warns about the `bool` it then does
# not return. A read-only fixture is fine for the rest: `age` only stats, and
# find-test-file is string work that never opens anything.
_typed_audit="$_typed_audit
a = trydiff(cat, \"$_testdir/audit-trydiff\")
puts \"AUDIT COMPLETE\"
"

# The sentinel is what makes a green run mean something. Grepping a pipeline for
# the *absence* of a warning passes just as happily when mesh died on the first
# line and printed nothing at all, and `| grep -c` throws the status away that
# would have said so. Asserting the last statement ran is the cheap version of
# checking that: no completion line, no pass.
#
# `_mesh_run_config ''` rather than `_mesh_run`, deliberately: the latter
# replaces have-command with a stub, so the sweep would audit the stub's
# declaration instead of the one in env.mesh -- the single function whose type
# every session helper is written against, and the one place this test would be
# describing itself rather than the config. Nothing here needs the stub either;
# it exists to make the *answers* deterministic, and a type sweep only cares
# that no warning fires. Both directions are driven for the two lookups, since a
# mismatch can hide on whichever path a given host does not take.
#
# `ssh-add` is faked on PATH for the one call that would otherwise reach the
# real agent. is-ssh-valid is deliberately *unbounded* -- rc.mesh:118 puts the
# limit in auth-info so an override of the hook inherits it -- so calling it
# straight, as this does, is the one place in the suite with nothing between it
# and a stale $SSH_AUTH_SOCK, which the harness does not clear. That is a socket
# nobody answers, so the audit would sit there until run_with_timeout killed it
# at 15s and report a type failure that was really a hang. The fake keeps the
# production is-ssh-valid in the sweep, which is the whole point of not using
# the stub above; it only stops ssh-add itself from blocking.
start_test "mesh no function answers with a type it did not declare"
touch "$_testdir/audit-trydiff"
_audit_out="$(PATH="$_fake_ssh_add_bin:$PATH" _mesh_run_config '' "$_typed_audit" 2>&1)"
assert_contains "AUDIT COMPLETE" "$_audit_out"
assert_not_contains "declared " "$_audit_out"

# confirm needs stdin, so it is driven separately rather than left out.
start_test "mesh confirm answers the bool it declares"
_audit_out="$(printf 'y\n' | _mesh_run_stdin '' 'r = confirm("ok")
puts "CONFIRM COMPLETE"' 2>&1)"
assert_contains "CONFIRM COMPLETE" "$_audit_out"
assert_not_contains "declared " "$_audit_out"

# The list above is only as good as its coverage, so every declared name in the
# two config files has to appear in it. Adding `str func whatever()` without a
# line in the audit fails here rather than going unswept.
#
# The alternation is mesh's whole return-type vocabulary, `regex`, `job` and
# `func` included -- none of which this config declares yet. A scan that knew
# only the words in use would let the first `regex func` past while still
# claiming nothing can escape, which is the one way this test can lie. The
# second literal `func` is what keeps a plain `func preprompt()` out and lets
# `func func f()` in.
#
# The names exercised above are extracted and compared whole, rather than the
# audit being searched for `$_name(` as a substring: a kebab-case vocabulary is
# full of names that end in another one, so `str func info()` would have counted
# `auth-info(` as its coverage and gone unswept -- the exact hole this test is
# supposed to close.
start_test "mesh the return-type audit covers every declared function"
_audited="$(printf '%s' "$_typed_audit" | grep -o '[A-Za-z][A-Za-z0-9-]*(' | tr -d '(' | sort -u)"
_missing=""
for _name in $(sed -n 's/^\(status\|int\|str\|bool\|list\|map\|any\|regex\|job\|func\) \(wrapper \)\?func \([A-Za-z][A-Za-z0-9-]*\)(.*/\3/p' \
        "$_env_mesh" "$_rc_mesh"); do
    case "$_name" in
        confirm) continue ;;  # driven by its own stdin test above
    esac
    printf '%s\n' "$_audited" | grep -qxF -- "$_name" || _missing="$_missing $_name"
done
assert_equal "" "$_missing"

# A predicate answers `true`/`false`, including on the line that asks PATH:
# `have-command` is a status, so shpool-available converts it rather than
# passing it through and having to call itself `any`.
start_test "mesh an availability check declares bool and answers one"
result="$(_mesh_run 'type shpool-available' 2>&1)"
assert_contains "bool func shpool-available()" "$result"

start_test "mesh shpool-available answers false when autoshpool is missing"
result="$(_mesh_run_config '
    status func have-command(name) {
        match $name {
            autoshpool => { return status(1) }
            _ => { return status(0) }
        }
    }
' 'puts shpool-available()')"
assert_equal "false" "$result"

# The converted line, not just the deciding ones: with everything on PATH the
# answer is still a bool rather than have-command'"'"'s 0.
start_test "mesh shpool-available answers true when both are present"
result="$(_mesh_run_config '
    status func have-command(name) { return status(0) }
' 'puts shpool-available()')"
assert_equal "true" "$result"

# The conversion is a guard, not a `== 0`, so it survives a have-command that
# answers with a bool -- which is how the tests stub it throughout, and how
# ~/.rc.local.mesh may override it. A comparison would raise "cannot compare a
# bool with an int" here instead.
start_test "mesh shpool-available takes a bool-answering have-command"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
' 'puts shpool-available()')"
assert_equal "true" "$result"

# The value channel itself, asked of a `str func` through a binding rather than
# a call in command position -- which is exactly what the narrowing changed.
start_test "mesh binding a value function's call yields its value"
result="$(_mesh_run 'cd $env.HOME
    here = tilde-pwd()
    puts $here')"
assert_equal "~" "$result"

start_test "mesh ips reads column-padded ip output"
result="$(_mesh_run_config '
    func ip(...args) {
        puts "2: eth0    inet 10.0.0.5/24 brd 10.0.0.255 scope global eth0"
        puts "3: wlan0   inet6 fe80::1/64 scope global wlan0"
    }
' 'ips')"
assert_equal "eth0 10.0.0.5/24
wlan0 fe80::1/64" "$result"

###############
# TEST: the network and stream helpers the port had dropped

# The sed program pairs each `N: iface` line with the `link/ether` line that
# follows it, so a stub has to emit the real two-line shape.
start_test "mesh macs pairs each interface with its MAC"
result="$(_mesh_run_config '
    func ip(...args) {
        puts "1: lo: <LOOPBACK,UP> mtu 65536 qdisc noqueue state UNKNOWN"
        puts "    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00"
        puts "2: eth0: <BROADCAST,UP> mtu 1500 qdisc fq state UP"
        puts "    link/ether 02:42:ac:11:00:02 brd ff:ff:ff:ff:ff:ff"
    }
' 'macs')"
assert_equal "eth0 02:42:ac:11:00:02" "$result"

start_test "mesh with-address-records puts a hostname's addresses on one line"
result="$(printf 'host1\n' | _mesh_run_stdin '
    func addr(host) {
        puts "10.0.0.1"
        puts "fe80::1"
    }
' 'with-address-records')"
assert_equal "host1 10.0.0.1 fe80::1" "$result"

start_test "mesh with-hostnames puts an address's names on one line"
result="$(printf '10.0.0.1\n' | _mesh_run_stdin '
    func ptr(ip) { puts "host1.example.com." }
' 'with-hostnames')"
assert_equal "10.0.0.1 host1.example.com." "$result"

start_test "mesh each runs the command once per line of stdin"
result="$(printf 'one\ntwo\n' | _mesh_run_stdin '' 'each echo X')"
assert_equal "X one
X two" "$result"

# Null-delimited so an item may contain a space -- or a newline, which is the
# whole reason the form exists and what `tr` to newlines would destroy.
start_test "mesh each0 runs the command once per null-delimited item"
result="$(printf 'a b\0c\0' | _mesh_run_stdin '' 'each0 echo X')"
assert_equal "X a b
X c" "$result"

# A newline *inside* an item is the case the NUL form exists for, and the one
# `each` cannot express: a line read would tear this name in half.
start_test "mesh each0 keeps a newline inside an item"
result="$(printf 'a\nb\0c\0' | _mesh_run_stdin '' 'each0 echo X')"
assert_equal "X a
b
X c" "$result"

# The capability the xargs delegation cost: xargs runs programs, so a mesh
# function was unreachable through each0 while `each` could call one. The loop
# closes that gap, which is the reason for preferring it over the delegation.
start_test "mesh each0 calls a mesh function, not just a program"
result="$(printf 'one\0two\0' | _mesh_run_stdin '
    func shout(item) { puts "[$item]" }
' 'each0 shout')"
assert_equal "[one]
[two]" "$result"

# Zero times, matching the shrc and fish loops. xargs needed `-r` to agree --
# GNU runs the command once on empty input without it -- and a loop simply
# never enters, so the agreement no longer rests on a flag.
start_test "mesh each0 runs nothing at all on empty input"
result="$(printf '' | _mesh_run_stdin '' 'each0 echo X')"
assert_equal "" "$result"

# An item with no trailing NUL is still an item, the same rule a file's last
# line without a newline follows.
start_test "mesh each0 takes a final item with no trailing NUL"
result="$(printf 'a\0b' | _mesh_run_stdin '' 'each0 echo X')"
assert_equal "X a
X b" "$result"

start_test "mesh dev reads the filesystem out of column-padded df output"
result="$(_mesh_run_config '
    func df(...args) {
        puts "Filesystem     1024-blocks    Used Available Capacity Mounted on"
        puts "/dev/vda         264212084 8358000  30490524      22% /"
    }
' 'dev /etc')"
assert_equal "/dev/vda" "$result"

###############
# TEST: trydiff previews only when the command succeeded

start_test "mesh trydiff shows the proposed change"
printf 'one\n' > "$_testdir/try-ok.txt"
result="$(_mesh_run "
    func formatter(f) { puts two }
    trydiff formatter $_testdir/try-ok.txt
")"
assert_contains "two" "$result"

# The command's own status reaches the caller: 130 from a Ctrl-C has to stay
# distinguishable from an ordinary failure. mesh clears $sh.status while
# evaluating an `if` condition, so the status is captured before branching.
start_test "mesh trydiff returns the command's own status"
printf 'one\n' > "$_testdir/try-status130.txt"
result="$(_mesh_run "
    func boom(f) { fail 130 }
    trydiff boom $_testdir/try-status130.txt
    puts \"status=\$sh.status\"
" 2>/dev/null)"
assert_equal "status=130" "$result"

start_test "mesh applydiff returns the command's own status"
result="$(_mesh_run "
    func boom(f) { fail 130 }
    applydiff boom $_testdir/try-status130.txt
    puts \"status=\$sh.status\"
" 2>/dev/null)"
assert_equal "status=130" "$result"

start_test "mesh isort returns sort's own status"
result="$(_mesh_run "
    trap-nothing = 0
    isort /no-such-file-here
    puts \"failed=\$sh.status\"
" 2>/dev/null)"
assert_not_contains "failed=0" "$result"

start_test "mesh trydiff shows nothing and reports when the command fails"
printf 'one\n' > "$_testdir/try-fail.txt"
result="$(_mesh_run "
    func formatter(f) { fail }
    trydiff formatter $_testdir/try-fail.txt
    puts \"status=\$sh.status\"
" 2>&1)"
assert_contains "nothing to compare" "$result"
assert_contains "status=1" "$result"
assert_not_contains "one" "$result"

start_test "mesh trydiff removes its temporary file either way"
printf 'one\n' > "$_testdir/try-temp.txt"
_mesh_run "
    func formatter(f) { fail }
    trydiff formatter $_testdir/try-temp.txt
" >/dev/null 2>&1
result="$(ls "$_testdir"/try-temp.txt.trydiff.* 2>/dev/null | wc -l | tr -d ' ')"
assert_equal "0" "$result"

start_test "mesh trydiff leaves the original file alone"
printf 'one\n' > "$_testdir/try-orig.txt"
_mesh_run "
    func formatter(f) { puts two }
    trydiff formatter $_testdir/try-orig.txt
" >/dev/null 2>&1
assert_equal "one" "$(cat "$_testdir/try-orig.txt")"

# `diff` exits 1 when the files differ -- the whole point of a preview -- so
# passing that through would break `trydiff x f && applydiff x f` and make
# every useful run look failed.
start_test "mesh trydiff succeeds when the preview finds differences"
printf 'one\n' > "$_testdir/try-status.txt"
result="$(_mesh_run "
    func formatter(f) { puts two }
    trydiff formatter $_testdir/try-status.txt > /dev/null
    puts \"status=\$sh.status\"
")"
assert_equal "status=0" "$result"

start_test "mesh trydiff succeeds when the preview finds nothing to change"
result="$(_mesh_run "
    func formatter(f) { puts one }
    trydiff formatter $_testdir/try-status.txt > /dev/null
    puts \"status=\$sh.status\"
")"
assert_equal "status=0" "$result"

# 2-and-up is diff's "trouble" range -- a genuine failure, unlike 1 -- and is
# passed through. `diff` is looked up on PATH, so the stub is a real program.
start_test "mesh trydiff passes through a real diff failure"
_fake_diff_bin="$_testdir/fakediffbin"
mkdir -p "$_fake_diff_bin"
printf '#!/bin/sh\nexit 2\n' > "$_fake_diff_bin/diff"
chmod +x "$_fake_diff_bin/diff"
result="$(PATH="$_fake_diff_bin:$PATH" _mesh_run_config '' "
    func formatter(f) { puts two }
    trydiff formatter $_testdir/try-status.txt > /dev/null
    puts \"status=\$sh.status\"
")"
assert_equal "status=2" "$result"

###############
# TEST: isort only replaces the file when sort succeeded

start_test "mesh isort sorts the file in place"
printf 'c\na\nb\n' > "$_testdir/isort-ok.txt"
result="$(_mesh_run "
    isort $_testdir/isort-ok.txt
    cat $_testdir/isort-ok.txt
")"
assert_equal "a
b
c" "$result"

start_test "mesh isort leaves the file alone when sort fails"
printf 'c\na\n' > "$_testdir/isort-fail.txt"
result="$(_mesh_run "
    func sort(...args) { fail }
    isort $_testdir/isort-fail.txt
    cat $_testdir/isort-fail.txt
" 2>/dev/null)"
assert_equal "c
a" "$result"

start_test "mesh isort removes the staged file and reports when sort fails"
printf 'c\na\n' > "$_testdir/isort-staged.txt"
result="$(_mesh_run "
    func sort(...args) { fail }
    isort $_testdir/isort-staged.txt
    puts \"status=\$sh.status\"
" 2>&1)"
assert_false test -e "$_testdir/isort-staged.txt.bak"
assert_contains "is unchanged" "$result"
assert_contains "status=1" "$result"

###############
# TEST: the legacy shpool working directory is applied before handoff

start_test "mesh apply-shpool-initial-pwd cds to the launcher's directory"
mkdir -p "$_testdir/initial-pwd"
result="$(_mesh_run "
    \$env.SHPOOL_SESSION_NAME = \"sess\"
    \$env.SHPOOL_INITIAL_PWD = \"$_testdir/initial-pwd\"
    apply-shpool-initial-pwd
    pwd
")"
assert_equal "$_testdir/initial-pwd" "$result"

start_test "mesh apply-shpool-initial-pwd clears the variable so it applies once"
result="$(_mesh_run "
    \$env.SHPOOL_SESSION_NAME = \"sess\"
    \$env.SHPOOL_INITIAL_PWD = \"$_testdir/initial-pwd\"
    apply-shpool-initial-pwd
    puts \"[\$env.SHPOOL_INITIAL_PWD]\"
")"
assert_equal "[]" "$result"

start_test "mesh apply-shpool-initial-pwd is a no-op outside shpool"
result="$(_mesh_run "
    \$env.SHPOOL_INITIAL_PWD = \"$_testdir/initial-pwd\"
    cd /etc
    apply-shpool-initial-pwd
    pwd
")"
assert_equal "/etc" "$result"

start_test "mesh apply-shpool-initial-pwd is a no-op with no initial directory"
result="$(_mesh_run '
    $env.SHPOOL_SESSION_NAME = "sess"
    cd /etc
    apply-shpool-initial-pwd
    pwd
')"
assert_equal "/etc" "$result"

# The variable is the only record of where the handoff meant to land, so a cd
# that fails must leave it alone rather than clear it and land silently in the
# launcher's directory.
start_test "mesh apply-shpool-initial-pwd keeps the variable when the cd fails"
result="$(_mesh_run '
    $env.SHPOOL_SESSION_NAME = "sess"
    $env.SHPOOL_INITIAL_PWD = "/no-such-dir-here"
    apply-shpool-initial-pwd
    puts "status=$sh.status kept=[$env.SHPOOL_INITIAL_PWD]"
' 2>/dev/null)"
assert_equal "status=1 kept=[/no-such-dir-here]" "$result"

###############
# TEST: TTY is the terminal name or nothing, never tty's diagnostic

# `tty` prints "not a tty" on stdout and exits 1 with no terminal, so a naive
# capture exports the diagnostic to every child and into every history line.
start_test "mesh TTY is empty when stdin is not a terminal"
result="$(HOME="$_fakehome" run_with_timeout 15 env -u TTY mesh -c "
    source $_env_mesh
    puts \"[\$env.TTY]\"
" </dev/null)"
assert_equal "[]" "$result"

# Regression: env.mesh used to keep an inherited TTY to save a fork, which is
# right for a nested shell on the same terminal and wrong for every shell a
# daemon spawns. zsh fills and exports TTY before any rc runs, and config.nu,
# rc.elv and env.mesh export their own, so the value is usually present -- and
# under shpool it names whichever terminal started the daemon, not this
# session's pty. log-history then filed every command against the wrong
# terminal and publish-jobs wrote over another terminal's job file.
#
# Asserted as empty rather than as the real pty because the harness has no
# terminal: what matters is that the inherited value did not survive.
start_test "mesh TTY is recomputed rather than inherited"
result="$(HOME="$_fakehome" run_with_timeout 15 env TTY=/dev/pts/7 mesh -c "
    source $_env_mesh
    puts \"[\$env.TTY]\"
" </dev/null)"
assert_equal "[]" "$result"

###############
# TEST: the session-script wrappers report the script's own status
#
# Subtle, and worth pinning: mesh's bare `return` carries "the result so far --
# the status of a command that produced none", so `return unless $sh.status ==
# 0` propagates the picker's status rather than the guard's. shrc has to say
# `rc=$?; ... return $rc` by hand because its guards are one `&&` chain whose
# failure would otherwise mask a successful picker with 1.

_session_wrapper_status() {
    local _fn="$1"
    local _rc="$2"
    shift 2
    # These stand in for external scripts, so what they carry is a *status*.
    # `fail` is the verb for that channel; `fail 0` is refused, since the
    # channel only carries failure, so success is spelled `return true`.
    local _leave="fail $_rc"
    test "$_rc" = 0 && _leave="return true"
    _mesh_run_config "
        bool func have-command(name) { return true }
        # Wrappers, because the real ones are external scripts that take
        # whatever they are given -- a plain func would reject --list.
        # (No backticks here: this string is double-quoted in bash.)
        wrapper func changesession(...args) { $_leave }
        wrapper func changeshpool(...args) { $_leave }
        wrapper func makesession(...args) { $_leave }
        wrapper func makeshpool(...args) { $_leave }
    " "
        $_fn $*
        puts \$sh.status
    "
}

start_test "mesh cs propagates a cancelled picker's status"
assert_equal "130" "$(_session_wrapper_status cs 130)"

start_test "mesh cs reports success when the switch worked"
assert_equal "0" "$(_session_wrapper_status cs 0)"

# The guard under test is `$args:len == 0`, which any argument exercises.
start_test "mesh cs reports success on the non-picker path with arguments"
assert_equal "0" "$(_session_wrapper_status cs 0 somesession)"

# `cs --list` is the documented path that a plain `...rest` function used to
# reject as `unknown flag --list`; `wrapper func` is what makes it typeable,
# so it is asserted rather than worked around.
start_test "mesh cs forwards a long flag to the session script"
assert_equal "0" "$(_session_wrapper_status cs 0 --list)"

start_test "mesh cs propagates a failure even with arguments"
assert_equal "130" "$(_session_wrapper_status cs 130 somesession)"

start_test "mesh csp propagates the script's status"
assert_equal "130" "$(_session_wrapper_status csp 130)"
assert_equal "0" "$(_session_wrapper_status csp 0)"

start_test "mesh ms propagates the script's status"
assert_equal "130" "$(_session_wrapper_status ms 130)"
assert_equal "0" "$(_session_wrapper_status ms 0)"

start_test "mesh msp propagates the script's status"
assert_equal "130" "$(_session_wrapper_status msp 130)"
assert_equal "0" "$(_session_wrapper_status msp 0)"

start_test "mesh cs does nothing and succeeds with no backend at all"
# Matches config.nu, whose `if (skip-session-script $backend) { return }` also
# reports success on the nothing-to-do path.
result="$(_mesh_run_config '
    func changesession(...args) { puts "changesession ran" }
' '
    cs
    puts $sh.status
')"
assert_equal "0" "$result"

# The backend the wrappers picked reaches the script on a `VAR=value cmd`
# prefix. Real programs rather than mesh function stubs, because the whole
# point of the prefix is what a *child* inherits -- a function stub would
# read the same name off this shell and pass whether or not it crossed.
_fake_session_bin="$_testdir/fakesessionbin"
mkdir -p "$_fake_session_bin"
for _script in changesession detachsession makesession; do
    printf '#!/bin/sh\necho "%s: $@ [$SESSION_BACKEND]"\n' "$_script" \
        > "$_fake_session_bin/$_script"
    chmod +x "$_fake_session_bin/$_script"
done

# shpool is the default preference, and shpool-available() asks after
# `autoshpool` too, so both have to answer true for session-backend() to
# settle on `shpool` deterministically.
_session_backend_run() {
    PATH="$_fake_session_bin:$PATH" _mesh_run_config '
        status func have-command(name) {
            match $name {
                shpool | autoshpool => { return true }
                _                   => { return false }
            }
        }
    ' "$1"
}

start_test "mesh cs hands the backend to the session script"
assert_equal "changesession: --list [shpool]" "$(_session_backend_run 'cs --list')"

start_test "mesh ds hands the backend to the session script"
assert_equal "detachsession:  [shpool]" "$(_session_backend_run 'ds')"

start_test "mesh ms hands the backend to the session script"
assert_equal "makesession: work [shpool]" "$(_session_backend_run 'ms work')"

# The prefix restores what it found, so an unset SESSION_BACKEND has to come
# back unset -- leaving `shpool` behind would pin the preference for the rest
# of the session, which is exactly what session-backend() reads.
start_test "mesh cs does not leak SESSION_BACKEND into the shell"
result="$(unset SESSION_BACKEND; _session_backend_run 'cs --list > /dev/null
after = $env:get(SESSION_BACKEND, "unset")
puts "[$after]"')"
assert_equal "[unset]" "$result"

###############
# TEST: the session predicates answer both ways
#
# Each is a one-line `return <comparison>`, so the risk is a predicate that
# answers the same thing whatever the environment holds. Both answers are
# asserted for that reason.

start_test "mesh connected-via-ssh reads SSH_CONNECTION"
result="$(_mesh_run '
    $env.SSH_CONNECTION = "192.0.2.1 22 192.0.2.2 22"
    puts connected-via-ssh() connected-remotely()
')"
assert_equal "true true" "$result"

start_test "mesh connected-via-ssh is false without SSH_CONNECTION"
assert_equal "false false" "$(_mesh_run 'puts connected-via-ssh() connected-remotely()')"

start_test "mesh in-shpool reads SHPOOL_SESSION_NAME"
result="$(_mesh_run '
    $env.SHPOOL_SESSION_NAME = "work"
    puts in-shpool()
')"
assert_equal "true" "$result"

start_test "mesh in-shpool is false outside shpool"
assert_equal "false" "$(_mesh_run 'puts in-shpool()')"

start_test "mesh inside-tmux reads TMUX"
result="$(_mesh_run '
    $env.TMUX = "/tmp/tmux-1000/default,1,0"
    puts inside-tmux()
')"
assert_equal "true" "$result"

start_test "mesh inside-tmux is false outside tmux"
assert_equal "false" "$(_mesh_run 'puts inside-tmux()')"

# tmux already shows the host, so the title does not repeat it.
start_test "mesh show-hostname-in-title is false inside tmux"
result="$(_mesh_run '
    $env.TMUX = "/tmp/tmux-1000/default,1,0"
    puts show-hostname-in-title()
')"
assert_equal "false" "$result"

start_test "mesh show-hostname-in-title is true outside tmux"
assert_equal "true" "$(_mesh_run 'puts show-hostname-in-title()')"

start_test "mesh inside-project follows projectroot"
result="$(_mesh_run_config '
    str func projectroot() { return "/home/user/project" }
' 'puts inside-project()')"
assert_equal "true" "$result"

start_test "mesh inside-project is false with no project root"
result="$(_mesh_run_config '
    str func projectroot() { return "" }
' 'puts inside-project()')"
assert_equal "false" "$result"

###############
# TEST: host classification

start_test "mesh on-my-laptop reads ~/.laptop"
touch "$_fakehome/.laptop"
result="$(_mesh_run 'puts on-my-laptop()')"
rm -f "$_fakehome/.laptop"
assert_equal "true" "$result"

start_test "mesh on-my-laptop matches a laptop hostname"
result="$(_mesh_run '
    $env.HOSTNAME = "my-laptop-1"
    puts on-my-laptop()
')"
assert_equal "true" "$result"

start_test "mesh on-test-host and on-dev-host match by hostname"
result="$(_mesh_run '
    $env.HOSTNAME = "web-test-3"
    puts on-test-host() on-dev-host()
')"
assert_equal "true false" "$result"

start_test "mesh on-dev-host matches by hostname"
result="$(_mesh_run '
    $env.HOSTNAME = "web-dev-3"
    puts on-test-host() on-dev-host()
')"
assert_equal "false true" "$result"

start_test "mesh on-production-host is false on a test host"
result="$(_mesh_run '
    $env.HOSTNAME = "web-test-3"
    puts on-production-host()
')"
assert_equal "false" "$result"

start_test "mesh on-production-host is true on an unrecognized host"
result="$(_mesh_run '
    $env.HOSTNAME = "web1"
    $env.USERNAME = "someuser"
    puts on-production-host()
')"
assert_equal "true" "$result"

start_test "mesh on-my-workstation matches ~/.workstation"
printf 'ws1\n' > "$_fakehome/.workstation"
result="$(_mesh_run '
    $env.HOSTNAME = "ws1"
    puts on-my-workstation()
')"
rm -f "$_fakehome/.workstation"
assert_equal "true" "$result"

start_test "mesh on-my-workstation matches a \$USERNAME-prefixed hostname"
result="$(_mesh_run '
    $env.HOSTNAME = "someuser-desktop"
    $env.USERNAME = "someuser"
    puts on-my-workstation()
')"
assert_equal "true" "$result"

###############
# TEST: prompt pieces

start_test "mesh format-duration ignores anything under two seconds"
result="$(_mesh_run 'puts "[$(puts format-duration(1500))]"')"
assert_equal "[]" "$result"

start_test "mesh format-duration spells out hours, minutes and seconds"
result="$(_mesh_run 'puts format-duration(3661000)')"
assert_equal "1 hours 1 minutes 1 seconds" "$result"

start_test "mesh format-duration drops empty leading units"
result="$(_mesh_run 'puts format-duration(125000)')"
assert_equal "2 minutes 5 seconds" "$result"

# command-finished matches its integer arms against the `Status` postexec hands
# it, which works because a status compares to an int by its code. Success and
# the two expected signals stay silent; anything else is reported.
start_test "mesh command-finished says nothing on success"
result="$(_mesh_run 'command-finished("x", status(0), 0)')"
assert_equal "" "$result"

start_test "mesh command-finished names an interrupt"
result="$(_mesh_run 'command-finished("x", status(130), 0)')"
assert_contains "interrupted" "$result"

start_test "mesh command-finished stays quiet on a stop"
result="$(_mesh_run 'command-finished("x", status(148), 0)')"
assert_equal "" "$result"

start_test "mesh command-finished reports any other status"
result="$(_mesh_run 'command-finished("x", status(3), 0)')"
assert_contains "status 3" "$result"

start_test "mesh host-info tags the session name when attached"
result="$(_mesh_run '
    $env.HOSTNAME = "host1"
    $env.SHPOOL_SESSION_NAME = "myproject"
    puts host-info()
')"
assert_contains "myproject" "$result"

start_test "mesh host-info warns with the backend name when not in a session"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
' '
    $env.HOSTNAME = "host1"
    puts host-info()
')"
assert_contains "shpool" "$result"

start_test "mesh host-info falls back to shpool with no backend at all"
result="$(_mesh_run '
    $env.HOSTNAME = "host1"
    puts host-info()
')"
assert_contains "shpool" "$result"

start_test "mesh prompt-line joins host and directory"
result="$(_mesh_run '
    $env.HOSTNAME = "host1"
    str func auth-info() { return "" }
    cd /etc
    puts prompt-line()
')"
assert_contains "host1" "$result"
assert_contains "/etc" "$result"

start_test "mesh prompt-line appends the auth warning"
result="$(_mesh_run '
    $env.HOSTNAME = "host1"
    str func auth-info() { return "SSH" }
    puts prompt-line()
')"
assert_contains "SSH" "$result"

start_test "mesh bar draws a rule of the requested width"
result="$(_mesh_run 'bar 3')"
assert_equal "―――" "$result"

# terminal-width reads $sh.width, which asks stdout, then stderr, then stdin,
# and answers 0 when none of them is a terminal. All three have to be off a
# terminal for the fallback to be the branch under test -- the harness already
# gives stdout a pipe and stdin /dev/null, but stderr is inherited, and a
# developer running the suite from a terminal would otherwise measure their
# own window.
start_test "mesh terminal-width falls back to 80 with no terminal"
result="$(_mesh_run 'puts terminal-width()' 2>/dev/null)"
assert_equal "80" "$result"

start_test "mesh title-text names host and project"
result="$(_mesh_run '
    $env.HOSTNAME = "host1"
    str func projectname() { return "myproject" }
    puts title-text()
')"
assert_equal "host1 myproject" "$result"

start_test "mesh title-text drops the hostname inside tmux"
result="$(_mesh_run '
    $env.HOSTNAME = "host1"
    $env.TMUX = "/tmp/tmux-0/default,1,0"
    str func session-name() { return "sess" }
    str func projectname() { return "myproject" }
    puts title-text()
')"
assert_equal "sess myproject" "$result"

# `title` is mesh's builtin and writes to the terminal rather than stdout, so
# what is assertable here is that both handlers name the window from the same
# builder -- the parity point, since shrc's preprompt and precommand both set
# the context title and neither shows the command line.
start_test "mesh title-idle and title-busy both go through title-text"
result="$(_mesh_run '
    str func title-text() { puts asked; return "the title" }
    title-idle
    title-busy "some command"
')"
assert_equal "asked
asked" "$result"

start_test "mesh job-info is empty with no jobs"
result="$(_mesh_run 'puts "[$(puts job-info())]"')"
assert_equal "[]" "$result"

###############
# TEST: the prompt spends no more VCS forks than fish and nushell do

# A fake `vcs` on PATH that logs every invocation. `dir-info` and `unmerged`
# reach the binary through `command vcs`, which steps past any mesh function of
# that name, so the only way to count the forks is a real executable.
_fake_vcs_bin="$_testdir/fakevcsbin"
mkdir -p "$_fake_vcs_bin"
cat > "$_fake_vcs_bin/vcs" <<EOF
#!/bin/sh
echo "\$@" >> "$_testdir/vcs-calls"
case "\$1" in
    --list-commands) printf 'commit\\ndiffs\\nrootdir\\nstatus\\nabsorb\\n' ;;
    rootdir) echo "$_testdir" ;;
    prompt-info) echo "myproject (main)" ;;
    unmerged) ;;
esac
exit 0
EOF
chmod +x "$_fake_vcs_bin/vcs"

# Run preprompt with the fake vcs on PATH and report which subcommands it ran.
_prompt_vcs_calls() {
    rm -f "$_testdir/vcs-calls"
    PATH="$_fake_vcs_bin:$PATH" _mesh_run_config '
        int func terminal-width() { return 1 }
        str func auth-info() { return "" }
        func maybe-background-fetch(auth = "") { return }
    ' 'preprompt' >/dev/null 2>&1
    sort "$_testdir/vcs-calls" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'
}

# Three, and the third is the window title's. `rootdir` is what names the
# project in the title, and preprompt warms it once so the title hook -- which
# runs after preprompt returns -- reuses it instead of asking again. shrc pays
# the same three: its preprompt calls set_title "$(title)", which reaches
# project_or_pwd -> projectname -> projectroot -> `vcs rootdir`.
start_test "mesh preprompt runs vcs exactly three times, one of them for the title"
result="$(_prompt_vcs_calls)"
assert_equal "prompt-info --color=always rootdir unmerged" "$result"

# The point of the warm cache: the title hook is a second reader of both
# answers, and neither is asked twice in one render.
start_test "mesh a render asks for the session and project names once each"
result="$(_mesh_run '
    str func session-name() { puts asked-session >&2; return "sess" }
    str func projectname() { puts asked-project >&2; return "proj" }
    warm-prompt-cache
    host-info()
    title-text()
    puts done
' 2>&1 | sort | tr '\n' ' ' | sed 's/ $//')"
assert_equal "asked-project asked-session done" "$result"

# Cold -- a test, or a direct call before any prompt has drawn -- asks rather
# than answering from a cache that was never filled.
start_test "mesh prompt-session-name asks when the cache is cold"
result="$(_mesh_run '
    str func session-name() { return "fresh" }
    puts prompt-session-name()
')"
assert_equal "fresh" "$result"

# The command line is the other side of it: once preexec has run, the user's
# own command must see live answers, not the ones the prompt drew with. The
# sharp case is `cd /tmp; puts title-text()` from inside a repository, which
# would otherwise still name the repository it left.
start_test "mesh cool-prompt-cache puts the accessors back on live answers"
result="$(_mesh_run '
    project = "before"
    str func session-name() { return "sess" }
    str func projectname() { return $project }
    warm-prompt-cache
    global project = "after"
    puts prompt-project-name()
    cool-prompt-cache "some command"
    puts prompt-project-name()
')"
assert_equal "before
after" "$result"

# The binary's command is `diffs`, alongside `diffedit` and `diffstat`; there
# is no `diff` in vcs/commands.go, so a `vcs diff` shortcut would just fail.
start_test "mesh diffs runs the plural vcs subcommand"
rm -f "$_testdir/vcs-calls"
PATH="$_fake_vcs_bin:$PATH" _mesh_run_config '' 'set-up-vcs-aliases
    diffs --stat' >/dev/null 2>&1
assert_contains "diffs --stat" "$(cat "$_testdir/vcs-calls")"

###############
# TEST: the vcs shortcuts are generated from the binary

# One alias per name the binary lists, so a subcommand added to vcs is
# reachable without editing this file -- which is what the hand-written list
# could not promise. `absorb` is in the fake's list and was never in that list.
start_test "mesh set-up-vcs-aliases defines an alias per listed subcommand"
result="$(PATH="$_fake_vcs_bin:$PATH" _mesh_run_config '' 'set-up-vcs-aliases
    puts (is-function(commit))
    puts (is-function(absorb))')"
assert_equal "true
true" "$result"

# Each alias carries its own subcommand, baked at the definition: an alias body
# is otherwise syntax read at call time, where the loop variable is long gone.
start_test "mesh generated vcs aliases each run their own subcommand"
rm -f "$_testdir/vcs-calls"
PATH="$_fake_vcs_bin:$PATH" _mesh_run_config '' 'set-up-vcs-aliases
    commit -m one
    absorb' >/dev/null 2>&1
assert_contains "commit -m one" "$(cat "$_testdir/vcs-calls")"
assert_contains "absorb" "$(cat "$_testdir/vcs-calls")"

# `status` is a mesh builtin, so it cannot be bound at all. The generator skips
# it and every other name in the list is still defined.
start_test "mesh set-up-vcs-aliases skips a name mesh owns"
result="$(PATH="$_fake_vcs_bin:$PATH" _mesh_run_config '' 'set-up-vcs-aliases
    puts (is-function(status))')"
assert_equal "false" "$result"

# A shortcut this file defines with behavior of its own keeps it: `rootdir`
# silences stderr, which a plain generated alias would not.
start_test "mesh set-up-vcs-aliases leaves a config function alone"
result="$(PATH="$_fake_vcs_bin:$PATH" _mesh_run_config '' 'set-up-vcs-aliases
    puts rootdir()')"
assert_equal "$_testdir" "$result"

# Nothing to generate from and nothing pretending otherwise.
start_test "mesh set-up-vcs-aliases defines nothing without vcs"
result="$(_mesh_run_config 'func have-command(name) { return false }' 'set-up-vcs-aliases
    puts (is-function(absorb))')"
assert_equal "false" "$result"

# A `vcs` that is present but cannot list its subcommands is reported rather
# than leaving every shortcut quietly undefined.
_fake_badvcs_bin="$_testdir/fakebadvcsbin"
mkdir -p "$_fake_badvcs_bin"
printf '#!/bin/sh\necho "vcs: broken" >&2\nexit 1\n' > "$_fake_badvcs_bin/vcs"
chmod +x "$_fake_badvcs_bin/vcs"

start_test "mesh set-up-vcs-aliases reports a vcs that cannot list its subcommands"
result="$(PATH="$_fake_badvcs_bin:$PATH" _mesh_run_config '' 'set-up-vcs-aliases' 2>&1)"
assert_contains "cannot list the subcommands" "$result"

###############
# TEST: publishing this shell's jobs for a status bar

_jobs_runtime="$_testdir/runtime"

# Only the command word is published, not its arguments -- the same reduction
# shrc's and fish's awk does -- and the line ends in a space with no newline,
# so a consumer can `cat` it straight into a status bar.
start_test "mesh publish-jobs writes a command-word summary"
rm -rf "$_jobs_runtime"
_mesh_run_config "
    \$env.TTY = \"/dev/pts/9\"
    \$env.XDG_RUNTIME_DIR = \"$_jobs_runtime\"
" 'sleep 30 &
sleep 31 &
publish-jobs' >/dev/null 2>&1
result="$(cat "$_jobs_runtime/shell-jobs/dev/pts/9")"
assert_equal "%1 sleep %2 sleep " "$result"

start_test "mesh publish-jobs writes an empty file when nothing is running"
_mesh_run_config "
    \$env.TTY = \"/dev/pts/9\"
    \$env.XDG_RUNTIME_DIR = \"$_jobs_runtime\"
" 'publish-jobs' >/dev/null 2>&1
result="$(cat "$_jobs_runtime/shell-jobs/dev/pts/9")"
assert_equal "" "$result"

start_test "mesh unpublish-jobs removes the file"
_mesh_run_config "
    \$env.TTY = \"/dev/pts/9\"
    \$env.XDG_RUNTIME_DIR = \"$_jobs_runtime\"
" 'unpublish-jobs' >/dev/null 2>&1
test -e "$_jobs_runtime/shell-jobs/dev/pts/9"
assert_equal "1" "$?"

# A failed write leaves a truncated line, which a status bar reads as a real
# job list -- worse than no file at all. Dropped, said once, and publishing
# turned off for the shell: this runs on every prompt, so warning per prompt
# would be worse than the problem. Simulated with a directory at the leaf,
# since these run as root in CI where a permission bit wouldn't stop a write.
start_test "mesh publish-jobs reports a failed write and stops publishing"
rm -rf "$_jobs_runtime"
mkdir -p "$_jobs_runtime/shell-jobs/dev/pts/9"
result="$(_mesh_run_config "
    \$env.TTY = \"/dev/pts/9\"
    \$env.XDG_RUNTIME_DIR = \"$_jobs_runtime\"
" 'publish-jobs
publish-jobs
puts "disabled=$shell-jobs-disabled"' 2>&1)"
# Said once, not twice, for two calls.
assert_equal "1" "$(printf '%s\n' "$result" | grep -c 'publishing is off')"
assert_contains "disabled=true" "$result"

# The flag is this shell's, not the environment's. It used to be an exported
# SHELL_JOBS_DISABLED, which handed the disable to every shell this one started
# -- and, through a daemon's inherited environment, to shpool sessions on
# terminals that could write perfectly well.
start_test "mesh a failed write does not disable publishing for child shells"
rm -rf "$_jobs_runtime"
mkdir -p "$_jobs_runtime/shell-jobs/dev/pts/9"
result="$(_mesh_run_config "
    \$env.TTY = \"/dev/pts/9\"
    \$env.XDG_RUNTIME_DIR = \"$_jobs_runtime\"
" 'publish-jobs
leaked = $env:get(SHELL_JOBS_DISABLED, "no")
puts "leaked=$leaked"' 2>&1)"
assert_contains "leaked=no" "$result"

# No /tmp fallback on purpose: a predictable per-uid path there could be
# pre-created as a symlink for the prompt to truncate on every render.
start_test "mesh publishing is off without XDG_RUNTIME_DIR"
result="$(_mesh_run_config '
    $env.TTY = "/dev/pts/9"
    $env.XDG_RUNTIME_DIR = ""
' 'puts "[$(puts publish-jobs-file())]"')"
assert_equal "[]" "$result"

start_test "mesh publishing is off when TTY is not a device"
result="$(_mesh_run_config "
    \$env.TTY = \"not a tty\"
    \$env.XDG_RUNTIME_DIR = \"$_jobs_runtime\"
" 'puts "[$(puts publish-jobs-file())]"')"
assert_equal "[]" "$result"

start_test "mesh publish-jobs is a no-op with publishing off"
result="$(_mesh_run_config '
    $env.TTY = "not a tty"
    $env.XDG_RUNTIME_DIR = ""
' 'publish-jobs
unpublish-jobs
puts survived' 2>&1)"
assert_equal "survived" "$result"

# The prompt is what keeps the file fresh, so the call has to be in preprompt
# rather than left to the user.
start_test "mesh preprompt publishes the jobs"
rm -rf "$_jobs_runtime"
_mesh_run_config "
    \$env.TTY = \"/dev/pts/9\"
    \$env.XDG_RUNTIME_DIR = \"$_jobs_runtime\"
    int func terminal-width() { return 1 }
    str func auth-info() { return \"\" }
    func maybe-background-fetch(auth = \"\") { return }
" 'sleep 30 &
preprompt' >/dev/null 2>&1
result="$(cat "$_jobs_runtime/shell-jobs/dev/pts/9")"
assert_equal "%1 sleep " "$result"

###############
# TEST: the exit shortcuts and xr

# safe-exit refuses to leave while a job is live, listing the jobs instead --
# shrc:1421's _exit, whose name mesh won't take (a leading underscore is a
# syntax error there).
start_test "mesh safe-exit leaves when nothing is running"
result="$(_mesh_run_config '' 'safe-exit 3
puts "not reached"')"
assert_equal "" "$result"

start_test "mesh safe-exit passes its status through"
_mesh_run_config '' 'safe-exit 3' >/dev/null 2>&1
assert_equal "3" "$?"

# A real background job rather than a stubbed `jobs`: mesh reserves that name,
# so it cannot be replaced from a test.
start_test "mesh safe-exit lists jobs instead of leaving while one is live"
result="$(_mesh_run_config '' 'sleep 30 &
safe-exit
puts "still here"' 2>&1)"
assert_contains "sleep 30" "$result"
assert_contains "still here" "$result"

# `f` reaches mesh's `fg` builtin with no `command` in between -- shrc and fish
# need one only because their own `fg` is a function.
start_test "mesh f reaches the fg builtin"
result="$(_mesh_run_config '' 'f' 2>&1)"
assert_contains "no current job" "$result"

# Being an alias makes it a wrapper, so `--help` reaches fg rather than being
# answered here -- which is also how a job id gets through.
start_test "mesh f forwards --help to fg"
result="$(_mesh_run_config '' 'f --help' 2>&1)"
assert_contains "Usage: fg [JOB]" "$result"

# xa drains suspended jobs with fg first. With none, fg fails immediately and
# the loop ends -- and its "no current job" diagnostic must not reach the user.
start_test "mesh xa exits without complaining when there is nothing to resume"
result="$(_mesh_run_config '' 'xa
puts "not reached"' 2>&1)"
assert_equal "" "$result"

start_test "mesh q is xa"
result="$(_mesh_run_config '
    wrapper func xa(...args) { puts "xa: $args:len" }
' 'q')"
assert_equal "xa: 0" "$result"

start_test "mesh x is xa"
result="$(_mesh_run_config '
    wrapper func safe-exit(...args) { puts "safe-exit: $args:len" }
' 'x')"
assert_equal "safe-exit: 0" "$result"

# xrandr under DISPLAY=:0.0, carried on a `VAR=value cmd` prefix. The prefix
# restores what it found, so the variable must not leak into this shell --
# and an unset one has to go back to *unset*, not to empty, which a child can
# tell apart.
_fake_xrandr_bin="$_testdir/fakexrandrbin"
mkdir -p "$_fake_xrandr_bin"
printf '#!/bin/sh\necho "xrandr: $@ [$DISPLAY]"\n' > "$_fake_xrandr_bin/xrandr"
chmod +x "$_fake_xrandr_bin/xrandr"

start_test "mesh xr runs xrandr with DISPLAY set"
result="$(PATH="$_fake_xrandr_bin:$PATH" _mesh_run_config '' 'xr --query')"
assert_equal "xrandr: --query [:0.0]" "$result"

start_test "mesh xr does not leak DISPLAY into the shell"
result="$(PATH="$_fake_xrandr_bin:$PATH" DISPLAY= _mesh_run_config '' 'xr --query > /dev/null
after = $env:get(DISPLAY, "unset")
puts "[$after]"')"
assert_equal "[]" "$result"

# The inherited-empty case above cannot tell "restored to empty" from
# "restored to unset". With DISPLAY unset on the way in, only the second is
# correct -- an empty one would have xrandr fail against the wrong display
# rather than fall back.
#
# Unset in a subshell rather than trusting the caller's environment: a
# developer running the suite from an X11 session has DISPLAY set, and the
# assertion is about the unset case.
start_test "mesh xr leaves an unset DISPLAY unset"
result="$(unset DISPLAY; PATH="$_fake_xrandr_bin:$PATH" _mesh_run_config '' 'xr --query > /dev/null
after = $env:get(DISPLAY, "unset")
puts "[$after]"')"
assert_equal "[unset]" "$result"

###############
# TEST: ssh-to and the ~/.ssh/config host aliases

# A fake `ssh` that reports its arguments and the forwarded variable. Real
# program, not a mesh function: ssh-to names ssh directly.
_fake_ssh_bin="$_testdir/fakesshbin"
mkdir -p "$_fake_ssh_bin"
printf '#!/bin/sh\necho "ssh: $@ [$LC_CLIENT_HOST]"\n' > "$_fake_ssh_bin/ssh"
chmod +x "$_fake_ssh_bin/ssh"

# `rw` absent is the common case and the one the option handling matters for;
# have-command is replaced so the branch is deterministic either way.
_ssh_run() {
    PATH="$_fake_ssh_bin:$PATH" HOSTNAME=mybox _mesh_run_config '
        bool func have-command(name) { return false if $name == "rw"
            return true }
        str func short-hostname() { return "mybox" }
    ' "$1"
}

start_test "mesh ssh-to forwards this machine's name as LC_CLIENT_HOST"
result="$(_ssh_run 'ssh-to host1')"
assert_equal "ssh: -t -oSendEnv=LC_CLIENT_HOST host1 [mybox]" "$result"

# The whole point of the option scan: ssh flags typed after the host have to
# move in front of it, or ssh runs them as the remote command.
start_test "mesh ssh-to moves trailing flags in front of the host"
result="$(_ssh_run 'ssh-to host1 -v uptime')"
assert_equal "ssh: -t -oSendEnv=LC_CLIENT_HOST -v host1 uptime [mybox]" "$result"

# A flag whose value is a separate word must take the value with it, or the
# host lands where the value belongs (`-p host1`).
start_test "mesh ssh-to keeps a separate-word flag value with its flag"
result="$(_ssh_run 'ssh-to host1 -p 2222 uptime')"
assert_equal "ssh: -t -oSendEnv=LC_CLIENT_HOST -p 2222 host1 uptime [mybox]" "$result"

# `-vp 2222` is `-v -p 2222`: the value-taking letter ends the cluster, so the
# next word is its value. shrc:2502 and config.fish:936 match a single letter
# and build `ssh -vp host1 2222 …`, where ssh reads the host as the port.
start_test "mesh ssh-to keeps a value with a clustered option"
result="$(_ssh_run 'ssh-to host1 -vp 2222 uptime')"
assert_equal "ssh: -t -oSendEnv=LC_CLIENT_HOST -vp 2222 host1 uptime [mybox]" "$result"

# An attached value is already complete, so the next word is the command.
start_test "mesh ssh-to does not take a second value for an attached one"
result="$(_ssh_run 'ssh-to host1 -p2222 uptime')"
assert_equal "ssh: -t -oSendEnv=LC_CLIENT_HOST -p2222 host1 uptime [mybox]" "$result"

# An attached value that happens to end in a value-taking letter is still an
# attached value: `-lBob` ends in `b`, so a prefix of "any letter" read it as a
# cluster and swallowed the command as -b's value.
start_test "mesh ssh-to does not mistake an attached value for a cluster"
result="$(_ssh_run 'ssh-to host1 -lBob uptime')"
assert_equal "ssh: -t -oSendEnv=LC_CLIENT_HOST -lBob host1 uptime [mybox]" "$result"

# The prefix letters must all be flags, so a value-taking letter mid-word ends
# the cluster: `-po` is `-p` with the attached value `o`, not `-p -o`.
start_test "mesh ssh-to ends a cluster at the first value-taking letter"
result="$(_ssh_run 'ssh-to host1 -po uptime')"
assert_equal "ssh: -t -oSendEnv=LC_CLIENT_HOST -po host1 uptime [mybox]" "$result"

start_test "mesh ssh-to still takes a value after a multi-flag cluster"
result="$(_ssh_run 'ssh-to host1 -4tvp 2222 uptime')"
assert_equal "ssh: -t -oSendEnv=LC_CLIENT_HOST -4tvp 2222 host1 uptime [mybox]" "$result"

start_test "mesh ssh-to leaves a valueless short option alone"
result="$(_ssh_run 'ssh-to host1 -4 uptime')"
assert_equal "ssh: -t -oSendEnv=LC_CLIENT_HOST -4 host1 uptime [mybox]" "$result"

start_test "mesh ssh-to rotates -- in front of the host too"
result="$(_ssh_run 'ssh-to host1 -- ls -l')"
assert_equal "ssh: -t -oSendEnv=LC_CLIENT_HOST -- host1 ls -l [mybox]" "$result"

start_test "mesh ssh-to stops scanning at the remote command"
result="$(_ssh_run 'ssh-to host1 uptime -l')"
assert_equal "ssh: -t -oSendEnv=LC_CLIENT_HOST host1 uptime -l [mybox]" "$result"

start_test "mesh ssh-to uses rw for a bare host when it is installed"
result="$(PATH="$_fake_ssh_bin:$PATH" _mesh_run_config '
    bool func have-command(name) { return true }
    str func short-hostname() { return "mybox" }
    wrapper func rw(...args) { puts rw: ...$args }
' 'ssh-to host1')"
assert_equal "rw: -r host1" "$result"

# Host names here are placeholders, not anyone's real config.
_ssh_config_home="$_testdir/sshhome"
_write_ssh_config() {
    rm -rf "$_ssh_config_home"
    mkdir -p "$_ssh_config_home/.ssh"
    cat > "$_ssh_config_home/.ssh/config" <<'EOF'
Host host1 host2
    User someone
Host *.example
Host neg-ated
Host dotted.name
host host3
EOF
}

# Run a snippet with the ssh config in place and the aliases already defined.
_ssh_aliases_run() {
    HOME="$_ssh_config_home" run_with_timeout 15 mesh -c "
        source $_env_mesh
        source $_rc_mesh
        set-up-ssh-aliases
        $1
" </dev/null 2>&1
}

start_test "mesh set-up-ssh-aliases defines an alias per usable Host entry"
_write_ssh_config
result="$(_ssh_aliases_run 'puts (is-function(host1)) (is-function(host2)) (is-function(host3))')"
assert_equal "true true true" "$result"

# A pattern, a negation and a dotted name are not hosts to connect to.
start_test "mesh set-up-ssh-aliases skips patterns, negations and dotted names"
result="$(_ssh_aliases_run 'puts (is-function(neg-ated))')"
assert_equal "false" "$result"

# The property the whole thing exists for: each alias carries *its own* host,
# baked at the definition. An alias body is otherwise syntax read at call time,
# where the loop variable is long gone.
start_test "mesh ssh host aliases each connect to their own host"
result="$(_ssh_aliases_run "func ssh-to(...args) { puts to: ...\$args }
        host1
        host2
        host3")"
assert_equal "to: host1
to: host2
to: host3" "$result"

# A `Host status` must not take over the `status` shortcut. shrc and fish get
# this from ordering -- ssh aliases first, shortcut block after -- which isn't
# available here, since the shortcuts are file-scope definitions above the
# interactive section. Skipping an existing function states the same rule.
start_test "mesh ssh aliases do not shadow a config shortcut"
rm -rf "$_ssh_config_home"
mkdir -p "$_ssh_config_home/.ssh"
printf 'Host status host1\n' > "$_ssh_config_home/.ssh/config"
result="$(_ssh_aliases_run "func ssh-to(...args) { puts to: ...\$args }
        host1")"
assert_equal "to: host1" "$result"

# And the shortcut that survives still reaches vcs: `status` is mesh's own
# builtin now, so `st` is what carries the vcs spelling.
start_test "mesh st still reaches vcs after the ssh aliases load"
result="$(PATH="$_fake_vcs_bin:$PATH" HOME="$_ssh_config_home" run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    set-up-ssh-aliases
    st
" </dev/null 2>&1)"
assert_equal "" "$result"
assert_contains "status" "$(cat "$_testdir/vcs-calls")"

start_test "mesh ssh aliases may still shadow a program name"
rm -rf "$_ssh_config_home"
mkdir -p "$_ssh_config_home/.ssh"
printf 'Host ls\n' > "$_ssh_config_home/.ssh/config"
result="$(_ssh_aliases_run 'puts (is-function(ls))')"
assert_equal "true" "$result"

# is-shell-name must catch every class of name mesh owns: keywords and
# builtins via `type -t`, and built-in value calls (invisible to -t, whose
# findings are not usable as commands) via the descriptive form.
start_test "mesh is-shell-name catches a built-in value call"
result="$(_mesh_run_config '' 'puts is-shell-name(files)')"
assert_equal "true" "$result"

start_test "mesh is-shell-name passes an ordinary host name"
result="$(_mesh_run_config '' 'puts is-shell-name(host1)')"
assert_equal "false" "$result"

# `files` is a built-in value call, so mesh refuses to bind it. The refusal now
# costs that name alone -- the loop carries on and every other host is still
# defined, where the generated file used to lose all of them together.
start_test "mesh ssh aliases skip a name mesh cannot bind"
rm -rf "$_ssh_config_home"
mkdir -p "$_ssh_config_home/.ssh"
printf 'Host files host1\n' > "$_ssh_config_home/.ssh/config"
result="$(_ssh_aliases_run 'puts (is-function(host1))')"
assert_equal "true" "$result"

start_test "mesh ssh aliases survive a Host mesh cannot bind"
result="$(PATH="$_fake_ssh_bin:$PATH" HOME="$_ssh_config_home" HOSTNAME=mybox \
    run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    set-up-ssh-aliases
    host1 uptime
" </dev/null 2>&1)"
assert_equal "ssh: -t -oSendEnv=LC_CLIENT_HOST host1 uptime [mybox]" "$result"

# A reserved word is the milder flavor -- a runtime error rather than a syntax
# one -- but it still cannot be defined, so it is skipped by the same rule.
start_test "mesh ssh aliases skip a reserved word"
rm -rf "$_ssh_config_home"
mkdir -p "$_ssh_config_home/.ssh"
printf 'Host source host1\n' > "$_ssh_config_home/.ssh/config"
result="$(_ssh_aliases_run 'puts (is-function(host1))')"
assert_equal "true" "$result"

start_test "mesh ssh host aliases forward every argument to ssh-to"
_write_ssh_config
result="$(PATH="$_fake_ssh_bin:$PATH" HOME="$_ssh_config_home" HOSTNAME=mybox \
    run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    bool func have-command(name) { return false if \$name == \"rw\"
        return true }
    str func short-hostname() { return \"mybox\" }
    set-up-ssh-aliases
    host1 --unknown-flag
" </dev/null 2>&1)"
assert_equal "ssh: -t -oSendEnv=LC_CLIENT_HOST --unknown-flag host1 [mybox]" "$result"

# The config passed the is-it-a-file test and then failed to read anyway --
# permissions changed since, an I/O error. A failing capture in a `for` head
# iterates nothing and carries on, so without the check every host alias would
# be silently missing, looking exactly like a config with no Host entries.
#
# A fake `cat` rather than a chmod, so the test does not depend on the uid it
# runs as: root reads a 0000 file regardless of mode, which would make this
# skip exactly where it is most likely to be run.
_fake_cat_bin="$_testdir/fakecatbin"
mkdir -p "$_fake_cat_bin"
printf '#!/bin/sh\necho "cat: cannot read" >&2\nexit 1\n' > "$_fake_cat_bin/cat"
chmod +x "$_fake_cat_bin/cat"

start_test "mesh set-up-ssh-aliases reports an unreadable ssh config"
_write_ssh_config
result="$(HOME="$_ssh_config_home" PATH="$_fake_cat_bin:$PATH" run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    set-up-ssh-aliases
    puts \"status=\$sh.status\"
    host1
" </dev/null 2>&1)"
assert_contains "cannot read the ssh config" "$result"
assert_contains "status=1" "$result"
assert_contains "command not found: host1" "$result"

start_test "mesh set-up-ssh-aliases reads a config under a path with a space"
_ssh_spaced_home="$_testdir/ssh home"
rm -rf "$_ssh_spaced_home"
mkdir -p "$_ssh_spaced_home/.ssh"
printf 'Host host1\n' > "$_ssh_spaced_home/.ssh/config"
result="$(HOME="$_ssh_spaced_home" run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    set-up-ssh-aliases
    puts (is-function(host1))
" </dev/null 2>&1)"
assert_equal "true" "$result"

start_test "mesh set-up-ssh-aliases does nothing without an ssh config"
rm -rf "$_ssh_config_home"
mkdir -p "$_ssh_config_home"
HOME="$_ssh_config_home" run_with_timeout 15 mesh -c "
    source $_env_mesh
    source $_rc_mesh
    set-up-ssh-aliases
    puts survived
" </dev/null 2>&1 | grep -q survived
assert_equal "0" "$?"

###############
# TEST: clone picks the VCS from the URL

# Real programs on PATH rather than mesh functions: `clone` names jj/git/hg
# directly, and the point of the test is which one it reached.
_fake_clone_bin="$_testdir/fakeclonebin"
mkdir -p "$_fake_clone_bin"
for _prog in jj git hg; do
    printf '#!/bin/sh\necho "%s: $@"\n' "$_prog" > "$_fake_clone_bin/$_prog"
    chmod +x "$_fake_clone_bin/$_prog"
done

start_test "mesh clone prefers jj for a git URL"
result="$(PATH="$_fake_clone_bin:$PATH" _mesh_run_config '' 'clone https://example.invalid/repo.git')"
assert_equal "jj: git clone https://example.invalid/repo.git" "$result"

start_test "mesh clone forwards flags that follow the URL"
result="$(PATH="$_fake_clone_bin:$PATH" _mesh_run_config '' 'clone https://example.invalid/r.git --depth 1')"
assert_equal "jj: git clone https://example.invalid/r.git --depth 1" "$result"

# The URL has to come first, since it is what picks the VCS. shrc's `case "$1"`
# and nushell's `url: string` require the same, so this asserts the shared
# contract rather than a mesh limitation.
start_test "mesh clone does nothing when a flag precedes the URL"
result="$(PATH="$_fake_clone_bin:$PATH" _mesh_run_config '' 'clone --depth 1 https://example.invalid/r.git' 2>&1)"
assert_equal "" "$result"

start_test "mesh clone falls back to git when the user agrees"
result="$(PATH="$_fake_clone_bin:$PATH" _mesh_run_config '
    bool func have-command(name) { return false if $name == "jj"
        return true }
    wrapper func confirm(...q) { return true }
' 'clone https://example.invalid/repo.git')"
assert_equal "git: clone https://example.invalid/repo.git" "$result"

start_test "mesh clone does nothing when the user declines the git fallback"
result="$(PATH="$_fake_clone_bin:$PATH" _mesh_run_config '
    bool func have-command(name) { return false if $name == "jj"
        return true }
    wrapper func confirm(...q) { return false }
' 'clone https://example.invalid/repo.git')"
assert_equal "" "$result"

start_test "mesh clone uses hg for an hg URL"
result="$(PATH="$_fake_clone_bin:$PATH" _mesh_run_config '' 'clone https://example.invalid/hg/repo')"
assert_equal "hg: clone https://example.invalid/hg/repo" "$result"

# Neither pattern matches, so nothing is cloned -- same as the other three,
# which all fall off the end of their case/switch/if without a default.
start_test "mesh clone runs nothing for a URL matching neither VCS"
result="$(PATH="$_fake_clone_bin:$PATH" _mesh_run_config '' 'clone https://example.invalid/plain')"
assert_equal "" "$result"

start_test "mesh dir-info renders what vcs prompt-info prints"
result="$(PATH="$_fake_vcs_bin:$PATH" _mesh_run_config '' 'puts dir-info()')"
assert_equal "myproject (main)" "$result"

start_test "mesh dir-info falls back to the working directory with no vcs"
result="$(_mesh_run '
    cd /etc
    puts dir-info()
')"
assert_equal "/etc" "$result"

start_test "mesh preprompt shows what unmerged prints"
# shrc redirects only stderr; the warning itself belongs on the prompt block.
result="$(PATH="$_fake_vcs_bin:$PATH" _mesh_run_config '
    int func terminal-width() { return 1 }
    str func auth-info() { return "" }
    func maybe-background-fetch(auth = "") { return }
    func unmerged() { puts "2 unmerged branches" }
' 'preprompt' 2>/dev/null)"
assert_contains "2 unmerged branches" "$result"

###############
# TEST: maybe-background-fetch gating

# Report which vcs subcommands the given maybe-background-fetch calls spawn.
_fetch_vcs_calls() {
    : > "$_testdir/vcs-calls"
    PATH="$_fake_vcs_bin:$PATH" _mesh_run_config '' "$1" >/dev/null 2>&1
    tr '\n' ' ' < "$_testdir/vcs-calls" | sed 's/ $//'
}

# A failed spawn leaves the directory uncached, so the next prompt tries again
# rather than silently giving up on it for the rest of the session.
start_test "mesh maybe-background-fetch retries after a failed spawn"
_fake_failing_vcs="$_testdir/failingvcsbin"
mkdir -p "$_fake_failing_vcs"
cat > "$_fake_failing_vcs/vcs" <<EOF
#!/bin/sh
echo "\$@" >> "$_testdir/vcs-calls"
exit 1
EOF
chmod +x "$_fake_failing_vcs/vcs"
: > "$_testdir/vcs-calls"
PATH="$_fake_failing_vcs:$PATH" _mesh_run_config '' '
    maybe-background-fetch ""
    maybe-background-fetch ""
' >/dev/null 2>&1
assert_equal "2" "$(grep -c auto-fetch "$_testdir/vcs-calls")"

start_test "mesh maybe-background-fetch fetches once per directory"
result="$(_fetch_vcs_calls '
    maybe-background-fetch ""
    maybe-background-fetch ""
')"
assert_equal "auto-fetch" "$result"

start_test "mesh maybe-background-fetch skips while something needs auth"
result="$(_fetch_vcs_calls 'maybe-background-fetch "SSH"')"
assert_equal "" "$result"

# The directory must not be recorded by a call the auth gate turned away, or
# the fetch would never happen in that directory once the user authenticates.
start_test "mesh maybe-background-fetch retries after authenticating"
result="$(_fetch_vcs_calls '
    maybe-background-fetch "SSH"
    maybe-background-fetch ""
')"
assert_equal "auto-fetch" "$result"

###############
# TEST: is-ssh-valid reads ssh-add's exit status
#
# Every other auth test stubs auth-info, so the real is-ssh-valid was never run
# and a `quiet ssh-add -L` that stopped working went unnoticed: mesh reads no
# int as a condition, and the version of this that yielded one drew the prompt
# anyway while complaining to stderr. A fake ssh-add whose status the test picks
# is what exercises the branch for real. The fake itself is built further up,
# where the return-type audit needs it first.

start_test "mesh is-ssh-valid is true when ssh-add lists a key"
result="$(PATH="$_fake_ssh_add_bin:$PATH" FAKE_SSH_ADD_STATUS=0 _mesh_run_config '' \
    'if is-ssh-valid() { puts valid } else { puts invalid }' 2>&1)"
assert_equal "valid" "$result"

start_test "mesh is-ssh-valid is false when ssh-add has no key"
result="$(PATH="$_fake_ssh_add_bin:$PATH" FAKE_SSH_ADD_STATUS=1 _mesh_run_config '' \
    'if is-ssh-valid() { puts valid } else { puts invalid }' 2>&1)"
assert_equal "invalid" "$result"

# The code itself, not just its truthiness. auth-info runs is-ssh-valid under
# `timeout` and treats the 124 as a failed check, so the status has to arrive
# as ssh-add left it; a translation to a bool somewhere in here would still
# pass the true/false cases above while flattening this one to 1.
start_test "mesh is-ssh-valid forwards ssh-add's exit code unchanged"
result="$(PATH="$_fake_ssh_add_bin:$PATH" FAKE_SSH_ADD_STATUS=124 _mesh_run_config '' \
    'puts is-ssh-valid()' 2>&1)"
assert_equal "124" "$result"

# The regression itself: the int-as-condition refusal went to stderr while the
# prompt still drew, so asserting on the return value alone would not have
# caught it.
start_test "mesh is-ssh-valid does not report an int as a condition"
result="$(PATH="$_fake_ssh_add_bin:$PATH" FAKE_SSH_ADD_STATUS=1 _mesh_run_config '' \
    'auth-info' 2>&1 | grep -c 'not a condition' || true)"
assert_equal "0" "$result"

start_test "mesh auth-info names SSH when no key is loaded"
result="$(PATH="$_fake_ssh_add_bin:$PATH" FAKE_SSH_ADD_STATUS=1 _mesh_run_config '' \
    'puts auth-info()' 2>&1)"
assert_equal "SSH" "$result"

start_test "mesh auth-info is empty when a key is loaded"
result="$(PATH="$_fake_ssh_add_bin:$PATH" FAKE_SSH_ADD_STATUS=0 _mesh_run_config '' \
    'puts auth-info()' 2>&1)"
assert_equal "" "$result"

###############
# The hang the two limits exist to stop: a stale $SSH_AUTH_SOCK leaves
# `ssh-add -L` waiting on a socket nobody answers, and the prompt runs it on
# every render.
_hanging_ssh_add_bin="$_testdir/hangingsshaddbin"
mkdir -p "$_hanging_ssh_add_bin"
printf '#!/bin/sh\nsleep 30\nexit 0\n' > "$_hanging_ssh_add_bin/ssh-add"
chmod +x "$_hanging_ssh_add_bin/ssh-add"

# Unbounded, the stub outlives the limit and then *succeeds*, so auth-info
# would report no problem at all; bounded, the check is abandoned and the
# prompt says SSH. `timeout` reports 124, which is a failed check either way.
start_test "mesh auth-info names SSH when ssh-add outlives the limit"
result="$(PATH="$_hanging_ssh_add_bin:$PATH" SSH_VALID_TIMEOUT=0.3 _mesh_run_config '' \
    'puts auth-info()' 2>&1)"
assert_equal "SSH" "$result"

# The point of the limit is that it comes back, not just that it answers. The
# stub sleeps 30s against a 0.3s limit, so the margin here is the whole gap
# rather than a tuned threshold.
start_test "mesh auth-info returns before a hanging ssh-add would have"
_started="$(date +%s)"
PATH="$_hanging_ssh_add_bin:$PATH" SSH_VALID_TIMEOUT=0.3 _mesh_run_config '' \
    'puts auth-info()' >/dev/null 2>&1
assert_true test "$(($(date +%s) - _started))" -lt 10

# An unset or empty setting takes the default; anything else goes to `timeout`
# as written.
start_test "mesh check-limit reads a plain number of seconds"
result="$(SSH_VALID_TIMEOUT=0.5 _mesh_run_config '' \
    'l = check-limit("SSH_VALID_TIMEOUT", "2")
puts $l' 2>&1)"
assert_equal "0.5" "$result"

start_test "mesh check-limit falls back when the setting is empty"
result="$(SSH_VALID_TIMEOUT= _mesh_run_config '' \
    'l = check-limit("SSH_VALID_TIMEOUT", "2")
puts $l' 2>&1)"
assert_equal "2" "$result"

# auth-info is a hook ~/.rc.local.mesh can replace outright, and an override
# that checks Kerberos or AWS SSO is exactly the sort that blocks -- so the
# prompt calls it through a limit of its own. All this outer one can say is
# that something took too long.
start_test "mesh bounded-auth-info bounds an overridden auth-info hook"
result="$(AUTH_TIMEOUT=0.3 _mesh_run_config '
    str func auth-info() { sleep 30; return "" }
' 'a = bounded-auth-info()
puts $a' 2>&1)"
assert_equal "auth" "$result"

# The outer backstop must not steal the ordinary case's precise answer: the
# inner limit is the shorter one, so it fires first and the prompt still names
# SSH rather than the vaguer `auth`.
start_test "mesh bounded-auth-info still says SSH when ssh-add is the slow part"
result="$(PATH="$_hanging_ssh_add_bin:$PATH" SSH_VALID_TIMEOUT=0.3 AUTH_TIMEOUT=5 \
    _mesh_run_config '' 'a = bounded-auth-info()
puts $a' 2>&1)"
assert_equal "SSH" "$result"

# Whatever the hook reports travels back out of the fork it ran in.
start_test "mesh bounded-auth-info reports what the hook said"
result="$(_mesh_run_config '
    str func auth-info() { return "KRB AWS" }
' 'a = bounded-auth-info()
puts $a' 2>&1)"
assert_equal "KRB AWS" "$result"

start_test "mesh bounded-auth-info is empty when the hook reports nothing"
result="$(_mesh_run_config '
    str func auth-info() { return "" }
' 'a = bounded-auth-info()
puts "<$a>"' 2>&1)"
assert_equal "<>" "$result"

# A hook that raises rather than answering -- a missing Kerberos or AWS helper,
# a bad `$env` read -- comes back empty with a nonzero status, which is not the
# limit's 124. Read as an empty answer it would tell the prompt all is well on
# the strength of a check that never ran, and maybe-background-fetch would
# fetch as though authenticated.
start_test "mesh bounded-auth-info reports a hook that failed without answering"
result="$(_mesh_run_config '
    str func auth-info() { return $env.DEFINITELY_NOT_SET }
' 'a = bounded-auth-info()
puts $a' 2>/dev/null)"
assert_equal "auth" "$result"

start_test "mesh need-auth is true when the hook could not answer"
result="$(_mesh_run_config '
    str func auth-info() { return $env.DEFINITELY_NOT_SET }
' 'if need-auth() { puts needed } else { puts fine }' 2>/dev/null)"
assert_equal "needed" "$result"

# The other direction: an authenticated session must not run `auth` at startup.
start_test "mesh need-auth is false when the hook has nothing to report"
result="$(_mesh_run_config '
    str func auth-info() { return "" }
' 'if need-auth() { puts needed } else { puts fine }' 2>/dev/null)"
assert_equal "fine" "$result"

# The startup gate at the foot of rc.mesh runs before any prompt, so it needs
# the bounded accessor too -- an override that blocks would otherwise hang the
# shell before it drew anything.
start_test "mesh need-auth goes through the limit"
result="$(AUTH_TIMEOUT=0.3 _mesh_run_config '
    str func auth-info() { sleep 30; return "" }
' 'if need-auth() { puts needed } else { puts fine }' 2>&1)"
assert_equal "needed" "$result"

###############
# is-ssh-valid forks `ssh-add -L`, so preprompt asks once and hands the answer
# to both maybe-background-fetch and prompt-line.
#
# Counted in a file rather than in a shell global: bounded-auth-info runs the
# hook under `timeout`, which is a fork, so an increment made there dies with
# it.
start_test "mesh preprompt asks auth-info once per render"
_auth_calls="$_testdir/auth-calls"
rm -f "$_auth_calls"
PATH="$_fake_vcs_bin:$PATH" _mesh_run_config "
    int func terminal-width() { return 1 }
    str func auth-info() {
        puts asked >> $_auth_calls
        return \"\"
    }
" 'preprompt' >/dev/null 2>&1
assert_equal "1" "$(wc -l < "$_auth_calls" | tr -d ' ')"

###############
# TEST: i-am-root reads $UID rather than forking

# `UID` is readonly in bash, so it is handed to the child through `env` rather
# than a variable assignment prefix.
_run_with_uid() {
    HOME="$_fakehome" run_with_timeout 15 env "UID=$1" mesh -c "
        source $_env_mesh
        source $_rc_mesh
        puts i-am-root():repr
    " </dev/null
}

start_test "mesh i-am-root answers from \$UID"
assert_equal "true" "$(_run_with_uid 0)"
assert_equal "false" "$(_run_with_uid 1000)"

# `id` is a fork and i-am-root runs on every prompt, where bash, zsh and fish
# read their own $UID for free. Count the calls rather than trust the code:
# env.mesh only computes UID when it isn't already set, so a preset one means
# no `id -u` anywhere in a session.
_fake_id_bin="$_testdir/fakeidbin"
mkdir -p "$_fake_id_bin"
cat > "$_fake_id_bin/id" <<EOF
#!/bin/sh
echo "\$@" >> "$_testdir/id-calls"
exec /usr/bin/id "\$@"
EOF
chmod +x "$_fake_id_bin/id"

start_test "mesh i-am-root forks no id when \$UID is set"
rm -f "$_testdir/id-calls"
HOME="$_fakehome" run_with_timeout 15 \
    env "PATH=$_fake_id_bin:$PATH" UID=1000 USERNAME=someone mesh -c "
        source $_env_mesh
        source $_rc_mesh
        puts i-am-root():repr
        puts i-am-root():repr
        puts i-am-root():repr
    " </dev/null >/dev/null 2>&1
assert_equal "" "$(cat "$_testdir/id-calls" 2>/dev/null)"

# With UID *unset* -- a login mesh with no POSIX parent to inherit one from --
# env.mesh has to compute it, and `$sh.uid` is what it asks instead of forking.
# USERNAME is preset so the `id -un` beside it does not muddy the count; the
# assertion is about `id -u` specifically.
start_test "mesh env.mesh forks no id for an unset \$UID"
rm -f "$_testdir/id-calls"
HOME="$_fakehome" run_with_timeout 15 \
    env -u UID "PATH=$_fake_id_bin:$PATH" USERNAME=someone HOSTNAME=host1 mesh -c "
        source $_env_mesh
        puts \$env.UID
    " </dev/null >/dev/null 2>&1
assert_equal "" "$(cat "$_testdir/id-calls" 2>/dev/null)"

start_test "mesh env.mesh sets \$UID from \$sh.uid when it is unset"
result="$(HOME="$_fakehome" run_with_timeout 15 \
    env -u UID USERNAME=someone HOSTNAME=host1 mesh -c "
        source $_env_mesh
        puts \$env.UID
    " </dev/null)"
assert_equal "$(id -u)" "$result"

###############
# TEST: log-history

start_test "mesh log-history appends to HISTORY_FILE"
result="$(_mesh_run '
    $env.HISTORY_FILE = "$env.HOME/history-test"
    log-history "hello world"
    cat $env.HISTORY_FILE
')"
assert_contains "hello world" "$result"

start_test "mesh log-history is a no-op with no HISTORY_FILE"
result="$(_mesh_run '
    $env.HISTORY_FILE = ""
    log-history "ignored"
    puts done
')"
assert_equal "done" "$result"

###############
# TEST: env.mesh environment

start_test "mesh env.mesh exports an editor and a pager"
result="$(_mesh_run '
    if $env:get(EDITOR, "") != "" { puts editor }
    if $env:get(PAGER, "") != "" { puts pager }
')"
assert_contains "editor" "$result"
assert_contains "pager" "$result"

start_test "mesh env.mesh sets the grep and block-size defaults"
result="$(_mesh_run 'puts $env.GREP_COLORS $env.BLOCKSIZE')"
assert_equal "mt=4 1024" "$result"

start_test "mesh env.mesh picks light-background ls colors by default"
result="$(HOME="$_fakehome" TERM=xterm-256color run_with_timeout 15 mesh -c "
    source $_env_mesh
    puts \$env.LSCOLORS
" </dev/null)"
assert_equal "exfxxxxxcxxxxx" "$result"

start_test "mesh env.mesh picks dark-background ls colors on a linux console"
result="$(HOME="$_fakehome" TERM=linux run_with_timeout 15 mesh -c "
    source $_env_mesh
    puts \$env.LSCOLORS
" </dev/null)"
assert_equal "ExFxxxxxCxxxxx" "$result"

start_test "mesh env.mesh keeps an inherited GOPATH"
result="$(HOME="$_fakehome" GOPATH=/somewhere/else run_with_timeout 15 mesh -c "
    source $_env_mesh
    puts \$env.GOPATH
" </dev/null)"
assert_equal "/somewhere/else" "$result"

start_test "mesh env.mesh defaults GOPATH to \$HOME"
result="$(HOME="$_fakehome" GOPATH= run_with_timeout 15 mesh -c "
    source $_env_mesh
    puts \$env.GOPATH
" </dev/null)"
assert_equal "$_fakehome" "$result"

start_test "mesh env.mesh sets HISTORY_FILE under HOME"
result="$(_mesh_run 'puts $env.HISTORY_FILE')"
assert_equal "$_fakehome/.history" "$result"

start_test "mesh env.mesh failsafe skips the environment setup"
result="$(HOME="$_fakehome" FAILSAFE=1 run_with_timeout 15 env -u GREP_COLORS mesh -c "
    source $_env_mesh
    puts \$env:get(GREP_COLORS, \"(unset)\")
" 2>/dev/null </dev/null)"
assert_equal "(unset)" "$result"

###############
# TEST: rc.mesh is definitions only until its interactive section

start_test "mesh rc.mesh starts no session when not interactive"
result="$(_mesh_run_config '
    bool func have-command(name) { return true }
    bool func stdin-is-tty() { return true }
    bool func inside-project() { return true }
    func autoshpool(...args) { puts "autoshpool ran" }
' 'puts done')"
assert_equal "done" "$result"

###############
# TEST: rerc stops when the environment half fails

# `source` sets the status and keeps going, so an env.mesh that no longer parses
# would be followed by an rc.mesh that does, and rerc would report success over
# a half-reloaded shell.
_rerc_home="$_testdir/rerchome"
rm -rf "$_rerc_home"
mkdir -p "$_rerc_home/.config/mesh"
printf 'puts "rc.mesh was read"\n' > "$_rerc_home/.config/mesh/rc.mesh"

start_test "mesh rerc does not read rc.mesh when env.mesh fails"
printf 'this is not( valid mesh\n' > "$_rerc_home/.config/mesh/env.mesh"
result="$(_mesh_run "\$env.HOME = \"$_rerc_home\"
    rerc
    puts \"status=\$sh.status\"" 2>&1)"
assert_contains "env.mesh failed" "$result"
# Not a literal status: mesh's own is passed through (2 for a syntax error, 127
# for a missing file) rather than flattened, so only "not success" is asserted.
assert_not_contains "status=0" "$result"
assert_not_contains "rc.mesh was read" "$result"

start_test "mesh rerc reads both halves when env.mesh is fine"
printf 'puts "env.mesh was read"\n' > "$_rerc_home/.config/mesh/env.mesh"
result="$(_mesh_run "\$env.HOME = \"$_rerc_home\"
    rerc" 2>&1)"
assert_equal "env.mesh was read
rc.mesh was read" "$result"

###############
# TEST: emacs stays in the terminal

_fake_emacs_bin="$_testdir/fakeemacsbin"
mkdir -p "$_fake_emacs_bin"
printf '#!/bin/sh\necho "emacs: $*"\n' > "$_fake_emacs_bin/emacs"
chmod +x "$_fake_emacs_bin/emacs"

start_test "mesh emacs runs in terminal mode"
result="$(PATH="$_fake_emacs_bin:$PATH" _mesh_run_config '' 'emacs file.txt')"
assert_equal "emacs: --no-window-system file.txt" "$result"

###############
# PERFORMANCE
# prompt-line runs on every prompt, so its cost matters. The bash suite times
# 50 calls with `vcs prompt-info` stubbed (shrc_prompt_test.sh:1052); this is
# the mesh equivalent, and the same 1000ms budget. Timing the loop *inside*
# mesh rather than around it keeps the ~100ms interpreter startup out of the
# measurement -- otherwise the budget would mostly be measuring `mesh -c`.
#
# The stubs are what make this a composition measurement rather than a fork
# measurement: auth-info and prompt-info are the two `vcs`/`ssh-add` forks a
# real render pays, and they are replaced so what is left is host-info,
# dir-info, the styling and the string building.

start_test "mesh prompt-line within ${_mesh_prompt_budget_ms:=${PROMPT_PERF_BUDGET_MS:-1000}}ms budget"
result="$(_mesh_run '
    $env.HOSTNAME = "host1"
    str func auth-info() { return "" }
    func prompt-info() { return "proj main" }
    # Warmup, so first-call variance stays out of the timed loop.
    prompt-line()
    start = $(date +%s%N)
    i = 0
    while $i < 50 {
      prompt-line()
      i = $i + 1
    }
    end = $(date +%s%N)
    puts (($end:int - $start:int) / 1000000)
' 2>/dev/null)"
case "$result" in
    ''|*[!0-9]*) skip_block "mesh prompt-line perf check: date +%s%N unavailable" ;;
    *)
        echo "  50 x prompt-line (mesh compose): ${result}ms (budget ${_mesh_prompt_budget_ms}ms)"
        if test "$_mesh_prompt_budget_ms" -gt 0; then
            assert_true test "$result" -le "$_mesh_prompt_budget_ms"
        fi
        ;;
esac

# The other half of a render, and the one the compose measurement above cannot
# reach: inside tmux the context line and the window title both want the
# session and project names, and both answers are forks. This times the pair
# with real stub binaries on PATH -- so the number is fork cost, not string
# building -- and again inside mesh, keeping interpreter startup out of it.
#
# Reported, not asserted. This one measures process spawns -- 50 with the cache
# warm, 100 without -- where the compose benchmark above measures interpretation
# with its forks stubbed out, so its wall clock is at the mercy of whatever else
# the machine is doing: the same run here has come back at 195ms and at 660ms on
# a loaded box. A budget over that spread would be too loose to catch anything
# and a tight one would just flake, so the *shape* is guarded deterministically
# instead, by "a render asks for the session and project names once each" above.
# This number is here to be read when the prompt path changes.
_fake_tmux_bin="$_testdir/fake-tmux-bin"
mkdir -p "$_fake_tmux_bin"
cat > "$_fake_tmux_bin/tmux" <<'EOF'
#!/bin/sh
echo mysession
EOF
chmod +x "$_fake_tmux_bin/tmux"

start_test "mesh render inside tmux reports its timing"
result="$(PATH="$_fake_tmux_bin:$_fake_vcs_bin:$PATH" TMUX="/tmp/tmux-0/default,1,0" _mesh_run '
    $env.HOSTNAME = "host1"
    warm-prompt-cache
    host-info()
    title-text()
    start = $(date +%s%N)
    i = 0
    while $i < 50 {
      warm-prompt-cache
      host-info()
      title-text()
      i = $i + 1
    }
    end = $(date +%s%N)
    puts (($end:int - $start:int) / 1000000)
' 2>/dev/null)"
case "$result" in
    ''|*[!0-9]*) skip_block "mesh tmux render perf check: date +%s%N unavailable" ;;
    *)
        echo "  50 x render inside tmux (host-info + title): ${result}ms"
        assert_true test "$result" -ge 0
        ;;
esac

test_summary "mesh_test"
