#!/bin/bash
#
# Tests for prompt and preprompt functions in shrc.
# Stubs/mocks VCS and environment functions to test prompt output.
#

source "$(dirname "$0")/shrc_test_lib.sh"

# Disable colors for predictable output in assertions.
# Run with VISUAL_TEST=true to see colored prompt output in terminal:
#   VISUAL_TEST=true bash shrc_prompt_test.sh | less -R
color=false
normal='' bold='' underline='' standout=''
black='' red='' green='' yellow='' blue='' magenta='' cyan='' white=''

# Disable terminal title sequences
titlestart=''
titlefinish=''

# Set baseline environment
HOSTNAME="testhost"
USERNAME="testuser"
TERM="dumb"
shell="bash"

# Extract prompt functions from shrc
extract_func basic_prompt
extract_func preprompt
extract_func prompt_line
extract_func host_info
extract_func dir_info
extract_func tilde_pwd
extract_func maybe_space
extract_func bar
extract_func last_job_info
extract_func flash_terminal
extract_func job_info
extract_func short_hostname
extract_func set_prompt
extract_func ps1
extract_func ps1_character
extract_func keymap_character
extract_func getshopt
extract_func _color_print
extract_func blue
extract_func green
extract_func red
extract_func yellow
extract_func set_color
extract_func title
extract_func set_title
extract_func short_pwd
extract_func project_or_pwd
extract_func session_name
extract_func show_hostname_in_title
extract_func i_am_root
extract_func on_production_host
extract_func auth_info
extract_func need_auth
extract_func is_ssh_valid
extract_func inside_project
extract_func in_shpool
extract_func is_function
extract_func bash_last_error

# Stub VCS functions (no VCS by default). prompt_line calls
# `vcs prompt-line`; stub vcs() so tests don't depend on the real binary.
have_command() {
    command -v "$1" >/dev/null 2>&1
}
projectroot() { :; }
projectname() { :; }
vcs() { return 1; }
outgoing() { return 1; }
base() { :; }
# `map` is defined in shrc.vcs via the command dispatch loop; stub it
# here so preprompt's `map 2>/dev/null` call is a silent no-op by default.
map() { :; }

# Stub environment functions
on_my_machine() { true; }
on_my_workstation() { true; }
on_my_laptop() { false; }
on_test_host() { false; }
on_dev_host() { false; }
inside_tmux() { false; }
in_shpool() { false; }
bell() { :; }
log_history() { :; }

###############
start_test "basic_prompt"

basic_prompt
assert_equal '$ ' "$PS1"
assert_equal '_ ' "$PS2"
assert_equal '#? ' "$PS3"

###############
# $UID is readonly in bash, so we can't toggle it at runtime. Instead
# re-extract ps1_character with $UID replaced by a settable $_test_uid
# so both branches are exercised on every run (regardless of the user
# the test runs as).

start_test "ps1_character for root"
extract_func_subst ps1_character 's/\$UID/$_test_uid/g'
_test_uid=0
assert_equal '#' "$(ps1_character)"
start_test "ps1_character for non-root"
_test_uid=1000
assert_equal '$' "$(ps1_character)"

# Likewise re-extract ps1 with the same substitution so its output can
# be tested under both UIDs. ps1 calls keymap_character (stubbed by
# returning early when no keymap is active) and ps1_character.
start_test "ps1 output for root"
extract_func_subst ps1 's/\$UID/$_test_uid/g'
_test_uid=0
assert_equal '# ' "$(ps1)"
start_test "ps1 output for non-root"
_test_uid=1000
assert_equal '$ ' "$(ps1)"

# Re-extract the real ps1/ps1_character for the rest of the tests so
# subsequent assertions see shrc's actual UID binding.
extract_func ps1_character
extract_func ps1

###############
start_test "short_hostname strips domain and username prefix"

HOSTNAME="testuser-myhost.example.com"
USERNAME="testuser"
result="$(short_hostname)"
assert_equal "myhost" "$result"

start_test "short_hostname simple"
HOSTNAME="simplehost"
result="$(short_hostname)"
assert_equal "simplehost" "$result"

HOSTNAME="testhost"

