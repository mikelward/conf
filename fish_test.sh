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

###############
# TEST: maybe_start_shpool_and_exit is a no-op when shpool is not installed

start_test "fish maybe_start_shpool_and_exit no-op without shpool"
result="$(_fish_run '
    function projectroot; return 1; end
    maybe_start_shpool_and_exit
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
# TEST: jd/hd/gd & mjd/mhd/mgd run autoshpool after the underlying
# command succeeds, and skip it when the command fails.

start_test "fish jd runs jjd then autoshpool"
result="$(_fish_run '
    function jjd; echo "jjd $argv"; end
    function autoshpool; echo autoshpool; end
    jd repo
')"
assert_equal "jjd repo
autoshpool" "$result"

start_test "fish hd runs hgd then autoshpool"
result="$(_fish_run '
    function hgd; echo "hgd $argv"; end
    function autoshpool; echo autoshpool; end
    hd repo
')"
assert_equal "hgd repo
autoshpool" "$result"

start_test "fish gd runs gitd then autoshpool"
result="$(_fish_run '
    function gitd; echo "gitd $argv"; end
    function autoshpool; echo autoshpool; end
    gd repo
')"
assert_equal "gitd repo
autoshpool" "$result"

start_test "fish mjd runs jjd -f then autoshpool"
result="$(_fish_run '
    function jjd; echo "jjd $argv"; end
    function autoshpool; echo autoshpool; end
    mjd repo
')"
assert_equal "jjd -f repo
autoshpool" "$result"

start_test "fish mhd runs hgd -f then autoshpool"
result="$(_fish_run '
    function hgd; echo "hgd $argv"; end
    function autoshpool; echo autoshpool; end
    mhd repo
')"
assert_equal "hgd -f repo
autoshpool" "$result"

start_test "fish mgd runs gitd -f then autoshpool"
result="$(_fish_run '
    function gitd; echo "gitd $argv"; end
    function autoshpool; echo autoshpool; end
    mgd repo
')"
assert_equal "gitd -f repo
autoshpool" "$result"

start_test "fish mjd skips autoshpool when jjd fails"
result="$(_fish_run '
    function jjd; echo "jjd $argv"; return 1; end
    function autoshpool; echo autoshpool; end
    mjd repo
')"
assert_equal "jjd -f repo" "$result"

###############
# TEST: FAILSAFE=1 bails out of config.fish before defining functions
# Mirrors shrc's FAILSAFE=1 escape hatch.

start_test "fish FAILSAFE=1 prints failsafe mode and skips heavy setup"
_failsafe_out="$(HOME=$_testdir/fakehome FAILSAFE=1 run_with_timeout 15 \
    fish --no-config -c "source $_config; echo AFTER; functions --query autoshpool; and echo autoshpool-defined" 2>&1)"
assert_contains "failsafe mode" "$_failsafe_out"
assert_contains "AFTER" "$_failsafe_out"
# `asp` / wrappers like `jd` are defined past the early-return point.
assert_not_contains "autoshpool-defined" "$_failsafe_out"

start_test "fish FAILSAFE unset loads config.fish normally"
_failsafe_out="$(HOME=$_testdir/fakehome run_with_timeout 15 \
    fish --no-config -c "source $_config; echo AFTER" 2>&1)"
assert_not_contains "failsafe mode" "$_failsafe_out"
assert_contains "AFTER" "$_failsafe_out"

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

test_summary "fish_test"
