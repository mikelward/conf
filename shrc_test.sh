#!/bin/sh
#
# Tests for functions in shrc.
# Run under both sh and bash to catch compatibility issues.
#

. "$(dirname "$0")/shrc_test_lib.sh"

# Pin USERNAME / HOSTNAME so sourcing shrc doesn't fork `id -un` /
# `hostname -f` to fill them in -- keeps the test hermetic and
# decouples it from the host's hostname resolution. UID and TTY are
# left alone: UID is a special parameter under zsh (assigning it
# actually changes the effective user) and TTY is harmless to
# inherit.
HOSTNAME="testhost"
USERNAME="testuser"

# Pull in every shrc function via a single sourcing pass. The
# SHRC_LOAD_FUNCTIONS_ONLY guards inside shrc skip the env-setup and
# interactive / .shrc.local / auth blocks, so $PATH and exported state
# are left untouched. Replaces what used to be ~50 individual
# extract_func calls.
SHRC_LOAD_FUNCTIONS_ONLY=1 . "$_srcdir/shrc"

# Save PATH for restoration after path function tests
_saved_path="$PATH"

start_test "prepend_path adds to front"
PATH="/usr/bin:/bin"
prepend_path /usr/local/bin
assert_equal "/usr/local/bin:/usr/bin:/bin" "$PATH"

start_test "prepend_path moves existing to front"
PATH="/usr/local/bin:/usr/bin:/bin"
prepend_path /bin
assert_equal "/bin:/usr/local/bin:/usr/bin" "$PATH"

start_test "prepend_path on empty PATH"
PATH=
prepend_path /usr/bin
assert_equal "/usr/bin" "$PATH"

start_test "append_path adds to end"
PATH="/usr/bin:/bin"
append_path /usr/local/bin
assert_equal "/usr/bin:/bin:/usr/local/bin" "$PATH"

start_test "append_path moves existing to end"
PATH="/usr/local/bin:/usr/bin:/bin"
append_path /usr/local/bin
assert_equal "/usr/bin:/bin:/usr/local/bin" "$PATH"

start_test "append_path on empty PATH"
PATH=
append_path /usr/bin
assert_equal "/usr/bin" "$PATH"

start_test "delete_path removes entry"
PATH="/usr/local/bin:/usr/bin:/bin"
delete_path /usr/bin
assert_equal "/usr/local/bin:/bin" "$PATH"

start_test "delete_path no-op if not present"
PATH="/usr/bin:/bin"
delete_path /nonexistent
assert_equal "/usr/bin:/bin" "$PATH"

start_test "delete_path removes only entry"
PATH="/usr/bin"
delete_path /usr/bin
assert_equal "" "$PATH"

start_test "inpath finds existing entry"
PATH="/usr/bin:/bin"
inpath /usr/bin
assert_equal "0" "$?"

start_test "inpath returns false for missing"
PATH="/usr/bin:/bin"
inpath /nonexistent
assert_equal "1" "$?"

start_test "add_path appends if not present"
PATH="/usr/bin:/bin"
add_path /usr/local/bin
assert_equal "/usr/bin:/bin:/usr/local/bin" "$PATH"

start_test "add_path no-op if already present"
PATH="/usr/bin:/bin"
add_path /usr/bin
assert_equal "/usr/bin:/bin" "$PATH"

start_test "add_path start prepends"
PATH="/usr/bin:/bin"
add_path /usr/local/bin start
assert_equal "/usr/local/bin:/usr/bin:/bin" "$PATH"

start_test "add_path start moves existing to front"
PATH="/usr/bin:/bin:/usr/local/bin"
add_path /usr/local/bin start
assert_equal "/usr/local/bin:/usr/bin:/bin" "$PATH"

start_test "add_path end appends"
PATH="/usr/bin:/bin"
add_path /usr/local/bin end
assert_equal "/usr/bin:/bin:/usr/local/bin" "$PATH"

start_test "add_path end moves existing to end"
PATH="/usr/local/bin:/usr/bin:/bin"
add_path /usr/local/bin end
assert_equal "/usr/bin:/bin:/usr/local/bin" "$PATH"

# Test PATH functions with paths containing spaces
_tmpdir=$(mktemp -d)
mkdir -p "$_tmpdir/my programs/bin"
mkdir -p "$_tmpdir/path (v2)/bin"
mkdir -p "$_tmpdir/path\$HOME/bin"

start_test "prepend_path with spaces"
PATH="/usr/bin:/bin"
prepend_path "$_tmpdir/my programs/bin"
assert_equal "$_tmpdir/my programs/bin:/usr/bin:/bin" "$PATH"

start_test "append_path with parens"
append_path "$_tmpdir/path (v2)/bin"
assert_equal "$_tmpdir/my programs/bin:/usr/bin:/bin:$_tmpdir/path (v2)/bin" "$PATH"

start_test "inpath with spaces"
inpath "$_tmpdir/my programs/bin"
assert_equal "0" "$?"

start_test "inpath with parens"
inpath "$_tmpdir/path (v2)/bin"
assert_equal "0" "$?"

start_test "delete_path with spaces"
delete_path "$_tmpdir/my programs/bin"
assert_equal "/usr/bin:/bin:$_tmpdir/path (v2)/bin" "$PATH"

start_test "delete_path with parens"
delete_path "$_tmpdir/path (v2)/bin"
assert_equal "/usr/bin:/bin" "$PATH"

start_test "add_path start with parens"
add_path "$_tmpdir/path (v2)/bin" start
assert_equal "$_tmpdir/path (v2)/bin:/usr/bin:/bin" "$PATH"

start_test "add_path end with spaces"
PATH="/usr/bin:/bin"
add_path "$_tmpdir/my programs/bin" end
assert_equal "/usr/bin:/bin:$_tmpdir/my programs/bin" "$PATH"

rm -rf "$_tmpdir"

# Restore PATH for remaining tests
PATH="$_saved_path"

###############
# SETUP_FNM (Fast Node Manager integration)

_saved_path="$PATH"
_saved_shell="$shell"

start_test "setup_fnm no-op when dir missing and fnm absent"
_fnm_scrub=$(mktemp -d)   # empty dir on PATH: fnm not found
PATH="$_fnm_scrub"
FNM_PATH="/nonexistent-fnm-dir-xyz"
setup_fnm
_rc=$?
assert_equal "1" "$_rc"
assert_equal "$_fnm_scrub" "$PATH"
PATH="$_saved_path"
unset FNM_PATH
rm -rf "$_fnm_scrub"

start_test "setup_fnm adds dir to PATH but skips eval when fnm absent"
_fnm_home=$(mktemp -d)
PATH="$_fnm_home"   # scrub PATH so fnm is not found
FNM_PATH="$_fnm_home"
setup_fnm
_rc=$?
assert_equal "1" "$_rc"
assert_true inpath "$_fnm_home"
PATH="$_saved_path"
unset FNM_PATH
rm -rf "$_fnm_home"

# A Homebrew/Cargo/release install has fnm on PATH already but may not
# have created the data dir yet; setup_fnm must still run `fnm env`
# (which creates it) rather than bailing on the missing dir.
start_test "setup_fnm runs fnm env when fnm present even if dir missing"
_fnm_bin=$(mktemp -d)
cat > "$_fnm_bin/fnm" << 'SCRIPT'
#!/bin/sh
echo 'export FNM_MARKER=loaded'
SCRIPT
chmod +x "$_fnm_bin/fnm"
PATH="$_fnm_bin:$_saved_path"
FNM_PATH="/nonexistent-fnm-dir-xyz"
shell=bash
setup_fnm
assert_equal "loaded" "${FNM_MARKER:-}"
PATH="$_saved_path"
shell="$_saved_shell"
unset FNM_MARKER FNM_PATH
rm -rf "$_fnm_bin"

start_test "setup_fnm loads env and adds dir when fnm present"
_fnm_home=$(mktemp -d)
_fnm_bin=$(mktemp -d)
cat > "$_fnm_bin/fnm" << 'SCRIPT'
#!/bin/sh
echo 'export FNM_MARKER=loaded'
SCRIPT
chmod +x "$_fnm_bin/fnm"
PATH="$_fnm_bin:$_saved_path"
FNM_PATH="$_fnm_home"
shell=bash
setup_fnm
assert_equal "loaded" "${FNM_MARKER:-}"

start_test "setup_fnm puts FNM_PATH on PATH when fnm present"
assert_true inpath "$_fnm_home"

PATH="$_saved_path"
shell="$_saved_shell"
unset FNM_MARKER FNM_PATH
rm -rf "$_fnm_home" "$_fnm_bin"

###############
# UTILITY FUNCTIONS

start_test "puts single arg"
assert_equal "hello" "$(puts hello)"
start_test "puts multiple args"
assert_equal "hello world" "$(puts hello world)"
start_test "puts empty"
assert_equal "" "$(puts)"
start_test "puts special chars"
assert_equal "-n -e" "$(puts -n -e)"
start_test "puts backslash"
assert_equal 'hello\nworld' "$(puts 'hello\nworld')"

start_test "gets preserves backslashes"
result=$(printf '%s\n' 'hello\tworld' | { gets val; puts "$val"; })
assert_equal 'hello\tworld' "$result"

start_test "join comma"
assert_equal "a,b,c" "$(join , a b c)"
start_test "join space"
assert_equal "a b c" "$(join " " a b c)"
start_test "join single"
assert_equal "a" "$(join , a)"
start_test "join empty sep"
assert_equal "abc" "$(join "" a b c)"

start_test "body passes header and body"
result=$(printf 'HEADER\nline1\nline2\n' | body cat)
assert_equal "HEADER
line1
line2" "$result"

start_test "body filters body only"
result=$(printf 'HEADER\nfoo\nbar\nbaz\n' | body grep bar)
assert_equal "HEADER
bar" "$result"

start_test "body -2 keeps two header lines"
result=$(printf 'H1\nH2\ndata1\ndata2\n' | body -2 cat)
assert_equal "H1
H2
data1
data2" "$result"

start_test "body -2 filters body only"
result=$(printf 'H1\nH2\nalpha\nbeta\n' | body -2 grep beta)
assert_equal "H1
H2
beta" "$result"

start_test "first_arg_last moves first arg to end"
result=$(first_arg_last echo target a b)
assert_equal "a b target" "$result"

start_test "first_arg_last single arg"
result=$(first_arg_last echo only)
assert_equal "only" "$result"

start_test "shift_options moves options before target"
result=$(shift_options echo target -a -b rest)
assert_equal "-a -b target rest" "$result"

start_test "shift_options no options"
result=$(shift_options echo target rest)
assert_equal "target rest" "$result"

