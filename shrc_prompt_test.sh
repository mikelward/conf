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

# Pull in every shrc function via a single sourcing pass. The
# SHRC_LOAD_FUNCTIONS_ONLY guards inside shrc skip the env-setup and
# interactive / .shrc.local / auth blocks, so $PATH and exported state
# are left untouched. Replaces what used to be ~40 individual
# extract_func calls.
SHRC_LOAD_FUNCTIONS_ONLY=1 . "$_srcdir/shrc"

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
# `unmerged` is defined in shrc.vcs via the command dispatch loop; stub it
# here so preprompt's `unmerged 2>/dev/null` call is a silent no-op by default.
unmerged() { :; }
# preprompt now calls maybe_background_fetch on each prompt to keep
# remote refs warm. The real implementation invokes `command vcs
# auto-fetch`, which spawns a detached fetch per the cwd's VCS. Install
# a fake `vcs` script on PATH that records auto-fetch invocations to
# $_bg_fetch_log so the gating logic runs end-to-end without invoking
# the real binary. `command` bypasses any vcs() shell function, so a
# script on PATH is the right interception point.
_bg_fetch_log="$_testdir/bg_fetch.log"
mkdir -p "$_testdir/bin"
cat >"$_testdir/bin/vcs" <<EOF
#!/bin/sh
if test "\$1" = "auto-fetch"; then
    printf 'auto-fetch\n' >>"$_bg_fetch_log"
fi
exit 0
EOF
chmod +x "$_testdir/bin/vcs"
PATH="$_testdir/bin:$PATH"

# Stub environment functions
on_my_machine() { true; }
on_my_workstation() { true; }
on_my_laptop() { false; }
on_test_host() { false; }
on_dev_host() { false; }
inside_tmux() { false; }
in_shpool() { false; }
# Default to non-root. Tests that specifically exercise the root
# branches of host_info / ps1_character re-stub this to `true`. The
# sandbox frequently runs as UID 0, so without this stub every test
# would hit the `[root]` / red-prompt-char paths.
i_am_root() { false; }
bell() { :; }
log_history() { :; }

###############
start_test "basic_prompt"

basic_prompt
assert_equal '$ ' "$PS1"
assert_equal '_ ' "$PS2"
assert_equal '#? ' "$PS3"

###############
# ps1_character is always `$` (the bash/zsh-native glyph). When root,
# it's the same glyph wrapped in red escape markers so readline's
# width calculation still sees one character. When colour is off
# (the default in these tests), the wrap is a no-op.

start_test "ps1_character non-root prints plain dollar"
i_am_root() { false; }
assert_equal '$' "$(ps1_character)"

start_test "ps1_character root prints plain dollar when colour off"
i_am_root() { true; }
assert_equal '$' "$(ps1_character)"
i_am_root() { false; }

start_test "ps1 output non-root"
assert_equal '$ ' "$(ps1)"

start_test "ps1 output root when colour off"
i_am_root() { true; }
assert_equal '$ ' "$(ps1)"
i_am_root() { false; }

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
# No wanted/installed backend, so the warning falls back to shpool.
session_backend() { :; }
result="$(host_info)"
assert_equal "laptop shpool" "$result"

start_test "host_info in shpool"
in_shpool() { true; }
SHPOOL_SESSION_NAME="mysession"
result="$(host_info)"
assert_equal "laptop mysession" "$result"
in_shpool() { false; }
unset SHPOOL_SESSION_NAME

start_test "host_info warning honours SESSION_BACKEND"
# Outside any session, an explicitly set $SESSION_BACKEND wins over
# session_backend so the warning names the chosen backend.
in_shpool() { false; }
SESSION_BACKEND="tmux"
result="$(host_info)"
assert_equal "laptop tmux" "$result"
unset SESSION_BACKEND

