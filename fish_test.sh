#!/bin/bash
#
# Tests for non-prompt helpers in config/fish/config.fish.
# Mirrors shrc_test.sh but exercises the fish implementation via
# `fish -c`. Skips gracefully when fish is not installed.
#

. "$(dirname "$0")/shrc_test_lib.sh"

if ! command -v fish >/dev/null 2>&1; then
    skip_all "fish not installed"
    test_summary "fish_test"
    exit 0
fi

_config="$_srcdir/config/fish/config.fish"

# Run a fish snippet with config.fish preloaded. Uses a fake HOME so
# config.fish's interactive setup (history file, ssh alias parsing,
# shpool startup) runs against a clean workspace. The have_command stub
# runs AFTER source so it overrides any definition config.fish installs.
_fish_run() {
    _fish_run_config "" '
        function have_command
            switch $argv[1]
                case shpool autoshpool brew yum apt-get; return 1
                case "*"; command -v $argv[1] >/dev/null 2>&1
            end
        end
    ' "$1"
}

###############
# TEST: log_history writes to HISTORY_FILE

start_test "fish log_history writes argv to HISTORY_FILE"
result="$(_fish_run '
    set -g HISTORY_FILE $HOME/history-test
    log_history "hello world"
    cat $HISTORY_FILE
')"
assert_contains "hello world" "$result"

start_test "fish log_history no-op when HISTORY_FILE empty"
result="$(_fish_run '
    set -g HISTORY_FILE ""
    log_history "ignored"
    echo done
')"
assert_equal "done" "$result"

###############
# TEST: shift_options moves leading -x options past the target argument

start_test "fish shift_options moves leading options past target"
result="$(_fish_run '
    function fake_ssh
        printf "%s\n" $argv
    end
    shift_options fake_ssh target -t -v
')"
expected="-t
-v
target"
assert_equal "$expected" "$result"

start_test "fish shift_options leaves positional args alone"
result="$(_fish_run '
    function fake_ssh
        printf "%s\n" $argv
    end
    shift_options fake_ssh target foo bar
')"
expected="target
foo
bar"
assert_equal "$expected" "$result"

start_test "fish shift_options stops at --"
result="$(_fish_run '
    function fake_ssh
        printf "%s\n" $argv
    end
    shift_options fake_ssh target -t -- -v
')"
expected="-t
target
--
-v"
assert_equal "$expected" "$result"

###############
# TEST: set_up_ssh_aliases parses ~/.ssh/config and defines functions

start_test "fish set_up_ssh_aliases defines foo"
result="$(_fish_run '
    mkdir -p $HOME/.ssh
    printf "%s\n" "Host foo foo.example.com" "    HostName foo.example.com" "Host bar" "Host *.wild" "Host nope-wild" >$HOME/.ssh/config
    set_up_ssh_aliases
    # foo, foo.example.com, bar should all be functions; wildcards and
    # entries containing - or ? or * are skipped.
    functions --query foo; and echo foo-ok
    functions --query foo.example.com; and echo foo-fqdn-ok
    functions --query bar; and echo bar-ok
    functions --query nope-wild; or echo no-nope
    functions --query "*.wild"; or echo no-wild
')"
assert_contains "foo-ok" "$result"
start_test "fish set_up_ssh_aliases defines foo.example.com"
assert_contains "foo-fqdn-ok" "$result"
start_test "fish set_up_ssh_aliases defines bar"
assert_contains "bar-ok" "$result"
start_test "fish set_up_ssh_aliases skips entries with -"
assert_contains "no-nope" "$result"
start_test "fish set_up_ssh_aliases skips wildcard entries"
assert_contains "no-wild" "$result"

start_test "fish set_up_ssh_aliases no-op without ~/.ssh/config"
result="$(_fish_run '
    # No config file: set_up_ssh_aliases should silently return without error.
    rm -rf $HOME/.ssh
    set_up_ssh_aliases
    echo ok
')"
assert_equal "ok" "$result"

###############
# TEST: in_shpool / want_shpool / connected_via_ssh gating

start_test "fish in_shpool false when SHPOOL_SESSION_NAME unset"
result="$(_fish_run '
    if in_shpool; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

start_test "fish in_shpool true when SHPOOL_SESSION_NAME set"
result="$(_fish_run '
    set -gx SHPOOL_SESSION_NAME main
    if in_shpool; echo yes; else; echo no; end
')"
assert_equal "yes" "$result"

start_test "fish connected_via_ssh false when SSH_CONNECTION unset"
result="$(_fish_run '
    if connected_via_ssh; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

start_test "fish connected_via_ssh true when SSH_CONNECTION set"
result="$(_fish_run '
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    if connected_via_ssh; echo yes; else; echo no; end
')"
assert_equal "yes" "$result"

###############
# TEST: ssh_client_host (reader) and ssh_to (sender)

start_test "fish ssh_client_host returns LC_CLIENT_HOST when set"
result="$(_fish_run '
    set -gx LC_CLIENT_HOST laptop
    ssh_client_host
