#!/bin/sh
#
# Tests for functions in shrc.
# Run under both sh and bash to catch compatibility issues.
#

. "$(dirname "$0")/shrc_test_lib.sh"

# Extract and source just the path functions.
# They are self-contained and only depend on each other.
extract_func prepend_path
extract_func append_path
extract_func delete_path
extract_func inpath
extract_func add_path

# Save PATH for restoration after path function tests
_saved_path="$PATH"

# Test prepend_path
start_test "prepend_path adds to front"
PATH="/usr/bin:/bin"
prepend_path /usr/local/bin
assert_equal "/usr/local/bin:/usr/bin:/bin" "$PATH"

# Test prepend_path removes duplicates
start_test "prepend_path moves existing to front"
PATH="/usr/local/bin:/usr/bin:/bin"
prepend_path /bin
assert_equal "/bin:/usr/local/bin:/usr/bin" "$PATH"

# Test prepend_path on empty PATH
start_test "prepend_path on empty PATH"
PATH=
prepend_path /usr/bin
assert_equal "/usr/bin" "$PATH"

# Test append_path
start_test "append_path adds to end"
PATH="/usr/bin:/bin"
append_path /usr/local/bin
assert_equal "/usr/bin:/bin:/usr/local/bin" "$PATH"

# Test append_path removes duplicates
start_test "append_path moves existing to end"
PATH="/usr/local/bin:/usr/bin:/bin"
append_path /usr/local/bin
assert_equal "/usr/bin:/bin:/usr/local/bin" "$PATH"

# Test append_path on empty PATH
start_test "append_path on empty PATH"
PATH=
append_path /usr/bin
assert_equal "/usr/bin" "$PATH"

# Test delete_path
start_test "delete_path removes entry"
PATH="/usr/local/bin:/usr/bin:/bin"
delete_path /usr/bin
assert_equal "/usr/local/bin:/bin" "$PATH"

# Test delete_path with entry not present
start_test "delete_path no-op if not present"
PATH="/usr/bin:/bin"
delete_path /nonexistent
assert_equal "/usr/bin:/bin" "$PATH"

# Test delete_path only entry
start_test "delete_path removes only entry"
PATH="/usr/bin"
delete_path /usr/bin
assert_equal "" "$PATH"

# Test inpath
start_test "inpath finds existing entry"
PATH="/usr/bin:/bin"
inpath /usr/bin
assert_equal "0" "$?"

start_test "inpath returns false for missing"
PATH="/usr/bin:/bin"
inpath /nonexistent
assert_equal "1" "$?"

# Test add_path (default = append if not present)
start_test "add_path appends if not present"
PATH="/usr/bin:/bin"
add_path /usr/local/bin
assert_equal "/usr/bin:/bin:/usr/local/bin" "$PATH"

# Test add_path does not duplicate
start_test "add_path no-op if already present"
PATH="/usr/bin:/bin"
add_path /usr/bin
assert_equal "/usr/bin:/bin" "$PATH"

# Test add_path start
start_test "add_path start prepends"
PATH="/usr/bin:/bin"
add_path /usr/local/bin start
assert_equal "/usr/local/bin:/usr/bin:/bin" "$PATH"

# Test add_path start moves existing entry
start_test "add_path start moves existing to front"
PATH="/usr/bin:/bin:/usr/local/bin"
add_path /usr/local/bin start
assert_equal "/usr/local/bin:/usr/bin:/bin" "$PATH"

# Test add_path end
start_test "add_path end appends"
PATH="/usr/bin:/bin"
add_path /usr/local/bin end
assert_equal "/usr/bin:/bin:/usr/local/bin" "$PATH"

# Test add_path end moves existing entry
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

# Test add_path with special chars
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
# UTILITY FUNCTIONS
# Extract additional functions from shrc for testing.

extract_func puts
extract_func join
extract_func body
extract_func first_arg_last
extract_func shift_options
extract_func find_test_file
extract_func path
extract_func get_address_records
extract_func get_ptr_records
extract_func each
extract_func delline

# Test puts
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

# Test gets (read -r wrapper)
start_test "gets preserves backslashes"
extract_func gets
result=$(printf '%s\n' 'hello\tworld' | { gets val; puts "$val"; })
assert_equal 'hello\tworld' "$result"

