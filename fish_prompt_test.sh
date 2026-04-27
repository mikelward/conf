#!/bin/bash
#
# Tests for prompt and preprompt functions in config/fish/config.fish.
# Mirrors shrc_prompt_test.sh but exercises the fish implementation via
# `fish -c`. Skips gracefully when fish is not installed.
#

. "$(dirname "$0")/shrc_test_lib.sh"

if ! command -v fish >/dev/null 2>&1; then
    skip_all "fish not installed"
    test_summary "fish_prompt_test"
    exit 0
fi

# Shared fish color/stub preamble. Colors are set pre-source so
# config.fish sees color=false at source time, and re-set post-source so
# anything config.fish overwrites is restored. Function stubs are
# post-source so they override config.fish definitions.
_fish_colors='
    set -g color false
    set -g normal ""
    set -g bold ""
    set -g underline ""
    set -g standout ""
    set -g black ""
    set -g red ""
    set -g green ""
    set -g yellow ""
    set -g blue ""
    set -g magenta ""
    set -g cyan ""
    set -g white ""
    set -g titlestart ""
    set -g titlefinish ""
'

# Run a fish snippet with prompt-related functions from config.fish
# preloaded, using stubs that disable colors and avoid touching the real
# environment. The snippet runs inside an interactive fish (`fish -i -c`)
# so that prompt functions defined under `if is_interactive` are available.
_fish_run() {
    _fish_run_config "$_fish_colors" "$_fish_colors"'
        function bell; end
        function flash_terminal; end
        function jobs; end
        function is_ssh_valid; return 0; end
        function on_production_host; return 1; end
        function on_my_workstation; return 0; end
        function on_my_laptop; return 1; end
        function inside_tmux; return 1; end
        # Default to non-root. Tests that exercise the root branches
        # of host_info / ps1_character re-stub this to return 0 (true).
        function i_am_root; return 1; end
        function have_command
            switch $argv[1]
                case vcs; return 0
                case "*"; command -v $argv[1] >/dev/null 2>&1
            end
        end
        function vcs; return 1; end
        function projectroot; return 1; end
        function projectname; return 1; end
        function log_history; end
    ' "$1"
}

###############
start_test "fish maybe_space with content"
result="$(_fish_run 'maybe_space hello')"
assert_equal " hello" "$result"

start_test "fish maybe_space with empty"
result="$(_fish_run 'maybe_space ""')"
assert_equal "" "$result"

start_test "fish maybe_space with no args"
result="$(_fish_run 'maybe_space')"
assert_equal "" "$result"

###############
start_test "fish bar prints N separator characters"
result="$(_fish_run 'bar 5')"
assert_equal "―――――" "$result"

###############
start_test "fish ps1_character prints > non-root"
result="$(_fish_run 'ps1_character')"
assert_equal ">" "$result"

start_test "fish ps1_character prints plain > when root (colour off)"
# colour=false in the _fish_run preamble, so red() is a no-op wrap.
result="$(_fish_run 'function i_am_root; return 0; end; ps1_character')"
assert_equal ">" "$result"

###############
start_test "fish in_shpool false when unset"
result="$(_fish_run 'if in_shpool; echo yes; else; echo no; end')"
assert_equal "no" "$result"

start_test "fish in_shpool true when SHPOOL_SESSION_NAME set"
result="$(_fish_run 'set -g SHPOOL_SESSION_NAME main; if in_shpool; echo yes; else; echo no; end')"
assert_equal "yes" "$result"

###############
start_test "fish session_name empty when not in pool"
result="$(_fish_run 'session_name')"
assert_equal "" "$result"

start_test "fish session_name returns shpool session"
result="$(_fish_run 'set -g SHPOOL_SESSION_NAME edge1; session_name')"
assert_equal "edge1 " "$result"

###############
# TEST: format_duration (parity with bash last_job_info duration format)

start_test "fish format_duration 0ms -> empty"
result="$(_fish_run 'format_duration 0')"
assert_equal "" "$result"

start_test "fish format_duration 1s -> empty (below threshold)"
result="$(_fish_run 'format_duration 1000')"
assert_equal "" "$result"

start_test "fish format_duration 5s"
result="$(_fish_run 'format_duration 5000')"
assert_equal "5 seconds" "$result"

start_test "fish format_duration 1m5s"
result="$(_fish_run 'format_duration 65000')"
assert_equal "1 minutes 5 seconds" "$result"