')"
assert_equal "laptop" "$result"

start_test "fish ssh_client_host empty when not an ssh session"
result="$(_fish_run '
    set -e LC_CLIENT_HOST
    set -e SSH_CONNECTION
    set _h (ssh_client_host)
    echo "[$_h]"
')"
assert_equal "[]" "$result"

start_test "fish ssh_client_host reverse-resolves the client IP"
result="$(_fish_run '
    set -e LC_CLIENT_HOST
    set -gx SSH_CONNECTION "1.2.3.4 5555 10.0.0.1 22"
    function have_command; test $argv[1] = getent; end
    function getent; printf "%s\n" "1.2.3.4   client.example.com   alias"; end
    ssh_client_host
')"
assert_equal "client" "$result"

start_test "fish ssh_client_host falls back to the client IP"
result="$(_fish_run '
    set -e LC_CLIENT_HOST
    set -gx SSH_CONNECTION "1.2.3.4 5555 10.0.0.1 22"
    function have_command; return 1; end
    ssh_client_host
')"
assert_equal "1.2.3.4" "$result"

start_test "fish ssh_to sends client host via LC_CLIENT_HOST and SendEnv"
result="$(_fish_run '
    function short_hostname; echo clienthost; end
    function have_command; test $argv[1] = ssh; end
    function ssh; echo "ssh LC_CLIENT_HOST=$LC_CLIENT_HOST args=$argv"; end
    ssh_to myhost
')"
assert_contains "LC_CLIENT_HOST=clienthost" "$result"
assert_contains "-oSendEnv=LC_CLIENT_HOST" "$result"
assert_contains "myhost" "$result"

start_test "fish ssh_to rw path also sets LC_CLIENT_HOST"
result="$(_fish_run '
    function short_hostname; echo clienthost; end
    function have_command; test $argv[1] = rw; end
    function rw; echo "rw LC_CLIENT_HOST=$LC_CLIENT_HOST args=$argv"; end
    ssh_to myhost
')"
assert_contains "rw LC_CLIENT_HOST=clienthost" "$result"
assert_contains "args=-r myhost" "$result"

start_test "fish ssh_to does not leak LC_CLIENT_HOST"
result="$(_fish_run '
    function short_hostname; echo clienthost; end
    function have_command; test $argv[1] = ssh; end
    function ssh; true; end
    ssh_to myhost
    echo "after=[$LC_CLIENT_HOST]"
')"
assert_equal "after=[]" "$result"

start_test "fish ssh_to restores an inherited LC_CLIENT_HOST"
result="$(_fish_run '
    set -gx LC_CLIENT_HOST inbound
    function short_hostname; echo clienthost; end
    function have_command; test $argv[1] = ssh; end
    function ssh; echo "ssh saw $LC_CLIENT_HOST"; end
    ssh_to myhost
    echo "after=[$LC_CLIENT_HOST]"
')"
assert_contains "ssh saw clienthost" "$result"
assert_contains "after=[inbound]" "$result"

# want_shpool now also requires `have_command shpool`, `stdin_is_tty`,
# and `! in_shpool`. The "true" cases stub have_command to return success
# for shpool and stdin_is_tty to return true (the fish snippet runs with
# stdin redirected from /dev/null). _fish_run's default have_command
# refuses shpool, so the "false" case already exercises that branch.
start_test "fish want_shpool false when not remote and not in project"
result="$(_fish_run '
    function projectroot; return 1; end
    if want_shpool; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

start_test "fish want_shpool true when remote"
result="$(_fish_run '
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; return 1; end
    function have_command; return 0; end
    function stdin_is_tty; return 0; end
    if want_shpool; echo yes; else; echo no; end
')"
assert_equal "yes" "$result"

start_test "fish want_shpool true when inside project"
result="$(_fish_run '
    function projectroot; echo /some/project; end
    function have_command; return 0; end
    function stdin_is_tty; return 0; end
    if want_shpool; echo yes; else; echo no; end
')"
assert_equal "yes" "$result"

start_test "fish want_shpool false when WANT_SHPOOL=0"
result="$(_fish_run '
    set -gx WANT_SHPOOL 0
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; echo /some/project; end
    function have_command; return 0; end
    function stdin_is_tty; return 0; end
    if want_shpool; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

start_test "fish want_shpool false when already in shpool"
result="$(_fish_run '
    set -gx SHPOOL_SESSION_NAME main
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; echo /some/project; end
    function have_command; return 0; end
    function stdin_is_tty; return 0; end
    if want_shpool; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

start_test "fish want_shpool false when stdin is not a tty"
result="$(_fish_run '
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; echo /some/project; end
    function have_command; return 0; end
    function stdin_is_tty; return 1; end
    if want_shpool; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

start_test "fish want_shpool false when inside tmux"
result="$(_fish_run '
    set -gx TMUX /tmp/tmux-fake/default,12345,0
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; echo /some/project; end
    function have_command; return 0; end
    function stdin_is_tty; return 0; end
    if want_shpool; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