# Test join
start_test "join comma"
assert_equal "a,b,c" "$(join , a b c)"
start_test "join space"
assert_equal "a b c" "$(join " " a b c)"
start_test "join single"
assert_equal "a" "$(join , a)"
start_test "join empty sep"
assert_equal "abc" "$(join "" a b c)"

# Test body
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

# Test first_arg_last
start_test "first_arg_last moves first arg to end"
result=$(first_arg_last echo target a b)
assert_equal "a b target" "$result"

start_test "first_arg_last single arg"
result=$(first_arg_last echo only)
assert_equal "only" "$result"

# Test shift_options
# We use echo as the command to see what gets passed
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

# Test path
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

# Test get_address_records
start_test "get_address_records extracts A and AAAA"
input="example.com.		300	IN	A	93.184.216.34
example.com.		300	IN	AAAA	2606:2800:220:1:248:1893:25c8:1946"
result=$(echo "$input" | get_address_records)
expected="93.184.216.34
2606:2800:220:1:248:1893:25c8:1946"
assert_equal "$expected" "$result"

# Test get_ptr_records
start_test "get_ptr_records extracts PTR"
input="34.216.184.93.in-addr.arpa. 300	IN	PTR	example.com."
result=$(echo "$input" | get_ptr_records)
assert_equal "example.com." "$result"

# Test each
start_test "each runs command on each line"
result=$(printf 'a\nb\nc\n' | each echo "item:")
expected="item: a
item: b
item: c"
assert_equal "$expected" "$result"

# Test delline
start_test "delline removes specified line"
_tmpfile=$(mktemp)
printf 'line1\nline2\nline3\n' > "$_tmpfile"
delline 2 "$_tmpfile"
result=$(cat "$_tmpfile")
expected="line1
line3"
assert_equal "$expected" "$result"
rm -f "$_tmpfile"

# Test delline on empty file
start_test "delline on empty file"
_tmpfile=$(mktemp)
printf '' > "$_tmpfile"
delline 1 "$_tmpfile"
result=$(cat "$_tmpfile")
assert_equal "" "$result"
rm -f "$_tmpfile"

# Test delline on single-line file
start_test "delline removes only line"
_tmpfile=$(mktemp)
printf 'only line\n' > "$_tmpfile"
delline 1 "$_tmpfile"
result=$(cat "$_tmpfile")
assert_equal "" "$result"
rm -f "$_tmpfile"

# Test delline on single-line file removing non-existent line
start_test "delline no-op for out of range line"
_tmpfile=$(mktemp)
printf 'only line\n' > "$_tmpfile"
delline 5 "$_tmpfile"
result=$(cat "$_tmpfile")
assert_equal "only line" "$result"
rm -f "$_tmpfile"

###############
# Extract additional functions for testing.

extract_func error
extract_func warn
extract_func quiet
extract_func run
extract_func is_builtin
extract_func is_alias
extract_func is_command
extract_func have_command
extract_func is_runnable
extract_func bak
extract_func unbak
extract_func realdir
extract_func isort
extract_func age
extract_func find_up
extract_func tz2tz
extract_func what
extract_func trydiff
extract_func applydiff
extract_func recent
extract_func connected_via_ssh
extract_func connected_remotely
extract_func inside_tmux
extract_func in_shpool
extract_func want_shpool
extract_func switchshpool
extract_func maybe_start_shpool_and_exit

###############
# COMMAND INSPECTION

# Test is_builtin
start_test "is_builtin cd"
assert_true is_builtin cd
start_test "is_builtin ls"
assert_false is_builtin ls

# Test is_command
start_test "is_command /bin/sh"
assert_true is_command sh
start_test "is_command nonexistent_xyz"
assert_false is_command nonexistent_xyz

# Test have_command
start_test "have_command sh"
assert_true have_command sh
start_test "have_command nonexistent_xyz"
assert_false have_command nonexistent_xyz

# Test is_runnable (functions, builtins, and commands all count)
start_test "is_runnable sh"
assert_true is_runnable sh
start_test "is_runnable cd"
assert_true is_runnable cd
start_test "is_runnable is_runnable (function)"
assert_true is_runnable is_runnable
start_test "is_runnable nonexistent_xyz"
assert_false is_runnable nonexistent_xyz