###############
start_test "maybe_space with content"

result="$(maybe_space "hello")"
assert_equal " hello" "$result"

start_test "maybe_space with empty"
result="$(maybe_space "")"
assert_equal "" "$result"

start_test "maybe_space with no args"
result="$(maybe_space)"
assert_equal "" "$result"

###############
start_test "auth_info empty (SSH valid)"

is_ssh_valid() { true; }
result="$(auth_info)"
assert_equal "" "$result"

###############
start_test "auth_info shows warning when SSH invalid"

is_ssh_valid() { false; }
result="$(auth_info)"
assert_equal "SSH" "$result"

# Restore
is_ssh_valid() { true; }

###############
start_test "tilde_pwd replaces \$HOME with ~"

HOME="$_testdir/fakehome"
mkdir -p "$HOME/documents"
PWD="$HOME"
assert_equal "~" "$(tilde_pwd)"
PWD="$HOME/documents"
assert_equal "~/documents" "$(tilde_pwd)"
PWD="/usr/local"
assert_equal "/usr/local" "$(tilde_pwd)"

###############
start_test "host_info composes hostname and shpool tag"

HOSTNAME="mikel-laptop"
USERNAME="mikel"
on_production_host() { false; }
in_shpool() { false; }
result="$(host_info)"
assert_equal "laptop shpool" "$result"

start_test "host_info in shpool"
in_shpool() { true; }
SHPOOL_SESSION_NAME="mysession"
result="$(host_info)"
assert_equal "laptop [mysession]" "$result"
in_shpool() { false; }
unset SHPOOL_SESSION_NAME

###############
start_test "dir_info uses vcs prompt-info inside a project"

# prompt_info is defined in shrc.vcs; stub it here.
prompt_info() { echo "myproject main"; }
inside_project() { true; }
result="$(dir_info)"
assert_equal "myproject main" "$result"

###############
start_test "dir_info falls back to tilde_pwd outside a project"

inside_project() { false; }
PWD="$HOME/documents"
result="$(dir_info)"
assert_equal "~/documents" "$result"

###############
start_test "dir_info falls back to tilde_pwd when prompt_info outputs nothing"

inside_project() { true; }
prompt_info() { :; }
PWD="$HOME"
result="$(dir_info)"
assert_equal "~" "$result"

# Reset project stubs
inside_project() { false; }
prompt_info() { :; }
PWD="$HOME/documents"

###############
start_test "prompt_line composes host_info, dir_info, auth_info"

on_production_host() { false; }
in_shpool() { false; }
is_ssh_valid() { true; }
inside_project() { false; }
PWD="$HOME"
result="$(prompt_line)"
assert_equal "laptop shpool ~" "$result"

start_test "prompt_line with auth warning"
is_ssh_valid() { false; }
result="$(prompt_line)"
assert_equal "laptop shpool ~ SSH" "$result"
is_ssh_valid() { true; }

###############
start_test "prompt_line inside a project delegates dir info to prompt_info"

prompt_info() { echo "conf main"; }
inside_project() { true; }
result="$(prompt_line)"
assert_equal "laptop shpool conf main" "$result"
inside_project() { false; }
prompt_info() { :; }

###############
start_test "last_job_info with exit status 1"

current_command="false"
SECONDS=0

bash_last_error() { echo "status 1"; }
result="$(last_job_info)"
# Output ends with newline, captured by $() strips trailing newlines
assert_equal "status 1" "$result"

###############
start_test "last_job_info with no error"

bash_last_error() { :; }
current_command="true"
SECONDS=0
result="$(last_job_info)"
assert_equal "" "$result"

###############
start_test "last_job_info with duration"

bash_last_error() { :; }
current_command="sleep"
SECONDS=5
result="$(last_job_info)"
assert_equal "took 5 seconds" "$result"

###############
start_test "last_job_info with error and duration"

bash_last_error() { echo "status 1"; }
current_command="failing_command"
SECONDS=65
result="$(last_job_info)"
assert_equal "status 1 took 1 minutes 5 seconds" "$result"

###############
start_test "last_job_info skipped when no current_command"

bash_last_error() { echo "status 1"; }
current_command=
result="$(last_job_info)"
assert_equal "" "$result"