start_test "shift_options option only"
result=$(shift_options echo target -x)
assert_equal "-x target" "$result"

start_test "shift_options stops at --"
result=$(shift_options echo target -- -b)
assert_equal "target -- -b" "$result"

# Test find_test_file
# Create temp files to test against
_tmpdir=$(mktemp -d)
touch "$_tmpdir/foo.py"
touch "$_tmpdir/foo_test.py"
touch "$_tmpdir/bar.go"
touch "$_tmpdir/bar_test.go"

start_test "find_test_file finds python test"
result=$(find_test_file "$_tmpdir/foo.py")
assert_equal "${_tmpdir}/foo_test.py" "$result"

start_test "find_test_file finds go test"
result=$(find_test_file "$_tmpdir/bar.go")
assert_equal "${_tmpdir}/bar_test.go" "$result"

start_test "find_test_file returns empty for missing"
result=$(find_test_file "$_tmpdir/missing.py")
assert_equal "" "$result"

# Test find_test_file with nested directories
mkdir -p "$_tmpdir/src/pkg/sub"
touch "$_tmpdir/src/pkg/sub/handler.py"
touch "$_tmpdir/src/pkg/sub/handler_test.py"

start_test "find_test_file finds nested test"
result=$(find_test_file "$_tmpdir/src/pkg/sub/handler.py")
assert_equal "$_tmpdir/src/pkg/sub/handler_test.py" "$result"

# Test find_test_file with nested dir but no test file
mkdir -p "$_tmpdir/src/deep/dir"
touch "$_tmpdir/src/deep/dir/utils.go"

start_test "find_test_file empty for nested missing test"
result=$(find_test_file "$_tmpdir/src/deep/dir/utils.go")
assert_equal "" "$result"

rm -rf "$_tmpdir"

start_test "path finds sh"
PATH="/usr/bin:/bin"
result=$(path sh)
assert_equal "/usr/bin/sh" "$result"

start_test "path returns false for missing command"
path nonexistent_command_xyz >/dev/null 2>&1
assert_equal "1" "$?"

# Restore PATH so later `have_command <shell>` gates find zsh/bash/fish
# wherever they live (Homebrew, ~/.cargo/bin, etc.). Without this, the
# narrowed PATH above leaks through the rest of the file and the zsh
# autocd widget tests at the bottom silently skip on any machine where
# zsh isn't in /usr/bin.
PATH="$_saved_path"

start_test "get_address_records extracts A and AAAA"
input="example.com.		300	IN	A	93.184.216.34
example.com.		300	IN	AAAA	2606:2800:220:1:248:1893:25c8:1946"
result=$(echo "$input" | get_address_records)
expected="93.184.216.34
2606:2800:220:1:248:1893:25c8:1946"
assert_equal "$expected" "$result"

start_test "get_ptr_records extracts PTR"
input="34.216.184.93.in-addr.arpa. 300	IN	PTR	example.com."
result=$(echo "$input" | get_ptr_records)
assert_equal "example.com." "$result"

start_test "each runs command on each line"
result=$(printf 'a\nb\nc\n' | each echo "item:")
expected="item: a
item: b
item: c"
assert_equal "$expected" "$result"

start_test "delline removes specified line"
_tmpfile=$(mktemp)
printf 'line1\nline2\nline3\n' > "$_tmpfile"
delline 2 "$_tmpfile"
result=$(cat "$_tmpfile")
expected="line1
line3"
assert_equal "$expected" "$result"
rm -f "$_tmpfile"

start_test "delline on empty file"
_tmpfile=$(mktemp)
printf '' > "$_tmpfile"
delline 1 "$_tmpfile"
result=$(cat "$_tmpfile")
assert_equal "" "$result"
rm -f "$_tmpfile"

start_test "delline removes only line"
_tmpfile=$(mktemp)
printf 'only line\n' > "$_tmpfile"
delline 1 "$_tmpfile"
result=$(cat "$_tmpfile")
assert_equal "" "$result"
rm -f "$_tmpfile"

start_test "delline no-op for out of range line"
_tmpfile=$(mktemp)
printf 'only line\n' > "$_tmpfile"
delline 5 "$_tmpfile"
result=$(cat "$_tmpfile")
assert_equal "only line" "$result"
rm -f "$_tmpfile"

###############
# COMMAND INSPECTION

start_test "is_builtin cd"
assert_true is_builtin cd
start_test "is_builtin ls"
assert_false is_builtin ls

start_test "is_command /bin/sh"
assert_true is_command sh
start_test "is_command nonexistent_xyz"
assert_false is_command nonexistent_xyz

start_test "have_command sh"
assert_true have_command sh
start_test "have_command nonexistent_xyz"
assert_false have_command nonexistent_xyz

start_test "is_runnable sh"
assert_true is_runnable sh
start_test "is_runnable cd"
assert_true is_runnable cd
start_test "is_runnable is_runnable (function)"
assert_true is_runnable is_runnable
start_test "is_runnable nonexistent_xyz"
assert_false is_runnable nonexistent_xyz

start_test "is_alias detects alias"
alias _test_alias_xyz='echo hi'
assert_true is_alias _test_alias_xyz
start_test "is_alias not an alias"
assert_false is_alias nonexistent_xyz
unalias _test_alias_xyz

###############
# ERROR AND WARN

start_test "error prints to stderr"
result=$(error "test error message" 2>&1)
assert_equal "test error message" "$result"

start_test "warn prints to stderr"
result=$(warn "test warning" 2>&1)
assert_equal "test warning" "$result"

###############
# QUIET

start_test "quiet suppresses stdout"
result=$(quiet echo "should not appear")
assert_equal "" "$result"

start_test "quiet suppresses stderr"
result=$(quiet sh -c 'echo err >&2')
assert_equal "" "$result"

start_test "quiet preserves success"
quiet true
assert_equal "0" "$?"

start_test "quiet preserves failure"
quiet false
assert_equal "1" "$?"

###############
# RUN

start_test "run executes command"
result=$(SIMULATE=false run echo "hello")
# logger may not be available, so just check it runs
assert_equal "hello" "$result"

start_test "run simulates command"
result=$(SIMULATE=true run echo "hello")
assert_equal "Would run echo hello" "$result"

# Test that SIMULATE=true does NOT actually execute the command.
# Checking stdout alone can't distinguish "logged but also ran" from
# "logged only"; give run a command with an observable side effect
# (creating a file) and assert the side effect did not happen.
start_test "run SIMULATE=true does not execute command"
_simrun_dir=$(mktemp -d)
SIMULATE=true run touch "$_simrun_dir/marker" >/dev/null 2>&1
assert_false \
    test -e "$_simrun_dir/marker"
# And the default path (SIMULATE=false) really does execute it.
start_test "run SIMULATE=false executes command"
SIMULATE=false run touch "$_simrun_dir/marker" >/dev/null 2>&1
assert_true \
    test -e "$_simrun_dir/marker"
rm -rf "$_simrun_dir"

###############
# FILE OPERATIONS

_tmpdir=$(mktemp -d)

start_test "bak creates .bak file"
touch "$_tmpdir/testfile"
(cd "$_tmpdir" && bak testfile)
assert_true test -f "$_tmpdir/testfile.bak"
start_test "bak removes original"
assert_false test -f "$_tmpdir/testfile"

start_test "unbak restores from .bak arg"
(cd "$_tmpdir" && unbak testfile.bak)
assert_true test -f "$_tmpdir/testfile"
start_test "unbak removes .bak"
assert_false test -f "$_tmpdir/testfile.bak"

start_test "unbak restores from original name"
(cd "$_tmpdir" && bak testfile)
(cd "$_tmpdir" && unbak testfile)
assert_true test -f "$_tmpdir/testfile"
start_test "unbak removes .bak (original name)"
assert_false test -f "$_tmpdir/testfile.bak"

start_test "bak multiple files a"
touch "$_tmpdir/a" "$_tmpdir/b"
(cd "$_tmpdir" && bak a b)
assert_true test -f "$_tmpdir/a.bak"
start_test "bak multiple files b"
assert_true test -f "$_tmpdir/b.bak"

rm -rf "$_tmpdir"

start_test "isort sorts file in place"
_tmpfile=$(mktemp)
printf 'cherry\napple\nbanana\n' > "$_tmpfile"
isort "$_tmpfile"
result=$(cat "$_tmpfile")
expected="apple
banana
cherry"
assert_equal "$expected" "$result"
rm -f "$_tmpfile"

start_test "realdir returns absolute directory"
_tmpdir=$(mktemp -d)
mkdir -p "$_tmpdir/subdir"
touch "$_tmpdir/subdir/file"
result=$(realdir "$_tmpdir/subdir/file")
expected=$(readlink -f "$_tmpdir/subdir")
assert_equal "$expected" "$result"
rm -rf "$_tmpdir"

###############
# FIND_UP

_tmpdir=$(mktemp -d)
mkdir -p "$_tmpdir/a/b/c"
touch "$_tmpdir/a/marker.txt"

start_test "find_up finds file in ancestor"
result=$(cd "$_tmpdir/a/b/c" && find_up marker.txt)
assert_equal "$_tmpdir/a/marker.txt" "$result"

start_test "find_up finds file in current dir"
result=$(cd "$_tmpdir/a" && find_up marker.txt)
assert_equal "$_tmpdir/a/marker.txt" "$result"

start_test "find_up returns 1 for missing file"
(cd "$_tmpdir/a/b/c" && find_up nonexistent_file_xyz)
assert_equal "1" "$?"

rm -rf "$_tmpdir"

###############
# AGE

start_test "age returns positive number"
_tmpfile=$(mktemp)
touch -d '2 seconds ago' "$_tmpfile"
result=$(age "$_tmpfile")
assert_true test "$result" -ge 1
rm -f "$_tmpfile"

###############
# WHAT

start_test "what finds sh"
result=$(what sh)
assert_true test -n "$result"

start_test "what shows function definition"
result=$(what is_runnable)
assert_true test -n "$result"

###############
# TRYDIFF AND APPLYDIFF

start_test "trydiff produces output"
_tmpdir=$(mktemp -d)
printf 'hello\nworld\n' > "$_tmpdir/input"
# Create a transform script for testing
cat > "$_tmpdir/upcase" << 'SCRIPT'
#!/bin/sh
tr a-z A-Z < "$1"
SCRIPT
chmod +x "$_tmpdir/upcase"
trydiff_result=$(cd "$_tmpdir" && trydiff ./upcase input 2>&1)
assert_true test -n "$trydiff_result"
# Original file should be unchanged
start_test "trydiff does not modify original"
result=$(cat "$_tmpdir/input")
assert_equal "hello
world" "$result"