start_test "host_info warning falls back to session_backend"
# With no $SESSION_BACKEND, the warning names the backend the gating
# would actually start (session_backend, shpool by default).
in_shpool() { false; }
session_backend() { puts tmux; }
result="$(host_info)"
assert_equal "laptop tmux" "$result"
session_backend() { :; }

start_test "host_info prepends [root] when root"
i_am_root() { true; }
result="$(host_info)"
assert_equal "[root] laptop shpool" "$result"
i_am_root() { false; }

start_test "host_info shows tmux session as name"
# host_info now derives its tag from session_name, so a tmux session
# (no shpool) is shown as a green session name just like shpool.
inside_tmux() { true; }
tmux() { printf 'work\n'; }
result="$(host_info)"
assert_equal "laptop work" "$result"
inside_tmux() { false; }
unset -f tmux

###############
start_test "title uses session tag"
# The xterm title mirrors host_info's session format.
show_hostname_in_title() { true; }
project_or_pwd() { printf 'proj'; }
in_shpool() { true; }
SHPOOL_SESSION_NAME="mysession"
result="$(title)"
assert_equal "laptop mysession proj" "$result"

start_test "title omits session tag when no session"
in_shpool() { false; }
unset SHPOOL_SESSION_NAME
result="$(title)"
assert_equal "laptop proj" "$result"

start_test "host_info reuses warmed session name"
# preprompt warms _session_name once per render so host_info and title
# share a single tmux fork. host_info must reuse the warmed value rather
# than re-deriving it (here the warmed "cached" differs from the live
# session_name "live" to prove the warmed value wins).
in_shpool() { true; }
SHPOOL_SESSION_NAME="live"
_session_name="cached "
result="$(host_info)"
assert_equal "laptop cached" "$result"
result="$(title)"
assert_equal "laptop cached proj" "$result"
unset _session_name SHPOOL_SESSION_NAME
in_shpool() { false; }

start_test "host_info reuses warmed empty session (no fork)"
# An empty-but-set _session_name means "warmed, no session"; it must be
# honored rather than falling back to session_name (which would re-fork).
in_shpool() { true; }
SHPOOL_SESSION_NAME="live"
_session_name=""
result="$(host_info)"
assert_equal "laptop shpool" "$result"
unset _session_name SHPOOL_SESSION_NAME
in_shpool() { false; }

start_test "prompt_session_name recomputes when not warmed"
# The cache is render-scoped: preprompt unsets _session_name after the
# render, so direct callers recompute from session_name.
unset _session_name
in_shpool() { true; }
SHPOOL_SESSION_NAME="fresh"
result="$(prompt_session_name)"
assert_equal "fresh " "$result"
unset SHPOOL_SESSION_NAME
in_shpool() { false; }

start_test "preprompt unsets the cached session name"
# preprompt warms the cache for the render then unsets it so it is not
# globally sticky.
_session_name="stale "
preprompt >/dev/null 2>&1
assert_equal "" "${_session_name+set}"

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
# job_info renders all background jobs on a single space-separated
# line so the preprompt stays compact (one line for jobs rather than
# one line per job). Stub `jobs` to feed deterministic shell-builtin
# style output to the function's sed/grep pipeline. bash-only: under
# zsh job_info reads $jobtexts (the `jobs` builtin prints nothing in
# command substitutions there), so a `jobs` stub never reaches it;
# the zsh path's filter is covered by the _job_info_keep tests below
# and by the real-job tests in shrc_test.sh.
if test "$_real_shell" = bash; then

start_test "job_info joins multiple jobs onto one line"

jobs() {
    printf '[1]+  Stopped                 vi\n'
    printf '[2]-  Stopped                 cat\n'
}
result="$(job_info)"
assert_equal "%1 vi %2 cat" "$result"

###############
start_test "job_info renders a single job without a trailing space"

jobs() {
    printf '[1]+  Stopped                 vi\n'
}
result="$(job_info)"
assert_equal "%1 vi" "$result"

###############
start_test "job_info produces no output when there are no jobs"