# Test is_alias
start_test "is_alias detects alias"
alias _test_alias_xyz='echo hi'
assert_true is_alias _test_alias_xyz
start_test "is_alias not an alias"
assert_false is_alias nonexistent_xyz
unalias _test_alias_xyz

###############
# ERROR AND WARN

# Test error (output goes to stderr)
start_test "error prints to stderr"
result=$(error "test error message" 2>&1)
assert_equal "test error message" "$result"

# Test warn (output goes to stderr)
start_test "warn prints to stderr"
result=$(warn "test warning" 2>&1)
assert_equal "test warning" "$result"

###############
# QUIET

# Test quiet suppresses stdout and stderr
start_test "quiet suppresses stdout"
result=$(quiet echo "should not appear")
assert_equal "" "$result"

start_test "quiet suppresses stderr"
result=$(quiet sh -c 'echo err >&2')
assert_equal "" "$result"

# Test quiet preserves exit code
start_test "quiet preserves success"
quiet true
assert_equal "0" "$?"

start_test "quiet preserves failure"
quiet false
assert_equal "1" "$?"

###############
# RUN

# Test run with SIMULATE=false (default)
start_test "run executes command"
result=$(SIMULATE=false run echo "hello")
# logger may not be available, so just check it runs
assert_equal "hello" "$result"

# Test run with SIMULATE=true
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
SIMULATE=false run touch "$_simrun_dir/marker" >/dev/null 2>&1
start_test "run SIMULATE=false executes command"
assert_true \
    test -e "$_simrun_dir/marker"
rm -rf "$_simrun_dir"

###############
# FILE OPERATIONS

_tmpdir=$(mktemp -d)

# Test bak
start_test "bak creates .bak file"
touch "$_tmpdir/testfile"
(cd "$_tmpdir" && bak testfile)
assert_true test -f "$_tmpdir/testfile.bak"
start_test "bak removes original"
assert_false test -f "$_tmpdir/testfile"

# Test unbak with .bak argument
start_test "unbak restores from .bak arg"
(cd "$_tmpdir" && unbak testfile.bak)
assert_true test -f "$_tmpdir/testfile"
start_test "unbak removes .bak"
assert_false test -f "$_tmpdir/testfile.bak"

# Test unbak with original name argument
start_test "unbak restores from original name"
(cd "$_tmpdir" && bak testfile)
(cd "$_tmpdir" && unbak testfile)
assert_true test -f "$_tmpdir/testfile"
start_test "unbak removes .bak (original name)"
assert_false test -f "$_tmpdir/testfile.bak"

# Test bak with multiple files
start_test "bak multiple files a"
touch "$_tmpdir/a" "$_tmpdir/b"
(cd "$_tmpdir" && bak a b)
assert_true test -f "$_tmpdir/a.bak"
start_test "bak multiple files b"
assert_true test -f "$_tmpdir/b.bak"

rm -rf "$_tmpdir"

# Test isort
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

# Test realdir
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

# Test what for a command
start_test "what finds sh"
result=$(what sh)
assert_true test -n "$result"

# Test what for a function
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
result=$(cat "$_tmpdir/input")
start_test "trydiff does not modify original"
assert_equal "hello
world" "$result"

# Test applydiff
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

# Test that tz2tz converts between timezones
start_test "tz2tz converts timezone"
result=$(tz2tz UTC America/New_York "2024-01-15 12:00:00")
assert_contains "2024" "$result"

# Test that tz2tz handles multi-word date specs
start_test "tz2tz with multi-word date spec"
result=$(tz2tz UTC UTC "2024-01-15 12:00:00")
assert_contains "12:00:00" "$result"

###############
# ENVIRONMENT DETECTION

# Test connected_via_ssh
start_test "connected_via_ssh with SSH_CONNECTION"
SSH_CONNECTION="1.2.3.4 5678 5.6.7.8 22"
assert_true connected_via_ssh

start_test "connected_via_ssh without SSH_CONNECTION"
unset SSH_CONNECTION
assert_false connected_via_ssh

# Test connected_remotely (delegates to connected_via_ssh)
start_test "connected_remotely with SSH_CONNECTION"
SSH_CONNECTION="1.2.3.4 5678 5.6.7.8 22"
assert_true connected_remotely
unset SSH_CONNECTION
start_test "connected_remotely without SSH_CONNECTION"
assert_false connected_remotely

