#!/bin/sh
#
# Tests for functions in shrc.
# Run under both sh and bash to catch compatibility issues.
#

failures=0

assert_equal() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if test "$expected" = "$actual"; then
        echo "PASS: $label"
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

echo
if test "$failures" -eq 0; then
    echo "All tests passed."
else
    echo "$failures test(s) failed."
    exit 1
fi