start_test "fish format_duration 1h1m1s"
result="$(_fish_run 'format_duration 3661000')"
assert_equal "1 hours 1 minutes 1 seconds" "$result"

###############
# TEST: last_job_info (parity with bash). Same behaviour contract:
# - prints nothing when current_command is unset
# - prints red error status when fish_last_error is non-empty
# - prints "took <duration>" (lowercase, matches bash/nushell) when
#   CMD_DURATION is above the format_duration threshold
# - joins error + duration with a single space
# - emits a trailing newline only when something was printed

start_test "fish last_job_info shows error status"
result="$(_fish_run '
    function fish_last_error; echo "status 1"; end
    set -g current_command false
    set -g CMD_DURATION 0
    last_job_info
')"
assert_equal "status 1" "$result"

start_test "fish last_job_info no output on success"
result="$(_fish_run '
    function fish_last_error; end
    set -g current_command true
    set -g CMD_DURATION 0
    last_job_info
')"
assert_equal "" "$result"

start_test "fish last_job_info shows duration (lowercase took)"
result="$(_fish_run '
    function fish_last_error; end
    set -g current_command sleep
    set -g CMD_DURATION 5000
    last_job_info
')"
assert_equal \
    "took 5 seconds" "$result"

start_test "fish last_job_info shows error and duration"
result="$(_fish_run '
    function fish_last_error; echo "status 1"; end
    set -g current_command failing_command
    set -g CMD_DURATION 65000
    last_job_info
')"
assert_equal \
    "status 1 took 1 minutes 5 seconds" "$result"

start_test "fish last_job_info skipped without current_command"
result="$(_fish_run '
    function fish_last_error; echo "status 1"; end
    set -e current_command
    set -g CMD_DURATION 0
    last_job_info
')"
assert_equal "" "$result"

start_test "fish last_job_info shows hours"
result="$(_fish_run '
    function fish_last_error; end
    set -g current_command long_command
    set -g CMD_DURATION 3661000
    last_job_info
')"
assert_equal \
    "took 1 hours 1 minutes 1 seconds" "$result"

start_test "fish last_job_info shows interrupted"
result="$(_fish_run '
    function fish_last_error; echo "interrupted"; end
    set -g current_command interrupted_cmd
    set -g CMD_DURATION 0
    last_job_info
')"
assert_equal "interrupted" "$result"

# Sub-threshold durations must not print, matching bash's `seconds -gt 1`.
start_test "fish last_job_info suppresses 1s duration"
result="$(_fish_run '
    function fish_last_error; end
    set -g current_command quick
    set -g CMD_DURATION 1000
    last_job_info
')"
assert_equal "" "$result"

###############
# TEST: fish_last_error (parity with bash_last_error / nushell last-job-info)
# Exercises the real fish_last_error by setting last_job_status directly.
# Expected output contract:
#   0    -> ""                (success)
#   130  -> "interrupted"     (Ctrl-C)
#   148  -> ""                (suspended)
#   other-> "status <N>"      (matches bash/nushell wording, lowercase)

start_test "fish fish_last_error silent on success"
result="$(_fish_run 'set -g last_job_status 0; fish_last_error')"
assert_equal "" "$result"

start_test "fish fish_last_error formats status N"
result="$(_fish_run 'set -g last_job_status 1; fish_last_error')"
assert_equal "status 1" "$result"

start_test "fish fish_last_error 130 is interrupted"
result="$(_fish_run 'set -g last_job_status 130; fish_last_error')"
assert_equal "interrupted" "$result"

start_test "fish fish_last_error silent when suspended (148)"
result="$(_fish_run 'set -g last_job_status 148; fish_last_error')"
assert_equal "" "$result"

start_test "fish fish_last_error preserves arbitrary codes"
result="$(_fish_run 'set -g last_job_status 42; fish_last_error')"
assert_equal "status 42" "$result"

###############
# TEST: fish_prompt integrates prompt_line and bar

# Use a fixed COLUMNS so the bar width is predictable.
# Resolve \r like shrc_prompt_test's _resolve_cr so assertions match
# what the user actually sees in the terminal.
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

# ps1_character is always '>' in fish.
_ps1char='>'

###############
# TEST: host_info composes short hostname and shpool tag

start_test "fish host_info off shpool off prod"
result="$(_fish_run '
    set -g HOSTNAME mikel-laptop
    set -g USERNAME mikel
    function on_production_host; return 1; end
    function in_shpool; return 1; end
    host_info
')"
assert_equal "laptop shpool" "$result"