start_test "fish want_shpool false when autoshpool not installed"
result="$(_fish_run '
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; echo /some/project; end
    function have_command; test $argv[1] = shpool; end
    function stdin_is_tty; return 0; end
    if want_shpool; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

###############
# TEST: want_tmux gating (mirrors want_shpool but on the tmux binary)

start_test "fish want_tmux true when remote"
result="$(_fish_run '
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; return 1; end
    function have_command; return 0; end
    function stdin_is_tty; return 0; end
    if want_tmux; echo yes; else; echo no; end
')"
assert_equal "yes" "$result"

start_test "fish want_tmux true when inside project"
result="$(_fish_run '
    function projectroot; echo /some/project; end
    function have_command; return 0; end
    function stdin_is_tty; return 0; end
    if want_tmux; echo yes; else; echo no; end
')"
assert_equal "yes" "$result"

start_test "fish want_tmux false when not remote and not in project"
result="$(_fish_run '
    function projectroot; return 1; end
    function have_command; return 0; end
    function stdin_is_tty; return 0; end
    if want_tmux; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

start_test "fish want_tmux false when WANT_TMUX=0"
result="$(_fish_run '
    set -gx WANT_TMUX 0
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; echo /some/project; end
    function have_command; return 0; end
    function stdin_is_tty; return 0; end
    if want_tmux; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

start_test "fish want_tmux false when tmux not installed"
result="$(_fish_run '
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; echo /some/project; end
    function have_command; return 1; end
    function stdin_is_tty; return 0; end
    if want_tmux; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

start_test "fish want_tmux false when autotmux not installed"
result="$(_fish_run '
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; echo /some/project; end
    function have_command; test $argv[1] = tmux; end
    function stdin_is_tty; return 0; end
    if want_tmux; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

start_test "fish want_tmux false when already inside tmux"
result="$(_fish_run '
    set -gx TMUX /tmp/tmux-fake/default,12345,0
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; echo /some/project; end
    function have_command; return 0; end
    function stdin_is_tty; return 0; end
    if want_tmux; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

start_test "fish want_tmux false when inside shpool"
result="$(_fish_run '
    set -gx SHPOOL_SESSION_NAME main
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; echo /some/project; end
    function have_command; return 0; end
    function stdin_is_tty; return 0; end
    if want_tmux; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

start_test "fish want_tmux false when stdin is not a tty"
result="$(_fish_run '
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; echo /some/project; end
    function have_command; return 0; end
    function stdin_is_tty; return 1; end
    if want_tmux; echo yes; else; echo no; end
')"
assert_equal "no" "$result"

###############
# TEST: session_backend picks shpool by default, tmux as fallback

start_test "fish session_backend prefers shpool when both available"
result="$(_fish_run '
    function have_command; return 0; end
    session_backend
')"
assert_equal "shpool" "$result"

start_test "fish session_backend uses tmux when WANT_SHPOOL=0"
result="$(_fish_run '
    set -gx WANT_SHPOOL 0
    function have_command; return 0; end
    session_backend
')"
assert_equal "tmux" "$result"

start_test "fish session_backend uses tmux when shpool missing"
result="$(_fish_run '
    function have_command; contains $argv[1] tmux autotmux; end
    session_backend
')"
assert_equal "tmux" "$result"

start_test "fish session_backend uses shpool when autotmux missing"
result="$(_fish_run '
    function have_command; contains $argv[1] tmux shpool autoshpool; end
    session_backend
')"
assert_equal "shpool" "$result"

start_test "fish session_backend uses tmux when autoshpool missing"
result="$(_fish_run '
    function have_command; contains $argv[1] tmux autotmux shpool; end
    session_backend
')"
assert_equal "tmux" "$result"

start_test "fish session_backend empty when nothing available"
result="$(_fish_run '
    function have_command; return 1; end
    set _b (session_backend)
    echo "[$_b]"
')"
assert_equal "[]" "$result"

# SESSION_BACKEND=tmux flips the preference: tmux preferred, shpool fallback.
start_test "fish session_backend prefers tmux when SESSION_BACKEND=tmux"
result="$(_fish_run '
    set -gx SESSION_BACKEND tmux
    function have_command; return 0; end
    session_backend
')"
assert_equal "tmux" "$result"

start_test "fish session_backend SESSION_BACKEND=tmux falls back to shpool when tmux missing"
result="$(_fish_run '
    set -gx SESSION_BACKEND tmux
    function have_command; contains $argv[1] shpool autoshpool; end
    session_backend
')"
assert_equal "shpool" "$result"

start_test "fish session_backend honours WANT_TMUX=0 over SESSION_BACKEND=tmux"
result="$(_fish_run '
    set -gx SESSION_BACKEND tmux
    set -gx WANT_TMUX 0
    function have_command; return 0; end
    session_backend
')"
assert_equal "shpool" "$result"

###############
# TEST: sessionattach / sessionlist dispatch to the backend

start_test "fish sessionattach runs tmux attach on the tmux backend"
result="$(_fish_run '
    function session_backend; echo tmux; end
    function tmux; echo "tmux $argv"; end
    sessionattach work