###############
start_test "last_job_info with hours"

bash_last_error() { :; }
current_command="long_command"
SECONDS=3661
result="$(last_job_info)"
assert_equal "took 1 hours 1 minutes 1 seconds" "$result"

###############
start_test "last_job_info with interrupted (exit 130)"

bash_last_error() { echo "interrupted"; }
current_command="interrupted_cmd"
SECONDS=0
result="$(last_job_info)"
assert_equal "interrupted" "$result"

###############
# shrc's last_job_info uses `seconds -gt 1`, mirrored by fish
# format_duration and nushell format-duration. A 1-second command must
# not emit "took 1 seconds" so every fast command doesn't noisily
# annotate the prompt.
start_test "last_job_info suppresses sub-threshold durations"

bash_last_error() { :; }
current_command="quick_command"
SECONDS=1
result="$(last_job_info)"
assert_equal "" "$result"

###############
start_test "preprompt integrates components"

HOME="$_testdir/fakehome"
mkdir -p "$HOME"
COLUMNS=10
HOSTNAME="testhost"
in_shpool() { false; }
on_production_host() { false; }
is_ssh_valid() { true; }
inside_project() { false; }
projectroot() { :; }
prompt_info() { :; }
outgoing() { return 1; }
current_command=
SECONDS=0
PWD="$HOME"
bash_last_error() { :; }

result="$(preprompt)"
assert_contains "testhost" "$result"
assert_contains "~" "$result"

###############
start_test "preprompt with auth warning"

is_ssh_valid() { false; }
current_command=
SECONDS=0
result="$(preprompt)"
assert_contains "SSH" "$result"

# Restore
is_ssh_valid() { true; }

###############
start_test "preprompt sets PS1"

PS1=""
current_command=
SECONDS=0
preprompt >/dev/null
if test "$UID" -eq 0; then
    _expected_ps1='# '
else
    _expected_ps1='$ '
fi
assert_equal "$_expected_ps1" "$PS1"

###############
start_test "set_prompt"

PS1=""
set_prompt
assert_equal "$_expected_ps1" "$PS1"

###############
# WHOLE PROMPT TESTS
# These test the complete output of preprompt in realistic scenarios.
# Expected values show what the user would actually see in the terminal.

# Resolve carriage returns to show terminal-visible output.
# The bar is printed first, then \r returns to column 0,
# and the prompt text overwrites the beginning of the bar.
_resolve_cr() {
    local LC_ALL=C.utf8
    local line
    while IFS= read -r line || test -n "$line"; do
        case "$line" in
        *$'\r'*)
            local before="${line%%$'\r'*}"
            local after="${line#*$'\r'}"
            if test ${#after} -lt ${#before}; then
                echo "${after}${before:${#after}}"
            else
                echo "$after"
            fi
            ;;
        *)
            echo "$line"
            ;;
        esac
    done <<< "$1"
}

# Determine expected ps1_character based on actual UID
if test "$UID" -eq 0; then
    _ps1char='#'
else
    _ps1char='$'
fi

###############
start_test "whole prompt: mikel on laptop, at home, need to auth"

HOME="$_testdir/fakehome"
mkdir -p "$HOME"
COLUMNS=80
USERNAME="mikel"
HOSTNAME="mikel-laptop"
PWD="$HOME"
current_command=
SECONDS=0
bash_last_error() { :; }
is_ssh_valid() { false; }
in_shpool() { false; }
on_production_host() { false; }
inside_project() { false; }
projectroot() { :; }
prompt_info() { :; }
outgoing() { return 1; }

result="$(_resolve_cr "$(preprompt)")"
expected="
laptop shpool ~ SSH ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――"
assert_equal "$expected" "$result"
assert_equal "$_ps1char " "$PS1"

###############
start_test "whole prompt: mikel on laptop, in /usr, last command exited with status 1"

USERNAME="mikel"
HOSTNAME="mikel-laptop"
PWD="/usr"
COLUMNS=80
current_command="ls"
SECONDS=0
bash_last_error() { echo "status 1"; }
is_ssh_valid() { true; }
in_shpool() { false; }
on_production_host() { false; }
inside_project() { false; }
projectroot() { :; }
prompt_info() { :; }
outgoing() { return 1; }