# Test inside_tmux
start_test "inside_tmux with TMUX set"
TMUX="/tmp/tmux-1000/default,12345,0"
assert_true inside_tmux
unset TMUX
start_test "inside_tmux without TMUX"
assert_false inside_tmux

# Test in_shpool
start_test "in_shpool with SHPOOL_SESSION_NAME"
SHPOOL_SESSION_NAME="main"
assert_true in_shpool
unset SHPOOL_SESSION_NAME
start_test "in_shpool without SHPOOL_SESSION_NAME"
assert_false in_shpool

###############
# SHPOOL FUNCTIONS

# Test want_shpool
# want_shpool returns true if connected remotely or inside a project
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
result="$(cat "$_autoshpool_calls" 2>/dev/null)"
start_test "switchshpool calls autoshpool switch"
assert_equal "autoshpool switch newsession" "$result"

# Test switchshpool when autoshpool fails → does not exit
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

# Test maybe_start_shpool_and_exit
_autoshpool_calls="$_testdir/autoshpool_calls"
_returned="$_testdir/shpool_returned"

# When not in shpool, want shpool, shpool available → calls autoshpool and exits
start_test "maybe_start_shpool_and_exit exits when autoshpool succeeds"
rm -f "$_autoshpool_calls" "$_returned"
(
    in_shpool() { false; }
    want_shpool() { true; }
    have_command() { test "$1" = "shpool"; }
    autoshpool() { echo "autoshpool $*" >> "$_autoshpool_calls"; return 0; }
    maybe_start_shpool_and_exit
    echo yes > "$_returned"
)
assert_false test -f "$_returned"
result="$(cat "$_autoshpool_calls" 2>/dev/null)"
start_test "maybe_start_shpool_and_exit calls autoshpool with no args"
assert_equal "autoshpool " "$result"

# When autoshpool fails → does not exit
start_test "maybe_start_shpool_and_exit does not exit when autoshpool fails"
rm -f "$_autoshpool_calls" "$_returned"
(
    in_shpool() { false; }
    want_shpool() { true; }
    have_command() { test "$1" = "shpool"; }
    autoshpool() { return 1; }
    maybe_start_shpool_and_exit
    echo yes > "$_returned"
)
assert_true test -f "$_returned"

# When already in shpool → does not call autoshpool
start_test "maybe_start_shpool_and_exit skips when already in shpool"
rm -f "$_autoshpool_calls" "$_returned"
(
    in_shpool() { true; }
    want_shpool() { true; }
    have_command() { test "$1" = "shpool"; }
    autoshpool() { echo "autoshpool $*" >> "$_autoshpool_calls"; return 0; }
    maybe_start_shpool_and_exit
    echo yes > "$_returned"
)
assert_true test -f "$_returned"
start_test "maybe_start_shpool_and_exit does not call autoshpool when in shpool"
assert_false test -f "$_autoshpool_calls"

# When don't want shpool → does not call autoshpool
start_test "maybe_start_shpool_and_exit skips when not wanted"
rm -f "$_autoshpool_calls" "$_returned"
(
    in_shpool() { false; }
    want_shpool() { false; }
    have_command() { test "$1" = "shpool"; }
    autoshpool() { echo "autoshpool $*" >> "$_autoshpool_calls"; return 0; }
    maybe_start_shpool_and_exit
    echo yes > "$_returned"
)
assert_true test -f "$_returned"
start_test "maybe_start_shpool_and_exit does not call autoshpool when not wanted"
assert_false test -f "$_autoshpool_calls"

# Clean up: re-extract the real connected_remotely / inside_project so
# later tests (and any code added below) see shrc's actual implementation
# instead of the stubs left over from the shpool block above.
rm -f "$_autoshpool_calls" "$_returned"
unset -f connected_remotely inside_project
extract_func connected_remotely
extract_func inside_project

###############
# each0 uses `read -d ''`, which is supported by both bash and zsh but
# not by dash / ash. Run on either real shell; skip only on dash/sh.
# _real_shell is set by shrc_test_lib.sh to the actual interpreter
# (not the bash-masquerading stub).

if test "$_real_shell" = bash || test "$_real_shell" = zsh; then
    extract_func each0

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
extract_func is_function

