#!/bin/sh
#
# Tests for claude/statusline.sh, the Claude Code status line.
#

. "$(dirname "$0")/shrc_test_lib.sh"

_script="$_srcdir/claude/statusline.sh"

if ! command -v jq >/dev/null 2>&1; then
    skip_all "jq not installed"
    test_summary "claude statusline"
    exit 0
fi

start_test "shows the model, directory and session title"
_out=$(printf '%s' '{"session_id":"abc-123","session_name":"Fix the boiler","model":{"display_name":"Opus"},"workspace":{"current_dir":"/srv/ha"}}' | sh "$_script")
assert_equal "Opus · /srv/ha · Fix the boiler" "$_out"

start_test "does not show the session ID"
assert_not_contains "$_out" "abc-123"

start_test "abbreviates the home directory"
_out=$(printf '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"%s/HA"}}' "$HOME" | HOME="$HOME" sh "$_script")
assert_equal "Opus · ~/HA" "$_out"

start_test "leaves out a missing session title"
_out=$(printf '%s' '{"model":{"display_name":"Opus"},"cwd":"/srv/ha"}' | sh "$_script")
assert_equal "Opus · /srv/ha" "$_out"

test_summary "claude statusline"