')"
assert_equal "tmux attach work" "$result"

start_test "fish sessionattach runs shpool attach on the shpool backend"
result="$(_fish_run '
    function session_backend; echo shpool; end
    function shpool; echo "shpool $argv"; end
    sessionattach work
')"
assert_equal "shpool attach work" "$result"

start_test "fish sessionlist runs tmuxlist on the tmux backend"
result="$(_fish_run '
    function session_backend; echo tmux; end
    function tmuxlist; echo tmuxlist-called; end
    sessionlist
')"
assert_equal "tmuxlist-called" "$result"

start_test "fish sessionlist runs shpoollist on the shpool backend"
result="$(_fish_run '
    function session_backend; echo shpool; end
    function shpoollist; echo shpoollist-called; end
    sessionlist
')"
assert_equal "shpoollist-called" "$result"

###############
# TEST: the {verb}{backend} session aliases forward args to their command
# (a shell function for auto*, a script on PATH for change*/detach*/make*).
# Each is stubbed by name so this checks the wiring without a real backend.

for _pair in \
    "as autosession" "asp autoshpool" "atm autotmux" \
    "cs changesession" "csp changeshpool" "ctm changetmux" \
    "ds detachsession" "dsp detachshpool" "dtm detachtmux" \
    "ms makesession" "msp makeshpool" "mtm maketmux"; do
    set -- $_pair
    _alias="$1"; _target="$2"
    start_test "fish $_alias calls $_target"
    # cs/ds/ms no-op unless a backend is selected, so stub session_backend; the
    # auto* aliases call their (stubbed) target directly and ignore it.
    result="$(_fish_run "
        function session_backend; echo tmux; end
        function $_target; echo \"$_target \$argv\"; end
        $_alias work
    ")"
    assert_equal "$_target work" "$result"
done

# The switch only happens on the no-arg picker path: in a shpool session it
# detaches us, so cs/csp must exit afterwards (the trailing echo must not run).
# --list/--preview/--help return 0 too but only print, so an arg means no exit.
start_test "fish csp exits the shell after a shpool switch"
result="$(_fish_run '
    function changeshpool; echo switched; end
    set -gx SHPOOL_SESSION_NAME work
    csp
    echo stayed
')"
assert_equal "switched" "$result"

start_test "fish cs exits the shell after a shpool switch"
result="$(_fish_run '
    function changesession; echo switched; end
    set -gx SHPOOL_SESSION_NAME work
    cs
    echo stayed
')"
assert_equal "switched" "$result"

start_test "fish csp does not exit for a non-switch subcommand"
result="$(_fish_run '
    function changeshpool; echo "changeshpool $argv"; end
    set -gx SHPOOL_SESSION_NAME work
    csp --list
    echo stayed
')"
expected="changeshpool --list
stayed"
assert_equal "$expected" "$result"

start_test "fish cs does not exit outside a shpool session"
result="$(_fish_run '
    function session_backend; echo tmux; end
    function changesession; echo switched; end
    set -e SHPOOL_SESSION_NAME
    cs
    echo stayed
')"
expected="switched
stayed"
assert_equal "$expected" "$result"

# make* mirror change*'s exit handling: inside a shpool session makeshpool hands
# the new session to autoshpool's loop via request_switch (detaching us), so the
# parked shell must exit. Unlike cs there's no no-arg gate: make always names a
# session, so it exits with an argument too.
start_test "fish ms exits the shell after a shpool make"
result="$(_fish_run '
    function makesession; echo made; end
    set -gx SHPOOL_SESSION_NAME work
    ms newproj
    echo stayed
')"
assert_equal "made" "$result"

start_test "fish msp exits the shell after a shpool make"
result="$(_fish_run '
    function makeshpool; echo made; end
    set -gx SHPOOL_SESSION_NAME work
    msp newproj
    echo stayed
')"
assert_equal "made" "$result"

start_test "fish ms does not exit outside a shpool session"
result="$(_fish_run '
    function session_backend; echo tmux; end
    function makesession; echo made; end
    set -e SHPOOL_SESSION_NAME
    ms newproj
    echo stayed
')"
expected="made
stayed"
assert_equal "$expected" "$result"

# tmux nested in shpool sets both vars; maketmux switches the tmux client in
# place, so ms must stay (not exit) there.
start_test "fish ms does not exit for tmux nested in shpool"
result="$(_fish_run '
    function makesession; echo made; end
    set -gx TMUX /tmp/sock
    set -gx SHPOOL_SESSION_NAME work
    ms newproj
    echo stayed
')"
expected="made
stayed"
assert_equal "$expected" "$result"

# A make that succeeds but does not exit must return its own status (0), not the
# failed exit guard's 1.
start_test "fish ms returns success when a successful make does not exit"
result="$(_fish_run '
    function session_backend; echo tmux; end
    function makesession; return 0; end
    set -e TMUX SHPOOL_SESSION_NAME
    ms newproj
    echo "rc=$status"