start_test "fish host_info in shpool"
result="$(_fish_run '
    set -g HOSTNAME mikel-laptop
    set -g USERNAME mikel
    set -g SHPOOL_SESSION_NAME edge1
    function on_production_host; return 1; end
    function in_shpool; return 0; end
    host_info
')"
assert_equal "laptop [edge1]" "$result"

start_test "fish host_info prepends [root] when root"
result="$(_fish_run '
    set -g HOSTNAME mikel-laptop
    set -g USERNAME mikel
    function on_production_host; return 1; end
    function in_shpool; return 1; end
    function i_am_root; return 0; end
    host_info
')"
assert_equal "[root] laptop shpool" "$result"

###############
# TEST: tilde_pwd replaces $HOME with ~

start_test "fish tilde_pwd at \$HOME"
result="$(_fish_run 'cd $HOME; tilde_pwd')"
assert_equal "~" "$result"

start_test "fish tilde_pwd inside \$HOME"
result="$(_fish_run 'mkdir -p $HOME/documents; cd $HOME/documents; tilde_pwd')"
assert_equal "~/documents" "$result"

start_test "fish tilde_pwd outside \$HOME"
result="$(_fish_run 'cd /usr; tilde_pwd')"
assert_equal "/usr" "$result"

###############
# TEST: dir_info delegates to prompt_info inside a project

start_test "fish dir_info uses prompt_info inside project"
result="$(_fish_run '
    function prompt_info; echo "myproject main"; end
    dir_info
')"
assert_equal \
    "myproject main" "$result"

###############
# TEST: dir_info falls back to tilde_pwd when prompt_info returns empty

start_test "fish dir_info falls back to tilde_pwd"
result="$(_fish_run '
    function prompt_info; return 1; end
    cd $HOME
    dir_info
')"
assert_equal "~" "$result"

###############
# TEST: prompt_line composes host_info + dir_info + auth_info

start_test "fish prompt_line without auth warning"
result="$(_fish_run '
    set -g HOSTNAME mikel-laptop
    set -g USERNAME mikel
    function on_production_host; return 1; end
    function in_shpool; return 1; end
    function is_ssh_valid; return 0; end
    function prompt_info; return 1; end
    cd $HOME
    prompt_line
')"
assert_equal \
    "laptop shpool ~" "$result"

start_test "fish prompt_line with auth warning"
result="$(_fish_run '
    set -g HOSTNAME mikel-laptop
    set -g USERNAME mikel
    function on_production_host; return 1; end
    function in_shpool; return 1; end
    function is_ssh_valid; return 1; end
    function prompt_info; return 1; end
    cd $HOME
    prompt_line
')"
assert_equal \
    "laptop shpool ~ SSH" "$result"

###############
# TEST: prompt_line inside a project shows vcs prompt-info output

start_test "fish prompt_line inside project shows vcs info"
result="$(_fish_run '
    set -g HOSTNAME mikel-laptop
    set -g USERNAME mikel
    function on_production_host; return 1; end
    function in_shpool; return 1; end
    function is_ssh_valid; return 0; end
    function prompt_info; echo "conf main"; end
    prompt_line
')"
assert_equal \
    "laptop shpool conf main" "$result"

###############
# WHOLE PROMPT: laptop, home directory, need to auth

start_test "fish whole prompt: laptop, home, need auth"
result="$(_fish_run '
    set -g HOSTNAME mikel-laptop
    set -g USERNAME mikel
    set -g COLUMNS 80
    mkdir -p $HOME
    cd $HOME
    function is_ssh_valid; return 1; end
    function prompt_info; return 1; end
    function vcs
        switch $argv[1]
            case map; return 0
            case "*"; return 1
        end
    end
    fish_prompt
')"
result="$(_resolve_cr "$result")"
expected="
laptop shpool ~ SSH ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
$_ps1char "
assert_equal "$expected" "$result"

###############
# WHOLE PROMPT: workstation, project dir with vcs info

start_test "fish whole prompt: workstation, project root, shpool"
result="$(_fish_run '
    set -g HOSTNAME mikel-workstation
    set -g USERNAME mikel
    set -g COLUMNS 80
    function prompt_info; echo "conf main"; end
    function vcs
        switch $argv[1]
            case map; return 0
            case "*"; return 1
        end
    end
    fish_prompt
')"
result="$(_resolve_cr "$result")"
expected="
workstation shpool conf main ―――――――――――――――――――――――――――――――――――――――――――――――――――
$_ps1char "
assert_equal "$expected" "$result"