result="$(_resolve_cr "$(preprompt)")"
expected="status 1

laptop shpool /usr ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――"
assert_equal "$expected" "$result"

###############
start_test "whole prompt: mikel on workstation, in project directory, need to shpool"

_vcsdir="$_testdir/conf"
mkdir -p "$_vcsdir"
USERNAME="mikel"
HOSTNAME="mikel-workstation"
PWD="$_vcsdir"
COLUMNS=80
current_command=
SECONDS=0
bash_last_error() { :; }
is_ssh_valid() { true; }
in_shpool() { false; }
on_production_host() { false; }
inside_project() { true; }
prompt_info() { echo "conf main"; }
outgoing() { return 1; }
base() { :; }

result="$(_resolve_cr "$(preprompt)")"
expected="
workstation shpool conf main ―――――――――――――――――――――――――――――――――――――――――――――――――――"
assert_equal "$expected" "$result"

###############
start_test "whole prompt: mikel on workstation, shpool, subdir, outgoing, changes, fetch"

_edgedir="$_testdir/edge1"
mkdir -p "$_edgedir/ui"
PWD="$_edgedir/ui"
COLUMNS=80
current_command=
SECONDS=0
in_shpool() { true; }
SHPOOL_SESSION_NAME="edge1"
inside_project() { true; }
prompt_info() { echo "edge1 ui somebranch * fetch"; }
# `map` is what preprompt actually calls (since commit 426dcda replaced
# the direct `base` call). It's defined in shrc.vcs's command dispatch
# loop and not extracted by this test, so stub it directly.
map() { echo "abc1234 Bump targetSdk to 36"; }
outgoing() { echo "abc1234 Bump targetSdk to 36"; }
base() { echo "abc1234 Bump targetSdk to 36"; }

result="$(_resolve_cr "$(preprompt)")"
expected="
workstation [edge1] edge1 ui somebranch * fetch ――――――――――――――――――――――――――――――――
abc1234 Bump targetSdk to 36"
assert_equal "$expected" "$result"

# Reset all stubs for subsequent tests
USERNAME="testuser"
HOSTNAME="testhost"
current_command=
SECONDS=0
bash_last_error() { :; }
is_ssh_valid() { true; }
in_shpool() { false; }
on_production_host() { false; }
inside_project() { false; }
prompt_info() { :; }
vcs() { return 1; }
outgoing() { return 1; }
base() { :; }
map() { :; }

###############
# VISUAL TEST MODE
# Run: VISUAL_TEST=true bash shrc_prompt_test.sh | less -R
# to see colored prompt output rendered in your terminal.

if test "${VISUAL_TEST:-}" = true; then
    color=true
    bold=$'\033[1m'
    underline=$'\033[4m'
    standout=$'\033[7m'
    normal=$'\033[0m'
    black=$'\033[30m'
    red=$'\033[31m'
    green=$'\033[32m'
    yellow=$'\033[33m'
    blue=$'\033[34m'
    magenta=$'\033[35m'
    cyan=$'\033[36m'
    white=$'\033[37m'

    echo "=== Visual Color Test ==="
    echo ""
    echo "--- Color functions ---"
    red "red text"; echo ""
    green "green text"; echo ""
    yellow "yellow text"; echo ""
    blue "blue text"; echo ""
    echo ""

    echo "--- last_job_info (error, should be red) ---"
    in_shpool() { false; }
    current_command="failing"
    SECONDS=0
    bash_last_error() { echo "status 1"; }
    last_job_info
    echo ""

    echo "--- last_job_info (duration, should be yellow) ---"
    bash_last_error() { :; }
    current_command="slow"
    SECONDS=65
    last_job_info
    echo ""

    echo "--- preprompt (production host) ---"
    on_production_host() { true; }
    HOSTNAME="prodhost"
    COLUMNS=40
    current_command=
    SECONDS=0
    bash_last_error() { :; }
    preprompt
    echo ""

    echo "=== End Visual Color Test ==="

    # Restore
    on_production_host() { false; }
    in_shpool() { false; }
    unset SHPOOL_SESSION_NAME
    bash_last_error() { :; }
    current_command=
    HOSTNAME="testhost"
    color=false
    normal='' bold='' underline='' standout=''
    black='' red='' green='' yellow='' blue='' magenta='' cyan='' white=''
