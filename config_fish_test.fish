#!/usr/bin/env fish
#
# Tests for config/fish/config.fish and config/fish/vcs.fish.
#

set failures 0
set passes 0

function assert_equal
    set label $argv[1]
    set expected $argv[2]
    set actual $argv[3]
    if test "$expected" = "$actual"
        set --global passes (math $passes + 1)
    else
        echo "FAIL: $label"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        set --global failures (math $failures + 1)
    end
end

function assert_true
    set label $argv[1]
    set --erase argv[1]
    if $argv
        set --global passes (math $passes + 1)
    else
        echo "FAIL: $label"
        echo "  expected command to succeed: $argv"
        set --global failures (math $failures + 1)
    end
end

function assert_false
    set label $argv[1]
    set --erase argv[1]
    if $argv
        echo "FAIL: $label"
        echo "  expected command to fail: $argv"
        set --global failures (math $failures + 1)
    else
        set --global passes (math $passes + 1)
    end
end

function test_summary
    set name $argv[1]
    echo
    if test $failures -eq 0
        echo "$name: all $passes tests passed."
    else
        echo "$name: $failures test(s) failed, $passes passed."
        exit 1
    end
end

set _testdir (mktemp -d)
set _srcdir (status dirname)

###############
# Source the files under test

source $_srcdir/config/fish/config.fish 2>/dev/null
source $_srcdir/config/fish/vcs.fish 2>/dev/null

###############
# Test trim_prefix

assert_equal "trim_prefix basic" "bar" (trim_prefix "/foo/" "/foo/bar")
assert_equal "trim_prefix no match" "/baz/bar" (trim_prefix "/foo/" "/baz/bar")
assert_equal "trim_prefix empty prefix" "hello" (trim_prefix "" "hello")

###############
# Test shift_options

set result (shift_options echo target arg1 arg2)
assert_equal "shift_options no options" "target arg1 arg2" "$result"

# Test that options are moved before target
set result (shift_options echo target -v arg1)
assert_equal "shift_options with option" "-v target arg1" "$result"

set result (shift_options echo target -v --foo arg1)
assert_equal "shift_options multiple options" "-v --foo target arg1" "$result"

# Test -- stops option processing
set result (shift_options echo target -- -notanoption)
assert_equal "shift_options -- stops processing" "target -- -notanoption" "$result"

###############
# Test VCS cache reading

# Create a fake .vcs_cache
mkdir -p $_testdir/fakerepo
printf 'git git github\n%s\n' $_testdir/fakerepo > $_testdir/fakerepo/.vcs_cache

# Test vcs reads from cache
set result (cd $_testdir/fakerepo && vcs)
assert_equal "vcs reads VCS type from cache" "git" "$result"

# Test rootdir reads from cache
set result (cd $_testdir/fakerepo && rootdir)
assert_equal "rootdir reads from cache" "$_testdir/fakerepo" "$result"

# Test rootdir with arguments
set result (cd $_testdir/fakerepo && rootdir "src/main.c")
assert_equal "rootdir with argument" "$_testdir/fakerepo/src/main.c" "$result"

# Test vcs_backend reads from cache
set result (cd $_testdir/fakerepo && vcs_backend)
assert_equal "vcs_backend reads from cache" "git" "$result"

# Test vcs_hosting reads from cache
set result (cd $_testdir/fakerepo && vcs_hosting)
assert_equal "vcs_hosting reads from cache" "github" "$result"

# Test cache with sentinel values
mkdir -p $_testdir/hgrepo
printf 'hg - -\n%s\n' $_testdir/hgrepo > $_testdir/hgrepo/.vcs_cache

set result (cd $_testdir/hgrepo && vcs_backend)
assert_equal "vcs_backend returns empty for sentinel" "" "$result"
cd $_testdir/hgrepo && vcs_backend
assert_equal "vcs_backend returns false for sentinel" "1" "$status"

set result (cd $_testdir/hgrepo && vcs_hosting)
assert_equal "vcs_hosting returns empty for sentinel" "" "$result"

# Test projectroot delegates to rootdir
set result (cd $_testdir/fakerepo && projectroot)
assert_equal "projectroot delegates to rootdir" "$_testdir/fakerepo" "$result"

