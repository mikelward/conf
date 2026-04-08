#!/bin/bash
#
# Tests for non-prompt helpers in config/fish/config.fish.
# Mirrors shrc_test.sh but exercises the fish implementation via
# `fish -c`. Skips gracefully when fish is not installed.
#

. "$(dirname "$0")/shrc_test_lib.sh"

if ! command -v fish >/dev/null 2>&1; then
    echo "fish not installed, skipping fish tests"
    test_summary "fish shrc_fish_test"
    exit 0
fi

_srcdir="$(cd "$(dirname "$0")" && pwd)"
_config="$_srcdir/config/fish/config.fish"

# Run a fish snippet with config.fish preloaded. Uses a fake HOME so
# config.fish's interactive setup (history file, ssh alias parsing,
# shpool startup) runs against a clean workspace.
_fish_run() {
    local _snippet="$1"
    local _fakehome="$_testdir/fakehome"
    mkdir -p "$_fakehome"
    HOME="$_fakehome" \
        TERM=dumb \
        SHPOOL_SESSION_NAME= \
        TMUX= \
        SSH_CONNECTION= \
        fish --no-config -i -c "
            function tput; return 1; end
            source $_config
            # Ensure stubs survive config.fish's interactive setup.
            function have_command
                switch \$argv[1]
                    case shpool autoshpool brew yum apt-get; return 1
                    case '*'; command -v \$argv[1] >/dev/null 2>&1
                end
            end
            $_snippet
        "
}

###############
# TEST: log_history writes to HISTORY_FILE

result="$(_fish_run '
    set -g HISTORY_FILE $HOME/history-test
    log_history "hello world"
    cat $HISTORY_FILE
')"
assert_contains "fish log_history writes argv to HISTORY_FILE" "hello world" "$result"

result="$(_fish_run '
    set -g HISTORY_FILE ""
    log_history "ignored"
    echo done
')"
assert_equal "fish log_history no-op when HISTORY_FILE empty" "done" "$result"

###############
# TEST: shift_options moves leading -x options past the target argument

result="$(_fish_run '
    function fake_ssh
        printf "%s\n" $argv
    end
    shift_options fake_ssh target -t -v
')"
expected="-t
-v
target"
assert_equal "fish shift_options moves leading options past target" "$expected" "$result"

result="$(_fish_run '
    function fake_ssh
        printf "%s\n" $argv
    end
    shift_options fake_ssh target foo bar
')"
expected="target
foo
bar"
assert_equal "fish shift_options leaves positional args alone" "$expected" "$result"

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
assert_equal "fish shift_options stops at --" "$expected" "$result"

###############
# TEST: set_up_ssh_aliases parses ~/.ssh/config and defines functions

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
assert_contains "fish set_up_ssh_aliases defines foo" "foo-ok" "$result"
assert_contains "fish set_up_ssh_aliases defines foo.example.com" "foo-fqdn-ok" "$result"
assert_contains "fish set_up_ssh_aliases defines bar" "bar-ok" "$result"
assert_contains "fish set_up_ssh_aliases skips entries with -" "no-nope" "$result"
assert_contains "fish set_up_ssh_aliases skips wildcard entries" "no-wild" "$result"

result="$(_fish_run '
    # No config file: set_up_ssh_aliases should silently return without error.
    rm -rf $HOME/.ssh
    set_up_ssh_aliases
    echo ok
')"
assert_equal "fish set_up_ssh_aliases no-op without ~/.ssh/config" "ok" "$result"

###############
# TEST: in_shpool / want_shpool / connected_via_ssh gating

result="$(_fish_run '
    if in_shpool; echo yes; else; echo no; end
')"
assert_equal "fish in_shpool false when SHPOOL_SESSION_NAME unset" "no" "$result"

result="$(_fish_run '
    set -gx SHPOOL_SESSION_NAME main
    if in_shpool; echo yes; else; echo no; end
')"
assert_equal "fish in_shpool true when SHPOOL_SESSION_NAME set" "yes" "$result"

result="$(_fish_run '
    if connected_via_ssh; echo yes; else; echo no; end
')"
assert_equal "fish connected_via_ssh false when SSH_CONNECTION unset" "no" "$result"

result="$(_fish_run '
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    if connected_via_ssh; echo yes; else; echo no; end
')"
assert_equal "fish connected_via_ssh true when SSH_CONNECTION set" "yes" "$result"

result="$(_fish_run '
    function projectroot; return 1; end
    if want_shpool; echo yes; else; echo no; end
')"
assert_equal "fish want_shpool false when not remote and not in project" "no" "$result"

