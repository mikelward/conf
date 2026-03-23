#!/bin/sh
#
# Tests for functions in shrc.
# Run under both sh and bash to catch compatibility issues.
#

failures=0
passes=0

assert_equal() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if test "$expected" = "$actual"; then
        passes=$((passes + 1))
    else
        echo "FAIL: $label"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        failures=$((failures + 1))
    fi
}

# Source only the path functions from shrc.
# We need to stub out things that would fail in a test environment.
BASH_VERSION="${BASH_VERSION:-fake}"
ZSH_VERSION=
is_zsh() { false; }
is_bash() { true; }
is_dash() { false; }
is_sh() { false; }

# Extract and source just the path functions.
# They are self-contained and only depend on each other.
eval "$(sed -n '/^prepend_path()/,/^add_path()/p' "$(dirname "$0")/shrc" | head -n -1)"
eval "$(sed -n '/^add_path()/,/^#####/p' "$(dirname "$0")/shrc" | head -n -1)"

# Test prepend_path
PATH="/usr/bin:/bin"
prepend_path /usr/local/bin
assert_equal "prepend_path adds to front" "/usr/local/bin:/usr/bin:/bin" "$PATH"

# Test prepend_path removes duplicates
PATH="/usr/local/bin:/usr/bin:/bin"
prepend_path /bin
assert_equal "prepend_path moves existing to front" "/bin:/usr/local/bin:/usr/bin" "$PATH"

# Test prepend_path on empty PATH
PATH=
prepend_path /usr/bin
assert_equal "prepend_path on empty PATH" "/usr/bin" "$PATH"

# Test append_path
PATH="/usr/bin:/bin"
append_path /usr/local/bin
assert_equal "append_path adds to end" "/usr/bin:/bin:/usr/local/bin" "$PATH"

# Test append_path removes duplicates
PATH="/usr/local/bin:/usr/bin:/bin"
append_path /usr/local/bin
assert_equal "append_path moves existing to end" "/usr/bin:/bin:/usr/local/bin" "$PATH"

# Test append_path on empty PATH
PATH=
append_path /usr/bin
assert_equal "append_path on empty PATH" "/usr/bin" "$PATH"

# Test delete_path
PATH="/usr/local/bin:/usr/bin:/bin"
delete_path /usr/bin
assert_equal "delete_path removes entry" "/usr/local/bin:/bin" "$PATH"

# Test delete_path with entry not present
PATH="/usr/bin:/bin"
delete_path /nonexistent
assert_equal "delete_path no-op if not present" "/usr/bin:/bin" "$PATH"

# Test delete_path only entry
PATH="/usr/bin"
delete_path /usr/bin
assert_equal "delete_path removes only entry" "" "$PATH"

# Test inpath
PATH="/usr/bin:/bin"
inpath /usr/bin
assert_equal "inpath finds existing entry" "0" "$?"

PATH="/usr/bin:/bin"
inpath /nonexistent
assert_equal "inpath returns false for missing" "1" "$?"

# Test add_path (default = append if not present)
PATH="/usr/bin:/bin"
add_path /usr/local/bin
assert_equal "add_path appends if not present" "/usr/bin:/bin:/usr/local/bin" "$PATH"

# Test add_path does not duplicate
PATH="/usr/bin:/bin"
add_path /usr/bin
assert_equal "add_path no-op if already present" "/usr/bin:/bin" "$PATH"

# Test add_path start
PATH="/usr/bin:/bin"
add_path /usr/local/bin start
assert_equal "add_path start prepends" "/usr/local/bin:/usr/bin:/bin" "$PATH"

# Test add_path start moves existing entry
PATH="/usr/bin:/bin:/usr/local/bin"
add_path /usr/local/bin start
assert_equal "add_path start moves existing to front" "/usr/local/bin:/usr/bin:/bin" "$PATH"

# Test add_path end
PATH="/usr/bin:/bin"
add_path /usr/local/bin end
assert_equal "add_path end appends" "/usr/bin:/bin:/usr/local/bin" "$PATH"

# Test add_path end moves existing entry
PATH="/usr/local/bin:/usr/bin:/bin"
add_path /usr/local/bin end
assert_equal "add_path end moves existing to end" "/usr/bin:/bin:/usr/local/bin" "$PATH"