')"
assert_equal "rc=0" "$result"

start_test "fish msp returns success when a successful make does not exit"
result="$(_fish_run '
    function makeshpool; return 0; end
    set -e SHPOOL_SESSION_NAME
    msp newproj
    echo "rc=$status"
')"
assert_equal "rc=0" "$result"

start_test "fish ms returns a failed make's status"
result="$(_fish_run '
    function session_backend; echo tmux; end
    function makesession; return 3; end
    set -e TMUX SHPOOL_SESSION_NAME
    ms newproj
    echo "rc=$status"
')"
assert_equal "rc=3" "$result"

# When no backend is wanted/available and we aren't in a session, cs/ds/ms
# do nothing rather than let the script fall back to tmux; inside a session
# they still act on it ($TMUX/$SHPOOL_SESSION_NAME win in the script).
start_test "fish cs is a no-op when no backend is selected"
result="$(_fish_run '
    function session_backend; echo ""; end
    function changesession; echo "changesession $argv"; end
    set -e TMUX
    set -e SHPOOL_SESSION_NAME
    cs work
    echo done
')"
assert_equal "done" "$result"

start_test "fish cs still runs in a session when no backend is selected"
result="$(_fish_run '
    function session_backend; echo ""; end
    function changesession; echo "changesession $argv"; end
    set -gx TMUX /tmp/sock
    set -e SHPOOL_SESSION_NAME
    cs work
    echo done
')"
expected="changesession work
done"
assert_equal "$expected" "$result"

# tmux nested in shpool sets both $TMUX and $SHPOOL_SESSION_NAME; changesession
# switches the tmux client in place, so cs must stay (not exit) there.
start_test "fish cs does not exit for tmux nested in shpool"
result="$(_fish_run '
    function changesession; echo "changesession $argv"; end
    set -gx TMUX /tmp/sock
    set -gx SHPOOL_SESSION_NAME work
    cs work
    echo stayed
')"
expected="changesession work
stayed"
assert_equal "$expected" "$result"

# A switch that succeeds but does not exit (an in-place tmux switch, or an
# attach/detach from outside any session) must return the picker's own status
# (0), not the failed exit guard's 1.
start_test "fish cs returns success when a tmux-nested switch does not exit"
result="$(_fish_run '
    function changesession; return 0; end
    set -gx TMUX /tmp/sock
    set -gx SHPOOL_SESSION_NAME work
    cs
    echo "rc=$status"
')"
assert_equal "rc=0" "$result"

start_test "fish cs returns success when an outside-session switch does not exit"
result="$(_fish_run '
    function session_backend; echo shpool; end
    function changesession; return 0; end
    set -e TMUX SHPOOL_SESSION_NAME
    cs
    echo "rc=$status"
')"
assert_equal "rc=0" "$result"

start_test "fish csp returns success when an outside-session switch does not exit"
result="$(_fish_run '
    function changeshpool; return 0; end
    set -e SHPOOL_SESSION_NAME
    csp
    echo "rc=$status"
')"
assert_equal "rc=0" "$result"

# A cancelled picker (ESC) returns non-zero; cs must propagate that status.
start_test "fish cs returns a cancelled picker's status"
result="$(_fish_run '
    function session_backend; echo shpool; end
    function changesession; return 130; end
    set -e TMUX SHPOOL_SESSION_NAME
    cs
    echo "rc=$status"
')"
assert_equal "rc=130" "$result"

# cs/ds/ms pass session_backend's choice (which honours WANT_SHPOOL/WANT_TMUX
# and the $SESSION_BACKEND preference) as SESSION_BACKEND so the *s scripts
# don't fall back to tmux for a WANT_SHPOOL=0 user.
start_test "fish cs passes session_backend to the script as SESSION_BACKEND"
result="$(_fish_run '
    function session_backend; echo shpool; end
    function changesession; echo "SESSION_BACKEND=$SESSION_BACKEND"; end
    set -e SHPOOL_SESSION_NAME
    cs work
')"
assert_equal "SESSION_BACKEND=shpool" "$result"

###############
# TEST: maybe_start_session_and_exit prefers shpool, falls back to tmux

start_test "fish maybe_start_session_and_exit no-op without a backend"
result="$(_fish_run '
    function projectroot; return 1; end
    maybe_start_session_and_exit
    echo survived
')"
assert_equal "survived" "$result"

start_test "fish maybe_start_session_and_exit prefers shpool"
result="$(_fish_run '
    function session_backend; echo shpool; end
    function want_tmux; return 0; end
    function want_shpool; return 0; end
    function autotmux; echo autotmux-called; end
    function autoshpool; echo autoshpool-called; end
    maybe_start_session_and_exit
    echo after
')"
assert_equal "autoshpool-called" "$result"

start_test "fish maybe_start_session_and_exit falls back to tmux when session_backend is tmux"
result="$(_fish_run '
    function session_backend; echo tmux; end
    function want_tmux; return 0; end
    function want_shpool; return 1; end
    function autotmux; echo autotmux-called; end
    maybe_start_session_and_exit
    echo after
