#!/bin/bash
#
# Tests for config/nushell/config.nu.
# Mirrors shrc_fish_prompt_test.sh: a bash harness that runs short Nushell
# snippets via `nu --no-config-file -c`, sourcing the real config.nu and
# stubbing out side effects (tty, colors, vcs binary).
# Skips gracefully when Nushell is not installed.
#

. "$(dirname "$0")/shrc_test_lib.sh"

if ! command -v nu >/dev/null 2>&1; then
    echo "nushell not installed, skipping nushell tests"
    test_summary "nushell shrc_nushell_test"
    exit 0
fi

_srcdir="$(cd "$(dirname "$0")" && pwd)"
_config="$_srcdir/config/nushell/config.nu"

# Run a Nushell snippet with the real config.nu pre-loaded. A fake HOME
# keeps config.nu from touching ~/.config/nushell/local.nu, NO_COLOR
# disables ANSI escapes so assertions are simple, and TERM=dumb avoids any
# terminal queries.
_nu_run() {
    local _snippet="$1"
    local _fakehome="$_testdir/nufakehome"
    mkdir -p "$_fakehome"
    HOME="$_fakehome" \
        NO_COLOR=1 \
        TERM=dumb \
        SHPOOL_SESSION_NAME= \
        TMUX= \
        SSH_CONNECTION= \
        DISPLAY= \
        nu --no-config-file -c "
            source $_config
            $_snippet
        "
}

###############
# TEST: bar prints N separator characters
result="$(_nu_run 'print -n (bar 5)')"
assert_equal "nu bar prints N separators" "―――――" "$result"

result="$(_nu_run 'print -n (bar 0)')"
assert_equal "nu bar 0 prints empty" "" "$result"

###############
# TEST: maybe_space
result="$(_nu_run 'print -n (maybe_space "hello")')"
assert_equal "nu maybe_space with content" " hello" "$result"

result="$(_nu_run 'print -n (maybe_space "")')"
assert_equal "nu maybe_space with empty" "" "$result"

result="$(_nu_run 'print -n (maybe_space)')"
assert_equal "nu maybe_space with no args" "" "$result"

###############
# TEST: format_duration
result="$(_nu_run 'print -n (format_duration 0sec)')"
assert_equal "nu format_duration 0s is empty" "" "$result"

result="$(_nu_run 'print -n (format_duration 1sec)')"
assert_equal "nu format_duration 1s is empty (shrc rounds down)" "" "$result"

result="$(_nu_run 'print -n (format_duration 5sec)')"
assert_equal "nu format_duration 5s" "5 seconds" "$result"

result="$(_nu_run 'print -n (format_duration 125sec)')"
assert_equal "nu format_duration 2m5s" "2 minutes 5 seconds" "$result"

result="$(_nu_run 'print -n (format_duration 3723sec)')"
assert_equal "nu format_duration 1h2m3s" "1 hours 2 minutes 3 seconds" "$result"

###############
# TEST: ps1_character
# When not root, shows '$'. When root (UID=0), shows '#'.
result="$(_nu_run '$env.UID = 1000; print -n (ps1_character)')"
assert_equal "nu ps1_character non-root" "\$" "$result"

result="$(_nu_run '$env.UID = 0; print -n (ps1_character)')"
assert_equal "nu ps1_character root" "#" "$result"

###############
# TEST: have_command / is_runnable
result="$(_nu_run 'if (have_command "sh") { print -n yes } else { print -n no }')"
assert_equal "nu have_command sh is true" "yes" "$result"

result="$(_nu_run 'if (have_command "zzzzznotacommand") { print -n yes } else { print -n no }')"
assert_equal "nu have_command bogus is false" "no" "$result"

result="$(_nu_run 'if (is_runnable "bar") { print -n yes } else { print -n no }')"
assert_equal "nu is_runnable custom command" "yes" "$result"

###############
# TEST: inpath
result="$(_nu_run '
$env.PATH = ["/usr/bin" "/bin"]
if (inpath "/usr/bin") { print -n yes } else { print -n no }')"
assert_equal "nu inpath true when in PATH" "yes" "$result"

result="$(_nu_run '
$env.PATH = ["/usr/bin" "/bin"]
if (inpath "/tmp") { print -n yes } else { print -n no }')"
assert_equal "nu inpath false when not in PATH" "no" "$result"

###############
# TEST: prepend_path / append_path / delete_path / add_path
# Use /tmp and /var as existing directories.
result="$(_nu_run '
$env.PATH = ["/usr/bin"]
prepend_path "/tmp"
print -n ($env.PATH | str join ":")')"
assert_equal "nu prepend_path existing dir" "/tmp:/usr/bin" "$result"

result="$(_nu_run '
$env.PATH = ["/usr/bin"]
prepend_path "/definitely/not/a/real/dir"
print -n ($env.PATH | str join ":")')"
assert_equal "nu prepend_path ignores missing" "/usr/bin" "$result"

result="$(_nu_run '
$env.PATH = ["/usr/bin"]
append_path "/tmp"
print -n ($env.PATH | str join ":")')"
assert_equal "nu append_path existing dir" "/usr/bin:/tmp" "$result"

result="$(_nu_run '
$env.PATH = ["/usr/bin" "/tmp" "/bin"]
delete_path "/tmp"
print -n ($env.PATH | str join ":")')"
assert_equal "nu delete_path removes entry" "/usr/bin:/bin" "$result"

result="$(_nu_run '
$env.PATH = ["/usr/bin" "/tmp"]
add_path "/tmp" "start"
print -n ($env.PATH | str join ":")')"
assert_equal "nu add_path moves existing to start" "/tmp:/usr/bin" "$result"