start_test "applydiff modifies file"
(cd "$_tmpdir" && applydiff ./upcase input)
result=$(cat "$_tmpdir/input")
assert_equal "HELLO
WORLD" "$result"
rm -rf "$_tmpdir"

###############
# RECENT

start_test "recent shows newest first"
_tmpdir=$(mktemp -d)
touch -d '2 seconds ago' "$_tmpdir/old"
touch "$_tmpdir/new"
result=$(cd "$_tmpdir" && recent)
first_line=$(echo "$result" | head -n 1)
assert_equal "new" "$first_line"

start_test "recent -1 shows one file"
result=$(cd "$_tmpdir" && recent -1)
line_count=$(echo "$result" | wc -l)
assert_equal "1" "$line_count"
rm -rf "$_tmpdir"

###############
# TZ2TZ

start_test "tz2tz converts timezone"
result=$(tz2tz UTC America/New_York "2024-01-15 12:00:00")
assert_contains "2024" "$result"

start_test "tz2tz with multi-word date spec"
result=$(tz2tz UTC UTC "2024-01-15 12:00:00")
assert_contains "12:00:00" "$result"

###############
# ENVIRONMENT DETECTION

start_test "connected_via_ssh with SSH_CONNECTION"
SSH_CONNECTION="1.2.3.4 5678 5.6.7.8 22"
assert_true connected_via_ssh

start_test "connected_via_ssh without SSH_CONNECTION"
unset SSH_CONNECTION
assert_false connected_via_ssh

start_test "connected_remotely with SSH_CONNECTION"
SSH_CONNECTION="1.2.3.4 5678 5.6.7.8 22"
assert_true connected_remotely

start_test "connected_remotely without SSH_CONNECTION"
unset SSH_CONNECTION
assert_false connected_remotely

###############
# SSH CLIENT HOST

start_test "ssh_client_host returns LC_CLIENT_HOST when set"
result="$(LC_CLIENT_HOST="laptop" SSH_CONNECTION="" ssh_client_host)"
assert_equal "laptop" "$result"

start_test "ssh_client_host fails when not an ssh session"
unset LC_CLIENT_HOST SSH_CONNECTION
assert_false ssh_client_host

start_test "ssh_client_host reverse-resolves the client IP"
result="$(
    unset LC_CLIENT_HOST
    SSH_CONNECTION="1.2.3.4 5555 10.0.0.1 22"
    have_command() { test "$1" = getent; }
    getent() { printf '%s\n' "1.2.3.4   client.example.com   alias"; }
    ssh_client_host
)"
assert_equal "client" "$result"

start_test "ssh_client_host falls back to the client IP"
result="$(
    unset LC_CLIENT_HOST
    SSH_CONNECTION="1.2.3.4 5555 10.0.0.1 22"
    have_command() { return 1; }
    ssh_client_host
)"
assert_equal "1.2.3.4" "$result"

start_test "ssh_to sends client host via LC_CLIENT_HOST and SendEnv"
result="$(
    short_hostname() { puts "clienthost"; }
    have_command() { return 1; }   # no rw -> ssh path
    ssh() { puts "ssh LC_CLIENT_HOST=$LC_CLIENT_HOST args=$*"; }
    ssh_to myhost
)"
assert_contains "LC_CLIENT_HOST=clienthost" "$result"
assert_contains "-oSendEnv=LC_CLIENT_HOST" "$result"
assert_contains "myhost" "$result"

start_test "ssh_to rw path also sets LC_CLIENT_HOST"
result="$(
    short_hostname() { puts "clienthost"; }
    have_command() { test "$1" = rw; }   # rw available, single arg -> rw path
    rw() { puts "rw LC_CLIENT_HOST=$LC_CLIENT_HOST args=$*"; }
    ssh_to myhost
)"
assert_contains "rw LC_CLIENT_HOST=clienthost" "$result"
assert_contains "args=-r myhost" "$result"

start_test "ssh_to does not leak LC_CLIENT_HOST into the shell"
result="$(
    short_hostname() { puts "clienthost"; }
    have_command() { return 1; }
    ssh() { :; }
    ssh_to myhost
    puts "after=[${LC_CLIENT_HOST:-}]"
)"
assert_equal "after=[]" "$result"

start_test "ssh_to preserves an inherited LC_CLIENT_HOST"
result="$(
    short_hostname() { puts "clienthost"; }
    have_command() { return 1; }
    ssh() { puts "ssh saw $LC_CLIENT_HOST"; }
    export LC_CLIENT_HOST="inbound"
    ssh_to myhost
    puts "after=[${LC_CLIENT_HOST:-}]"
)"
assert_contains "ssh saw clienthost" "$result"
assert_contains "after=[inbound]" "$result"

# set_up_ssh_aliases is inside the SHRC_LOAD_FUNCTIONS_ONLY guard, so
# extract it directly to exercise the no-config branch.
_set_up_ssh_aliases_def="$(sed -n '/^set_up_ssh_aliases() {/,/^}/p' "$_srcdir/shrc")"

start_test "set_up_ssh_aliases returns 0 when ~/.ssh/config is missing"
result="$(
    eval "$_set_up_ssh_aliases_def"
    HOME="$(mktemp -d)"
    set -e
    set_up_ssh_aliases
    puts ok
    rm -rf "$HOME"
)"
assert_equal "ok" "$result"

unset _set_up_ssh_aliases_def

start_test "inside_tmux with TMUX set"
TMUX="/tmp/tmux-1000/default,12345,0"
assert_true inside_tmux

start_test "inside_tmux without TMUX"
unset TMUX
assert_false inside_tmux

start_test "in_shpool with SHPOOL_SESSION_NAME"
SHPOOL_SESSION_NAME="main"
assert_true in_shpool

start_test "in_shpool without SHPOOL_SESSION_NAME"
unset SHPOOL_SESSION_NAME
assert_false in_shpool

###############
# SHPOOL FUNCTIONS

# want_shpool folds in `! in_shpool`, `! inside_tmux`,
# `have_command shpool`, `have_command autoshpool`, the `stdin_is_tty`
# check, and the WANT_SHPOOL=0 opt-out, so each block sets all the
# gating stubs.
in_shpool() { false; }
inside_tmux() { false; }
have_command() { case "$1" in shpool|autoshpool) return 0 ;; *) return 1 ;; esac; }
stdin_is_tty() { true; }

start_test "want_shpool when connected remotely"
connected_remotely() { true; }
inside_project() { false; }
assert_true want_shpool

start_test "want_shpool when inside project"
connected_remotely() { false; }
inside_project() { true; }
assert_true want_shpool

start_test "want_shpool when both remote and inside project"
connected_remotely() { true; }
inside_project() { true; }
assert_true want_shpool

start_test "want_shpool when neither remote nor inside project"
connected_remotely() { false; }
inside_project() { false; }
assert_false want_shpool

start_test "want_shpool false when WANT_SHPOOL=0"
connected_remotely() { true; }
inside_project() { true; }
WANT_SHPOOL=0
assert_false want_shpool
unset WANT_SHPOOL

start_test "want_shpool true when WANT_SHPOOL unset"
unset WANT_SHPOOL
connected_remotely() { true; }
inside_project() { false; }
assert_true want_shpool

start_test "want_shpool false when already in shpool"
in_shpool() { true; }
connected_remotely() { true; }
assert_false want_shpool
in_shpool() { false; }

start_test "want_shpool false when shpool not installed"
have_command() { false; }
connected_remotely() { true; }
assert_false want_shpool
have_command() { case "$1" in shpool|autoshpool) return 0 ;; *) return 1 ;; esac; }

start_test "want_shpool false when autoshpool not installed"
# Mirrors want_tmux's autotmux gate: shpool without the scripts repo must
# fall through to the tmux path, not error at every shell start.
have_command() { test "$1" = shpool; }
connected_remotely() { true; }
assert_false want_shpool
have_command() { case "$1" in shpool|autoshpool) return 0 ;; *) return 1 ;; esac; }

start_test "want_shpool false when stdin is not a tty"
stdin_is_tty() { false; }
connected_remotely() { true; }
assert_false want_shpool
stdin_is_tty() { true; }

start_test "want_shpool false when inside tmux"
inside_tmux() { true; }
connected_remotely() { true; }
assert_false want_shpool
inside_tmux() { false; }

# want_tmux mirrors want_shpool but gates on both the tmux and autotmux
# binaries. Reuse the in_shpool / inside_tmux / stdin_is_tty stubs from
# above; only the looked-up command names differ.
have_command() { case "$1" in tmux|autotmux) return 0 ;; *) return 1 ;; esac; }

start_test "want_tmux when connected remotely"
connected_remotely() { true; }
inside_project() { false; }
assert_true want_tmux

start_test "want_tmux when inside project"
connected_remotely() { false; }
inside_project() { true; }
assert_true want_tmux

start_test "want_tmux when neither remote nor inside project"
connected_remotely() { false; }
inside_project() { false; }
assert_false want_tmux

start_test "want_tmux false when WANT_TMUX=0"
connected_remotely() { true; }
inside_project() { true; }
WANT_TMUX=0
assert_false want_tmux
unset WANT_TMUX

start_test "want_tmux false when tmux not installed"
have_command() { false; }
connected_remotely() { true; }
assert_false want_tmux
have_command() { case "$1" in tmux|autotmux) return 0 ;; *) return 1 ;; esac; }

start_test "want_tmux false when autotmux not installed"
have_command() { test "$1" = tmux; }
connected_remotely() { true; }
assert_false want_tmux
have_command() { case "$1" in tmux|autotmux) return 0 ;; *) return 1 ;; esac; }

start_test "want_tmux false when already inside tmux"
inside_tmux() { true; }
connected_remotely() { true; }
assert_false want_tmux
inside_tmux() { false; }

start_test "want_tmux false when inside shpool"
in_shpool() { true; }
connected_remotely() { true; }
assert_false want_tmux
in_shpool() { false; }

start_test "want_tmux false when stdin is not a tty"
stdin_is_tty() { false; }
connected_remotely() { true; }
assert_false want_tmux
stdin_is_tty() { true; }

# Restore real in_shpool / inside_tmux / have_command / stdin_is_tty so
# later tests use the real implementations (the
# maybe_start_session_and_exit block re-stubs them inside its own
# subshells).
unset -f in_shpool inside_tmux have_command stdin_is_tty
SHRC_LOAD_FUNCTIONS_ONLY=1 . "$_srcdir/shrc"

# Test switchshpool
# Stub autoshpool to record what it was called with
_autoshpool_calls="$_testdir/autoshpool_calls"
autoshpool() {
    echo "autoshpool $*" >> "$_autoshpool_calls"
    return 0
}