jobs() { :; }
result="$(job_info)"
assert_equal "" "$result"

###############
# Some `jobs` implementations emit lines like
#   [1]+  Done    pushd /tmp  (pwd now: /tmp)
# job_info filters those so they don't show up in the preprompt;
# verify the filter survives the new single-line join.
start_test "job_info filters pwd-change noise"

jobs() {
    printf '[1]+  Stopped                 vi\n'
    printf '[2]-  Done                    pushd /tmp  (pwd now: /tmp)\n'
    printf '[3]+  Stopped                 cat\n'
}
result="$(job_info)"
assert_equal "%1 vi %3 cat" "$result"

###############
# The preprompt shells out to the vcs binary via `command vcs`
# (maybe_background_fetch's `command vcs auto-fetch`, and the vcs()
# wrapper's `command vcs "$@"`). Under bash's job control those can
# surface in `jobs` and leak the preprompt's own plumbing into the
# job list it prints. job_info filters the `command vcs` prefix so
# they don't show up. A user's deliberately backgrounded `vcs foo &`
# renders as `vcs foo` (not `command vcs`) and must survive the filter.
start_test "job_info filters the preprompt's own command-vcs jobs"

jobs() {
    printf '[1]+  Running                 command vcs auto-fetch > /dev/null 2>&1 &\n'
    printf '[2]-  Done                    command vcs "$@"\n'
    printf '[3]+  Stopped                 vi\n'
    printf '[4]-  Running                 vcs log &\n'
}
result="$(job_info)"
assert_equal "%3 vi %4 vcs log &" "$result"

###############
# A non-zero exit shows as a two-word `Exit N` status; the sed only
# strips the first word, leaving the code as `%N M command vcs ...`.
# The filter allows that leftover so a failed command-vcs job (e.g. a
# helper error) is dropped too, while a failed real job is kept.
start_test "job_info filters failed (Exit N) command-vcs jobs"

jobs() {
    printf '[1]+  Exit 1                  command vcs "$@"\n'
    printf '[2]-  Exit 137                command vcs prompt-info\n'
    printf '[3]+  Stopped                 vi\n'
}
result="$(job_info)"
assert_equal "%3 vi" "$result"

###############
start_test "job_info returns nothing when only command-vcs jobs are present"

jobs() {
    printf '[1]+  Running                 command vcs auto-fetch > /dev/null 2>&1 &\n'
    printf '[2]-  Done                    command vcs "$@"\n'
}
result="$(job_info)"
assert_equal "" "$result"

unset -f jobs

else
    skip_block "job_info jobs-stub tests: zsh reads \$jobtexts, not \`jobs\` output"
fi

###############
# _job_info_keep is the zsh branch's per-job filter (plain POSIX, so
# test it under every shell): keep real jobs, drop pushd's pwd-change
# noise and the preprompt's own `command vcs` plumbing.
start_test "_job_info_keep keeps real jobs"
assert_true _job_info_keep "vi notes.txt"
assert_true _job_info_keep "vcs log"

start_test "_job_info_keep drops pwd-change noise"
assert_false _job_info_keep "pushd /tmp  (pwd now: /tmp)"

start_test "_job_info_keep drops command-vcs plumbing"
assert_false _job_info_keep "command vcs auto-fetch > /dev/null 2>&1"
assert_false _job_info_keep "command vcs"

start_test "_job_info_keep keeps commands merely mentioning command vcs"
assert_true _job_info_keep "man command vcs"

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
# PS1 is always `$ ` now (colour off in this test; root would get a
# red `$` via escape markers otherwise). The # vs $ root glyph is
# gone -- host_info carries the [root] tag as the visible cue.
start_test "preprompt sets PS1"

PS1=""
current_command=
SECONDS=0
preprompt >/dev/null
_expected_ps1='$ '
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

# The PS1 glyph is always `$` under the test's colour-off setup;
# root's red wrapping is empty when colour is disabled.
_ps1char='$'

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
start_test "whole prompt: mikel on workstation, shpool, subdir, outgoing, changes, pull"