# Stub "command root" to record what was called
_root_log=""
root_cmd() { _root_log="root: $*"; }

extract_func root
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

# Test root with a function argument
start_test "root detects function argument"
_root_log=""
root myfunc arg1 arg2
assert_equal "function: myfunc arg1 arg2" "$_root_log"

# Test root with a non-function argument
start_test "root passes non-function to root command"
_root_log=""
root systemctl restart nginx
assert_equal "root: systemctl restart nginx" "$_root_log"

# Test root with a command that doesn't exist
start_test "root passes unknown command to root command"
_root_log=""
root nonexistent_command --flag
assert_equal "root: nonexistent_command --flag" "$_root_log"

# Clean up
unset _root_log
unset -f root_cmd myfunc root

###############
# RETRY

extract_func bell
extract_func retry

# Test retry succeeds immediately when command passes
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

# Test retry retries after failure then stops on success
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

# Test retry --sleep=N form
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

# Test retry without --sleep flag defaults (just verify it parses)
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
# Trailing-slash autocd hook (maybe_autocd_trailing_slash)
# Verify shrc no longer enables the aggressive autocd options.
start_test "shrc does not shopt -s autocd"
assert_equal "" \
    "$(grep -E '^[[:space:]]*shopt -s autocd' "$_srcdir/shrc")"
start_test "shrc does not setopt AUTO_CD"
assert_equal "" \
    "$(grep -E '^[[:space:]]*setopt AUTO_CD' "$_srcdir/shrc")"

extract_func resolve_cdpath_dir
extract_func try_autocd_trailing_slash
extract_func maybe_autocd_trailing_slash

# Set up a temp directory tree for cd tests
_autocd_root="$_testdir/autocd"
mkdir -p "$_autocd_root/sub"

# Trailing slash on an existing dir cds into it.
start_test "maybe_autocd_trailing_slash cds on trailing slash"
_saved_pwd="$PWD"
(
    cd "$_autocd_root" || exit 1
    CDPATH=  # avoid surprising CDPATH lookups during the test
    maybe_autocd_trailing_slash "./sub/" >/dev/null 2>&1
    if test "$PWD" = "$_autocd_root/sub"; then
        exit 0
    else
        exit 1
    fi
)
assert_equal "0" "$?"
cd "$_saved_pwd" || true

# try_autocd_trailing_slash: returns 0 + cds for single-word trailing-slash
# dirs, returns 1 without side effects for everything else.
start_test "try_autocd_trailing_slash cds on match"
(
    cd "$_autocd_root" || exit 1
    CDPATH=
    try_autocd_trailing_slash "./sub/" >/dev/null 2>&1
    test "$PWD" = "$_autocd_root/sub"
)
assert_equal "0" "$?"

start_test "try_autocd_trailing_slash returns 1 for non-existent"
(
    cd "$_autocd_root" || exit 1
    CDPATH=
    try_autocd_trailing_slash "./no_such/"
)
assert_equal "1" "$?"

start_test "try_autocd_trailing_slash returns 1 without trailing /"
(
    cd "$_autocd_root" || exit 1
    CDPATH=
    try_autocd_trailing_slash "./sub"
)
assert_equal "1" "$?"

# A multi-word buffer like `./sub/ arg` must not autocd -- it's a real
# command invocation, not a directory the user wants to enter.
start_test "try_autocd_trailing_slash returns 1 for multi-word"
(
    cd "$_autocd_root" || exit 1
    CDPATH=
    try_autocd_trailing_slash "./sub/ arg"
)
assert_equal "1" "$?"

# resolve_cdpath_dir honors CDPATH for relative names, matching `cd`.
# Mirror the real-world bug: from $_autocd_root (no local `peer`), but
# with CDPATH pointing at a parent that *does* contain `peer`, both
# resolve_cdpath_dir and try_autocd_trailing_slash must succeed.
start_test "resolve_cdpath_dir prints CDPATH-resolved path"
mkdir -p "$_autocd_root/peer"
_cdpath_parent="$_testdir/autocd_cdpath"
mkdir -p "$_cdpath_parent/elsewhere"
result=$(
    cd "$_autocd_root/sub" || exit 1
    CDPATH="$_cdpath_parent"
    resolve_cdpath_dir "elsewhere/"
)
assert_equal \
    "$_cdpath_parent/elsewhere/" "$result"

