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
    local _stdin="${2:-}"
    local _fakehome="$_testdir/nufakehome"
    mkdir -p "$_fakehome"
    printf '%s' "$_stdin" | HOME="$_fakehome" \
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
# TEST: maybe-space
result="$(_nu_run 'print -n (maybe-space "hello")')"
assert_equal "nu maybe-space with content" " hello" "$result"

result="$(_nu_run 'print -n (maybe-space "")')"
assert_equal "nu maybe-space with empty" "" "$result"

result="$(_nu_run 'print -n (maybe-space)')"
assert_equal "nu maybe-space with no args" "" "$result"

###############
# TEST: format-duration
result="$(_nu_run 'print -n (format-duration 0sec)')"
assert_equal "nu format-duration 0s is empty" "" "$result"

result="$(_nu_run 'print -n (format-duration 1sec)')"
assert_equal "nu format-duration 1s is empty (shrc rounds down)" "" "$result"

result="$(_nu_run 'print -n (format-duration 5sec)')"
assert_equal "nu format-duration 5s" "5 seconds" "$result"

result="$(_nu_run 'print -n (format-duration 125sec)')"
assert_equal "nu format-duration 2m5s" "2 minutes 5 seconds" "$result"

result="$(_nu_run 'print -n (format-duration 3723sec)')"
assert_equal "nu format-duration 1h2m3s" "1 hours 2 minutes 3 seconds" "$result"

###############
# TEST: ps1-character
# When not root, shows '〉'. When root (UID=0), shows '#'.
result="$(_nu_run '$env.UID = 1000; print -n (ps1-character)')"
assert_equal "nu ps1-character non-root" "〉" "$result"

result="$(_nu_run '$env.UID = 0; print -n (ps1-character)')"
assert_equal "nu ps1-character root" "#" "$result"

###############
# TEST: have-command / is-runnable
result="$(_nu_run 'if (have-command "sh") { print -n yes } else { print -n no }')"
assert_equal "nu have-command sh is true" "yes" "$result"

result="$(_nu_run 'if (have-command "zzzzznotacommand") { print -n yes } else { print -n no }')"
assert_equal "nu have-command bogus is false" "no" "$result"

result="$(_nu_run 'if (is-runnable "bar") { print -n yes } else { print -n no }')"
assert_equal "nu is-runnable custom command" "yes" "$result"

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
# TEST: prepend-path / append-path / delete-path / add-path
# Use /tmp and /var as existing directories.
result="$(_nu_run '
$env.PATH = ["/usr/bin"]
prepend-path "/tmp"
print -n ($env.PATH | str join ":")')"
assert_equal "nu prepend-path existing dir" "/tmp:/usr/bin" "$result"

result="$(_nu_run '
$env.PATH = ["/usr/bin"]
prepend-path "/definitely/not/a/real/dir"
print -n ($env.PATH | str join ":")')"
assert_equal "nu prepend-path ignores missing" "/usr/bin" "$result"

result="$(_nu_run '
$env.PATH = ["/usr/bin"]
append-path "/tmp"
print -n ($env.PATH | str join ":")')"
assert_equal "nu append-path existing dir" "/usr/bin:/tmp" "$result"

result="$(_nu_run '
$env.PATH = ["/usr/bin" "/tmp" "/bin"]
delete-path "/tmp"
print -n ($env.PATH | str join ":")')"
assert_equal "nu delete-path removes entry" "/usr/bin:/bin" "$result"

result="$(_nu_run '
$env.PATH = ["/usr/bin" "/tmp"]
add-path "/tmp" "start"
print -n ($env.PATH | str join ":")')"
assert_equal "nu add-path moves existing to start" "/tmp:/usr/bin" "$result"

result="$(_nu_run '
$env.PATH = ["/tmp" "/usr/bin"]
add-path "/tmp" "end"
print -n ($env.PATH | str join ":")')"
assert_equal "nu add-path moves existing to end" "/usr/bin:/tmp" "$result"