start_test "switchshpool exits 0 on success"
rm -f "$_autoshpool_calls"
# Run in subshell since switchshpool calls exit on success
(switchshpool "newsession")
assert_equal "0" "$?"

start_test "switchshpool calls autoshpool switch"
result="$(cat "$_autoshpool_calls" 2>/dev/null)"
assert_equal "autoshpool switch newsession" "$result"

start_test "switchshpool does not exit when autoshpool fails"
rm -f "$_autoshpool_calls"
_returned="$_testdir/shpool_returned"
autoshpool() {
    echo "autoshpool $*" >> "$_autoshpool_calls"
    return 1
}
rm -f "$_returned"
(switchshpool "badsession"; echo yes > "$_returned")
assert_true test -f "$_returned"

# Clean up
unset -f autoshpool
rm -f "$_autoshpool_calls" "$_returned"
# Re-source shrc to restore the real functions the switchshpool tests above
# stubbed. autoshpool is now a plain scripts-repo binary (it passes
# `shpool attach -d` to open the session in the caller's directory), so shrc no
# longer defines an autoshpool wrapper for the pwd workaround.
SHRC_LOAD_FUNCTIONS_ONLY=1 . "$_srcdir/shrc"

start_test "shrc does not wrap autoshpool (the scripts-repo binary is used directly)"
assert_false is_function autoshpool

# Test maybe_start_session_and_exit. The "should we even try" gating lives
# in want_tmux / want_shpool; the dispatch picks the backend named by
# session_backend (shpool by default, tmux as the fallback).
_autoshpool_calls="$_testdir/autoshpool_calls"
_autotmux_calls="$_testdir/autotmux_calls"
_returned="$_testdir/shpool_returned"

start_test "maybe_start_session_and_exit starts shpool when shpool is preferred"
rm -f "$_autoshpool_calls" "$_autotmux_calls" "$_returned"
(
    session_backend() { echo shpool; }
    want_tmux() { true; }
    want_shpool() { true; }
    autotmux() { echo "autotmux $*" >> "$_autotmux_calls"; return 0; }
    autoshpool() { echo "autoshpool $*" >> "$_autoshpool_calls"; return 0; }
    maybe_start_session_and_exit
    echo yes > "$_returned"
)
assert_false test -f "$_returned"

start_test "maybe_start_session_and_exit prefers shpool over tmux"
assert_equal "autoshpool " "$(cat "$_autoshpool_calls" 2>/dev/null)"
assert_false test -f "$_autotmux_calls"

start_test "maybe_start_session_and_exit does not exit when autoshpool fails"
rm -f "$_autoshpool_calls" "$_returned"
(
    session_backend() { echo shpool; }
    want_shpool() { true; }
    autoshpool() { return 1; }
    maybe_start_session_and_exit
    echo yes > "$_returned"
)
assert_true test -f "$_returned"

start_test "maybe_start_session_and_exit falls back to tmux when session_backend is tmux"
rm -f "$_autotmux_calls" "$_returned"
(
    session_backend() { echo tmux; }
    want_tmux() { true; }
    want_shpool() { false; }
    autotmux() { echo "autotmux $*" >> "$_autotmux_calls"; return 0; }
    maybe_start_session_and_exit
    echo yes > "$_returned"
)
assert_false test -f "$_returned"

start_test "maybe_start_session_and_exit calls autotmux with no args on fallback"
assert_equal "autotmux " "$(cat "$_autotmux_calls" 2>/dev/null)"

start_test "maybe_start_session_and_exit does not exit when tmux fallback fails"
rm -f "$_autotmux_calls" "$_returned"
(
    session_backend() { echo tmux; }
    want_tmux() { true; }
    autotmux() { return 1; }
    maybe_start_session_and_exit
    echo yes > "$_returned"
)
assert_true test -f "$_returned"

start_test "maybe_start_session_and_exit skips when session_backend is empty"
rm -f "$_autoshpool_calls" "$_autotmux_calls" "$_returned"
(
    session_backend() { echo ""; }
    want_tmux() { true; }
    want_shpool() { true; }
    autotmux() { echo "autotmux $*" >> "$_autotmux_calls"; return 0; }
    autoshpool() { echo "autoshpool $*" >> "$_autoshpool_calls"; return 0; }
    maybe_start_session_and_exit
    echo yes > "$_returned"
)
assert_true test -f "$_returned"

start_test "maybe_start_session_and_exit starts no backend when none selected"
assert_false test -f "$_autotmux_calls"
assert_false test -f "$_autoshpool_calls"

# want_* still gates: an opted-out backend doesn't auto-start even when
# session_backend names it (e.g. inside_tmux is true).
start_test "maybe_start_session_and_exit skips shpool when want_shpool false"
rm -f "$_autoshpool_calls" "$_returned"
(
    session_backend() { echo shpool; }
    want_shpool() { false; }
    autoshpool() { echo "autoshpool $*" >> "$_autoshpool_calls"; return 0; }
    maybe_start_session_and_exit
    echo yes > "$_returned"
)
assert_true test -f "$_returned"
assert_false test -f "$_autoshpool_calls"

######################################
# Shell re-exec: switching $SHELL via ~/.env without chsh. sshd always
# launches the /etc/passwd login shell and ignores $SHELL, so the login shell
# re-execs into $SHELL itself. want_reexec is the (interactive/tty-independent)
# policy; reexec_into_shell adds the interactive + tty gate and performs it.

# Fake, executable shells so `command -v "$SHELL"` succeeds without depending
# on bash/zsh living at a particular path on the test host.
mkdir -p "$_testdir/fakebin"
printf '#!/bin/sh\nexit 0\n' > "$_testdir/fakebin/bash"
printf '#!/bin/sh\nexit 0\n' > "$_testdir/fakebin/zsh"
chmod +x "$_testdir/fakebin/bash" "$_testdir/fakebin/zsh"
_fakebash="$_testdir/fakebin/bash"
_fakezsh="$_testdir/fakebin/zsh"

# Run want_reexec in a subshell so the temporary $shell/$SHELL/guard
# assignments don't bleed into later tests; echo yes/no for the parent.
_want_reexec_result() {
    # usage: _want_reexec_result RUNNING_SHELL SHELL_VALUE [GUARD]
    ( shell="$1"; SHELL="$2"; SHELL_REEXEC_DONE="$3"
      if want_reexec; then echo yes; else echo no; fi )
}

start_test "want_reexec switches zsh -> a different supported, executable shell"
assert_equal "yes" "$(_want_reexec_result zsh "$_fakebash" "")"

start_test "want_reexec switches bash -> a different supported, executable shell"
assert_equal "yes" "$(_want_reexec_result bash "$_fakezsh" "")"

start_test "want_reexec stays put when SHELL names the running shell"
assert_equal "no" "$(_want_reexec_result bash "$_fakebash" "")"

start_test "want_reexec ignores an unsupported target shell"
assert_equal "no" "$(_want_reexec_result zsh "$_testdir/fakebin/fish" "")"

start_test "want_reexec ignores a non-executable target shell"
assert_equal "no" "$(_want_reexec_result zsh "$_testdir/nope/bash" "")"

start_test "want_reexec does not switch twice (SHELL_REEXEC_DONE guard)"
assert_equal "no" "$(_want_reexec_result zsh "$_fakebash" "1")"

# reexec_into_shell must NEVER exec for a non-interactive shell, or it would
# break `ssh host cmd`, scp, rsync, and cron. The test runs non-interactively,
# so even with want_reexec satisfied it must fall through (the process
# survives to write the marker rather than being replaced by exec).
start_test "reexec_into_shell is a no-op in a non-interactive shell"
rm -f "$_testdir/reexec_survived"
( shell=zsh; SHELL="$_fakebash"
  unset SHELL_REEXEC_DONE SHRC_LOAD_FUNCTIONS_ONLY
  reexec_into_shell
  echo survived > "$_testdir/reexec_survived" )
assert_true test -f "$_testdir/reexec_survived"

# The re-exec is limited to login shells, so manually starting the other shell
# from an existing prompt (e.g. `zsh` from a bash login) isn't hijacked. The
# test harness itself is a non-login shell, so login_shell is false here.
start_test "login_shell is false for a non-login shell"
assert_false login_shell

# Lock in the login gate: reexec_into_shell must consult login_shell.
start_test "reexec_into_shell is gated on login_shell"
assert_contains "login_shell || return" \
    "$(grep -F 'login_shell || return' "$_srcdir/shrc")"

######################################
# setup_shell_compat_common / setup_shell_compat_interactive split
# (essential, always-run vs interactive-only)

start_test "setup_shell_compat_common is defined"
assert_true is_function setup_shell_compat_common

start_test "setup_shell_compat_interactive is defined"
assert_true is_function setup_shell_compat_interactive

start_test "setup_shell_compat_interactive runs without error"
assert_true setup_shell_compat_interactive

######################################
# ~/.env (shared, from this repo) and ~/.env.local (per-host overrides) are
# applied once per process tree via the exported DOTENV_SOURCED sentinel, so
# a zsh login's .zlogin re-read and a zsh->bash re-exec don't re-apply
# self-referential assignments like `PATH=$HOME/bin:$PATH`.

start_test "zshenv guards ~/.env sourcing with the DOTENV_SOURCED sentinel"
assert_contains "export DOTENV_SOURCED=1" \
    "$(grep -F 'export DOTENV_SOURCED=1' "$_srcdir/zshenv")"

start_test "profile guards ~/.env sourcing with the DOTENV_SOURCED sentinel"
assert_contains "export DOTENV_SOURCED=1" \
    "$(grep -F 'export DOTENV_SOURCED=1' "$_srcdir/profile")"

start_test "shrc guards ~/.env sourcing with the DOTENV_SOURCED sentinel"
assert_contains "export DOTENV_SOURCED=1" \
    "$(grep -F 'export DOTENV_SOURCED=1' "$_srcdir/shrc")"

# All three sourcing sites apply ~/.env then ~/.env.local, in that order,
# so per-host PATH prepends land in front of the shared dirs.
for _dotenv_file in zshenv profile shrc; do
    start_test "$_dotenv_file sources ~/.env then ~/.env.local"
    assert_contains '"$HOME/.env" "$HOME/.env.local"' "$(cat "$_srcdir/$_dotenv_file")"
done