')"
assert_equal "autotmux-called" "$result"

start_test "fish maybe_start_session_and_exit skips shpool when want_shpool false"
result="$(_fish_run '
    function session_backend; echo shpool; end
    function want_shpool; return 1; end
    function autoshpool; echo autoshpool-called; end
    maybe_start_session_and_exit
    echo survived
')"
assert_equal "survived" "$result"

###############
# TEST: CDPATH is set for all shells (not just interactive)

start_test "fish CDPATH contains HOME"
result="$(HOME=$_testdir/fakehome run_with_timeout 15 fish --no-config -c "source $_config; echo \$CDPATH" 2>/dev/null)"
assert_contains "$_testdir/fakehome" "$result"
start_test "fish CDPATH does not contain conf"
assert_not_contains "$_testdir/fakehome/conf" "$result"

###############
# TEST: EDITRC is exported when ~/.editrc exists

start_test "fish EDITRC exported when ~/.editrc exists"
result="$(_fish_run '
    touch $HOME/.editrc
    # Re-source to pick up the newly-created file.
    source '"$_config"'
    echo $EDITRC
')"
assert_contains ".editrc" "$result"

###############
# TEST: environment-only vars (BLOCKSIZE, GREP_COLOR, CLICOLOR, LSCOLORS)
# are set even in a non-interactive fish

start_test "fish BLOCKSIZE/GREP_COLOR/CLICOLOR set in non-interactive shell"
result="$(HOME=$_testdir/fakehome run_with_timeout 15 fish --no-config -c "source $_config; echo \$BLOCKSIZE \$GREP_COLOR \$CLICOLOR" 2>/dev/null)"
assert_equal "1024 4 true" "$result"

start_test "fish LSCOLORS for xterm"
result="$(HOME=$_testdir/fakehome TERM=xterm run_with_timeout 15 fish --no-config -c "source $_config; echo \$LSCOLORS" 2>/dev/null)"
assert_equal "exfxxxxxcxxxxx" "$result"

start_test "fish LSCOLORS for linux terminal"
result="$(HOME=$_testdir/fakehome TERM=linux run_with_timeout 15 fish --no-config -c "source $_config; echo \$LSCOLORS" 2>/dev/null)"
assert_equal "ExFxxxxxCxxxxx" "$result"

###############
# TEST: rd cds to project root

_rd_proj="$_testdir/rd_proj"
mkdir -p "$_rd_proj/.git" "$_rd_proj/src/lib"

start_test "fish rd cds to project root"
result="$(_fish_run '
    function projectroot; echo '"$_rd_proj"'; end
    cd '"$_rd_proj/src/lib"'
    rd
    pwd
')"
assert_equal "$_rd_proj" "$result"

###############
# TEST: find_up finds file in ancestor directory

_find_up_dir="$_testdir/find_up_proj"
mkdir -p "$_find_up_dir/a/b/c"
touch "$_find_up_dir/a/marker.txt"

start_test "fish find_up finds file in ancestor"
result="$(_fish_run '
    cd '"$_find_up_dir/a/b/c"'
    find_up marker.txt '"$_find_up_dir/a/b/c"'
')"
assert_equal "$_find_up_dir/a/marker.txt" "$result"

start_test "fish find_up finds file in current dir"
result="$(_fish_run '
    cd '"$_find_up_dir/a"'
    find_up marker.txt '"$_find_up_dir/a"'
')"
assert_equal "$_find_up_dir/a/marker.txt" "$result"

# Run find_up with a missing file and have the snippet echo a specific
# marker if it returns 1. Don't rely on $? from _fish_run alone: a fish
# crash, timeout (124), or missing-binary (127) would also be non-zero
# and pass a naive "exit code is 1" check for the wrong reason.
start_test "fish find_up returns 1 for missing file"
result="$(_fish_run '
    cd '"$_find_up_dir/a/b/c"'
    if not find_up nonexistent_file_xyz '"$_find_up_dir/a/b/c"'
        echo FIND_UP_MISSING
    end
')"
assert_contains \
    "FIND_UP_MISSING" "$result"

rm -rf "$_find_up_dir"

###############
# TEST: jd/hd/gd & mjd/mhd/mgd run autosession after the underlying
# command succeeds, and skip it when the command fails.

start_test "fish jd runs jjd then autosession"
result="$(_fish_run '
    function jjd; echo "jjd $argv"; end
    function autosession; echo autosession; end
    jd repo
')"
assert_equal "jjd repo
autosession" "$result"

start_test "fish hd runs hgd then autosession"
result="$(_fish_run '
    function hgd; echo "hgd $argv"; end
    function autosession; echo autosession; end
    hd repo
')"
assert_equal "hgd repo
autosession" "$result"

start_test "fish gd runs gitd then autosession"
result="$(_fish_run '
    function gitd; echo "gitd $argv"; end
    function autosession; echo autosession; end
    gd repo
')"
assert_equal "gitd repo
autosession" "$result"