# Test PATH functions with paths containing spaces
_tmpdir=$(mktemp -d)
mkdir -p "$_tmpdir/my programs/bin"
mkdir -p "$_tmpdir/path (v2)/bin"
mkdir -p "$_tmpdir/path\$HOME/bin"

PATH="/usr/bin:/bin"
prepend_path "$_tmpdir/my programs/bin"
assert_equal "prepend_path with spaces" "$_tmpdir/my programs/bin:/usr/bin:/bin" "$PATH"

append_path "$_tmpdir/path (v2)/bin"
assert_equal "append_path with parens" "$_tmpdir/my programs/bin:/usr/bin:/bin:$_tmpdir/path (v2)/bin" "$PATH"

inpath "$_tmpdir/my programs/bin"
assert_equal "inpath with spaces" "0" "$?"

inpath "$_tmpdir/path (v2)/bin"
assert_equal "inpath with parens" "0" "$?"

delete_path "$_tmpdir/my programs/bin"
assert_equal "delete_path with spaces" "/usr/bin:/bin:$_tmpdir/path (v2)/bin" "$PATH"

delete_path "$_tmpdir/path (v2)/bin"
assert_equal "delete_path with parens" "/usr/bin:/bin" "$PATH"

# Test add_path with special chars
add_path "$_tmpdir/path (v2)/bin" start
assert_equal "add_path start with parens" "$_tmpdir/path (v2)/bin:/usr/bin:/bin" "$PATH"

PATH="/usr/bin:/bin"
add_path "$_tmpdir/my programs/bin" end
assert_equal "add_path end with spaces" "/usr/bin:/bin:$_tmpdir/my programs/bin" "$PATH"

rm -rf "$_tmpdir"

# Restore PATH for remaining tests
PATH="/usr/bin:/bin"

###############
# UTILITY FUNCTIONS
# Extract additional functions from shrc for testing.

eval "$(sed -n '/^join()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^body()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^first_arg_last()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^shift_options()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^find_test_file()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^path()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^get_address_records()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^get_ptr_records()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^each()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^delline()/,/^}/p' "$(dirname "$0")/shrc")"

# Test join
assert_equal "join comma" "a,b,c" "$(join , a b c)"
assert_equal "join space" "a b c" "$(join " " a b c)"
assert_equal "join single" "a" "$(join , a)"
assert_equal "join empty sep" "abc" "$(join "" a b c)"

# Test body
result=$(printf 'HEADER\nline1\nline2\n' | body cat)
assert_equal "body passes header and body" "HEADER
line1
line2" "$result"

result=$(printf 'HEADER\nfoo\nbar\nbaz\n' | body grep bar)
assert_equal "body filters body only" "HEADER
bar" "$result"

result=$(printf 'H1\nH2\ndata1\ndata2\n' | body -2 cat)
assert_equal "body -2 keeps two header lines" "H1
H2
data1
data2" "$result"

result=$(printf 'H1\nH2\nalpha\nbeta\n' | body -2 grep beta)
assert_equal "body -2 filters body only" "H1
H2
beta" "$result"

# Test first_arg_last
result=$(first_arg_last echo target a b)
assert_equal "first_arg_last moves first arg to end" "a b target" "$result"

result=$(first_arg_last echo only)
assert_equal "first_arg_last single arg" "only" "$result"

# Test shift_options
# We use echo as the command to see what gets passed
result=$(shift_options echo target -a -b rest)
assert_equal "shift_options moves options before target" "-a -b target rest" "$result"

result=$(shift_options echo target rest)
assert_equal "shift_options no options" "target rest" "$result"

result=$(shift_options echo target -x)
assert_equal "shift_options option only" "-x target" "$result"

result=$(shift_options echo target -- -b)
assert_equal "shift_options stops at --" "target -- -b" "$result"

# Test find_test_file
# Create temp files to test against
_tmpdir=$(mktemp -d)
touch "$_tmpdir/foo.py"
touch "$_tmpdir/foo_test.py"
touch "$_tmpdir/bar.go"
touch "$_tmpdir/bar_test.go"

result=$(find_test_file "$_tmpdir/foo.py")
assert_equal "find_test_file finds python test" "${_tmpdir}/foo_test.py" "$result"

result=$(find_test_file "$_tmpdir/bar.go")
assert_equal "find_test_file finds go test" "${_tmpdir}/bar_test.go" "$result"