# Behavioural check of the guard pattern: running the guarded source twice
# (as zshenv then profile would) applies ~/.env only once.
start_test "DOTENV_SOURCED sentinel applies ~/.env only once"
_dotenv="$_testdir/dotenv"
printf 'COUNT_VAR=$((${COUNT_VAR:-0}+1)); export COUNT_VAR\n' > "$_dotenv"
_dotenv_result=$(
    unset DOTENV_SOURCED COUNT_VAR
    if test -z "${DOTENV_SOURCED:-}" && test -f "$_dotenv"; then . "$_dotenv"; export DOTENV_SOURCED=1; fi
    if test -z "${DOTENV_SOURCED:-}" && test -f "$_dotenv"; then . "$_dotenv"; export DOTENV_SOURCED=1; fi
    echo "$COUNT_VAR"
)
assert_equal "1" "$_dotenv_result"

# zshenv and profile wrap the ~/.env source in `set -a` / `set +a` so bare
# `VAR=val` lines (the format gcloud and other deployment tools expect) are
# auto-exported into child processes -- and `set +a` is restored so the
# caller's allexport state doesn't leak.
start_test "zshenv wraps ~/.env sourcing in set -a / set +a"
assert_true grep -qF 'set -a' "$_srcdir/zshenv"
assert_true grep -qF 'set +a' "$_srcdir/zshenv"

start_test "profile wraps ~/.env sourcing in set -a / set +a"
assert_true grep -qF 'set -a' "$_srcdir/profile"
assert_true grep -qF 'set +a' "$_srcdir/profile"

# Run the exact dotenv-sourcing guard from zshenv/profile, so the tests
# below exercise the real wrapper instead of an inline copy that can drift.
_run_dotenv_guard() {
    if test -z "${DOTENV_SOURCED:-}" && test -f "$_dotenv"; then
        case $- in *a*) _dotenv_had_a=1;; *) _dotenv_had_a=0;; esac
        set -a
        . "$_dotenv"
        test "$_dotenv_had_a" = 1 || set +a
        unset _dotenv_had_a
        export DOTENV_SOURCED=1
    fi
}

start_test "set -a around ~/.env exports bare VAR=val to children"
_dotenv="$_testdir/dotenv_bare"
printf 'BARE_VAR=hello\n' > "$_dotenv"
_dotenv_bare_result=$(
    unset DOTENV_SOURCED BARE_VAR
    _run_dotenv_guard
    sh -c 'echo "$BARE_VAR"'
)
assert_equal "hello" "$_dotenv_bare_result"

start_test "~/.env sourcing leaves allexport off when caller had it off"
_dotenv="$_testdir/dotenv_bare"
printf 'BARE_VAR=hello\n' > "$_dotenv"
_dotenv_allexport_off=$(
    unset DOTENV_SOURCED BARE_VAR
    _run_dotenv_guard
    LATER_VAR=world
    sh -c 'echo "${LATER_VAR:-unset}"'
)
assert_equal "unset" "$_dotenv_allexport_off"

# Regression: if the caller already had `set -a` on (e.g. `bash -a -l`), the
# guard must NOT turn it off, or later assignments would silently stop
# propagating to children.
start_test "~/.env sourcing preserves allexport when caller had it on"
_dotenv="$_testdir/dotenv_bare"
printf 'BARE_VAR=hello\n' > "$_dotenv"
_dotenv_allexport_on=$(
    unset DOTENV_SOURCED BARE_VAR
    set -a
    _run_dotenv_guard
    LATER_VAR=world
    sh -c 'echo "${LATER_VAR:-unset}"'
    set +a
)
assert_equal "world" "$_dotenv_allexport_on"

# Test session_backend / autosession / switchsession dispatch. session_backend
# names the preferred manager; the wrappers route to the matching binary. Each
# branch requires both the multiplexer and its auto* helper (tmux+autotmux,
# shpool+autoshpool).
_dispatch_calls="$_testdir/dispatch_calls"
have_command() { case "$1" in tmux|autotmux|shpool|autoshpool) return 0;; *) return 1;; esac; }

start_test "session_backend prefers shpool when both available"
assert_equal "shpool" "$(session_backend)"

start_test "session_backend uses tmux when WANT_SHPOOL=0"
WANT_SHPOOL=0
assert_equal "tmux" "$(session_backend)"
unset WANT_SHPOOL

start_test "session_backend uses tmux when shpool missing"
have_command() { case "$1" in tmux|autotmux) return 0;; *) return 1;; esac; }
assert_equal "tmux" "$(session_backend)"
have_command() { case "$1" in tmux|autotmux|shpool|autoshpool) return 0;; *) return 1;; esac; }

start_test "session_backend uses shpool when autotmux missing"
have_command() { case "$1" in tmux|shpool|autoshpool) return 0;; *) return 1;; esac; }
assert_equal "shpool" "$(session_backend)"
have_command() { case "$1" in tmux|autotmux|shpool|autoshpool) return 0;; *) return 1;; esac; }

start_test "session_backend uses tmux when autoshpool missing"
have_command() { case "$1" in tmux|autotmux|shpool) return 0;; *) return 1;; esac; }
assert_equal "tmux" "$(session_backend)"
have_command() { case "$1" in tmux|autotmux|shpool|autoshpool) return 0;; *) return 1;; esac; }

start_test "session_backend empty when nothing available"
have_command() { false; }
assert_equal "" "$(session_backend)"
have_command() { case "$1" in tmux|autotmux|shpool|autoshpool) return 0;; *) return 1;; esac; }

start_test "session_backend empty when both backends opted out"
WANT_TMUX=0
WANT_SHPOOL=0
assert_equal "" "$(session_backend)"
unset WANT_TMUX WANT_SHPOOL

# SESSION_BACKEND=tmux flips the preference: tmux wins when both are available,
# shpool is the fallback if tmux is missing.
start_test "session_backend prefers tmux when SESSION_BACKEND=tmux"
SESSION_BACKEND=tmux
assert_equal "tmux" "$(session_backend)"
unset SESSION_BACKEND

start_test "session_backend SESSION_BACKEND=tmux falls back to shpool when tmux missing"
SESSION_BACKEND=tmux
have_command() { case "$1" in shpool|autoshpool) return 0;; *) return 1;; esac; }
assert_equal "shpool" "$(session_backend)"
have_command() { case "$1" in tmux|autotmux|shpool|autoshpool) return 0;; *) return 1;; esac; }
unset SESSION_BACKEND

# SESSION_BACKEND=shpool matches the default ordering: shpool wins.
start_test "session_backend prefers shpool when SESSION_BACKEND=shpool"
SESSION_BACKEND=shpool
assert_equal "shpool" "$(session_backend)"
unset SESSION_BACKEND

# WANT_*=0 still wins even when SESSION_BACKEND names that backend.
start_test "session_backend honours WANT_TMUX=0 over SESSION_BACKEND=tmux"
SESSION_BACKEND=tmux
WANT_TMUX=0
assert_equal "shpool" "$(session_backend)"
unset SESSION_BACKEND WANT_TMUX

start_test "autosession runs autotmux on the tmux backend"
rm -f "$_dispatch_calls"
(
    session_backend() { echo tmux; }
    autotmux() { echo "autotmux $*" >> "$_dispatch_calls"; }
    autosession
)
assert_equal "autotmux " "$(cat "$_dispatch_calls" 2>/dev/null)"

start_test "autosession runs autoshpool on the shpool backend"
rm -f "$_dispatch_calls"
(
    session_backend() { echo shpool; }
    autoshpool() { echo "autoshpool $*" >> "$_dispatch_calls"; }
    autosession
)
assert_equal "autoshpool " "$(cat "$_dispatch_calls" 2>/dev/null)"

start_test "switchsession runs autotmux switch on the tmux backend"
rm -f "$_dispatch_calls"
(
    session_backend() { echo tmux; }
    autotmux() { echo "autotmux $*" >> "$_dispatch_calls"; }
    switchsession work
)
assert_equal "autotmux switch work" "$(cat "$_dispatch_calls" 2>/dev/null)"

start_test "switchsession runs switchshpool on the shpool backend"
rm -f "$_dispatch_calls"
(
    session_backend() { echo shpool; }
    switchshpool() { echo "switchshpool $*" >> "$_dispatch_calls"; }
    switchsession work
)
assert_equal "switchshpool work" "$(cat "$_dispatch_calls" 2>/dev/null)"

start_test "sessionattach runs tmux attach on the tmux backend"
rm -f "$_dispatch_calls"
(
    session_backend() { echo tmux; }
    tmux() { echo "tmux $*" >> "$_dispatch_calls"; }
    sessionattach work
)
assert_equal "tmux attach work" "$(cat "$_dispatch_calls" 2>/dev/null)"

start_test "sessionattach runs shpool attach on the shpool backend"
rm -f "$_dispatch_calls"
(
    session_backend() { echo shpool; }
    shpool() { echo "shpool $*" >> "$_dispatch_calls"; }
    sessionattach work
)
assert_equal "shpool attach work" "$(cat "$_dispatch_calls" 2>/dev/null)"

start_test "sessionlist runs tmuxlist on the tmux backend"
rm -f "$_dispatch_calls"
(
    session_backend() { echo tmux; }
    tmuxlist() { echo "tmuxlist $*" >> "$_dispatch_calls"; }
    sessionlist
)
assert_equal "tmuxlist " "$(cat "$_dispatch_calls" 2>/dev/null)"

start_test "sessionlist runs shpoollist on the shpool backend"
rm -f "$_dispatch_calls"
(
    session_backend() { echo shpool; }
    shpoollist() { echo "shpoollist $*" >> "$_dispatch_calls"; }
    sessionlist
)
assert_equal "shpoollist " "$(cat "$_dispatch_calls" 2>/dev/null)"

unset -f have_command
rm -f "$_dispatch_calls"
SHRC_LOAD_FUNCTIONS_ONLY=1 . "$_srcdir/shrc"

# Test jd/hd/gd & mjd/mhd/mgd. These live in shrc's interactive block as
# indented one-liners, so extract_func (which anchors on a column-0
# name()) can't reach them. Pull each one out by name, strip the leading
# indentation, and eval it. Fails loudly if the line is gone so a rename
# doesn't silently fall through to a system command.
_extract_oneliner() {
    local _def
    _def=$(sed -n "s/^[[:space:]]*\($1() {.*}\)\$/\1/p" "$_srcdir/shrc")
    if test -z "$_def"; then
        echo "FAIL: could not find one-liner '$1' in shrc" >&2
        failures=$((failures + 1))
        return 1
    fi
    eval "$_def"
}

_vcsdir_calls="$_testdir/vcsdir_calls"
# Record the underlying command + args, then autosession, in call order.
jjd()  { echo "jjd $*"  >> "$_vcsdir_calls"; return 0; }
hgd()  { echo "hgd $*"  >> "$_vcsdir_calls"; return 0; }
gitd() { echo "gitd $*" >> "$_vcsdir_calls"; return 0; }
autosession() { echo "autosession $*" >> "$_vcsdir_calls"; return 0; }