start_test "resolve_cdpath_dir returns 1 when missing everywhere"
(
    cd "$_autocd_root/sub" || exit 1
    CDPATH="$_cdpath_parent"
    resolve_cdpath_dir "no_such_peer/" >/dev/null
)
assert_equal "1" "$?"

# Absolute / ./ / ../ paths bypass CDPATH.
start_test "resolve_cdpath_dir ./ bypasses CDPATH"
(
    cd "$_autocd_root/sub" || exit 1
    CDPATH="$_cdpath_parent"
    # `elsewhere` is in CDPATH but we pass `./elsewhere/` -- must NOT find it.
    resolve_cdpath_dir "./elsewhere/" >/dev/null
)
assert_equal "1" "$?"

# resolve_cdpath_dir expands a leading ~ / ~/ manually. test(1) does
# not tilde-expand, so without this `~/scripts/` would miss even when
# $HOME/scripts exists -- the original bug behind this fix.
start_test "resolve_cdpath_dir expands ~/foo/"
result=$(HOME="$_autocd_root" CDPATH= resolve_cdpath_dir "~/sub/")
assert_equal \
    "$_autocd_root/sub/" "$result"

start_test "resolve_cdpath_dir expands bare ~"
result=$(HOME="$_autocd_root" CDPATH= resolve_cdpath_dir "~")
assert_equal \
    "$_autocd_root" "$result"

# Echo the resolved path for direct / ./ forms too.
start_test "resolve_cdpath_dir prints ./-relative path as-is"
result=$(cd "$_autocd_root" && CDPATH= resolve_cdpath_dir "./sub/")
assert_equal \
    "./sub/" "$result"

# try_autocd_trailing_slash cds via the tilde-expanded path.
start_test "try_autocd_trailing_slash cds via ~/foo/"
(
    HOME="$_autocd_root" CDPATH= \
        try_autocd_trailing_slash "~/sub/" >/dev/null 2>&1
    test "$PWD" = "$_autocd_root/sub"
)
assert_equal "0" "$?"

# try_autocd_trailing_slash now uses CDPATH too.
start_test "try_autocd_trailing_slash cds via CDPATH"
(
    cd "$_autocd_root/sub" || exit 1
    CDPATH="$_cdpath_parent"
    try_autocd_trailing_slash "elsewhere/" >/dev/null 2>&1
    test "$PWD" = "$_cdpath_parent/elsewhere"
)
assert_equal "0" "$?"

# Trailing slash on a non-existent dir falls through to the "not found"
# fallback (no system hook defined here).
start_test "maybe_autocd_trailing_slash non-existent falls through"
result=$(CDPATH= maybe_autocd_trailing_slash "./no_such_dir_xyz/" 2>&1)
assert_contains \
    "command not found" "$result"

# No trailing slash: falls through to the "not found" fallback.
start_test "maybe_autocd_trailing_slash no slash falls through"
result=$(maybe_autocd_trailing_slash "someweirdcmd" 2>&1)
assert_contains \
    "command not found" "$result"

# With a saved system hook, it gets called for non-matches.
start_test "maybe_autocd_trailing_slash delegates to system hook"
system_command_not_found_handle() { printf 'SYSTEM:%s\n' "$1"; }
result=$(maybe_autocd_trailing_slash "someweirdcmd" 2>&1)
assert_equal \
    "SYSTEM:someweirdcmd" "$result"
unset -f system_command_not_found_handle

# And the zsh-style name also works.
start_test "maybe_autocd_trailing_slash delegates to zsh-style system hook"
system_command_not_found_handler() { printf 'SYSTEMR:%s\n' "$1"; }
result=$(maybe_autocd_trailing_slash "someweirdcmd" 2>&1)
assert_equal \
    "SYSTEMR:someweirdcmd" "$result"
unset -f system_command_not_found_handler

# End-to-end tests that exercise shrc under a real `bash -i` subshell
# live in shrc_bash_test.sh (driven via the Makefile's test-shrc-bash
# target). Likewise shrc_zsh_test.sh covers the zsh accept-line widget
# autocd path. Keeping those cross-shell spawns out of this file means
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

test_summary "$_real_shell shrc_test"