result=$(find_test_file "$_tmpdir/missing.py")
assert_equal "find_test_file returns empty for missing" "" "$result"

# Test find_test_file with nested directories
mkdir -p "$_tmpdir/src/pkg/sub"
touch "$_tmpdir/src/pkg/sub/handler.py"
touch "$_tmpdir/src/pkg/sub/handler_test.py"

result=$(find_test_file "$_tmpdir/src/pkg/sub/handler.py")
assert_equal "find_test_file finds nested test" "$_tmpdir/src/pkg/sub/handler_test.py" "$result"

# Test find_test_file with nested dir but no test file
mkdir -p "$_tmpdir/src/deep/dir"
touch "$_tmpdir/src/deep/dir/utils.go"

result=$(find_test_file "$_tmpdir/src/deep/dir/utils.go")
assert_equal "find_test_file empty for nested missing test" "" "$result"

rm -rf "$_tmpdir"

# Test path
PATH="/usr/bin:/bin"
result=$(path sh)
assert_equal "path finds sh" "/usr/bin/sh" "$result"

path nonexistent_command_xyz >/dev/null 2>&1
assert_equal "path returns false for missing command" "1" "$?"

# Test get_address_records
input="example.com.		300	IN	A	93.184.216.34
example.com.		300	IN	AAAA	2606:2800:220:1:248:1893:25c8:1946"
result=$(echo "$input" | get_address_records)
expected="93.184.216.34
2606:2800:220:1:248:1893:25c8:1946"
assert_equal "get_address_records extracts A and AAAA" "$expected" "$result"

# Test get_ptr_records
input="34.216.184.93.in-addr.arpa. 300	IN	PTR	example.com."
result=$(echo "$input" | get_ptr_records)
assert_equal "get_ptr_records extracts PTR" "example.com." "$result"

# Test each
result=$(printf 'a\nb\nc\n' | each echo "item:")
expected="item: a
item: b
item: c"
assert_equal "each runs command on each line" "$expected" "$result"

# Test delline
_tmpfile=$(mktemp)
printf 'line1\nline2\nline3\n' > "$_tmpfile"
delline 2 "$_tmpfile"
result=$(cat "$_tmpfile")
expected="line1
line3"
assert_equal "delline removes specified line" "$expected" "$result"
rm -f "$_tmpfile"

# Test delline on empty file
_tmpfile=$(mktemp)
printf '' > "$_tmpfile"
delline 1 "$_tmpfile"
result=$(cat "$_tmpfile")
assert_equal "delline on empty file" "" "$result"
rm -f "$_tmpfile"

# Test delline on single-line file
_tmpfile=$(mktemp)
printf 'only line\n' > "$_tmpfile"
delline 1 "$_tmpfile"
result=$(cat "$_tmpfile")
assert_equal "delline removes only line" "" "$result"
rm -f "$_tmpfile"

# Test delline on single-line file removing non-existent line
_tmpfile=$(mktemp)
printf 'only line\n' > "$_tmpfile"
delline 5 "$_tmpfile"
result=$(cat "$_tmpfile")
assert_equal "delline no-op for out of range line" "only line" "$result"
rm -f "$_tmpfile"

###############
# ASSERTION HELPERS

assert_true() {
    local label="$1"
    shift
    if "$@"; then
        passes=$((passes + 1))
    else
        echo "FAIL: $label"
        echo "  expected command to succeed: $*"
        failures=$((failures + 1))
    fi
}

assert_false() {
    local label="$1"
    shift
    if "$@"; then
        echo "FAIL: $label"
        echo "  expected command to fail: $*"
        failures=$((failures + 1))
    else
        passes=$((passes + 1))
    fi
}

###############
# Extract additional functions for testing.

eval "$(sed -n '/^error()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^warn()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^quiet()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^run()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^is_builtin()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^is_alias()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^is_command()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^have_command()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^is_runnable()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^bak()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^unbak()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^realdir()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^isort()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^age()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^find_up()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^what()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^trydiff()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^applydiff()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^recent()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^connected_via_ssh()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^connected_remotely()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^inside_tmux()/,/^}/p' "$(dirname "$0")/shrc")"
eval "$(sed -n '/^in_shpool_session()/,/^}/p' "$(dirname "$0")/shrc")"

###############
# COMMAND INSPECTION

# Test is_builtin
assert_true "is_builtin cd" is_builtin cd
assert_false "is_builtin ls" is_builtin ls