result="$(_fish_run '
    set -gx SSH_CONNECTION "1.2.3.4 1 2.3.4.5 22"
    function projectroot; return 1; end
    if want_shpool; echo yes; else; echo no; end
')"
assert_equal "fish want_shpool true when remote" "yes" "$result"

result="$(_fish_run '
    function projectroot; echo /some/project; end
    if want_shpool; echo yes; else; echo no; end
')"
assert_equal "fish want_shpool true when inside project" "yes" "$result"

###############
# TEST: maybe_start_shpool_and_exit is a no-op when shpool is not installed

result="$(_fish_run '
    function projectroot; return 1; end
    maybe_start_shpool_and_exit
    echo survived
')"
assert_equal "fish maybe_start_shpool_and_exit no-op without shpool" "survived" "$result"

###############
# TEST: CDPATH is set for all shells (not just interactive)

result="$(HOME=$_testdir/fakehome fish --no-config -c "source $_config; echo \$CDPATH" 2>/dev/null)"
assert_contains "fish CDPATH contains HOME" "$_testdir/fakehome" "$result"
assert_not_contains "fish CDPATH does not contain conf" "$_testdir/fakehome/conf" "$result"

###############
# TEST: EDITRC is exported when ~/.editrc exists

result="$(_fish_run '
    touch $HOME/.editrc
    # Re-source to pick up the newly-created file.
    source '"$_config"'
    echo $EDITRC
')"
assert_contains "fish EDITRC exported when ~/.editrc exists" ".editrc" "$result"

###############
# TEST: environment-only vars (BLOCKSIZE, GREP_COLOR, CLICOLOR, LSCOLORS)
# are set even in a non-interactive fish

result="$(HOME=$_testdir/fakehome fish --no-config -c "source $_config; echo \$BLOCKSIZE \$GREP_COLOR \$CLICOLOR" 2>/dev/null)"
assert_equal "fish BLOCKSIZE/GREP_COLOR/CLICOLOR set in non-interactive shell" "1024 4 true" "$result"

result="$(HOME=$_testdir/fakehome TERM=xterm fish --no-config -c "source $_config; echo \$LSCOLORS" 2>/dev/null)"
assert_equal "fish LSCOLORS for xterm" "exfxxxxxcxxxxx" "$result"

result="$(HOME=$_testdir/fakehome TERM=linux fish --no-config -c "source $_config; echo \$LSCOLORS" 2>/dev/null)"
assert_equal "fish LSCOLORS for linux terminal" "ExFxxxxxCxxxxx" "$result"

###############
# TEST: trailing-slash autocd via fish_command_not_found
# Typing `foo/` at the prompt should cd into foo if it's a directory.

_fish_autocd="$_testdir/fish_autocd"
mkdir -p "$_fish_autocd/sub"

# fish_command_not_found cds into an existing dir when given a trailing slash
result="$(_fish_run '
    cd '"$_fish_autocd"'
    set -e CDPATH
    fish_command_not_found ./sub/ >/dev/null 2>&1
    pwd
')"
assert_equal "fish fish_command_not_found cds on trailing slash" \
    "$_fish_autocd/sub" "$result"

# fish_command_not_found without a trailing slash falls through
result="$(_fish_run '
    fish_command_not_found someweirdcmd 2>&1
' 2>&1)"
assert_contains "fish fish_command_not_found no slash falls through" \
    "Unknown command" "$result"

# fish_command_not_found with non-existent trailing slash falls through
result="$(_fish_run '
    fish_command_not_found ./no_such_dir_xyz/ 2>&1
' 2>&1)"
assert_contains "fish fish_command_not_found non-existent falls through" \
    "Unknown command" "$result"

# When a system_fish_command_not_found is defined ahead of sourcing,
# it is preserved and called for non-slash commands.
result="$(HOME=$_testdir/fakehome fish --no-config -c '
    function fish_command_not_found
        echo "SYSTEM:$argv[1]"
    end
    source '"$_config"'
    fish_command_not_found someweirdcmd
' 2>&1)"
assert_contains "fish preserves and delegates to system hook" \
    "SYSTEM:someweirdcmd" "$result"

# Re-sourcing the config does NOT wrap the system hook inside itself
# (idempotency: system_fish_command_not_found should still print SYSTEM:,
# not be clobbered by our own override).
result="$(HOME=$_testdir/fakehome fish --no-config -c '
    function fish_command_not_found
        echo "SYSTEM:$argv[1]"
    end
    source '"$_config"'
    source '"$_config"'
    system_fish_command_not_found xyz
' 2>&1)"
assert_contains "fish re-sourcing preserves system hook idempotently" \
    "SYSTEM:xyz" "$result"

test_summary "fish shrc_fish_test"