# Test subdir
set result (cd $_testdir/fakerepo && subdir)
assert_equal "subdir returns empty at root" "" "$result"

###############
# Test SSH aliases parsing

# Create a fake SSH config
mkdir -p $_testdir/.ssh
printf 'Host foo\n    Hostname foo.example.com\n\nHost bar baz\n    Hostname bar.example.com\n\nHost *.example.com\n    User mikel\n\nHost test-host\n    Hostname test.example.com\n' > $_testdir/.ssh/config

# set_up_ssh_aliases is inside "if is_interactive" in config.fish,
# re-define it here for testing
function set_up_ssh_aliases
    test -f $HOME/.ssh/config; or return
    while read _field1 _rest
        switch $_field1
        case Host host
            for _alias in (string split ' ' $_rest)
                string match --quiet '*\**' $_alias; and continue
                string match --quiet '*\?*' $_alias; and continue
                string match --quiet '*-*' $_alias; and continue
                eval "function $_alias; shift_options ssh -t $_alias \$argv; end"
            end
        end
    end <$HOME/.ssh/config
end

# Override HOME for the test
set saved_HOME $HOME
set HOME $_testdir
set_up_ssh_aliases
set HOME $saved_HOME

# Check that aliases were created (no wildcards or patterns with -)
assert_true "ssh alias foo created" functions --query foo
assert_true "ssh alias bar created" functions --query bar
assert_true "ssh alias baz created" functions --query baz
assert_false "ssh wildcard host not aliased" functions --query '*.example.com'

# test-host contains - so should be skipped
# (functions --query won't work with - in names easily, just verify
# the others were created)

###############
# Test utility functions

# confirm (non-interactive, provide input)
echo "y" | confirm "Do something" >/dev/null
assert_equal "confirm returns true for y" "0" "$status"

echo "n" | confirm "Do something" >/dev/null
assert_equal "confirm returns false for n" "1" "$status"

# connected_via_ssh
set --export SSH_CONNECTION "1.2.3.4 1234 5.6.7.8 22"
assert_true "connected_via_ssh returns true when set" connected_via_ssh
set --erase SSH_CONNECTION
assert_false "connected_via_ssh returns false when unset" connected_via_ssh

# connected_remotely delegates to connected_via_ssh
set --export SSH_CONNECTION "1.2.3.4 1234 5.6.7.8 22"
assert_true "connected_remotely returns true" connected_remotely
set --erase SSH_CONNECTION

# in_shpool
set --export SHPOOL_SESSION_NAME "test"
assert_true "in_shpool returns true when set" in_shpool
set --erase SHPOOL_SESSION_NAME
assert_false "in_shpool returns false when unset" in_shpool

# inside_project (uses projectroot which reads cache)
cd $_testdir/fakerepo
assert_true "inside_project true when cache exists" inside_project
mkdir -p $_testdir/norepo
cd $_testdir/norepo
assert_false "inside_project false when no cache" inside_project
cd $_srcdir

###############
# Test status_chars

# Create a git repo with modifications
mkdir -p $_testdir/gitrepo
cd $_testdir/gitrepo
git init --initial-branch=main -q
git config core.hooksPath /dev/null
git config commit.gpgsign false
git config user.email "test@test.com"
git config user.name "Test"
git commit --allow-empty -m "initial" -q
echo "tracked" > file.txt
git add file.txt
git commit -m "add file" -q
echo "modified" > file.txt
printf 'git git -\n%s\n' $_testdir/gitrepo > .vcs_cache
# .vcs_cache is untracked, so exclude it from status
echo ".vcs_cache" > .gitignore
git add .gitignore
git commit -m "add gitignore" -q

set result (status_chars)
# M = modified tracked file
assert_equal "status_chars shows M for modified file" "M" "$result"

# test with untracked file too
echo "new" > untracked.txt
set result (status_chars)
# both M (modified) and ?? (untracked), sorted
assert_equal "status_chars shows both ?? and M" "?? M" "$result"

# Clean up
cd /tmp
command rm -rf $_testdir
test_summary "fish config tests"
