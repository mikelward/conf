#!/bin/bash
#
# prompt_line runs on every prompt, so its cost matters. Time 50 calls
# with `vcs prompt-info` stubbed to echo a fixed line — this measures
# the shell-composition cost (host_info, dir_info, auth_info, color
# wrapping, subshell captures) without forking the Go binary.
#
# A timing is only meaningful on an otherwise idle machine, so `make test`
# runs this alone, after the parallel suites have finished, rather than as
# part of test-all.
#

source "$(dirname "$0")/shrc_test_lib.sh"

color=false
normal='' bold='' underline='' standout=''
black='' red='' green='' yellow='' blue='' magenta='' cyan='' white=''
titlestart=''
titlefinish=''
HOSTNAME="testhost"
USERNAME="testuser"
TERM="dumb"
shell="bash"

SHRC_LOAD_FUNCTIONS_ONLY=1 . "$_srcdir/shrc"

# The same stubs as shrc_prompt_test.sh, so no VCS or host lookup runs.
have_command() {
    command -v "$1" >/dev/null 2>&1
}
projectroot() { :; }
projectname() { :; }
vcs() { return 1; }
on_my_machine() { true; }
on_my_workstation() { true; }
on_my_laptop() { false; }
on_test_host() { false; }
on_dev_host() { false; }
inside_tmux() { false; }
in_shpool() { false; }
i_am_root() { false; }
on_production_host() { false; }
session_backend() { :; }
# The auth probes (ssh agent, Kerberos) depend on the host; the bounded
# wrapper prompt_line runs them in is still timed.
auth_info() { :; }
inside_project() { true; }
prompt_info() { echo "proj main"; }
is_ssh_valid() { true; }
# An interactive shell allocates the auth probe's temp file once
# (allocate_timeout_file); without one, every prompt would fork mktemp and
# time that too. This one is under the test's directory, so it goes with it.
_with_timeout_file="$_testdir/timeout"

# Budget: 50 prompt_line calls with prompt_info stubbed should stay
# under 1s even on slow CI. The shell-composition path forks several
# subshells per prompt, so it's noticeably slower than the old single
# `vcs prompt-line` call. A regression past the budget fails the test
# rather than silently slowing every prompt.
# PROMPT_PERF_BUDGET_MS=0 disables the check for manual profiling.
_prompt_perf_budget_ms="${PROMPT_PERF_BUDGET_MS:-1000}"

start_test "prompt_line within ${_prompt_perf_budget_ms}ms budget"
# Warmup: exclude first-call disk/icache variance (module resolution,
# readline setup, etc.) from the timed loop.
prompt_line >/dev/null 2>&1
_start=$(_now_ns)
_i=0
while test $_i -lt 50; do
    prompt_line >/dev/null 2>&1
    _i=$((_i + 1))
done
_end=$(_now_ns)
if test "$_start" != "0" && test "$_end" != "0"; then
    _elapsed_ms=$(( (_end - _start) / 1000000 ))
    echo "  50 x prompt_line (shell compose): ${_elapsed_ms}ms (budget ${_prompt_perf_budget_ms}ms)"
    if test "$_prompt_perf_budget_ms" -gt 0; then
        assert_true test "$_elapsed_ms" -le "$_prompt_perf_budget_ms"
    fi
else
    skip_block "prompt_line perf check: date +%s%N unavailable"
fi

test_summary "$_real_shell shrc_prompt_perf_test"