start_test "fish mjd runs jjd -f then autosession"
result="$(_fish_run '
    function jjd; echo "jjd $argv"; end
    function autosession; echo autosession; end
    mjd repo
')"
assert_equal "jjd -f repo
autosession" "$result"

start_test "fish mhd runs hgd -f then autosession"
result="$(_fish_run '
    function hgd; echo "hgd $argv"; end
    function autosession; echo autosession; end
    mhd repo
')"
assert_equal "hgd -f repo
autosession" "$result"

start_test "fish mgd runs gitd -f then autosession"
result="$(_fish_run '
    function gitd; echo "gitd $argv"; end
    function autosession; echo autosession; end
    mgd repo
')"
assert_equal "gitd -f repo
autosession" "$result"

start_test "fish mjd skips autosession when jjd fails"
result="$(_fish_run '
    function jjd; echo "jjd $argv"; return 1; end
    function autosession; echo autosession; end
    mjd repo
')"
assert_equal "jjd -f repo" "$result"

###############
# TEST: FAILSAFE=1 bails out of config.fish before defining functions
# Mirrors shrc's FAILSAFE=1 escape hatch.

start_test "fish FAILSAFE=1 prints failsafe mode and skips heavy setup"
_failsafe_out="$(HOME=$_testdir/fakehome FAILSAFE=1 run_with_timeout 15 \
    fish --no-config -c "source $_config; echo AFTER; functions --query switchshpool; and echo switchshpool-defined" 2>&1)"
assert_contains "failsafe mode" "$_failsafe_out"
assert_contains "AFTER" "$_failsafe_out"
# `asp` / wrappers like `jd` / switchshpool are defined past the early-return point.
assert_not_contains "switchshpool-defined" "$_failsafe_out"

start_test "fish FAILSAFE unset loads config.fish normally"
_failsafe_out="$(HOME=$_testdir/fakehome run_with_timeout 15 \
    fish --no-config -c "source $_config; echo AFTER; functions --query switchshpool; and echo switchshpool-defined" 2>&1)"
assert_not_contains "failsafe mode" "$_failsafe_out"
assert_contains "AFTER" "$_failsafe_out"
# switchshpool lives past the failsafe early-return, so a normal load defines it.
assert_contains "switchshpool-defined" "$_failsafe_out"

# LC_FAILSAFE=1 is the ssh-survivable alias (most sshd configs
# AcceptEnv LC_*), so `LC_FAILSAFE=1 ssh host` reaches the remote.
start_test "fish LC_FAILSAFE=1 also triggers failsafe mode"
_failsafe_out="$(HOME=$_testdir/fakehome LC_FAILSAFE=1 run_with_timeout 15 \
    fish --no-config -c "source $_config; echo AFTER" 2>&1)"
assert_contains "failsafe mode" "$_failsafe_out"
assert_contains "AFTER" "$_failsafe_out"

# ~/.failsafe file is a persistent opt-in: presence of the file alone
# forces failsafe mode for every new shell.
_fish_failsafe_home="$_testdir/fish_failsafe_home"
mkdir -p "$_fish_failsafe_home"
touch "$_fish_failsafe_home/.failsafe"
start_test "fish ~/.failsafe file triggers failsafe mode"
_failsafe_out="$(HOME=$_fish_failsafe_home run_with_timeout 15 \
    fish --no-config -c "source $_config; echo AFTER" 2>&1)"
assert_contains "failsafe mode" "$_failsafe_out"
assert_contains "AFTER" "$_failsafe_out"

###############
# TEST: set_up_ssh_aliases is deferred into the interactive block (after the
# handoff), so a launcher that hands off never builds the aliases. WANT_TMUX/
# WANT_SHPOOL=0 keep maybe_start_session_and_exit from firing here.

# The interactive block runs set_up_ssh_aliases, so a Host alias function is built.
start_test "fish interactive block builds ssh aliases after the handoff"
result="$(_fish_run_config '
    set -gx WANT_TMUX 0
    set -gx WANT_SHPOOL 0
    mkdir -p $HOME/.ssh
    printf "%s\n" "Host foo" >$HOME/.ssh/config
' '' '
    if functions --query foo; echo built; else; echo skipped; end
')"
assert_equal "built" "$result"

###############
# TEST: rg shells out to ripgrep with --follow to follow symlinks.

_fish_rg_dir=$(mktemp -d)
cat > "$_fish_rg_dir/rg" << 'STUB'
#!/bin/sh
printf '%s\n' "$@"
STUB
chmod +x "$_fish_rg_dir/rg"

start_test "fish rg invokes ripgrep with --follow"
result="$(_fish_run "
    set -gx PATH $_fish_rg_dir \$PATH
    rg pattern path
")"
assert_contains "--follow" "$result"

start_test "fish rg forces --line-number so piped output keeps line numbers"
result="$(_fish_run "
    set -gx PATH $_fish_rg_dir \$PATH
    rg pattern path
")"
assert_contains "--line-number" "$result"