# Test is_command
assert_true "is_command /bin/sh" is_command sh
assert_false "is_command nonexistent_xyz" is_command nonexistent_xyz

# Test have_command
assert_true "have_command sh" have_command sh
assert_false "have_command nonexistent_xyz" have_command nonexistent_xyz

# Test is_runnable (functions, builtins, and commands all count)
assert_true "is_runnable sh" is_runnable sh
assert_true "is_runnable cd" is_runnable cd
assert_true "is_runnable is_runnable (function)" is_runnable is_runnable
assert_false "is_runnable nonexistent_xyz" is_runnable nonexistent_xyz

# Test is_alias
alias _test_alias_xyz='echo hi'
assert_true "is_alias detects alias" is_alias _test_alias_xyz
assert_false "is_alias not an alias" is_alias nonexistent_xyz
unalias _test_alias_xyz

###############
# ERROR AND WARN

# Test error (output goes to stderr)
result=$(error "test error message" 2>&1)
assert_equal "error prints to stderr" "test error message" "$result"

# Test warn (output goes to stderr)
result=$(warn "test warning" 2>&1)
assert_equal "warn prints to stderr" "test warning" "$result"

###############
# QUIET

# Test quiet suppresses stdout and stderr
result=$(quiet echo "should not appear")
assert_equal "quiet suppresses stdout" "" "$result"

result=$(quiet sh -c 'echo err >&2')
assert_equal "quiet suppresses stderr" "" "$result"

# Test quiet preserves exit code
quiet true
assert_equal "quiet preserves success" "0" "$?"

quiet false
assert_equal "quiet preserves failure" "1" "$?"

###############
# RUN

# Test run with SIMULATE=false (default)
result=$(SIMULATE=false run echo "hello")
# logger may not be available, so just check it runs
assert_equal "run executes command" "hello" "$result"

# Test run with SIMULATE=true
result=$(SIMULATE=true run echo "hello")
assert_equal "run simulates command" "Would run echo hello" "$result"

###############
# FILE OPERATIONS

_tmpdir=$(mktemp -d)

# Test bak
touch "$_tmpdir/testfile"
(cd "$_tmpdir" && bak testfile)
assert_true "bak creates .bak file" test -f "$_tmpdir/testfile.bak"
assert_false "bak removes original" test -f "$_tmpdir/testfile"

# Test unbak with .bak argument
(cd "$_tmpdir" && unbak testfile.bak)
assert_true "unbak restores from .bak arg" test -f "$_tmpdir/testfile"
assert_false "unbak removes .bak" test -f "$_tmpdir/testfile.bak"

# Test unbak with original name argument
(cd "$_tmpdir" && bak testfile)
(cd "$_tmpdir" && unbak testfile)
assert_true "unbak restores from original name" test -f "$_tmpdir/testfile"
assert_false "unbak removes .bak (original name)" test -f "$_tmpdir/testfile.bak"

# Test bak with multiple files
touch "$_tmpdir/a" "$_tmpdir/b"
(cd "$_tmpdir" && bak a b)
assert_true "bak multiple files a" test -f "$_tmpdir/a.bak"
assert_true "bak multiple files b" test -f "$_tmpdir/b.bak"

rm -rf "$_tmpdir"

# Test isort
_tmpfile=$(mktemp)
printf 'cherry\napple\nbanana\n' > "$_tmpfile"
isort "$_tmpfile"
result=$(cat "$_tmpfile")
expected="apple
banana
cherry"
assert_equal "isort sorts file in place" "$expected" "$result"
rm -f "$_tmpfile"

# Test realdir
_tmpdir=$(mktemp -d)
mkdir -p "$_tmpdir/subdir"
touch "$_tmpdir/subdir/file"
result=$(realdir "$_tmpdir/subdir/file")
expected=$(readlink -f "$_tmpdir/subdir")
assert_equal "realdir returns absolute directory" "$expected" "$result"
rm -rf "$_tmpdir"

###############
# FIND_UP

_tmpdir=$(mktemp -d)
mkdir -p "$_tmpdir/a/b/c"
touch "$_tmpdir/a/marker.txt"

result=$(cd "$_tmpdir/a/b/c" && find_up marker.txt)
assert_equal "find_up finds file in ancestor" "$_tmpdir/a/marker.txt" "$result"