result="$(_nu_run '
$env.PATH = ["/usr/bin"]
add-path "/var"
print -n ($env.PATH | str join ":")')"
assert_equal "nu add-path default appends if missing" "/usr/bin:/var" "$result"

result="$(_nu_run '
$env.PATH = ["/var" "/usr/bin"]
add-path "/var"
print -n ($env.PATH | str join ":")')"
assert_equal "nu add-path default no-op when present" "/var:/usr/bin" "$result"

###############
# TEST: short-hostname
result="$(_nu_run '
$env.HOSTNAME = "mikel-workstation.example.com"
$env.USERNAME = "mikel"
print -n (short-hostname)')"
assert_equal "nu short-hostname strips user prefix and domain" "workstation" "$result"

result="$(_nu_run '
$env.HOSTNAME = "edgehost.example.com"
$env.USERNAME = "mikel"
print -n (short-hostname)')"
assert_equal "nu short-hostname without user prefix" "edgehost" "$result"

###############
# TEST: is-env-set
result="$(_nu_run '
hide-env --ignore-errors NU_TEST_VAR
if (is-env-set "NU_TEST_VAR") { print -n yes } else { print -n no }')"
assert_equal "nu is-env-set false when unset" "no" "$result"

result="$(_nu_run '
$env.NU_TEST_VAR = ""
if (is-env-set "NU_TEST_VAR") { print -n yes } else { print -n no }')"
assert_equal "nu is-env-set false when empty string" "no" "$result"

result="$(_nu_run '
$env.NU_TEST_VAR = "value"
if (is-env-set "NU_TEST_VAR") { print -n yes } else { print -n no }')"
assert_equal "nu is-env-set true when set to non-empty" "yes" "$result"

###############
# TEST: in-shpool
result="$(_nu_run '
hide-env --ignore-errors SHPOOL_SESSION_NAME
if (in-shpool) { print -n yes } else { print -n no }')"
assert_equal "nu in-shpool false when unset" "no" "$result"

result="$(_nu_run '
$env.SHPOOL_SESSION_NAME = "main"
if (in-shpool) { print -n yes } else { print -n no }')"
assert_equal "nu in-shpool true when SHPOOL_SESSION_NAME set" "yes" "$result"

###############
# TEST: session-name
result="$(_nu_run '
hide-env --ignore-errors SHPOOL_SESSION_NAME
hide-env --ignore-errors TMUX
print -n (session-name)')"
assert_equal "nu session-name empty when no pool/tmux" "" "$result"

result="$(_nu_run '
$env.SHPOOL_SESSION_NAME = "edge1"
print -n (session-name)')"
assert_equal "nu session-name returns shpool session" "edge1 " "$result"

###############
# TEST: on-my-workstation / on-my-laptop / on-production-host
result="$(_nu_run '
$env.HOSTNAME = "mikel-workstation"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
if (on-my-workstation) { print -n yes } else { print -n no }')"
assert_equal "nu on-my-workstation user-prefixed host" "yes" "$result"

result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
if (on-my-workstation) { print -n yes } else { print -n no }')"
assert_equal "nu on-my-workstation laptop is false" "no" "$result"

result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
if (on-my-laptop) { print -n yes } else { print -n no }')"
assert_equal "nu on-my-laptop laptop hostname" "yes" "$result"

result="$(_nu_run '
$env.HOSTNAME = "prodhost"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
if (on-production-host) { print -n yes } else { print -n no }')"
assert_equal "nu on-production-host true for unknown host" "yes" "$result"

result="$(_nu_run '
$env.HOSTNAME = "mikel-workstation"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
if (on-production-host) { print -n yes } else { print -n no }')"
assert_equal "nu on-production-host false on my workstation" "no" "$result"