_extract_oneliner jd
_extract_oneliner hd
_extract_oneliner gd
_extract_oneliner mjd
_extract_oneliner mhd
_extract_oneliner mgd

start_test "jd runs jjd then autosession"
rm -f "$_vcsdir_calls"
jd repo
assert_equal "jjd repo
autosession " "$(cat "$_vcsdir_calls")"

start_test "hd runs hgd then autosession"
rm -f "$_vcsdir_calls"
hd repo
assert_equal "hgd repo
autosession " "$(cat "$_vcsdir_calls")"

start_test "gd runs gitd then autosession"
rm -f "$_vcsdir_calls"
gd repo
assert_equal "gitd repo
autosession " "$(cat "$_vcsdir_calls")"

start_test "mjd runs jjd -f then autosession"
rm -f "$_vcsdir_calls"
mjd repo
assert_equal "jjd -f repo
autosession " "$(cat "$_vcsdir_calls")"

start_test "mhd runs hgd -f then autosession"
rm -f "$_vcsdir_calls"
mhd repo
assert_equal "hgd -f repo
autosession " "$(cat "$_vcsdir_calls")"

start_test "mgd runs gitd -f then autosession"
rm -f "$_vcsdir_calls"
mgd repo
assert_equal "gitd -f repo
autosession " "$(cat "$_vcsdir_calls")"

start_test "mjd does not run autosession when jjd fails"
rm -f "$_vcsdir_calls"
jjd() { echo "jjd $*" >> "$_vcsdir_calls"; return 1; }
_extract_oneliner mjd
mjd repo
assert_equal "jjd -f repo" "$(cat "$_vcsdir_calls")"

# The session-manager aliases are the lean {verb}{backend} set, each a thin
# wrapper that calls the matching command (a shell function for auto*, a script
# on PATH for change*/detach*/make*). They live in the interactive block, so
# pull each out and confirm it forwards its args to the expected command. The
# command is stubbed by name, so this checks the wiring without a real backend.
_alias_calls="$_testdir/alias_calls"
for _cmd in autosession autoshpool autotmux \
            changesession changeshpool changetmux \
            detachsession detachshpool detachtmux \
            makesession makeshpool maketmux; do
    eval "$_cmd() { echo \"$_cmd \$*\" >> \"\$_alias_calls\"; }"
done
for _alias in as asp atm cs csp ctm ds dsp dtm ms msp mtm; do
    _extract_oneliner "$_alias"
done

# cs/ds/ms no-op unless a backend is selected, so stub session_backend; the
# auto* aliases call their (stubbed) target directly and ignore it. Also keep
# SHPOOL_SESSION_NAME out of the way or the cs/csp exit would end the test.
session_backend() { echo tmux; }
unset SHPOOL_SESSION_NAME

# Each alias and the command it must call, with a sample argument.
while read -r _alias _target; do
    start_test "$_alias calls $_target"
    rm -f "$_alias_calls"
    "$_alias" work
    assert_equal "$_target work" "$(cat "$_alias_calls")"
done <<'ALIASES'
as autosession
asp autoshpool
atm autotmux
cs changesession
csp changeshpool
ctm changetmux
ds detachsession
dsp detachshpool
dtm detachtmux
ms makesession
msp makeshpool
mtm maketmux
ALIASES

# The switch only happens on the no-arg picker path: in a shpool session it
# detaches us and the outer autoshpool loop attaches the target, so cs/csp must
# exit the now-parked shell (a bare echo after must not run). Run in subshells
# so the exit only ends the subshell. Local stubs write a fixed marker.
start_test "cs exits the shell after a shpool switch"
rm -f "$_alias_calls"
(
    changesession() { echo switched >> "$_alias_calls"; }
    unset TMUX; SHPOOL_SESSION_NAME=work
    cs
    echo stayed >> "$_alias_calls"
)
assert_equal "switched" "$(cat "$_alias_calls")"

start_test "csp exits the shell after a shpool switch"
rm -f "$_alias_calls"
(
    changeshpool() { echo switched >> "$_alias_calls"; }
    SHPOOL_SESSION_NAME=work
    csp
    echo stayed >> "$_alias_calls"
)
assert_equal "switched" "$(cat "$_alias_calls")"

# --list/--preview/--help return 0 too but only print, so an arg means no exit.
start_test "csp does not exit for a non-switch subcommand"
rm -f "$_alias_calls"
(
    changeshpool() { echo "changeshpool $*" >> "$_alias_calls"; }
    SHPOOL_SESSION_NAME=work
    csp --list
    echo stayed >> "$_alias_calls"
)
assert_equal "changeshpool --list
stayed" "$(cat "$_alias_calls")"

start_test "cs does not exit outside a shpool session"
rm -f "$_alias_calls"
(
    changesession() { echo switched >> "$_alias_calls"; }
    unset TMUX SHPOOL_SESSION_NAME
    cs
    echo stayed >> "$_alias_calls"
)
assert_equal "switched
stayed" "$(cat "$_alias_calls")"

# tmux nested in shpool sets both $TMUX and $SHPOOL_SESSION_NAME; changesession
# switches the tmux client in place, so cs must stay (not exit) there.
start_test "cs does not exit for tmux nested in shpool"
rm -f "$_alias_calls"
(
    changesession() { echo switched >> "$_alias_calls"; }
    TMUX=/tmp/sock; SHPOOL_SESSION_NAME=work
    cs
    echo stayed >> "$_alias_calls"
)
assert_equal "switched
stayed" "$(cat "$_alias_calls")"

# A switch that succeeds but does not exit (an in-place tmux switch, or an
# attach/detach from outside any session) must return the picker's own status
# (0), not the failed exit guard's 1 -- otherwise `cs && ...` and $? checks break
# and the prompt shows a spurious error after a successful switch.
start_test "cs returns success when a tmux-nested switch does not exit"
rm -f "$_alias_calls"
(
    changesession() { return 0; }
    TMUX=/tmp/sock; SHPOOL_SESSION_NAME=work
    cs
    echo "rc=$?" >> "$_alias_calls"
)
assert_equal "rc=0" "$(cat "$_alias_calls")"

start_test "cs returns success when an outside-session switch does not exit"
rm -f "$_alias_calls"
(
    session_backend() { echo shpool; }
    changesession() { return 0; }
    unset TMUX SHPOOL_SESSION_NAME
    cs
    echo "rc=$?" >> "$_alias_calls"
)
assert_equal "rc=0" "$(cat "$_alias_calls")"

start_test "csp returns success when an outside-session switch does not exit"
rm -f "$_alias_calls"
(
    changeshpool() { return 0; }
    unset SHPOOL_SESSION_NAME
    csp
    echo "rc=$?" >> "$_alias_calls"
)
assert_equal "rc=0" "$(cat "$_alias_calls")"

# A cancelled picker (ESC) returns non-zero; cs must propagate that status so we
# stay put and the caller sees the cancel.
start_test "cs returns a cancelled picker's status"
rm -f "$_alias_calls"
(
    session_backend() { echo shpool; }
    changesession() { return 130; }
    unset TMUX SHPOOL_SESSION_NAME
    cs
    echo "rc=$?" >> "$_alias_calls"
)
assert_equal "rc=130" "$(cat "$_alias_calls")"

# The *s scripts dispatch on $SESSION_BACKEND (falling back to tmux), so cs/ds/ms
# pass session_backend's choice (which honours WANT_SHPOOL/WANT_TMUX and the
# $SESSION_BACKEND preference) as SESSION_BACKEND, or a WANT_SHPOOL=0 user
# outside a session would be handed the scripts' default.
start_test "cs passes session_backend to the script as SESSION_BACKEND"
rm -f "$_alias_calls"
(
    session_backend() { echo shpool; }
    changesession() { echo "SESSION_BACKEND=$SESSION_BACKEND" >> "$_alias_calls"; }
    unset SHPOOL_SESSION_NAME
    cs work
)
assert_equal "SESSION_BACKEND=shpool" "$(cat "$_alias_calls")"

# When no backend is wanted/available (session_backend empty) and we aren't in
# a session, cs/ds/ms do nothing rather than let the script fall back to tmux
# (matches autosession/switchsession). But inside a session they still act on
# it, since the script honours $TMUX/$SHPOOL_SESSION_NAME first.
start_test "cs is a no-op when no backend is selected"
rm -f "$_alias_calls"
(
    session_backend() { echo ""; }
    changesession() { echo "changesession $*" >> "$_alias_calls"; }
    unset TMUX SHPOOL_SESSION_NAME
    cs work
)
assert_equal "" "$(cat "$_alias_calls" 2>/dev/null)"

start_test "cs still runs in a session when no backend is selected"
rm -f "$_alias_calls"
(
    session_backend() { echo ""; }
    changesession() { echo "changesession $*" >> "$_alias_calls"; }
    TMUX=/tmp/sock; unset SHPOOL_SESSION_NAME
    cs work
)
assert_equal "changesession work" "$(cat "$_alias_calls")"

# make* mirror change*'s exit handling. Inside a shpool session makeshpool hands
# the new session to autoshpool's loop via request_switch (detaching us), so the
# parked shell must exit. Unlike cs there's no no-arg gate: make always names a
# session, so it exits with an argument too.
start_test "ms exits the shell after a shpool make"
rm -f "$_alias_calls"
(
    makesession() { echo made >> "$_alias_calls"; }
    unset TMUX; SHPOOL_SESSION_NAME=work
    ms newproj
    echo stayed >> "$_alias_calls"
)
assert_equal "made" "$(cat "$_alias_calls")"

start_test "msp exits the shell after a shpool make"
rm -f "$_alias_calls"
(
    makeshpool() { echo made >> "$_alias_calls"; }
    SHPOOL_SESSION_NAME=work
    msp newproj
    echo stayed >> "$_alias_calls"
)
assert_equal "made" "$(cat "$_alias_calls")"

start_test "ms does not exit outside a shpool session"
rm -f "$_alias_calls"
(
    makesession() { echo made >> "$_alias_calls"; }
    unset TMUX SHPOOL_SESSION_NAME
    ms newproj
    echo stayed >> "$_alias_calls"
)
assert_equal "made
stayed" "$(cat "$_alias_calls")"

# tmux nested in shpool sets both vars; maketmux switches the tmux client in
# place, so ms must stay (not exit) there.
start_test "ms does not exit for tmux nested in shpool"
rm -f "$_alias_calls"
(
    makesession() { echo made >> "$_alias_calls"; }
    TMUX=/tmp/sock; SHPOOL_SESSION_NAME=work
    ms newproj
    echo stayed >> "$_alias_calls"
)
assert_equal "made
stayed" "$(cat "$_alias_calls")"