result=$(cd "$_tmpdir/a" && find_up marker.txt)
assert_equal "find_up finds file in current dir" "$_tmpdir/a/marker.txt" "$result"

(cd "$_tmpdir/a/b/c" && find_up nonexistent_file_xyz)
assert_equal "find_up returns 1 for missing file" "1" "$?"

rm -rf "$_tmpdir"

###############
# AGE

_tmpfile=$(mktemp)
touch -d '2 seconds ago' "$_tmpfile"
result=$(age "$_tmpfile")
assert_true "age returns positive number" test "$result" -ge 1
rm -f "$_tmpfile"

###############
# WHAT

# Test what for a command
result=$(what sh)
assert_true "what finds sh" test -n "$result"

# Test what for a function
result=$(what is_runnable)
assert_true "what shows function definition" test -n "$result"

###############
# TRYDIFF AND APPLYDIFF

_tmpdir=$(mktemp -d)
printf 'hello\nworld\n' > "$_tmpdir/input"
# Create a transform script for testing
cat > "$_tmpdir/upcase" << 'SCRIPT'
#!/bin/sh
tr a-z A-Z < "$1"
SCRIPT
chmod +x "$_tmpdir/upcase"
trydiff_result=$(cd "$_tmpdir" && trydiff ./upcase input 2>&1)
assert_true "trydiff produces output" test -n "$trydiff_result"
# Original file should be unchanged
result=$(cat "$_tmpdir/input")
assert_equal "trydiff does not modify original" "hello
world" "$result"

# Test applydiff
(cd "$_tmpdir" && applydiff ./upcase input)
result=$(cat "$_tmpdir/input")
assert_equal "applydiff modifies file" "HELLO
WORLD" "$result"
rm -rf "$_tmpdir"

###############
# RECENT

_tmpdir=$(mktemp -d)
touch -d '2 seconds ago' "$_tmpdir/old"
touch "$_tmpdir/new"
result=$(cd "$_tmpdir" && recent)
first_line=$(echo "$result" | head -n 1)
assert_equal "recent shows newest first" "new" "$first_line"

result=$(cd "$_tmpdir" && recent -1)
line_count=$(echo "$result" | wc -l)
assert_equal "recent -1 shows one file" "1" "$line_count"
rm -rf "$_tmpdir"

###############
# ENVIRONMENT DETECTION

# Test connected_via_ssh
SSH_CONNECTION="1.2.3.4 5678 5.6.7.8 22"
assert_true "connected_via_ssh with SSH_CONNECTION" connected_via_ssh

unset SSH_CONNECTION
assert_false "connected_via_ssh without SSH_CONNECTION" connected_via_ssh

# Test connected_remotely (delegates to connected_via_ssh)
SSH_CONNECTION="1.2.3.4 5678 5.6.7.8 22"
assert_true "connected_remotely with SSH_CONNECTION" connected_remotely
unset SSH_CONNECTION
assert_false "connected_remotely without SSH_CONNECTION" connected_remotely

# Test inside_tmux
TMUX="/tmp/tmux-1000/default,12345,0"
assert_true "inside_tmux with TMUX set" inside_tmux
unset TMUX
assert_false "inside_tmux without TMUX" inside_tmux

# Test in_shpool_session
SHPOOL_SESSION_NAME="main"
assert_true "in_shpool_session with SHPOOL_SESSION_NAME" in_shpool_session
unset SHPOOL_SESSION_NAME
assert_false "in_shpool_session without SHPOOL_SESSION_NAME" in_shpool_session

###############
# BASH-ONLY TESTS

if test -n "${BASH_VERSION:-}" && test "$BASH_VERSION" != "fake"; then
    # Test each0 (uses read -d '' which is bash-only)
    eval "$(sed -n '/^each0()/,/^}/p' "$(dirname "$0")/shrc")"

    result=$(printf 'a\0b\0c\0' | each0 echo "item:")
    expected="item: a
item: b
item: c"
    assert_equal "each0 runs command on null-delimited input" "$expected" "$result"
fi

_shell="$(basename "$(readlink -f /proc/$$/exe)" 2>/dev/null || echo "sh")"

echo
if test "$failures" -eq 0; then
    echo "$_shell shrc_test: all $passes tests passed."
else
    echo "$_shell shrc_test: $failures test(s) failed, $passes passed."
    exit 1
fi
