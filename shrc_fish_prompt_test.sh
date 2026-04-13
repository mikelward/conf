#!/bin/bash
#
# Tests for prompt and preprompt functions in config/fish/config.fish.
# Mirrors shrc_prompt_test.sh but exercises the fish implementation via
# `fish -c`. Skips gracefully when fish is not installed.
#

. "$(dirname "$0")/shrc_test_lib.sh"

if ! command -v fish >/dev/null 2>&1; then
    skip_all "fish not installed"
    test_summary "fish shrc_fish_prompt_test"
    exit 0
fi

_srcdir="$(cd "$(dirname "$0")" && pwd)"
_config="$_srcdir/config/fish/config.fish"

# Run a fish snippet with prompt-related functions from config.fish preloaded,
# using stubs that disable colors and avoid touching the real environment.
# The snippet runs inside an interactive fish (`fish -i -c`) so that the
# prompt functions defined under `if is_interactive` are available. A
# minimal fake home directory is used to keep config.fish from sourcing
# local overrides. Tty/color escapes are suppressed by stubbing tput.
_fish_run() {
    local _snippet="$1"
    local _fakehome="$_testdir/fakehome"
    mkdir -p "$_fakehome"
    HOME="$_fakehome" \
        TERM=dumb \
        SHPOOL_SESSION_NAME= \
        TMUX= \
        fish --no-config -i -c "
            function tput; return 1; end
            set -g color false
            set -g normal ''
            set -g bold ''
            set -g underline ''
            set -g standout ''
            set -g black ''
            set -g red ''
            set -g green ''
            set -g yellow ''
            set -g blue ''
            set -g magenta ''
            set -g cyan ''
            set -g white ''
            set -g titlestart ''
            set -g titlefinish ''
            source $_config
            # Ensure stubs survive config.fish's interactive setup.
            set -g color false
            set -g normal ''
            set -g bold ''
            set -g underline ''
            set -g standout ''
            set -g black ''
            set -g red ''
            set -g green ''
            set -g yellow ''
            set -g blue ''
            set -g magenta ''
            set -g cyan ''
            set -g white ''
            set -g titlestart ''
            set -g titlefinish ''
            function bell; end
            function flash_terminal; end
            function jobs; end
            function is_ssh_valid; return 0; end
            function on_production_host; return 1; end
            function on_my_workstation; return 0; end
            function on_my_laptop; return 1; end
            function inside_tmux; return 1; end
            function have_command
                switch \$argv[1]
                    case vcs; return 0
                    case '*'; command -v \$argv[1] >/dev/null 2>&1
                end
            end
            function vcs; return 1; end
            function projectroot; return 1; end
            function projectname; return 1; end
            function log_history; end
            $_snippet
        "
}

###############
# TEST: maybe_space

result="$(_fish_run 'maybe_space hello')"
assert_equal "fish maybe_space with content" " hello" "$result"

result="$(_fish_run 'maybe_space ""')"
assert_equal "fish maybe_space with empty" "" "$result"

result="$(_fish_run 'maybe_space')"
assert_equal "fish maybe_space with no args" "" "$result"

###############
# TEST: bar

result="$(_fish_run 'bar 5')"
assert_equal "fish bar prints N separator characters" "―――――" "$result"

###############
# TEST: ps1_character

result="$(_fish_run 'ps1_character')"
assert_equal "fish ps1_character prints >" ">" "$result"

###############
# TEST: in_shpool

result="$(_fish_run 'if in_shpool; echo yes; else; echo no; end')"
assert_equal "fish in_shpool false when unset" "no" "$result"

result="$(_fish_run 'set -g SHPOOL_SESSION_NAME main; if in_shpool; echo yes; else; echo no; end')"
assert_equal "fish in_shpool true when SHPOOL_SESSION_NAME set" "yes" "$result"

###############
# TEST: session_name

result="$(_fish_run 'session_name')"
assert_equal "fish session_name empty when not in pool" "" "$result"

result="$(_fish_run 'set -g SHPOOL_SESSION_NAME edge1; session_name')"
assert_equal "fish session_name returns shpool session" "edge1 " "$result"

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
# TEST: prompt_line delegates to `vcs prompt-line` when binary available

result="$(_fish_run '
    set -g HOSTNAME mikel-laptop
    set -g USERNAME mikel
    function on_production_host; return 1; end
    function vcs
        switch $argv[1]
            case prompt-line
                echo "called-with: $argv[2..]"
            case "*"; return 1
        end
    end
    prompt_line
')"
assert_contains "fish prompt_line delegates to vcs prompt-line" "called-with:" "$result"
assert_contains "fish prompt_line passes --hostname=<short_hostname>" "--hostname=laptop" "$result"
assert_contains "fish prompt_line passes --color=never when color disabled" "--color=never" "$result"
assert_not_contains "fish prompt_line omits --production off production" "--production" "$result"

