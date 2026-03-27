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
extract_func maybe_space
extract_func bar
extract_func last_job_info
extract_func flash_terminal
extract_func host_info
extract_func dir_info
extract_func _dir_info
extract_func job_info
extract_func short_hostname
extract_func tilde_directory
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
extract_func fetch_info
extract_func is_ssh_valid
extract_func bash_last_error
extract_func vcs_info
extract_func status_chars "$_srcdir/shrc.vcs"
extract_func git_where "$_srcdir/shrc.vcs.git"

# Stub VCS functions (no VCS by default)
projectroot() { :; }
projectname() { :; }
vcs() { return 1; }
git_branch() { :; }
git() { return 1; }
status() { :; }
outgoing() { return 1; }
base() { :; }
fetchtime() { return 1; }

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
# TEST: basic_prompt

basic_prompt
assert_equal "basic_prompt sets PS1" '$ ' "$PS1"
assert_equal "basic_prompt sets PS2" '_ ' "$PS2"
assert_equal "basic_prompt sets PS3" '#? ' "$PS3"

###############
# TEST: ps1_character

# UID is readonly in bash, so test based on actual UID
if test "$UID" -eq 0; then
    result="$(ps1_character)"
    assert_equal "ps1_character for root" '#' "$result"

    result="$(ps1)"
    assert_equal "ps1 output for root" '# ' "$result"
else
    result="$(ps1_character)"
    assert_equal "ps1_character for non-root" '$' "$result"

    result="$(ps1)"
    assert_equal "ps1 output for non-root" '$ ' "$result"
fi

###############
# TEST: short_hostname

HOSTNAME="testuser-myhost.example.com"
USERNAME="testuser"
result="$(short_hostname)"
assert_equal "short_hostname strips domain and username prefix" "myhost" "$result"

HOSTNAME="simplehost"
result="$(short_hostname)"
assert_equal "short_hostname simple" "simplehost" "$result"

HOSTNAME="testhost"

###############
# TEST: maybe_space

result="$(maybe_space "hello")"
assert_equal "maybe_space with content" " hello" "$result"

result="$(maybe_space "")"
assert_equal "maybe_space with empty" "" "$result"

result="$(maybe_space)"
assert_equal "maybe_space with no args" "" "$result"

###############
# TEST: auth_info empty (SSH valid)

is_ssh_valid() { true; }
result="$(auth_info)"
assert_equal "auth_info empty when ssh valid" "" "$result"

###############
# TEST: auth_info shows warning when SSH invalid

is_ssh_valid() { false; }
result="$(auth_info)"
assert_equal "auth_info warns when ssh invalid" "SSH" "$result"

# Restore
is_ssh_valid() { true; }

###############
# TEST: dir_info outside VCS shows tilde directory

projectroot() { :; }
HOME="$_testdir/fakehome"
mkdir -p "$HOME/documents"
PWD="$HOME/documents"
result="$(_dir_info "$PWD")"
assert_equal "dir_info outside VCS shows tilde path" "~/documents" "$result"

###############
# TEST: dir_info in VCS root

_vcsdir="$_testdir/myproject"
mkdir -p "$_vcsdir"
projectroot() { echo "$_vcsdir"; }
# vcs with args dispatches to ${vcs}_${command}, so stub both
vcs() {
    if test $# -gt 0; then
        local command=$1; shift
        "git_${command}" "$@"
    else
        echo "git"
    fi
}
git_branch() { echo "main"; }
git() {
    case "$1 $2" in
        "rev-parse --short") echo "abc1234" ;;
        *) command git "$@" ;;
    esac
}
status() { :; }
fetchtime() { return 1; }

PWD="$_vcsdir"
result="$(_dir_info "$PWD")"
assert_equal "dir_info at VCS root" "myproject main abc1234" "$result"

###############
# TEST: dir_info in subdirectory of VCS root

_subdir="$_vcsdir/src/lib"
mkdir -p "$_subdir"
PWD="$_subdir"
result="$(_dir_info "$PWD")"
assert_equal "dir_info in VCS subdirectory" "myproject src/lib main abc1234" "$result"

###############
# TEST: dir_info with branch and status chars

status() { printf 'M  file1.txt\n'; }
PWD="$_vcsdir"
result="$(_dir_info "$PWD")"
assert_equal "dir_info with status chars" "myproject main abc1234 M" "$result"

###############
# TEST: dir_info with fetch warning

status() { :; }
fetchtime() { echo "0"; }
result="$(_dir_info "$PWD")"
assert_equal "dir_info with stale fetch" "myproject main abc1234 fetch" "$result"

# Reset stubs
git_branch() { :; }
git() { return 1; }
status() { :; }
fetchtime() { return 1; }
projectroot() { :; }
vcs() { return 1; }

###############
# TEST: last_job_info with exit status 1

current_command="false"
SECONDS=0