fi

###############
# COLOR TESTS
# These use real ANSI escapes to verify color functions produce correct output.

# Save and set ANSI color variables for color tests
_saved_color="$color"
_saved_red="$red"
_saved_green="$green"
_saved_yellow="$yellow"
_saved_blue="$blue"
_saved_normal="$normal"

color=true
red=$'\033[31m'
green=$'\033[32m'
yellow=$'\033[33m'
blue=$'\033[34m'
normal=$'\033[0m'

start_test "red() wraps text in red escape sequences"
result="$(red "error")"
assert_equal $'\033[31m'"error"$'\033[0m' "$result"

start_test "green() wraps text in green escape sequences"
result="$(green "ok")"
assert_equal $'\033[32m'"ok"$'\033[0m' "$result"

start_test "yellow() wraps text in yellow escape sequences"
result="$(yellow "warning")"
assert_equal $'\033[33m'"warning"$'\033[0m' "$result"

start_test "blue() wraps text in blue escape sequences"
result="$(blue "info")"
assert_equal $'\033[34m'"info"$'\033[0m' "$result"

start_test "set_color outputs the escape for a named color"
result="$(set_color red)"
assert_equal $'\033[31m' "$result"

start_test "set_color with multiple attributes"
bold=$'\033[1m'
result="$(set_color bold red)"
assert_equal $'\033[1m'$'\033[31m' "$result"
bold=''

start_test "last_job_info error is red"
in_shpool() { false; }
current_command="failing"
SECONDS=0
bash_last_error() { echo "status 1"; }
result="$(last_job_info)"
assert_contains $'\033[31m'"status 1"$'\033[0m' "$result"

start_test "last_job_info duration is yellow"
bash_last_error() { :; }
current_command="slow"
SECONDS=5
result="$(last_job_info)"
assert_contains $'\033[33m'"took 5 seconds"$'\033[0m' "$result"

# Restore color variables
color="$_saved_color"
red="$_saved_red"
green="$_saved_green"
yellow="$_saved_yellow"
blue="$_saved_blue"
normal="$_saved_normal"

# Restore stubs
on_production_host() { false; }
in_shpool() { false; }
unset SHPOOL_SESSION_NAME
bash_last_error() { :; }
current_command=
HOSTNAME="testhost"

###############
# PERFORMANCE
# prompt_line runs on every prompt, so its cost matters. Time 50 calls
# with `vcs prompt-info` stubbed to echo a fixed line — this measures
# the shell-composition cost (host_info, dir_info, auth_info, color
# wrapping, subshell captures) without forking the Go binary.

        start_test "prompt_line within ${_prompt_perf_budget_ms}ms budget"
inside_project() { true; }
prompt_info() { echo "proj main"; }
is_ssh_valid() { true; }
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
# Budget: 50 prompt_line calls with prompt_info stubbed should stay
# under 1s even on slow CI. The shell-composition path forks several
# subshells per prompt, so it's noticeably slower than the old single
# `vcs prompt-line` call. A regression past the budget fails the test
# rather than silently slowing every prompt.
# PROMPT_PERF_BUDGET_MS=0 disables the check for manual profiling.
_prompt_perf_budget_ms="${PROMPT_PERF_BUDGET_MS:-1000}"
if test "$_start" != "0" && test "$_end" != "0"; then
    _elapsed_ms=$(( (_end - _start) / 1000000 ))
    echo "  50 x prompt_line (shell compose): ${_elapsed_ms}ms (budget ${_prompt_perf_budget_ms}ms)"
    if test "$_prompt_perf_budget_ms" -gt 0; then
        assert_true test "$_elapsed_ms" -le "$_prompt_perf_budget_ms"
    fi
else
    skip_block "prompt_line perf check: date +%s%N unavailable"
fi

# Reset
inside_project() { false; }
prompt_info() { :; }

test_summary "$_real_shell shrc_prompt_test"