start_test "fish rg passes through user arguments"
result="$(_fish_run "
    set -gx PATH $_fish_rg_dir \$PATH
    rg pattern path
")"
assert_contains "pattern" "$result"
assert_contains "path" "$result"

rm -rf "$_fish_rg_dir"

###############
# TEST: publish_jobs_file resolves a per-tty file under
# $XDG_RUNTIME_DIR; publish_jobs writes a "%N command" summary
# string; unpublish_jobs removes it.

start_test "fish publish_jobs_file empty when TTY isn't /dev/..."
result="$(_fish_run '
    set -gx XDG_RUNTIME_DIR (mktemp -d)
    set -gx TTY "not a tty"
    set --erase _publish_jobs_file 2>/dev/null
    echo "[" (publish_jobs_file | string collect) "]"
')"
assert_equal "[  ]" "$result"

start_test "fish publish_jobs_file empty when XDG_RUNTIME_DIR unset"
# We deliberately don't fall back to /tmp -- a predictable per-uid
# path under /tmp is a symlink-truncation vector.
result="$(_fish_run '
    set --erase XDG_RUNTIME_DIR 2>/dev/null
    set -gx TTY /dev/pts/99
    set --erase _publish_jobs_file 2>/dev/null
    echo "[" (publish_jobs_file | string collect) "]"
')"
assert_equal "[  ]" "$result"

start_test "fish publish_jobs_file builds path under XDG_RUNTIME_DIR"
result="$(_fish_run '
    set -gx XDG_RUNTIME_DIR (mktemp -d)
    set -gx TTY /dev/pts/99
    set --erase _publish_jobs_file 2>/dev/null
    publish_jobs_file
')"
expected_suffix="/shell-jobs/dev/pts/99"
case "$result" in
    *"$expected_suffix") assert_contains "$expected_suffix" "$result";;
    *) assert_equal "<path ending in $expected_suffix>" "$result";;
esac

start_test "fish publish_jobs writes empty file with no jobs, unpublish removes it"
result="$(_fish_run '
    set -gx XDG_RUNTIME_DIR (mktemp -d)
    set -gx TTY /dev/pts/99
    set --erase _publish_jobs_file 2>/dev/null
    function job_info; end
    publish_jobs
    set _file (publish_jobs_file | string collect)
    if test -f $_file
        echo wrote
    end
    cat $_file
    echo "<eof>"
    unpublish_jobs
    if test -e $_file
        echo lingered
    else
        echo gone
    end
')"
expected="wrote
<eof>
gone"
assert_equal "$expected" "$result"

start_test "fish job_info parses fish jobs table into %N command args"
# Stub `jobs` with the tabular header+rows format fish emits and
# confirm job_info turns it into the same single-line "%N command
# args & %M command args &" shape shrc produces.
result="$(_fish_run '
    function jobs
        printf "%s\t%s\t%s\t%s\t%s\n" Job Group CPU State Command
        printf "%s\t%s\t%s\t%s\t%s\n" 2 - 0% running "tail -f syslog &"
        printf "%s\t%s\t%s\t%s\t%s\n" 1 - 0% running "vi notes.txt &"
    end
    job_info
')"
assert_equal "%2 tail -f syslog & %1 vi notes.txt &" "$result"

start_test "fish publish_jobs writes %N command per job, space-separated"
# Drive through the now-correct job_info: stubbing `jobs` exercises
# both functions together. The trailing space matches awk format so
# consumers can concatenate without inserting their own separator.
result="$(_fish_run '
    set -gx XDG_RUNTIME_DIR (mktemp -d)
    set -gx TTY /dev/pts/99
    set --erase _publish_jobs_file 2>/dev/null
    function jobs
        printf "%s\t%s\t%s\t%s\t%s\n" Job Group CPU State Command
        printf "%s\t%s\t%s\t%s\t%s\n" 2 - 0% running "tail -f syslog &"
        printf "%s\t%s\t%s\t%s\t%s\n" 1 - 0% running "vi notes.txt &"
    end
    publish_jobs
    cat (publish_jobs_file | string collect)
')"
assert_equal "%2 tail %1 vi " "$result"

start_test "fish publish_jobs sees real fish background jobs"
# Regression: previously job_info's bash-style sed silently dropped
# every fish job because fish `jobs` is tabular, not `[N]+ Running
# cmd`. Run a real backgrounded job and confirm the parser picks it
# up end-to-end (jobs -> job_info -> publish_jobs).
result="$(_fish_run '
    set -gx XDG_RUNTIME_DIR (mktemp -d)
    set -gx TTY /dev/pts/99
    set --erase _publish_jobs_file 2>/dev/null
    sleep 30 &
    publish_jobs
    cat (publish_jobs_file | string collect)
    kill (jobs -p) 2>/dev/null
')"
# Job id varies across runs, so we only assert on the shape.
assert_contains "sleep " "$result"
case "$result" in
    %[0-9]*\ sleep\ ) ;;
    *) assert_equal "%N sleep " "$result";;
esac

test_summary "fish_test"
