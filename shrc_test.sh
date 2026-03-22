#!/bin/sh
#
# Tests for path functions in shrc.
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

echo
if test "$failures" -eq 0; then
    echo "All tests passed."
else
    echo "$failures test(s) failed."
    exit 1
fi