_edgedir="$_testdir/edge1"
mkdir -p "$_edgedir/ui"
PWD="$_edgedir/ui"
COLUMNS=80
current_command=
SECONDS=0
in_shpool() { true; }
SHPOOL_SESSION_NAME="edge1"
inside_project() { true; }
prompt_info() { echo "edge1 ui somebranch * pull"; }
# `unmerged` is what preprompt actually calls. It's defined in shrc.vcs's
# command dispatch loop and not extracted by this test, so stub it directly.
unmerged() { echo "abc1234 Bump targetSdk to 36"; }
outgoing() { echo "abc1234 Bump targetSdk to 36"; }

result="$(_resolve_cr "$(preprompt)")"
expected="
workstation edge1 edge1 ui somebranch * pull ―――――――――――――――――――――――――――――――――――
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
unmerged() { :; }

###############
# maybe_background_fetch: keeps remote refs warm by invoking `vcs
# auto-fetch` after a cd to a repo with working SSH auth. Per-VCS
# detection, marker mtime, and the detached spawn live in the vcs
# binary; this shell only owns the PWD-change gate and the auth gate.
# Tests rely on the `vcs` recorder stub installed near the top of the
# file (appends to $_bg_fetch_log when the auto-fetch subcommand is
# invoked).

# Helper: reset gating state between tests so each test sees a fresh
# "PWD just changed" situation.
_reset_bg_fetch_state() {
    unset _LAST_BG_FETCH_PWD
    : >"$_bg_fetch_log"
}

_dummy_pwd="$_testdir/bgfetch-pwd"
mkdir -p "$_dummy_pwd"

start_test "maybe_background_fetch no-op when PWD unchanged"
_reset_bg_fetch_state
PWD="$_dummy_pwd"
_LAST_BG_FETCH_PWD="$PWD"
maybe_background_fetch
assert_equal "" "$(cat "$_bg_fetch_log")"

start_test "maybe_background_fetch no-op when vcs is not on PATH"
_reset_bg_fetch_state
PWD="$_dummy_pwd"
# Stash the recorder, install a have_command that says no for vcs.
_real_have_command() { command -v "$1" >/dev/null 2>&1; }
have_command() { test "$1" = vcs && return 1; _real_have_command "$1"; }
maybe_background_fetch
assert_equal "" "$(cat "$_bg_fetch_log")"
# Restore.
have_command() { _real_have_command "$1"; }

start_test "maybe_background_fetch no-op when auth_info reports problems"
_reset_bg_fetch_state
PWD="$_dummy_pwd"
is_ssh_valid() { false; }   # makes auth_info emit "SSH"
maybe_background_fetch
assert_equal "" "$(cat "$_bg_fetch_log")"
is_ssh_valid() { true; }

start_test "maybe_background_fetch fires when gates pass"
_reset_bg_fetch_state
PWD="$_dummy_pwd"
maybe_background_fetch
assert_equal "auto-fetch" "$(cat "$_bg_fetch_log")"

# Reset for later tests.
unset _LAST_BG_FETCH_PWD

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

start_test "ps1_character is red-wrapped dollar when root"
# \[...\] are the bash markers that tell readline the enclosed
# sequence is zero-width. _ps1_red_char emits them around the ANSI
# escape + glyph; shell=bash is the shrc-detected mode under this
# test harness.
i_am_root() { true; }
assert_equal '\['$'\033[31m''\]$\['$'\033[0m''\]' "$(ps1_character)"
i_am_root() { false; }

start_test "host_info root tag: brackets plain, 'root' in red"
i_am_root() { true; }
result="$(host_info)"
# Literal "[" then red-wrapped "root" then plain "]" so the
# brackets stay readable even when the terminal swallows colour.
assert_contains "["$'\033[31m'"root"$'\033[0m'"]" "$result"
i_am_root() { false; }

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