###############
# TEST: title respects inside-tmux
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
# TEST: prompt-line fallback when vcs is missing
# With no `vcs` command, prompt-line should fall back to a simple
# "hostname [session ]pwd" string.
result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
$env.PATH = []
cd $env.HOME
print -n (prompt-line)')"
# PATH is empty so have-command "vcs" is false; the fallback is used.
assert_contains "nu prompt-line fallback has hostname" "laptop" "$result"

###############
# TEST: render-prompt structure matches shrc preprompt
# A leading newline, a separator bar, a CR, the prompt line, newline, and
# the prompt character followed by a space. Drive it with empty PATH so
# prompt-line uses its fallback (no `vcs` binary on PATH).
result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
$env.UID = 1000
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
$env.PATH = []
cd $env.HOME
print -n (render-prompt)')"
assert_contains "nu render-prompt contains separator" "―" "$result"
assert_contains "nu render-prompt contains hostname in prompt line" "laptop" "$result"
assert_contains "nu render-prompt ends with 〉 prompt" "〉 " "$result"

# And with UID=0, the prompt character should be #.
result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
$env.UID = 0
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
$env.PATH = []
cd $env.HOME
print -n (render-prompt)')"
assert_contains "nu render-prompt as root ends with # prompt" "# " "$result"

###############
# TEST: find-up climbs the tree
result="$(_nu_run '
let base = ($env.HOME | path expand)
mkdir ([$base "a" "b" "c"] | path join)
"marker" | save --force ([$base "a" "marker"] | path join)
cd ([$base "a" "b" "c"] | path join)
print -n (find-up "marker")')"
assert_contains "nu find-up finds ancestor file" "marker" "$result"

###############
# TEST: mcd creates and enters a directory
result="$(_nu_run '
let base = ($env.HOME | path expand)
cd $base
mcd newdir
print -n $env.PWD')"
assert_contains "nu mcd enters the new directory" "newdir" "$result"

###############
# TEST: clone dispatch
# Stub jj/git/hg as scripts on PATH so we can verify which one was invoked.
_stubdir="$_testdir/clone_stubs"
_stubdir_nojj="$_testdir/clone_stubs_nojj"
mkdir -p "$_stubdir" "$_stubdir_nojj"
for _cmd in jj git hg; do
    cat > "$_stubdir/$_cmd" <<EOF
#!/bin/sh
echo "$_cmd \$*"
EOF
    chmod +x "$_stubdir/$_cmd"
done
# nojj variant: same scripts, but no jj
cp "$_stubdir/git" "$_stubdir/hg" "$_stubdir_nojj/"

result="$(_nu_run "
\$env.PATH = ['$_stubdir' '/usr/bin' '/bin']
clone 'https://github.com/foo/bar.git'
" | tr -d '\n')"
assert_equal "nu clone .git uses jj git clone when jj available" "jj git clone https://github.com/foo/bar.git" "$result"

result="$(_nu_run "
\$env.PATH = ['$_stubdir' '/usr/bin' '/bin']
clone 'https://hg.example.com/hg/repo'
" | tr -d '\n')"
assert_equal "nu clone /hg/ uses hg clone" "hg clone https://hg.example.com/hg/repo" "$result"

# When jj isn't on PATH, clone should prompt and fall back to git on yes.
result="$(_nu_run "
\$env.PATH = ['$_stubdir_nojj' '/usr/bin' '/bin']
clone 'https://github.com/foo/bar.git'
" 'y' | tr -d '\n')"
assert_contains "nu clone falls back to git when jj missing and user says yes" "git clone https://github.com/foo/bar.git" "$result"

# When the user declines the fallback, no clone command runs.
result="$(_nu_run "
\$env.PATH = ['$_stubdir_nojj' '/usr/bin' '/bin']
clone 'https://github.com/foo/bar.git'
" 'n' | tr -d '\n')"
assert_not_contains "nu clone aborts when user declines git fallback" "git clone" "$result"

test_summary "nushell shrc_nushell_test"