# A make that succeeds but does not exit must return its own status (0), not the
# failed exit guard's 1 -- otherwise `ms ... && ...` and $? checks break.
start_test "ms returns success when a successful make does not exit"
rm -f "$_alias_calls"
(
    makesession() { return 0; }
    unset TMUX SHPOOL_SESSION_NAME
    ms newproj
    echo "rc=$?" >> "$_alias_calls"
)
assert_equal "rc=0" "$(cat "$_alias_calls")"

start_test "msp returns success when a successful make does not exit"
rm -f "$_alias_calls"
(
    makeshpool() { return 0; }
    unset SHPOOL_SESSION_NAME
    msp newproj
    echo "rc=$?" >> "$_alias_calls"
)
assert_equal "rc=0" "$(cat "$_alias_calls")"

# A failed make propagates its non-zero status rather than being masked.
start_test "ms returns a failed make's status"
rm -f "$_alias_calls"
(
    makesession() { return 3; }
    unset TMUX SHPOOL_SESSION_NAME
    ms newproj
    echo "rc=$?" >> "$_alias_calls"
)
assert_equal "rc=3" "$(cat "$_alias_calls")"

unset -f jjd hgd gitd autosession jd hd gd mjd mhd mgd _extract_oneliner
unset -f autoshpool autotmux changesession changeshpool changetmux session_backend
unset -f detachsession detachshpool detachtmux makesession makeshpool maketmux
unset -f as asp atm cs csp ctm ds dsp dtm ms msp mtm
rm -f "$_vcsdir_calls" "$_alias_calls"

# Re-source shrc so the real connected_remotely / inside_project are
# restored for later tests, replacing the stubs left over from the
# shpool block above. The SHRC_LOAD_FUNCTIONS_ONLY gate keeps the
# environment side effects skipped on this second pass too.
rm -f "$_autoshpool_calls" "$_returned"
SHRC_LOAD_FUNCTIONS_ONLY=1 . "$_srcdir/shrc"

###############
# each0 uses `read -d ''`, which is supported by both bash and zsh but
# not by dash / ash. Run on either real shell; skip only on dash/sh.
# _real_shell is set by shrc_test_lib.sh to the actual interpreter
# (not the bash-masquerading stub).

if test "$_real_shell" = bash || test "$_real_shell" = zsh; then
    start_test "each0 runs command on null-delimited input"
    result=$(printf 'a\0b\0c\0' | each0 echo "item:")
    expected="item: a
item: b
item: c"
    assert_equal "$expected" "$result"
else
    skip_block "each0 tests: requires read -d (bash / zsh only)"
fi

# Test root wrapper function

# Stub "command root" to record what was called
_root_log=""
root_cmd() { _root_log="root: $*"; }

# Override root to use our stub instead of "command root"
root() {
    if is_function "$1"; then
        _root_log="function: $*"
    else
        root_cmd "$@"
    fi
}

# A test function to use as an argument to root
myfunc() { echo "hello"; }

start_test "root detects function argument"
_root_log=""
root myfunc arg1 arg2
assert_equal "function: myfunc arg1 arg2" "$_root_log"

start_test "root passes non-function to root command"
_root_log=""
root systemctl restart nginx
assert_equal "root: systemctl restart nginx" "$_root_log"

start_test "root passes unknown command to root command"
_root_log=""
root nonexistent_command --flag
assert_equal "root: nonexistent_command --flag" "$_root_log"

# Clean up
unset _root_log
unset -f root_cmd myfunc root

###############
# RETRY

start_test "retry calls command once on immediate success"
_retry_dir=$(mktemp -d)
_retry_counter="$_retry_dir/count"
cat > "$_retry_dir/retrystub" << STUB
#!/bin/sh
c=\$(cat "$_retry_counter" 2>/dev/null || echo 0)
c=\$((c + 1))
echo \$c > "$_retry_counter"
exit 0
STUB
chmod +x "$_retry_dir/retrystub"
PATH="$_retry_dir:$PATH" retry --sleep 0 "$_retry_dir/retrystub"
result=$(cat "$_retry_counter")
assert_equal "1" "$result"

start_test "retry calls command twice when first attempt fails"
rm -f "$_retry_counter"
cat > "$_retry_dir/retrystub" << STUB
#!/bin/sh
c=\$(cat "$_retry_counter" 2>/dev/null || echo 0)
c=\$((c + 1))
echo \$c > "$_retry_counter"
if test \$c -lt 2; then exit 1; fi
exit 0
STUB
chmod +x "$_retry_dir/retrystub"
PATH="$_retry_dir:$PATH" retry --sleep 0 "$_retry_dir/retrystub"
result=$(cat "$_retry_counter")
assert_equal "2" "$result"

start_test "retry --sleep=0 calls command twice"
rm -f "$_retry_counter"
cat > "$_retry_dir/retrystub" << STUB
#!/bin/sh
c=\$(cat "$_retry_counter" 2>/dev/null || echo 0)
c=\$((c + 1))
echo \$c > "$_retry_counter"
if test \$c -lt 2; then exit 1; fi
exit 0
STUB
chmod +x "$_retry_dir/retrystub"
PATH="$_retry_dir:$PATH" retry --sleep=0 "$_retry_dir/retrystub"
result=$(cat "$_retry_counter")
assert_equal "2" "$result"

start_test "retry without --sleep succeeds"
rm -f "$_retry_counter"
cat > "$_retry_dir/retrystub" << 'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$_retry_dir/retrystub"
PATH="$_retry_dir:$PATH" retry "$_retry_dir/retrystub"
assert_equal "0" "$?"

rm -rf "$_retry_dir"

###############
# RG
# rg should shell out to ripgrep (`command rg`) with --follow to follow
# symlinks. The function lives inside shrc's interactive block (skipped
# under SHRC_LOAD_FUNCTIONS_ONLY), so pull its definition out by hand
# and dedent it before eval'ing.

_rg_def=$(grep -E '^[[:space:]]+rg\(\) \{' "$_srcdir/shrc" | sed 's/^[[:space:]]*//')
start_test "shrc defines rg as a one-liner function"
assert_true test -n "$_rg_def"
eval "$_rg_def"

_rg_dir=$(mktemp -d)
_rg_log="$_rg_dir/args"
# Stub `rg` on PATH so `command rg` resolves to it instead of the real
# ripgrep. The function uses `command rg` rather than calling itself, so
# no infinite recursion -- if it ever did recurse, this stub wouldn't be
# reached at all.
cat > "$_rg_dir/rg" << STUB
#!/bin/sh
printf '%s\n' "\$@" > "$_rg_log"
exit 0
STUB
chmod +x "$_rg_dir/rg"

start_test "rg invokes ripgrep with --follow"
PATH="$_rg_dir:$PATH" rg pattern path
assert_contains "--follow" "$(cat "$_rg_log")"

start_test "rg forces --line-number so piped output keeps line numbers"
PATH="$_rg_dir:$PATH" rg pattern path
assert_contains "--line-number" "$(cat "$_rg_log")"

start_test "rg passes through user arguments"
PATH="$_rg_dir:$PATH" rg pattern path
assert_contains "pattern" "$(cat "$_rg_log")"
assert_contains "path" "$(cat "$_rg_log")"

unset -f rg
rm -rf "$_rg_dir"

###############
# CDPATH
# Verify CDPATH contains HOME but not the conf/config subdirectories, which
# would surprisingly shadow directory names when `cd`ing from anywhere.
# Accept both `CDPATH=...` and `export CDPATH=...` so a future reformat
# doesn't silently make $_cdpath_line empty (which would make the
# assert_not_contains below trivially pass).
start_test "shrc CDPATH assignment found"
_cdpath_line=$(sed -n 's/^[[:space:]]*\(export[[:space:]]\{1,\}\)\{0,1\}CDPATH=//p' "$_srcdir/shrc")
assert_true test -n "$_cdpath_line"
start_test "shrc CDPATH contains HOME"
assert_contains "\$HOME" "$_cdpath_line"
start_test "shrc CDPATH does not contain \$HOME/conf"
assert_not_contains "\$HOME/conf" "$_cdpath_line"

###############
# Autocd: shrc enables `shopt -s autocd` (bash) and `setopt AUTO_CD`
# (zsh) so typing `Downloads<TAB><ENTER>` from any directory finds and
# enters $HOME/Downloads via CDPATH. The custom trailing-slash autocd
# machinery that used to gate this on a `/` suffix has been removed in
# favor of the shells' built-ins.
start_test "shrc enables shopt -s autocd"
assert_contains "shopt -s autocd" \
    "$(grep -E '^[[:space:]]*shopt -s autocd' "$_srcdir/shrc")"
start_test "shrc enables setopt AUTO_CD"
assert_contains "setopt AUTO_CD" \
    "$(grep -E '^[[:space:]]*setopt AUTO_CD' "$_srcdir/shrc")"

# End-to-end tests that exercise shrc under a real `bash -i` subshell
# live in shrc_bash_test.sh (driven via the Makefile's test-shrc-bash
# target). Keeping those cross-shell spawns out of this file means
# `dash shrc_test.sh` no longer launches `bash -i` / `zsh` subshells
# it wouldn't otherwise need, eliminating the SIGTTOU-under-tty hang
# that the outer run_with_timeout fence was only partially covering.

###############
# SHELL COMPATIBILITY
# Verify shrc does not use bashisms outside of bash/zsh-guarded sections.

# Check that "source" is not used as a command outside of bash/zsh guards.
# Lines starting with "source" or containing ". source" (after semicolons, etc.)
# are bashisms that break in dash/sh.  Allowed: comments, and inside
# case "$shell" in bash|zsh) ... ;; esac blocks.
start_test "no unguarded source commands in shrc"
_unguarded_source=$(
    awk '
    /^[[:space:]]*#/           { next }           # skip comments
    /case.*\$shell.*bash\|zsh/ { guarded++ ; next }
    guarded && /;;/            { guarded-- ; next }
    guarded                    { next }
    /[[:space:];]source[[:space:]]/ || /^source[[:space:]]/ { print NR": "$0 }
    ' "$_srcdir/shrc"
)
assert_equal "" "$_unguarded_source"