###############
# WHOLE PROMPT: inside shpool session, subdir, dirty, stale fetch

start_test "fish whole prompt: workstation, shpool, subdir, dirty, fetch"
result="$(_fish_run '
    set -g HOSTNAME mikel-workstation
    set -g USERNAME mikel
    set -g COLUMNS 80
    set -g SHPOOL_SESSION_NAME edge1
    function prompt_info; echo "edge1 ui somebranch * fetch"; end
    function vcs
        switch $argv[1]
            case map; return 0
            case "*"; return 1
        end
    end
    fish_prompt
')"
result="$(_resolve_cr "$result")"
expected="
workstation [edge1] edge1 ui somebranch * fetch ――――――――――――――――――――――――――――――――
$_ps1char "
assert_equal "$expected" "$result"

###############
# TEST: fish_mode_prompt displays the current vi-style bind mode

start_test "fish_mode_prompt insert mode"
result="$(_fish_run 'set -g fish_bind_mode insert; fish_mode_prompt')"
assert_equal "INSERT " "$result"

start_test "fish_mode_prompt default (normal) mode"
result="$(_fish_run 'set -g fish_bind_mode default; fish_mode_prompt')"
assert_equal "NORMAL " "$result"

start_test "fish_mode_prompt visual mode"
result="$(_fish_run 'set -g fish_bind_mode visual; fish_mode_prompt')"
assert_equal "VISUAL " "$result"

start_test "fish_mode_prompt replace mode"
result="$(_fish_run 'set -g fish_bind_mode replace; fish_mode_prompt')"
assert_equal "REPLACE " "$result"

start_test "fish_mode_prompt replace_one mode"
result="$(_fish_run 'set -g fish_bind_mode replace_one; fish_mode_prompt')"
assert_equal "REPLACE " "$result"

start_test "fish_mode_prompt empty when fish_bind_mode unset"
result="$(_fish_run 'set -e fish_bind_mode; fish_mode_prompt')"
assert_equal "" "$result"

start_test "fish_mode_prompt falls back to raw mode name"
result="$(_fish_run 'set -g fish_bind_mode mystery; fish_mode_prompt')"
assert_equal "mystery " "$result"

###############
# TEST: my_vi_key_bindings is selected as the key binding function

start_test "fish sets fish_key_bindings to my_vi_key_bindings"
result="$(_fish_run 'echo $fish_key_bindings')"
assert_equal "my_vi_key_bindings" "$result"

###############
# PERFORMANCE
# prompt_line runs on every prompt, so its cost matters. Time 50 calls
# inside a single fish process so we're measuring shell-composition
# overhead (host_info, dir_info, auth_info, subshell captures) rather
# than fish startup. `prompt_info` is stubbed so we don't fork the real
# Go binary here. The budget catches ~10x regressions without flaking on
# slow CI; FISH_PROMPT_PERF_BUDGET_MS=0 disables the check.
        start_test "fish prompt_line within ${_fish_perf_budget_ms}ms budget"
_fish_perf_budget_ms="${FISH_PROMPT_PERF_BUDGET_MS:-1000}"
_fish_perf_line=$(_fish_run '
    set -g HOSTNAME mikel-workstation
    set -g USERNAME mikel
    function prompt_info; echo "proj main"; end
    function is_ssh_valid; return 0; end
    # Warmup: exclude first-call disk/icache variance (module resolution,
    # function lookups, etc.) from the timed loop. Mirrors the warmup in
    # shrc_prompt_test.sh so fish and bash perf tests measure the same
    # thing.
    prompt_line >/dev/null 2>&1
    set _start (date +%s%N)
    for i in (seq 1 50)
        prompt_line >/dev/null 2>&1
    end
    set _end (date +%s%N)
    set _elapsed_ms (math --scale=0 "($_end - $_start) / 1000000")
    echo "PERF_MS=$_elapsed_ms"
')
_fish_perf_ms=$(printf '%s\n' "$_fish_perf_line" | sed -n 's/^PERF_MS=//p' | head -1)
if test -n "$_fish_perf_ms"; then
    echo "  50 x fish prompt_line (binary stub): ${_fish_perf_ms}ms (budget ${_fish_perf_budget_ms}ms)"
    if test "$_fish_perf_budget_ms" -gt 0; then
        assert_true \
            test "$_fish_perf_ms" -le "$_fish_perf_budget_ms"
    fi
else
    skip_block "fish prompt_line perf check: could not parse elapsed time"
fi

test_summary "fish_prompt_test"