result="$(_nu_run '
$env.PATH = ["/tmp" "/usr/bin"]
add_path "/tmp" "end"
print -n ($env.PATH | str join ":")')"
assert_equal "nu add_path moves existing to end" "/usr/bin:/tmp" "$result"

result="$(_nu_run '
$env.PATH = ["/usr/bin"]
add_path "/var"
print -n ($env.PATH | str join ":")')"
assert_equal "nu add_path default appends if missing" "/usr/bin:/var" "$result"

result="$(_nu_run '
$env.PATH = ["/var" "/usr/bin"]
add_path "/var"
print -n ($env.PATH | str join ":")')"
assert_equal "nu add_path default no-op when present" "/var:/usr/bin" "$result"

###############
# TEST: short_hostname
result="$(_nu_run '
$env.HOSTNAME = "mikel-workstation.example.com"
$env.USERNAME = "mikel"
print -n (short_hostname)')"
assert_equal "nu short_hostname strips user prefix and domain" "workstation" "$result"

result="$(_nu_run '
$env.HOSTNAME = "edgehost.example.com"
$env.USERNAME = "mikel"
print -n (short_hostname)')"
assert_equal "nu short_hostname without user prefix" "edgehost" "$result"

###############
# TEST: in_shpool
result="$(_nu_run '
hide-env --ignore-errors SHPOOL_SESSION_NAME
if (in_shpool) { print -n yes } else { print -n no }')"
assert_equal "nu in_shpool false when unset" "no" "$result"

result="$(_nu_run '
$env.SHPOOL_SESSION_NAME = "main"
if (in_shpool) { print -n yes } else { print -n no }')"
assert_equal "nu in_shpool true when SHPOOL_SESSION_NAME set" "yes" "$result"

###############
# TEST: session_name
result="$(_nu_run '
hide-env --ignore-errors SHPOOL_SESSION_NAME
hide-env --ignore-errors TMUX
print -n (session_name)')"
assert_equal "nu session_name empty when no pool/tmux" "" "$result"

result="$(_nu_run '
$env.SHPOOL_SESSION_NAME = "edge1"
print -n (session_name)')"
assert_equal "nu session_name returns shpool session" "edge1 " "$result"

###############
# TEST: on_my_workstation / on_my_laptop / on_production_host
result="$(_nu_run '
$env.HOSTNAME = "mikel-workstation"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
if (on_my_workstation) { print -n yes } else { print -n no }')"
assert_equal "nu on_my_workstation user-prefixed host" "yes" "$result"

result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
if (on_my_workstation) { print -n yes } else { print -n no }')"
assert_equal "nu on_my_workstation laptop is false" "no" "$result"

result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
if (on_my_laptop) { print -n yes } else { print -n no }')"
assert_equal "nu on_my_laptop laptop hostname" "yes" "$result"

result="$(_nu_run '
$env.HOSTNAME = "prodhost"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
if (on_production_host) { print -n yes } else { print -n no }')"
assert_equal "nu on_production_host true for unknown host" "yes" "$result"

result="$(_nu_run '
$env.HOSTNAME = "mikel-workstation"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
if (on_production_host) { print -n yes } else { print -n no }')"
assert_equal "nu on_production_host false on my workstation" "no" "$result"

###############
# TEST: title respects inside_tmux
# Outside tmux/shpool, show "<host> <pwd_basename>".
result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
mkdir ([$env.HOME "titletest"] | path join)
cd ([$env.HOME "titletest"] | path join)
print -n (title)')"
assert_equal "nu title shows hostname outside tmux" "laptop titletest" "$result"

result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
$env.TMUX = "/fake/tmux/socket"
$env.SHPOOL_SESSION_NAME = "main"
mkdir ([$env.HOME "titletest"] | path join)
cd ([$env.HOME "titletest"] | path join)
print -n (title)')"
assert_contains "nu title hides hostname in tmux" "main" "$result"
assert_not_contains "nu title hides hostname in tmux - no host" "laptop " "$result"

###############
# TEST: prompt_line fallback when vcs is missing
# With no `vcs` command, prompt_line should fall back to a simple
# "hostname [session ]pwd" string.
result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
$env.PATH = []
cd $env.HOME
print -n (prompt_line)')"
# PATH is empty so have_command "vcs" is false; the fallback is used.
assert_contains "nu prompt_line fallback has hostname" "laptop" "$result"

###############
# TEST: render_prompt structure matches shrc preprompt
# A leading newline, a separator bar, a CR, the prompt line, newline, and
# the prompt character followed by a space. Drive it with empty PATH so
# prompt_line uses its fallback (no `vcs` binary on PATH).
result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
$env.UID = 1000
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
$env.PATH = []
cd $env.HOME
print -n (render_prompt)')"
assert_contains "nu render_prompt contains separator" "―" "$result"
assert_contains "nu render_prompt contains hostname in prompt line" "laptop" "$result"
assert_contains "nu render_prompt ends with \$ prompt" "$ " "$result"

# And with UID=0, the prompt character should be #.
result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
$env.UID = 0
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
$env.PATH = []
cd $env.HOME
print -n (render_prompt)')"
assert_contains "nu render_prompt as root ends with # prompt" "# " "$result"

###############
# TEST: find_up climbs the tree
result="$(_nu_run '
let base = ($env.HOME | path expand)
mkdir ([$base "a" "b" "c"] | path join)
"marker" | save --force ([$base "a" "marker"] | path join)
cd ([$base "a" "b" "c"] | path join)
print -n (find_up "marker")')"
assert_contains "nu find_up finds ancestor file" "marker" "$result"

###############
# TEST: mcd creates and enters a directory
result="$(_nu_run '
let base = ($env.HOME | path expand)
cd $base
mcd newdir
print -n $env.PWD')"
assert_contains "nu mcd enters the new directory" "newdir" "$result"

test_summary "nushell shrc_nushell_test"