# shrc.vcs uses bash/zsh-only syntax (declare -a, array +=, etc.), so
# shrc must only source it under bash/zsh. Catching this as a test
# prevents regressions that would break dash startup with a syntax
# error in the middle of sourcing. Grep the `if`-line plus the body so
# we can assert the bash/zsh guard appears alongside the `source`/`.`.
start_test "shrc gates .shrc.vcs sourcing on bash/zsh"
_shrc_vcs_guard=$(awk '
    /\.shrc\.vcs/ && !/^[[:space:]]*#/ {
        # print preceding if-line + this line
        print prev
        print
    }
    { prev = $0 }
' "$_srcdir/shrc")
assert_contains \
    "is_bash" "$_shrc_vcs_guard"

# The end-to-end "shrc sources cleanly under dash despite .shrc.vcs
# present" regression lives in shrc_dash_test.sh (driven via the
# Makefile's test-shrc-dash target).

###############
# ASSERTION HELPER SELF-TESTS
# assert_contains / assert_not_contains with an empty needle used to
# silently pass (or silently fail) because the case pattern *""* matches
# any haystack. That masked wiring bugs where a variable was unset and
# expanded to "". Verify the helpers now reject an empty needle outright.
# Runs a helper in a subshell against a dummy `failures` counter so the
# expected-FAIL output doesn't pollute the real test summary.
_helper_selftest() {
    # stdout: "pass" or "fail" depending on whether the helper incremented
    # $failures. Runs in a subshell so the counter mutations don't leak.
    (
        failures=0
        passes=0
        "$@" >/dev/null 2>&1
        if test "$failures" -gt 0; then
            echo fail
        else
            echo pass
        fi
    )
}

start_test "assert_contains rejects empty needle"
result=$(_helper_selftest assert_contains "" "haystack")
assert_equal "fail" "$result"

start_test "assert_not_contains rejects empty needle"
result=$(_helper_selftest assert_not_contains "" "haystack")
assert_equal "fail" "$result"

# Sanity: non-empty needles on an empty haystack still behave correctly.
start_test "assert_contains fails on empty haystack with non-empty needle"
result=$(_helper_selftest assert_contains "x" "")
assert_equal "fail" "$result"

start_test "assert_not_contains passes on empty haystack with non-empty needle"
result=$(_helper_selftest assert_not_contains "x" "")
assert_equal "pass" "$result"

unset -f _helper_selftest

# extract_func / extract_func_subst must fail loudly when the function is
# absent AND when the extracted block doesn't end with a column-0 `}` (a
# truncated body caused by a renamed/removed function would otherwise be
# eval'd as a half-valid fragment).
_extract_selftest_dir=$(mktemp -d)
cat > "$_extract_selftest_dir/good" <<'GOOD'
good_fn() {
    echo ok
}
GOOD
cat > "$_extract_selftest_dir/truncated" <<'TRUNC'
good_fn() {
    echo ok
TRUNC

_extract_selftest() {
    (
        failures=0
        passes=0
        "$@" >/dev/null 2>&1
        if test "$failures" -gt 0; then
            echo fail
        else
            echo pass
        fi
    )
}

start_test "extract_func accepts well-formed function"
result=$(_extract_selftest extract_func good_fn "$_extract_selftest_dir/good")
assert_equal "pass" "$result"

start_test "extract_func rejects missing function"
result=$(_extract_selftest extract_func missing_fn "$_extract_selftest_dir/good")
assert_equal "fail" "$result"

start_test "extract_func rejects block without column-0 closing brace"
result=$(_extract_selftest extract_func good_fn "$_extract_selftest_dir/truncated")
assert_equal "fail" "$result"

start_test "extract_func_subst rejects block without column-0 closing brace"
result=$(_extract_selftest extract_func_subst good_fn 's/ok/OK/' "$_extract_selftest_dir/truncated")
assert_equal "fail" "$result"

# Regression: non-identifier function names are rejected (sed-metachar
# safety fence -- real shrc fns are all plain identifiers so this is
# belt-and-braces).
start_test "extract_func rejects non-identifier function name"
result=$(_extract_selftest extract_func 'bad.name' "$_extract_selftest_dir/good")
assert_equal "fail" "$result"

start_test "extract_func_subst rejects non-identifier function name"
result=$(_extract_selftest extract_func_subst 'bad.name' 's/x/y/' "$_extract_selftest_dir/good")
assert_equal "fail" "$result"

rm -rf "$_extract_selftest_dir"
unset -f _extract_selftest

###############
# FAILSAFE escape hatch
# Under bash/zsh, sourcing shrc with FAILSAFE=1 should hit the same
# early bail-out as plain sh / dash: emit "failsafe mode" on stderr, set a
# minimal PS1, and return before the autoshpool / interactive block
# runs. Run in a fresh interpreter so we don't pollute the test's own
# shell with the early-return prompt.

if test "$_real_shell" = bash || test "$_real_shell" = zsh; then
    start_test "FAILSAFE=1 triggers failsafe mode and returns early"
    _failsafe_out=$(FAILSAFE=1 HOME="$_testdir" \
        "$_real_shell" -c '. "$1"; echo AFTER; type asp 2>&1 || true' \
        -- "$_srcdir/shrc" 2>&1)
    assert_contains "failsafe mode" "$_failsafe_out"
    assert_contains "AFTER" "$_failsafe_out"
    # Interactive aliases (e.g. `asp`) are defined after the early-return
    # point, so they must not exist when failsafe fires.
    assert_not_contains "asp is a function" "$_failsafe_out"

    start_test "FAILSAFE unset loads shrc normally"
    _failsafe_out=$(HOME="$_testdir" \
        "$_real_shell" -c '. "$1"; echo AFTER' \
        -- "$_srcdir/shrc" 2>&1)
    assert_not_contains "failsafe mode" "$_failsafe_out"
    assert_contains "AFTER" "$_failsafe_out"

    # LC_FAILSAFE=1 is the ssh-survivable alias (most sshd configs
    # AcceptEnv LC_*), so `LC_FAILSAFE=1 ssh host` reaches the remote.
    start_test "LC_FAILSAFE=1 also triggers failsafe mode"
    _failsafe_out=$(LC_FAILSAFE=1 HOME="$_testdir" \
        "$_real_shell" -c '. "$1"; echo AFTER' \
        -- "$_srcdir/shrc" 2>&1)
    assert_contains "failsafe mode" "$_failsafe_out"
    assert_contains "AFTER" "$_failsafe_out"

    # ~/.failsafe is a persistent opt-in: presence of the file alone
    # forces failsafe mode for every new shell.
    _failsafe_home="$_testdir/failsafe_home"
    mkdir -p "$_failsafe_home"
    touch "$_failsafe_home/.failsafe"
    start_test "~/.failsafe file triggers failsafe mode"
    _failsafe_out=$(HOME="$_failsafe_home" \
        "$_real_shell" -c '. "$1"; echo AFTER' \
        -- "$_srcdir/shrc" 2>&1)
    assert_contains "failsafe mode" "$_failsafe_out"
    assert_contains "AFTER" "$_failsafe_out"

    start_test "absent ~/.failsafe leaves shrc in normal mode"
    rm -f "$_failsafe_home/.failsafe"
    _failsafe_out=$(HOME="$_failsafe_home" \
        "$_real_shell" -c '. "$1"; echo AFTER' \
        -- "$_srcdir/shrc" 2>&1)
    assert_not_contains "failsafe mode" "$_failsafe_out"
    assert_contains "AFTER" "$_failsafe_out"
else
    skip_block "FAILSAFE tests: dash/sh already take the failsafe branch"
fi

###############
# TEST: publish_jobs_file resolves a per-tty file under
# $XDG_RUNTIME_DIR; publish_jobs writes a "%N command" summary string
# there; unpublish_jobs removes it. We deliberately don't fall back
# to /tmp -- a predictable per-uid path under /tmp is a symlink-
# truncation vector. Each test resets the _JOB_PUBLISH_FILE_INIT
# cache so the next call recomputes.

_publish_dir="$_testdir/xdg"
XDG_RUNTIME_DIR="$_publish_dir"

start_test "publish_jobs_file returns empty when TTY isn't /dev/..."
TTY="not a tty"
unset _JOB_PUBLISH_FILE_INIT _JOB_PUBLISH_FILE
assert_equal "" "$(publish_jobs_file)"

start_test "publish_jobs_file returns empty when XDG_RUNTIME_DIR unset"
TTY=/dev/pts/99
unset _JOB_PUBLISH_FILE_INIT _JOB_PUBLISH_FILE
# Use a subshell so the temporary unset doesn't leak into later tests.
assert_equal "" "$(unset XDG_RUNTIME_DIR; publish_jobs_file)"

start_test "publish_jobs_file builds path under XDG_RUNTIME_DIR"
TTY=/dev/pts/99
unset _JOB_PUBLISH_FILE_INIT _JOB_PUBLISH_FILE
assert_equal "$_publish_dir/shell-jobs/dev/pts/99" "$(publish_jobs_file)"

start_test "publish_jobs_file caches after first call"
unset _JOB_PUBLISH_FILE_INIT _JOB_PUBLISH_FILE
publish_jobs_file >/dev/null
# Changing TTY now shouldn't affect the cached answer.
TTY=/dev/pts/100
assert_equal "$_publish_dir/shell-jobs/dev/pts/99" "$(publish_jobs_file)"

start_test "publish_jobs writes empty file with no jobs"
TTY=/dev/pts/99
unset _JOB_PUBLISH_FILE_INIT _JOB_PUBLISH_FILE
_file=$(publish_jobs_file)
rm -f "$_file"
# Override job_info with a stub that produces no lines so we exercise
# the no-jobs path without depending on the test driver's job table.
job_info() { :; }
publish_jobs
assert_true test -f "$_file"
assert_equal "" "$(cat "$_file")"

start_test "publish_jobs writes %N command per job, space-separated"
# Stub job_info with the same single-line "%N cmd args & %M cmd args
# &" shape the real job_info produces. The awk pair-walker should
# drop the args and keep only "%N cmd" tokens.
job_info() {
    printf '%s\n' "%1 vi notes.txt & %2 tail -f syslog &"
}
publish_jobs
# Trailing space after the last entry mirrors the awk format and lets
# consumers concatenate without inserting their own separator.
assert_equal "%1 vi %2 tail " "$(cat "$_file")"
unset -f job_info

start_test "unpublish_jobs removes the file"
assert_true test -f "$_file"
unpublish_jobs
assert_false test -e "$_file"

start_test "unpublish_jobs is a no-op when TTY is not a /dev/... path"
TTY="not a tty"
unset _JOB_PUBLISH_FILE_INIT _JOB_PUBLISH_FILE
# Should return without trying to remove anything; just verify it
# exits 0 and the function didn't somehow create a file.
unpublish_jobs
assert_equal "" "$(publish_jobs_file)"

test_summary "$_real_shell shrc_test"
