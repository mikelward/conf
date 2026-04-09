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
assert_equal "nu ps1-character non-root" ">" "$result"

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
assert_contains "nu render-prompt ends with > prompt" "> " "$result"

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

# And if the target already exists, mcd prints a message and does not crash.
result="$(_nu_run '
let base = ($env.HOME | path expand)
cd $base
mkdir existing-dir
mcd existing-dir')"
assert_contains "nu mcd reports when target already exists" "already exists" "$result"

###############
# TEST: mtd creates a fresh temp dir and cds into it
result="$(_nu_run '
let start = $env.PWD
mtd
print -n $env.PWD
print -n "|"
print -n $start')"
# The new PWD should be different from the starting PWD and live under /tmp
case "$result" in
    /tmp/*\|*) assert_true "nu mtd cds into a /tmp subdirectory" "true" ;;
    *)         assert_true "nu mtd cds into a /tmp subdirectory (got: $result)" "false" ;;
esac

###############
# TEST: cdfile / realdir resolve symlinks to the real containing directory
result="$(_nu_run '
let base = ($env.HOME | path expand)
mkdir ([$base "target"] | path join)
"hello" | save --force ([$base "target" "file.txt"] | path join)
^ln -s ([$base "target"] | path join) ([$base "link"] | path join)
# realdir on a file inside the symlink should resolve to the real target dir.
print -n (realdir ([$base "link" "file.txt"] | path join))')"
assert_contains "nu realdir resolves symlink to real dir" "/target" "$result"

result="$(_nu_run '
let base = ($env.HOME | path expand)
mkdir ([$base "cdfile-target"] | path join)
"x" | save --force ([$base "cdfile-target" "file.txt"] | path join)
cdfile ([$base "cdfile-target" "file.txt"] | path join)
print -n $env.PWD')"
assert_contains "nu cdfile cds to the file's real directory" "cdfile-target" "$result"

###############
# TEST: gh-search greps $HOME/.history
result="$(_nu_run '
"one two three
alpha beta gamma
one four five" | save --force ([$env.HOME ".history"] | path join)
gh-search "alpha"')"
assert_contains "nu gh-search finds a matching line" "alpha beta gamma" "$result"

# rh (gh-search | last 20) should return at most the last 20 matches.
result="$(_nu_run '
let lines = (1..25 | each {|i| $"match line ($i)" } | str join (char newline))
$lines | save --force ([$env.HOME ".history"] | path join)
rh "match" | length')"
assert_equal "nu rh limits gh-search output to 20 lines" "20" "$result"

###############
# TEST: confirm reads a yes/no answer from stdin.
# The prompt goes to stdout, and `^head -n 1` reads one line of stdin, so
# assert_contains on the combined output catches both the prompt and the
# boolean result. An empty reply (just a newline) should default to yes.
result="$(_nu_run 'let r = (confirm "go"); print -n $" <($r)>"' 'y
')"
assert_contains "nu confirm yes on y" "<true>" "$result"

result="$(_nu_run 'let r = (confirm "go"); print -n $" <($r)>"' 'Y
')"
assert_contains "nu confirm yes on Y (uppercase)" "<true>" "$result"

result="$(_nu_run 'let r = (confirm "go"); print -n $" <($r)>"' 'yes
')"
assert_contains "nu confirm yes on yes" "<true>" "$result"

result="$(_nu_run 'let r = (confirm "go"); print -n $" <($r)>"' 'n
')"
assert_contains "nu confirm no on n" "<false>" "$result"

result="$(_nu_run 'let r = (confirm "go"); print -n $" <($r)>"' 'no
')"
assert_contains "nu confirm no on no" "<false>" "$result"

result="$(_nu_run 'let r = (confirm "go"); print -n $" <($r)>"' '
')"
assert_contains "nu confirm defaults to yes on empty reply" "<true>" "$result"

result="$(_nu_run 'let r = (confirm "go"); print -n $" <($r)>"' 'maybe
')"
assert_contains "nu confirm treats non-y reply as no" "<false>" "$result"

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

###############
# TEST: CDPATH is set and does not include conf/ subdirectories
result="$(_nu_run 'print -n ($env.CDPATH | str join ":")')"
assert_contains "nu CDPATH contains HOME" "$_testdir/nufakehome" "$result"
assert_not_contains "nu CDPATH does not contain conf" "$_testdir/nufakehome/conf" "$result"

###############
# TEST: trailing-slash autocd is provided by nushell's native REPL path
# handling, not by any command_not_found hook of ours. We do install a
# pre_execution hook for command-duration tracking (covered separately
# below); the assertion here is just that no autocd hook is installed.
result="$(_nu_run 'print -n ($env.config.hooks.command_not_found | describe)')"
assert_equal "nu command_not_found hook is not set" "nothing" "$result"

# TEST: `cd` into a trailing-slash path works (sanity check for the
# `cd ./foo/` fallback users can type explicitly).
result="$(_nu_run '
let base = ($env.HOME | path expand)
mkdir ([$base "cdtest" "sub"] | path join)
cd ([$base "cdtest"] | path join)
cd ./sub/
print -n $env.PWD')"
assert_contains "nu cd with trailing slash enters directory" "cdtest/sub" "$result"

###############
# TEST: last-job-info shows nothing when no command has run
result="$(_nu_run '
hide-env --ignore-errors CMD_DURATION
print -n (last-job-info)')"
assert_equal "nu last-job-info empty when CMD_DURATION unset" "" "$result"

# And nothing when the duration is below the display threshold.
result="$(_nu_run '
$env.CMD_DURATION = 0sec
print -n (last-job-info)')"
assert_equal "nu last-job-info empty for 0sec" "" "$result"

result="$(_nu_run '
$env.CMD_DURATION = 1sec
print -n (last-job-info)')"
assert_equal "nu last-job-info empty for 1sec (rounds down)" "" "$result"

# With a meaningful duration it should contain the formatted text.
result="$(_nu_run '
$env.CMD_DURATION = 5sec
print -n (last-job-info)')"
assert_contains "nu last-job-info shows took for 5sec" "took 5 seconds" "$result"

result="$(_nu_run '
$env.CMD_DURATION = 1hr
print -n (last-job-info)')"
assert_contains "nu last-job-info shows hours for 1hr" "1 hours" "$result"

###############
# TEST: title-escape wraps the title in an OSC 0 sequence for xterm,
# and returns empty for non-xterm-family terminals.
result="$(_nu_run '
$env.TERM = "xterm-256color"
print -n (title-escape "my title")')"
assert_contains "nu title-escape includes OSC 0 on xterm" "]0;my title" "$result"

result="$(_nu_run '
$env.TERM = "dumb"
print -n (title-escape "my title")')"
assert_equal "nu title-escape empty on dumb terminal" "" "$result"

result="$(_nu_run '
$env.TERM = "rxvt-unicode"
print -n (title-escape "hi")')"
assert_contains "nu title-escape supports rxvt" "]0;hi" "$result"

###############
# TEST: flash-terminal returns the BEL char on xterm, empty elsewhere.
result="$(_nu_run '
$env.TERM = "xterm-256color"
print -n (flash-terminal)
print -n "END"')"
# BEL is char 07 -- assert it appears before the END marker.
case "$result" in
    *$'\a'END) assert_true "nu flash-terminal rings bell on xterm" "true";;
    *)         assert_true "nu flash-terminal rings bell on xterm" "false";;
esac

result="$(_nu_run '
$env.TERM = "dumb"
print -n (flash-terminal)')"
assert_equal "nu flash-terminal empty on dumb terminal" "" "$result"

###############
# TEST: render-prompt includes the title escape and bell when TERM=xterm.
result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
$env.UID = 1000
$env.TERM = "xterm-256color"
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
$env.PATH = []
cd $env.HOME
print -n (render-prompt)')"
assert_contains "nu render-prompt sets xterm title" "]0;" "$result"

# And the duration line when CMD_DURATION is populated.
result="$(_nu_run '
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
$env.UID = 1000
$env.TERM = "dumb"
$env.CMD_DURATION = 5sec
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
$env.PATH = []
cd $env.HOME
print -n (render-prompt)')"
assert_contains "nu render-prompt includes duration line" "took 5 seconds" "$result"

###############
# TEST: pre_execution / pre_prompt hooks are installed and track timing.
result="$(_nu_run 'print -n ($env.config.hooks.pre_execution | length)')"
assert_equal "nu pre_execution hook list has one entry" "1" "$result"

result="$(_nu_run 'print -n ($env.config.hooks.pre_prompt | length)')"
assert_equal "nu pre_prompt hook list has one entry" "1" "$result"

# Invoke the hook closures directly and verify CMD_DURATION gets set to
# a non-zero duration when pre_execution has recorded a start time.
# do --env propagates the closure's $env mutations back to the caller,
# matching how nushell itself invokes hooks.
result="$(_nu_run '
do --env ($env.config.hooks.pre_execution | first)
sleep 2100ms
do --env ($env.config.hooks.pre_prompt | first)
print -n (format-duration $env.CMD_DURATION)')"
assert_contains "nu timing hooks populate CMD_DURATION" "seconds" "$result"

# When pre_execution did not fire, pre_prompt zeroes CMD_DURATION.
result="$(_nu_run '
hide-env --ignore-errors CMD_START_TIME
hide-env --ignore-errors CMD_DURATION
do --env ($env.config.hooks.pre_prompt | first)
print -n ($env.CMD_DURATION | into int)')"
assert_equal "nu pre_prompt clears stale CMD_DURATION" "0" "$result"

###############
# TEST: auth helpers respond to ssh-add's exit status.
_authstub_ok="$_testdir/auth_stub_ok"
_authstub_fail="$_testdir/auth_stub_fail"
mkdir -p "$_authstub_ok" "$_authstub_fail"
cat > "$_authstub_ok/ssh-add" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$_authstub_fail/ssh-add" <<'EOF'
#!/bin/sh
echo "no agent" >&2
exit 2
EOF
chmod +x "$_authstub_ok/ssh-add" "$_authstub_fail/ssh-add"

result="$(_nu_run "
\$env.PATH = ['$_authstub_ok' '/usr/bin' '/bin']
print -n (is-ssh-valid)")"
assert_equal "nu is-ssh-valid true when ssh-add succeeds" "true" "$result"

result="$(_nu_run "
\$env.PATH = ['$_authstub_fail' '/usr/bin' '/bin']
print -n (is-ssh-valid)")"
assert_equal "nu is-ssh-valid false when ssh-add fails" "false" "$result"

result="$(_nu_run "
\$env.PATH = ['$_authstub_ok' '/usr/bin' '/bin']
print -n (need-auth)")"
assert_equal "nu need-auth false when ssh-add succeeds" "false" "$result"

result="$(_nu_run "
\$env.PATH = ['$_authstub_fail' '/usr/bin' '/bin']
print -n (need-auth)")"
assert_equal "nu need-auth true when ssh-add fails" "true" "$result"

# auth-info should include the "SSH" token on failure (ANSI-wrapped).
result="$(_nu_run "
\$env.PATH = ['$_authstub_fail' '/usr/bin' '/bin']
print -n (auth-info)")"
assert_contains "nu auth-info reports SSH on failure" "SSH" "$result"

# And be empty on success.
result="$(_nu_run "
\$env.PATH = ['$_authstub_ok' '/usr/bin' '/bin']
print -n (auth-info)")"
assert_equal "nu auth-info empty on success" "" "$result"

###############
# TEST: overridable hook points.
# config.nu exposes four hooks as closures in $env so that autoload files
# can override them and have the change propagate through every caller
# inside config.nu (nushell resolves def-to-def calls at parse time, so a
# plain `def` redefinition in an autoload file would NOT propagate).
# Each hook is smoke-tested here: override the closure and check that a
# downstream caller sees the new value.

# $env.auth: the `auth` wrapper should dispatch through it.
result="$(_nu_run '
$env.auth = {|| "custom-auth-called" }
print -n (auth)')"
assert_equal "nu auth wrapper dispatches through \$env.auth" "custom-auth-called" "$result"

# $env.with-agent: wsh/wcp are defined in config.nu and should pick up
# the override. Their bodies are `with-agent ssh ...` / `with-agent scp ...`.
result="$(_nu_run '
$env.with-agent = {|...cmd| print -n ($cmd | str join "|") }
wsh host arg')"
assert_equal "nu wsh dispatches through \$env.with-agent" "ssh|host|arg" "$result"

result="$(_nu_run '
$env.with-agent = {|...cmd| print -n ($cmd | str join "|") }
wcp src dst')"
assert_equal "nu wcp dispatches through \$env.with-agent" "scp|src|dst" "$result"

# $env.on-production-host: overriding it must flip the result even on a
# hostname that the default logic would classify as production.
result="$(_nu_run '
$env.HOSTNAME = "prodhost"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
$env.on-production-host = {|| false }
if (on-production-host) { print -n yes } else { print -n no }')"
assert_equal "nu on-production-host override wins over default" "no" "$result"

# And the reverse: flip a workstation hostname to production via the hook.
result="$(_nu_run '
$env.HOSTNAME = "mikel-workstation"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
$env.on-production-host = {|| true }
if (on-production-host) { print -n yes } else { print -n no }')"
assert_equal "nu on-production-host override flips workstation to prod" "yes" "$result"

###############
# TEST: bak / unbak roundtrip. Clear any leftover files first since tests
# share _fakehome.
result="$(_nu_run '
cd $env.HOME
["baktest" "baktest.bak"] | each {|f| if ($f | path exists) { ^rm -f $f } } | ignore
"hello" | save --force baktest
bak "baktest"
print -n (ls baktest* | get name | path basename | str join ",")')"
assert_equal "nu bak creates .bak file" "baktest.bak" "$result"

result="$(_nu_run '
cd $env.HOME
["baktest" "baktest.bak"] | each {|f| if ($f | path exists) { ^rm -f $f } } | ignore
"hello" | save --force baktest
bak "baktest"
unbak "baktest.bak"
print -n (ls baktest* | get name | path basename | str join ",")
print -n "|"
print -n (open baktest)')"
assert_equal "nu unbak restores original" "baktest|hello" "$result"

# unbak handles short names: the old `0..(-4)` substring math was
# off-by-one and dropped only three chars. This tests a short filename
# where the old and new implementations differ.
result="$(_nu_run '
cd $env.HOME
["shortbak" "shortbak.bak"] | each {|f| if ($f | path exists) { ^rm -f $f } } | ignore
"x" | save --force shortbak
bak "shortbak"
unbak "shortbak.bak"
print -n (open shortbak)')"
assert_equal "nu unbak short filename roundtrip" "x" "$result"

###############
# TEST: log-history appends timestamped entries to HISTORY_FILE
result="$(_nu_run '
$env.HISTORY_FILE = ([$env.HOME "history.log"] | path join)
$env.TTY = "/dev/pts/42"
log-history "hello world"
open --raw $env.HISTORY_FILE | str trim')"
assert_contains "nu log-history writes argv" "hello world" "$result"
assert_contains "nu log-history writes tty" "/dev/pts/42" "$result"

# log-history no-ops when HISTORY_FILE is empty
result="$(_nu_run '
$env.HISTORY_FILE = ""
log-history "ignored"
print -n "done"')"
assert_equal "nu log-history no-op when HISTORY_FILE empty" "done" "$result"

# log-history also no-ops when HISTORY_FILE unset entirely
result="$(_nu_run '
hide-env --ignore-errors HISTORY_FILE
log-history "ignored"
print -n "done"')"
assert_equal "nu log-history no-op when HISTORY_FILE unset" "done" "$result"

###############
# TEST: inside-project / want-shpool / maybe-start-shpool-and-exit
# projectroot returns "" by default, so inside-project is false.
result="$(_nu_run '
if (inside-project) { print -n yes } else { print -n no }')"
assert_equal "nu inside-project false when projectroot is empty" "no" "$result"

# want-shpool: false when neither remote nor inside project.
result="$(_nu_run '
hide-env --ignore-errors SSH_CONNECTION
if (want-shpool) { print -n yes } else { print -n no }')"
assert_equal "nu want-shpool false when not remote and not in project" "no" "$result"

# want-shpool: true when SSH_CONNECTION is set (remote).
result="$(_nu_run '
$env.SSH_CONNECTION = "1.2.3.4 22 5.6.7.8 22"
if (want-shpool) { print -n yes } else { print -n no }')"
assert_equal "nu want-shpool true when remote" "yes" "$result"

# Overriding `$env.projectroot` propagates through the whole
# inside-project/want-shpool/projectname/buildroot chain because
# config.nu defines `projectroot` as `do $env.projectroot` (see the
# comment block at the bottom of config.nu for the full explanation).
result="$(_nu_run '
$env.projectroot = {|| "/fake/project" }
if (inside-project) { print -n yes } else { print -n no }')"
assert_equal "nu inside-project true when projectroot override returns non-empty" "yes" "$result"

result="$(_nu_run '
$env.projectroot = {|| "/fake/project" }
hide-env --ignore-errors SSH_CONNECTION
if (want-shpool) { print -n yes } else { print -n no }')"
assert_equal "nu want-shpool true when projectroot override is non-empty" "yes" "$result"

result="$(_nu_run '
$env.projectroot = {|| "/srv/code/myrepo" }
print -n (projectname)')"
assert_equal "nu projectname picks up projectroot override" "myrepo" "$result"

result="$(_nu_run '
$env.projectroot = {|| "/srv/code/myrepo" }
print -n (buildroot)')"
assert_equal "nu buildroot picks up projectroot override" "/srv/code/myrepo" "$result"

# maybe-start-shpool-and-exit is a no-op when shpool is not on PATH, even if
# the other conditions would otherwise fire. The test simply asserts that
# calling it returns normally (no exit/crash).
result="$(_nu_run '
$env.PATH = []
$env.SSH_CONNECTION = "1.2.3.4 22"
hide-env --ignore-errors SHPOOL_SESSION_NAME
maybe-start-shpool-and-exit
print -n "returned"')"
assert_equal "nu maybe-start-shpool-and-exit no-op without shpool" "returned" "$result"

###############
# TEST: shift-options rearranges leading flags to come before the target.
# Nushell's parser only lets flags flow through via spread from wrappers,
# matching how fish aliases and shrc functions actually use shift_options.
result="$(_nu_run '
def wrap [...args: string] { shift-options echo target ...$args }
wrap "-a" "-b" "rest" | str trim')"
assert_equal "nu shift-options moves options before target" "-a -b target rest" "$result"

result="$(_nu_run '
def wrap [...args: string] { shift-options echo target ...$args }
wrap "rest" | str trim')"
assert_equal "nu shift-options no options" "target rest" "$result"

result="$(_nu_run '
def wrap [...args: string] { shift-options echo target ...$args }
wrap "-x" | str trim')"
assert_equal "nu shift-options option only" "-x target" "$result"

result="$(_nu_run '
def wrap [...args: string] { shift-options echo target ...$args }
wrap "--" "-b" | str trim')"
assert_equal "nu shift-options stops at --" "target -- -b" "$result"

###############
# TEST: first-arg-last guards against short arg lists.
# Before the guard, `first-arg-last echo` errored with
# nu::shell::access_beyond_end because `$args | get 1` on a 1-element
# list is out of range. 0 args is a no-op; 1 arg runs the command as-is;
# 2+ args rearrange first-to-last.
result="$(_nu_run 'first-arg-last | default "" | str trim')"
assert_equal "nu first-arg-last no crash on 0 args" "" "$result"

result="$(_nu_run 'first-arg-last echo | str trim')"
assert_equal "nu first-arg-last 1 arg runs the command" "" "$result"

result="$(_nu_run 'first-arg-last echo only | str trim')"
assert_equal "nu first-arg-last 2 args runs command with arg" "only" "$result"

result="$(_nu_run 'first-arg-last echo history.file tail | str trim')"
assert_equal "nu first-arg-last moves first positional to end" "tail history.file" "$result"

###############
# TEST: which-path handles empty `which` results without crashing.
# Before the is-empty guard, `get 0.path?` on an empty list errored
# with nu::shell::access_beyond_end (the `?` only makes the column
# optional, not the row index).
result="$(_nu_run 'which-path sh')"
assert_contains "nu which-path prints path for a known command" "sh" "$result"

# An unknown command should not crash; it reports via the error stream.
result="$(_nu_run 'which-path zzzz-not-a-real-command-xyz' 2>&1)"
assert_contains "nu which-path reports missing command" "not found" "$result"

# And explicit regression: the command should no longer raise
# nu::shell::access_beyond_end on a missing name.
result="$(_nu_run 'which-path zzzz-not-a-real-command-xyz' 2>&1)"
assert_not_contains "nu which-path does not raise access_beyond_end" "access_beyond_end" "$result"

###############
# TEST: rerc is defined and its body exec's a new nushell.
# Can't actually call rerc in the test harness (exec would replace the
# process), so verify structurally via `view source`.
result="$(_nu_run '(which rerc | get 0.type)')"
assert_equal "nu rerc is defined as a custom command" "custom" "$result"

result="$(_nu_run 'print ((view source rerc) | str contains "exec nu")')"
assert_equal "nu rerc body exec's nu" "true" "$result"

###############
# TEST: delline removes the given line in place
result="$(_nu_run '
cd $env.HOME
"line1
line2
line3" | save --force lines.txt
delline 2 lines.txt
open lines.txt | str trim')"
assert_equal "nu delline removes line 2" "line1
line3" "$result"

###############
# TEST: body forwards the first N header lines then runs the command on the
# remaining body. Default is 1 header line.
result="$(_nu_run '
"HEAD
c
a
b" | body sort | str trim')"
assert_equal "nu body default 1-line header" "HEAD
a
b
c" "$result"

# --lines 2 keeps a two-line header.
result="$(_nu_run '
"H1
H2
y
x
z" | body --lines 2 sort | str trim')"
assert_equal "nu body --lines 2 preserves two headers" "H1
H2
x
y
z" "$result"

###############
# TEST: trydiff runs the command on the file, diffs the result, leaves the
# original untouched. Using `sort` on unsorted input guarantees a diff.
result="$(_nu_run '
cd $env.HOME
"b
a
c" | save --force t.txt
trydiff sort t.txt
print "==="
open t.txt | str trim')"
# diff output should mention the sorted rearrangement
assert_contains "nu trydiff emits a diff" "> " "$result"
# And the file should be unchanged afterwards.
assert_contains "nu trydiff leaves file untouched" "b
a
c" "$result"

###############
# TEST: VCS aliases are defined even when the vcs binary is missing.
# The stubs shouldn't fail to parse and `which` should find them.
for _name in add amend annotate base branch branches changed changelog \
             changes checkout commit commitforce diffs fix graph incoming \
             lint map outgoing pending precommit presubmit pull push \
             recommit revert review reword submit submitforce unknown \
             upload uploadchain clone st ci di gr lg ma am; do
    result="$(_nu_run "which $_name | get 0.type? | default nothing" 2>&1)"
    case "$result" in
        *custom*|*alias*)
            assert_true "nu vcs alias $_name is defined" "true" ;;
        *)
            assert_true "nu vcs alias $_name is defined (got: $result)" "false" ;;
    esac
done

###############
# TEST: is-env-set handles missing, empty, and set values.
# Regression coverage for the `get -o` flag that used to break on nu 0.105+.
result="$(_nu_run '
hide-env --ignore-errors NU_TOTALLY_UNSET
if (is-env-set "NU_TOTALLY_UNSET") { print -n y } else { print -n n }')"
assert_equal "nu is-env-set false when missing from env" "n" "$result"

###############
# TEST: config.nu does not ship a manual `source` for local overrides;
# users drop files in ~/.config/nushell/autoload/, which nushell
# auto-sources. Missing directory is not an error -- covered implicitly
# by every other test in this file (no autoload dir under the fake HOME).
if grep -q '^source ' "$_config"; then
    assert_true "nu config.nu has no manual source statement" "false"
else
    assert_true "nu config.nu has no manual source statement" "true"
fi

test_summary "nushell shrc_nushell_test"