bash_last_error() { echo "status 1"; }
result="$(last_job_info)"
# Output ends with newline, captured by $() strips trailing newlines
assert_equal "last_job_info shows error status" "status 1" "$result"

###############
# TEST: last_job_info with no error

bash_last_error() { :; }
current_command="true"
SECONDS=0
result="$(last_job_info)"
assert_equal "last_job_info no output on success" "" "$result"

###############
# TEST: last_job_info with duration

bash_last_error() { :; }
current_command="sleep"
SECONDS=5
result="$(last_job_info)"
assert_equal "last_job_info shows duration" "took 5 seconds" "$result"

###############
# TEST: last_job_info with error and duration

bash_last_error() { echo "status 1"; }
current_command="failing_command"
SECONDS=65
result="$(last_job_info)"
assert_equal "last_job_info shows error and duration" "status 1 took 1 minutes 5 seconds" "$result"

###############
# TEST: last_job_info skipped when no current_command

bash_last_error() { echo "status 1"; }
current_command=
result="$(last_job_info)"
assert_equal "last_job_info skipped without current_command" "" "$result"

###############
# TEST: last_job_info with hours

bash_last_error() { :; }
current_command="long_command"
SECONDS=3661
result="$(last_job_info)"
assert_equal "last_job_info shows hours" "took 1 hours 1 minutes 1 seconds" "$result"

###############
# TEST: last_job_info with interrupted (exit 130)

bash_last_error() { echo "interrupted"; }
current_command="interrupted_cmd"
SECONDS=0
result="$(last_job_info)"
assert_equal "last_job_info shows interrupted" "interrupted" "$result"

###############
# TEST: host_info without shpool

in_shpool() { false; }
on_production_host() { false; }
HOSTNAME="testhost"
result="$(host_info)"
# host_info prints hostname\n then shpool suggestion
expected="testhost shpool"
assert_equal "host_info without shpool" "$expected" "$result"

###############
# TEST: host_info with shpool session

in_shpool() { true; }
SHPOOL_SESSION_NAME="main"
result="$(host_info)"
expected="testhost [main]"
assert_equal "host_info with shpool" "$expected" "$result"

in_shpool() { false; }
unset SHPOOL_SESSION_NAME

###############
# TEST: preprompt integrates components

HOME="$_testdir/fakehome"
mkdir -p "$HOME"
COLUMNS=10
HOSTNAME="testhost"
in_shpool() { false; }
on_production_host() { false; }
is_ssh_valid() { true; }
projectroot() { :; }
vcs() { return 1; }
outgoing() { return 1; }
current_command=
SECONDS=0
PWD="$HOME"
bash_last_error() { :; }

result="$(preprompt)"
assert_true "preprompt contains hostname" echo "$result" | grep -q "testhost"
assert_true "preprompt contains dir" echo "$result" | grep -q "~"

###############
# TEST: preprompt with auth warning

is_ssh_valid() { false; }
current_command=
SECONDS=0
result="$(preprompt)"
assert_true "preprompt contains SSH warning" echo "$result" | grep -q "SSH"

# Restore
is_ssh_valid() { true; }

###############
# TEST: preprompt sets PS1

PS1=""
current_command=
SECONDS=0
preprompt >/dev/null
if test "$UID" -eq 0; then
    _expected_ps1='# '
else
    _expected_ps1='$ '
fi
assert_equal "preprompt sets PS1 via set_prompt" "$_expected_ps1" "$PS1"

###############
# TEST: set_prompt

PS1=""
set_prompt
assert_equal "set_prompt sets PS1" "$_expected_ps1" "$PS1"

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
# WHOLE PROMPT: mikel on laptop, at home, need to auth

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
projectroot() { :; }
vcs() { return 1; }
outgoing() { return 1; }

result="$(_resolve_cr "$(preprompt)")"
expected="
laptop shpool ~ SSH ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――"
assert_equal "whole prompt: laptop, home, need auth" "$expected" "$result"
assert_equal "whole prompt: laptop sets PS1" "$_ps1char " "$PS1"

###############
# WHOLE PROMPT: mikel on laptop, in /usr, last command exited with status 1

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
projectroot() { :; }
vcs() { return 1; }
outgoing() { return 1; }

result="$(_resolve_cr "$(preprompt)")"
expected="status 1

laptop shpool /usr ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――"
assert_equal "whole prompt: laptop, /usr, status 1" "$expected" "$result"

###############
# WHOLE PROMPT: mikel on workstation, in project directory, need to shpool

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
projectroot() { echo "$_vcsdir"; }
vcs() {
    if test $# -gt 0; then
        local command=$1; shift
        "git_${command}" "$@"
    else
        echo "git"
    fi
}
git_branch() { echo "main"; }
git() {
    case "$1 $2" in
        "rev-parse --short") echo "abc1234" ;;
        *) command git "$@" ;;
    esac
}
status() { :; }
fetchtime() { return 1; }
outgoing() { return 1; }
base() { echo "abc1234 Some commit"; }