###############
# TEST: prompt_line passes --production on production hosts

result="$(_fish_run '
    set -g HOSTNAME prodhost
    set -g USERNAME mikel
    function on_production_host; return 0; end
    function vcs
        switch $argv[1]
            case prompt-line
                echo "called-with: $argv[2..]"
            case "*"; return 1
        end
    end
    prompt_line
')"
assert_contains "fish prompt_line passes --production on production host" "--production" "$result"

###############
# WHOLE PROMPT: laptop, home directory, need to auth

result="$(_fish_run '
    set -g HOSTNAME mikel-laptop
    set -g USERNAME mikel
    set -g COLUMNS 80
    mkdir -p $HOME
    cd $HOME
    function is_ssh_valid; return 1; end
    function vcs
        switch $argv[1]
            case prompt-line; echo "laptop shpool ~ SSH"
            case "*"; return 1
        end
    end
    fish_prompt
')"
result="$(_resolve_cr "$result")"
expected="
laptop shpool ~ SSH ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
$_ps1char "
assert_equal "fish whole prompt: laptop, home, need auth" "$expected" "$result"

###############
# WHOLE PROMPT: workstation, project dir with vcs info

result="$(_fish_run '
    set -g HOSTNAME mikel-workstation
    set -g USERNAME mikel
    set -g COLUMNS 80
    function vcs
        switch $argv[1]
            case prompt-line; echo "workstation shpool conf main"
            case "*"; return 1
        end
    end
    fish_prompt
')"
result="$(_resolve_cr "$result")"
expected="
workstation shpool conf main ―――――――――――――――――――――――――――――――――――――――――――――――――――
$_ps1char "
assert_equal "fish whole prompt: workstation, project root, shpool" "$expected" "$result"

###############
# WHOLE PROMPT: inside shpool session, subdir, dirty, stale fetch

result="$(_fish_run '
    set -g HOSTNAME mikel-workstation
    set -g USERNAME mikel
    set -g COLUMNS 80
    set -g SHPOOL_SESSION_NAME edge1
    function vcs
        switch $argv[1]
            case prompt-line; echo "workstation [edge1] edge1 ui somebranch * fetch"
            case "*"; return 1
        end
    end
    fish_prompt
')"
result="$(_resolve_cr "$result")"
expected="
workstation [edge1] edge1 ui somebranch * fetch ――――――――――――――――――――――――――――――――
$_ps1char "
assert_equal "fish whole prompt: workstation, shpool, subdir, dirty, fetch" "$expected" "$result"

###############
# TEST: fish_mode_prompt displays the current vi-style bind mode

result="$(_fish_run 'set -g fish_bind_mode insert; fish_mode_prompt')"
assert_equal "fish_mode_prompt insert mode" "INSERT " "$result"

result="$(_fish_run 'set -g fish_bind_mode default; fish_mode_prompt')"
assert_equal "fish_mode_prompt default (normal) mode" "NORMAL " "$result"

result="$(_fish_run 'set -g fish_bind_mode visual; fish_mode_prompt')"
assert_equal "fish_mode_prompt visual mode" "VISUAL " "$result"

result="$(_fish_run 'set -g fish_bind_mode replace; fish_mode_prompt')"
assert_equal "fish_mode_prompt replace mode" "REPLACE " "$result"

result="$(_fish_run 'set -g fish_bind_mode replace_one; fish_mode_prompt')"
assert_equal "fish_mode_prompt replace_one mode" "REPLACE " "$result"

result="$(_fish_run 'set -e fish_bind_mode; fish_mode_prompt')"
assert_equal "fish_mode_prompt empty when fish_bind_mode unset" "" "$result"

result="$(_fish_run 'set -g fish_bind_mode mystery; fish_mode_prompt')"
assert_equal "fish_mode_prompt falls back to raw mode name" "mystery " "$result"

###############
# TEST: my_vi_key_bindings is selected as the key binding function

result="$(_fish_run 'echo $fish_key_bindings')"
assert_equal "fish sets fish_key_bindings to my_vi_key_bindings" "my_vi_key_bindings" "$result"

###############
# PERFORMANCE
# prompt_line runs on every prompt, so its cost matters. Time 50 calls
# inside a single fish process so we're measuring wrapper overhead, not
# fish startup.
_fish_run '
    set -g HOSTNAME mikel-workstation
    set -g USERNAME mikel
    function vcs
        switch $argv[1]
            case prompt-line; echo "testhost shpool ~"
            case "*"; return 1
        end
    end
    set _start (date +%s%N)
    for i in (seq 1 50)
        prompt_line >/dev/null 2>&1
    end
    set _end (date +%s%N)
    set _elapsed_ms (math "($_end - $_start) / 1000000")
    echo "  50 x fish prompt_line (binary stub): $_elapsed_ms""ms"
'

test_summary "fish shrc_fish_prompt_test"
