#!/bin/sh
#
# Tests for .claude/settings.json, the permission allowlist that lets the
# autonomy loop schedule its own follow-up checks without a prompt.
#
# The file allows tool names only. Tool names take no arguments, so there is
# nothing to inject; a `Bash(...)` rule is a pattern over a whole command line,
# where a trailing `*` matches extra arguments and quietly admits destructive
# forms. That is the boundary these tests hold.
#

. "$(dirname "$0")/shrc_test_lib.sh"

_settings="$_srcdir/.claude/settings.json"

if ! command -v python3 >/dev/null 2>&1; then
    skip_all "python3 not installed"
    test_summary "claude settings"
    exit 0
fi

start_test "settings.json is valid JSON"
# No stderr redirect: on a malformed file the decoder message is the only
# thing that says *where* it broke, and `expected: 0 / actual: 1` alone isn't
# enough to fix it.
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$_settings"
assert_equal "0" "$?"

_allow=$(python3 -c "
import json, sys
print('\n'.join(json.load(open(sys.argv[1]))['permissions']['allow']))
" "$_settings")

start_test "the allowlist is not empty"
assert_false test -z "$_allow"

# The whole point: no shell rules. Adding one reopens the argument-injection
# surface, so it fails here rather than in a session.
start_test "no shell command is preauthorized"
_bash=$(puts "$_allow" | grep -F 'Bash(' || true)
assert_equal "" "$_bash"

# Without these the polling loop stops for a permission prompt that an
# unattended session cannot answer.
for _tool in send_later create_trigger list_triggers delete_trigger; do
    start_test "the $_tool scheduling tool is allowed"
    _hit=$(puts "$_allow" | grep -F "$_tool" || true)
    assert_false test -z "$_hit"
done

# The approved set, verbatim. Rejecting `Bash(` only catches the shell hole;
# a new MCP tool slips past it. Pinning the whole list means widening the
# grant has to be a deliberate edit here too, where someone reads it.
_expected=$(cat <<'EOF'
ScheduleWakeup
mcp__Claude_Code_Remote__create_trigger
mcp__Claude_Code_Remote__delete_trigger
mcp__Claude_Code_Remote__fire_trigger
mcp__Claude_Code_Remote__list_triggers
mcp__Claude_Code_Remote__send_later
mcp__Claude_Code_Remote__subscribe_pr_activity
mcp__Claude_Code_Remote__unsubscribe_pr_activity
mcp__Claude_Code_Remote__update_trigger
mcp__claude-code-remote__create_trigger
mcp__claude-code-remote__delete_trigger
mcp__claude-code-remote__fire_trigger
mcp__claude-code-remote__list_triggers
mcp__claude-code-remote__send_later
mcp__claude-code-remote__subscribe_pr_activity
mcp__claude-code-remote__unsubscribe_pr_activity
mcp__claude-code-remote__update_trigger
mcp__github__actions_get
mcp__github__actions_list
mcp__github__add_reply_to_pull_request_comment
mcp__github__create_pull_request
mcp__github__get_check_run
mcp__github__get_job_logs
mcp__github__list_pull_requests
mcp__github__merge_pull_request
mcp__github__pull_request_read
mcp__github__resolve_review_thread
mcp__github__search_pull_requests
mcp__github__subscribe_pr_activity
mcp__github__unsubscribe_pr_activity
mcp__github__update_pull_request
EOF
)

start_test "the allowlist matches the approved set exactly"
assert_equal "$_expected" "$(puts "$_allow" | LC_ALL=C sort)"

test_summary "claude settings"