result="$(_resolve_cr "$(preprompt)")"
expected="
workstation shpool conf main abc1234 ―――――――――――――――――――――――――――――――――――――――――――"
assert_equal "whole prompt: workstation, project root, shpool" "$expected" "$result"

###############
# WHOLE PROMPT: mikel on workstation, in shpool session, in project subdirectory,
#               with outgoing commit, local changes, and stale fetch

_edgedir="$_testdir/edge1"
mkdir -p "$_edgedir/ui"
PWD="$_edgedir/ui"
COLUMNS=80
current_command=
SECONDS=0
in_shpool() { true; }
SHPOOL_SESSION_NAME="edge1"
projectroot() { echo "$_edgedir"; }
git_branch() { echo "somebranch"; }
status() { printf 'M  file1.txt\n?? file2.txt\n'; }
fetchtime() { echo "0"; }
outgoing() { echo "abc1234 Bump targetSdk to 36"; }
base() { echo "abc1234 Bump targetSdk to 36"; }

result="$(_resolve_cr "$(preprompt)")"
expected="
workstation [edge1] edge1 ui somebranch abc1234 ?? M fetch ―――――――――――――――――――――
abc1234 Bump targetSdk to 36"
assert_equal "whole prompt: workstation, shpool, subdir, outgoing, changes, fetch" "$expected" "$result"

# Reset all stubs for subsequent tests
USERNAME="testuser"
HOSTNAME="testhost"
current_command=
SECONDS=0
bash_last_error() { :; }
is_ssh_valid() { true; }
in_shpool() { false; }
on_production_host() { false; }
projectroot() { :; }
vcs() { return 1; }
git_branch() { :; }
git() { return 1; }
status() { :; }
outgoing() { return 1; }
base() { :; }
fetchtime() { return 1; }

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

    echo "--- host_info (non-production) ---"
    on_production_host() { false; }
    in_shpool() { false; }
    HOSTNAME="devhost"
    host_info
    echo ""

    echo "--- host_info (production, should be red) ---"
    on_production_host() { true; }
    HOSTNAME="prodhost"
    host_info
    echo ""

    echo "--- host_info (shpool session, name should be green) ---"
    on_production_host() { false; }
    in_shpool() { true; }
    SHPOOL_SESSION_NAME="main"
    HOSTNAME="devhost"
    host_info
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

# TEST: red() wraps text in red escape sequences
result="$(red "error")"
assert_equal "red() wraps text" $'\033[31m'"error"$'\033[0m' "$result"

# TEST: green() wraps text in green escape sequences
result="$(green "ok")"
assert_equal "green() wraps text" $'\033[32m'"ok"$'\033[0m' "$result"

# TEST: yellow() wraps text in yellow escape sequences
result="$(yellow "warning")"
assert_equal "yellow() wraps text" $'\033[33m'"warning"$'\033[0m' "$result"

# TEST: blue() wraps text in blue escape sequences
result="$(blue "info")"
assert_equal "blue() wraps text" $'\033[34m'"info"$'\033[0m' "$result"

# TEST: set_color outputs the escape for a named color
result="$(set_color red)"
assert_equal "set_color red" $'\033[31m' "$result"

# TEST: set_color with multiple attributes
bold=$'\033[1m'
result="$(set_color bold red)"
assert_equal "set_color bold red" $'\033[1m'$'\033[31m' "$result"
bold=''

# TEST: host_info uses red for production hosts
on_production_host() { true; }
in_shpool() { false; }
HOSTNAME="prodhost"
result="$(host_info)"
assert_contains "production host_info contains red" $'\033[31m' "$result"
assert_contains "production host_info contains normal reset" $'\033[0m' "$result"

# TEST: host_info no red for non-production hosts
on_production_host() { false; }
HOSTNAME="devhost"
result="$(host_info)"
assert_not_contains "non-production host_info has no red" $'\033[31m' "$result"

# TEST: host_info shpool session name is green
in_shpool() { true; }
SHPOOL_SESSION_NAME="main"
result="$(host_info)"
assert_contains "shpool session name is green" $'\033[32m'"main"$'\033[0m' "$result"

# TEST: last_job_info error is red
in_shpool() { false; }
current_command="failing"
SECONDS=0
bash_last_error() { echo "status 1"; }
result="$(last_job_info)"
assert_contains "last_job_info error is red" $'\033[31m'"status 1"$'\033[0m' "$result"

# TEST: last_job_info duration is yellow
bash_last_error() { :; }
current_command="slow"
SECONDS=5
result="$(last_job_info)"
assert_contains "last_job_info duration is yellow" $'\033[33m'"took 5 seconds"$'\033[0m' "$result"

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

_shell="$(basename "$(readlink -f /proc/$$/exe)" 2>/dev/null || echo "bash")"

test_summary "$_shell shrc_prompt_test"
