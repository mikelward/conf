#!/usr/bin/env nu

const srcdir = (path self | path dirname)
const config_nu = ([ $srcdir "config" "nushell" "config.nu" ] | path join)

def strip-trailing-newlines [text: string] {
    $text | str replace -r '\n+$' ''
}

def --env record-pass [] {
    $env.TEST_PASSES = (($env.TEST_PASSES? | default 0) + 1)
}

def --env record-failure [label: string, expected: string, actual: string] {
    print $"FAIL: ($label)"
    print $"  expected: ($expected)"
    print $"  actual:   ($actual)"
    $env.TEST_FAILURES = (($env.TEST_FAILURES? | default 0) + 1)
}

def --env assert-equal [label: string, expected: string, actual: string] {
    if $expected == $actual {
        record-pass
    } else {
        record-failure $label $expected $actual
    }
}

def --env assert-contains [label: string, needle: string, haystack: string] {
    if ($haystack | str contains $needle) {
        record-pass
    } else {
        record-failure $label $needle $haystack
    }
}

def --env assert-not-contains [label: string, needle: string, haystack: string] {
    if ($haystack | str contains $needle) {
        record-failure $label $needle $haystack
    } else {
        record-pass
    }
}

def --env assert-true [label: string, condition: bool] {
    if $condition {
        record-pass
    } else {
        record-failure $label "true" "false"
    }
}

def mkexec [path: path, content: string] {
    mkdir ($path | path dirname)
    $content | save --force $path
    ^chmod +x $path
}

def nu-run [snippet: string, stdin: string = "", --stderr] {
    let fakehome = ([$env.TESTDIR "nufakehome"] | path join)
    mkdir $fakehome
    let script = $"source ($env.CONFIG_NU)\n($snippet)"
    let result = (with-env {
        HOME: $fakehome
        NO_COLOR: "1"
        TERM: "dumb"
        SHPOOL_SESSION_NAME: ""
        TMUX: ""
        SSH_CONNECTION: ""
        DISPLAY: ""
    } {
        $stdin | ^nu --no-config-file -c $script | complete
    })
    let output = if $stderr {
        $result.stdout + $result.stderr
    } else {
        $result.stdout
    }
    strip-trailing-newlines $output
}

def test-summary [name: string] {
    print ""
    if (($env.TEST_FAILURES? | default 0) == 0) {
        print $"($name): all ($env.TEST_PASSES) tests passed."
        true
    } else {
        print $"($name): ($env.TEST_FAILURES) test(s) failed, ($env.TEST_PASSES) passed."
        false
    }
}

def --env main [] {
    $env.TEST_PASSES = 0
    $env.TEST_FAILURES = 0
    $env.TESTDIR = (mktemp -d | str trim)
    $env.CONFIG_NU = $config_nu
###############
# TEST: bar prints N separator characters
let result = (nu-run r#'print -n (bar 5)'#)
assert-equal "nu bar prints N separators" r#'―――――'# $result

let result = (nu-run r#'print -n (bar 0)'#)
assert-equal "nu bar 0 prints empty" r#''# $result

###############
# TEST: maybe-space
let result = (nu-run r#'print -n (maybe-space "hello")'#)
assert-equal "nu maybe-space with content" r#' hello'# $result

let result = (nu-run r#'print -n (maybe-space "")'#)
assert-equal "nu maybe-space with empty" r#''# $result

let result = (nu-run r#'print -n (maybe-space)'#)
assert-equal "nu maybe-space with no args" r#''# $result

###############
# TEST: format-duration
let result = (nu-run r#'print -n (format-duration 0sec)'#)
assert-equal "nu format-duration 0s is empty" r#''# $result

let result = (nu-run r#'print -n (format-duration 1sec)'#)
assert-equal "nu format-duration 1s is empty (shrc rounds down)" r#''# $result

let result = (nu-run r#'print -n (format-duration 5sec)'#)
assert-equal "nu format-duration 5s" r#'5 seconds'# $result

let result = (nu-run r#'print -n (format-duration 125sec)'#)
assert-equal "nu format-duration 2m5s" r#'2 minutes 5 seconds'# $result

let result = (nu-run r#'print -n (format-duration 3723sec)'#)
assert-equal "nu format-duration 1h2m3s" r#'1 hours 2 minutes 3 seconds'# $result

###############
# TEST: ps1-character
# When not root, shows '〉'. When root (UID=0), shows '#'.
let result = (nu-run r#'$env.UID = 1000; print -n (ps1-character)'#)
assert-equal "nu ps1-character non-root" r#'>'# $result

let result = (nu-run r#'$env.UID = 0; print -n (ps1-character)'#)
assert-equal "nu ps1-character root" "#" $result

###############
# TEST: have-command / is-runnable
let result = (nu-run r#'if (have-command "sh") { print -n yes } else { print -n no }'#)
assert-equal "nu have-command sh is true" r#'yes'# $result

let result = (nu-run r#'if (have-command "zzzzznotacommand") { print -n yes } else { print -n no }'#)
assert-equal "nu have-command bogus is false" r#'no'# $result

let result = (nu-run r#'if (is-runnable "bar") { print -n yes } else { print -n no }'#)
assert-equal "nu is-runnable custom command" r#'yes'# $result

# have-command must also reject a non-executable file that happens to sit
# in a PATH directory with the right name. The earlier `path exists`-only
# implementation returned true here, masking the fact that the file
# isn't runnable.
let hcdir = ([$env.TESTDIR "have_cmd_nonexec"] | path join)
mkdir $hcdir
"" | save --force ([ $hcdir "fakecmd" ] | path join)
^chmod 644 ([ $hcdir "fakecmd" ] | path join)
let have_command_snippet = (r#'
$env.PATH = ['__HCDIR__']
if (have-command 'fakecmd') { print -n yes } else { print -n no }'# | str replace "__HCDIR__" $hcdir)
let result = (nu-run $have_command_snippet)
assert-equal "nu have-command rejects non-executable file in PATH" "no" $result

^chmod +x ([ $hcdir "fakecmd" ] | path join)
let result = (nu-run $have_command_snippet)
assert-equal "nu have-command accepts executable file in PATH" "yes" $result

###############
# TEST: inpath
let result = (nu-run r#'
$env.PATH = ["/usr/bin" "/bin"]
if (inpath "/usr/bin") { print -n yes } else { print -n no }'#)
assert-equal "nu inpath true when in PATH" r#'yes'# $result

let result = (nu-run r#'
$env.PATH = ["/usr/bin" "/bin"]
if (inpath "/tmp") { print -n yes } else { print -n no }'#)
assert-equal "nu inpath false when not in PATH" r#'no'# $result

###############
# TEST: prepend-path / append-path / delete-path / add-path
# Use /tmp and /var as existing directories.
let result = (nu-run r#'
$env.PATH = ["/usr/bin"]
prepend-path "/tmp"
print -n ($env.PATH | str join ":")'#)
assert-equal "nu prepend-path existing dir" r#'/tmp:/usr/bin'# $result

let result = (nu-run r#'
$env.PATH = ["/usr/bin"]
prepend-path "/definitely/not/a/real/dir"
print -n ($env.PATH | str join ":")'#)
assert-equal "nu prepend-path ignores missing" r#'/usr/bin'# $result

let result = (nu-run r#'
$env.PATH = ["/usr/bin"]
append-path "/tmp"
print -n ($env.PATH | str join ":")'#)
assert-equal "nu append-path existing dir" r#'/usr/bin:/tmp'# $result

let result = (nu-run r#'
$env.PATH = ["/usr/bin" "/tmp" "/bin"]
delete-path "/tmp"
print -n ($env.PATH | str join ":")'#)
assert-equal "nu delete-path removes entry" r#'/usr/bin:/bin'# $result

let result = (nu-run r#'
$env.PATH = ["/usr/bin" "/tmp"]
add-path "/tmp" "start"
print -n ($env.PATH | str join ":")'#)
assert-equal "nu add-path moves existing to start" r#'/tmp:/usr/bin'# $result

let result = (nu-run r#'
$env.PATH = ["/tmp" "/usr/bin"]
add-path "/tmp" "end"
print -n ($env.PATH | str join ":")'#)
assert-equal "nu add-path moves existing to end" r#'/usr/bin:/tmp'# $result

let result = (nu-run r#'
$env.PATH = ["/usr/bin"]
add-path "/var"
print -n ($env.PATH | str join ":")'#)
assert-equal "nu add-path default appends if missing" r#'/usr/bin:/var'# $result

let result = (nu-run r#'
$env.PATH = ["/var" "/usr/bin"]
add-path "/var"
print -n ($env.PATH | str join ":")'#)
assert-equal "nu add-path default no-op when present" r#'/var:/usr/bin'# $result

###############
# TEST: short-hostname
let result = (nu-run r#'
$env.HOSTNAME = "mikel-workstation.example.com"
$env.USERNAME = "mikel"
print -n (short-hostname)'#)
assert-equal "nu short-hostname strips user prefix and domain" r#'workstation'# $result

let result = (nu-run r#'
$env.HOSTNAME = "edgehost.example.com"
$env.USERNAME = "mikel"
print -n (short-hostname)'#)
assert-equal "nu short-hostname without user prefix" r#'edgehost'# $result

###############
# TEST: is-env-set
let result = (nu-run r#'
hide-env --ignore-errors NU_TEST_VAR
if (is-env-set "NU_TEST_VAR") { print -n yes } else { print -n no }'#)
assert-equal "nu is-env-set false when unset" r#'no'# $result

let result = (nu-run r#'
$env.NU_TEST_VAR = ""
if (is-env-set "NU_TEST_VAR") { print -n yes } else { print -n no }'#)
assert-equal "nu is-env-set false when empty string" r#'no'# $result

let result = (nu-run r#'
$env.NU_TEST_VAR = "value"
if (is-env-set "NU_TEST_VAR") { print -n yes } else { print -n no }'#)
assert-equal "nu is-env-set true when set to non-empty" r#'yes'# $result

###############
# TEST: in-shpool
let result = (nu-run r#'
hide-env --ignore-errors SHPOOL_SESSION_NAME
if (in-shpool) { print -n yes } else { print -n no }'#)
assert-equal "nu in-shpool false when unset" r#'no'# $result

let result = (nu-run r#'
$env.SHPOOL_SESSION_NAME = "main"
if (in-shpool) { print -n yes } else { print -n no }'#)
assert-equal "nu in-shpool true when SHPOOL_SESSION_NAME set" r#'yes'# $result

###############
# TEST: session-name
let result = (nu-run r#'
hide-env --ignore-errors SHPOOL_SESSION_NAME
hide-env --ignore-errors TMUX
print -n (session-name)'#)
assert-equal "nu session-name empty when no pool/tmux" r#''# $result

let result = (nu-run r#'
$env.SHPOOL_SESSION_NAME = "edge1"
print -n (session-name)'#)
assert-equal "nu session-name returns shpool session" r#'edge1 '# $result

###############
# TEST: on-my-workstation / on-my-laptop / on-production-host
let result = (nu-run r#'
$env.HOSTNAME = "mikel-workstation"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
if (on-my-workstation) { print -n yes } else { print -n no }'#)
assert-equal "nu on-my-workstation user-prefixed host" r#'yes'# $result

let result = (nu-run r#'
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
if (on-my-workstation) { print -n yes } else { print -n no }'#)
assert-equal "nu on-my-workstation laptop is false" r#'no'# $result

let result = (nu-run r#'
$env.HOSTNAME = "mikel-laptop"
if (on-my-laptop) { print -n yes } else { print -n no }'#)
assert-equal "nu on-my-laptop laptop hostname" r#'yes'# $result

let result = (nu-run r#'
$env.HOSTNAME = "prodhost"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
if (on-production-host) { print -n yes } else { print -n no }'#)
assert-equal "nu on-production-host true for unknown host" r#'yes'# $result

let result = (nu-run r#'
$env.HOSTNAME = "mikel-workstation"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
if (on-production-host) { print -n yes } else { print -n no }'#)
assert-equal "nu on-production-host false on my workstation" r#'no'# $result

###############
# TEST: title respects inside-tmux
# Outside tmux/shpool, show "<host> <pwd_basename>".
let result = (nu-run r#'
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
mkdir ([$env.HOME "titletest"] | path join)
cd ([$env.HOME "titletest"] | path join)
print -n (title)'#)
assert-equal "nu title shows hostname outside tmux" r#'laptop titletest'# $result

let result = (nu-run r#'
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
$env.TMUX = "/fake/tmux/socket"
$env.SHPOOL_SESSION_NAME = "main"
mkdir ([$env.HOME "titletest"] | path join)
cd ([$env.HOME "titletest"] | path join)
print -n (title)'#)
assert-contains "nu title hides hostname in tmux" r#'main'# $result
assert-not-contains "nu title hides hostname in tmux - no host" r#'laptop '# $result

###############
# TEST: prompt-line fallback when vcs is missing
# With no `vcs` command, prompt-line should fall back to a simple
# "hostname [session ]pwd" string.
let result = (nu-run r#'
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
$env.PATH = []
cd $env.HOME
print -n (prompt-line)'#)
# PATH is empty so have-command "vcs" is false; the fallback is used.
assert-contains "nu prompt-line fallback has hostname" r#'laptop'# $result

###############
# TEST: render-prompt structure matches shrc preprompt
# A leading newline, a separator bar, a CR, the prompt line, newline, and
# the prompt character followed by a space. Drive it with empty PATH so
# prompt-line uses its fallback (no `vcs` binary on PATH).
let result = (nu-run r#'
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
$env.UID = 1000
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
$env.PATH = []
cd $env.HOME
print -n (render-prompt)'#)
assert-contains "nu render-prompt contains separator" r#'―'# $result
assert-contains "nu render-prompt contains hostname in prompt line" r#'laptop'# $result
assert-contains "nu render-prompt ends with > prompt" r#'> '# $result

# And with UID=0, the prompt character should be #.
let result = (nu-run r#'
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
$env.UID = 0
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
$env.PATH = []
cd $env.HOME
print -n (render-prompt)'#)
assert-contains "nu render-prompt as root ends with # prompt" "# " $result

###############
# TEST: find-up climbs the tree
let result = (nu-run r#'
let base = ($env.HOME | path expand)
mkdir ([$base "a" "b" "c"] | path join)
"marker" | save --force ([$base "a" "marker"] | path join)
cd ([$base "a" "b" "c"] | path join)
print -n (find-up "marker")'#)
assert-contains "nu find-up finds ancestor file" r#'marker'# $result

###############
# TEST: mcd creates and enters a directory
let result = (nu-run r#'
let base = ($env.HOME | path expand)
cd $base
mcd newdir
print -n $env.PWD'#)
assert-contains "nu mcd enters the new directory" r#'newdir'# $result

# And if the target already exists, mcd prints a message and does not crash.
let result = (nu-run r#'
let base = ($env.HOME | path expand)
cd $base
mkdir existing-dir
mcd existing-dir'#)
assert-contains "nu mcd reports when target already exists" r#'already exists'# $result

###############
# TEST: mtd creates a fresh temp dir and cds into it
let result = (nu-run r#'
let start = $env.PWD
mtd
print -n $env.PWD
print -n "|"
print -n $start'#)
# The new PWD should be different from the starting PWD and live under /tmp
assert-true "nu mtd cds into a /tmp subdirectory" (($result | str starts-with "/tmp/") and ($result | str contains "|"))

###############
# TEST: cdfile / realdir resolve symlinks to the real containing directory
let result = (nu-run r#'
let base = ($env.HOME | path expand)
mkdir ([$base "target"] | path join)
"hello" | save --force ([$base "target" "file.txt"] | path join)
^ln -s ([$base "target"] | path join) ([$base "link"] | path join)
# realdir on a file inside the symlink should resolve to the real target dir.
print -n (realdir ([$base "link" "file.txt"] | path join))'#)
assert-contains "nu realdir resolves symlink to real dir" "/target" $result

let result = (nu-run r#'
let base = ($env.HOME | path expand)
mkdir ([$base "cdfile-target"] | path join)
"x" | save --force ([$base "cdfile-target" "file.txt"] | path join)
cdfile ([$base "cdfile-target" "file.txt"] | path join)
print -n $env.PWD'#)
assert-contains "nu cdfile cds to the file's real directory" r#'cdfile-target'# $result

###############
# TEST: gh-search greps $HOME/.history
let result = (nu-run r#'
"one two three
alpha beta gamma
one four five" | save --force ([$env.HOME ".history"] | path join)
gh-search "alpha"'#)
assert-contains "nu gh-search finds a matching line" r#'alpha beta gamma'# $result

# rh (gh-search | last 20) should return at most the last 20 matches.
let result = (nu-run r#'
let lines = (1..25 | each {|i| $"match line ($i)" } | str join (char newline))
$lines | save --force ([$env.HOME ".history"] | path join)
rh "match" | length'#)
assert-equal "nu rh limits gh-search output to 20 lines" r#'20'# $result

###############
# TEST: confirm reads a yes/no answer from stdin.
# The prompt goes to stdout, and `^head -n 1` reads one line of stdin, so
# assert_contains on the combined output catches both the prompt and the
# boolean result. An empty reply (just a newline) should default to yes.
let confirm_snippet = r#'let r = (confirm "go"); print -n $" <($r)>"'#
let result = (nu-run $confirm_snippet r#'y
'#)
assert-contains "nu confirm yes on y" "<true>" $result

let result = (nu-run $confirm_snippet r#'Y
'#)
assert-contains "nu confirm yes on Y (uppercase)" "<true>" $result

let result = (nu-run $confirm_snippet r#'yes
'#)
assert-contains "nu confirm yes on yes" "<true>" $result

let result = (nu-run $confirm_snippet r#'n
'#)
assert-contains "nu confirm no on n" "<false>" $result

let result = (nu-run $confirm_snippet r#'no
'#)
assert-contains "nu confirm no on no" "<false>" $result

let result = (nu-run $confirm_snippet r#'
'#)
assert-contains "nu confirm defaults to yes on empty reply" "<true>" $result

let result = (nu-run $confirm_snippet r#'maybe
'#)
assert-contains "nu confirm treats non-y reply as no" "<false>" $result

###############
# TEST: clone dispatch
# Stub jj/git/hg as scripts on PATH so we can verify which one was invoked.
let stubdir = ([$env.TESTDIR "clone_stubs"] | path join)
let stubdir_nojj = ([$env.TESTDIR "clone_stubs_nojj"] | path join)
mkdir $stubdir $stubdir_nojj
for cmd in [jj git hg] {
    mkexec ([$stubdir $cmd] | path join) (r##'#!/bin/sh
echo "__CMD__ $*"
'## | str replace "__CMD__" $cmd)
}
# nojj variant: same scripts, but no jj
^cp ([$stubdir "git"] | path join) ([$stubdir "hg"] | path join) $stubdir_nojj

let clone_git_snippet = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
clone 'https://github.com/foo/bar.git'
'# | str replace "__STUBDIR__" $stubdir)
let result = ((nu-run $clone_git_snippet) | str replace -a (char newline) "")
assert-equal "nu clone .git uses jj git clone when jj available" "jj git clone https://github.com/foo/bar.git" $result

let clone_hg_snippet = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
clone 'https://hg.example.com/hg/repo'
'# | str replace "__STUBDIR__" $stubdir)
let result = ((nu-run $clone_hg_snippet) | str replace -a (char newline) "")
assert-equal "nu clone /hg/ uses hg clone" "hg clone https://hg.example.com/hg/repo" $result

# When jj isn't on PATH, clone should prompt and fall back to git on yes.
let clone_fallback_snippet = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
clone 'https://github.com/foo/bar.git'
'# | str replace "__STUBDIR__" $stubdir_nojj)
let result = ((nu-run $clone_fallback_snippet "y") | str replace -a (char newline) "")
assert-contains "nu clone falls back to git when jj missing and user says yes" "git clone https://github.com/foo/bar.git" $result

# When the user declines the fallback, no clone command runs.
let result = ((nu-run $clone_fallback_snippet "n") | str replace -a (char newline) "")
assert-not-contains "nu clone aborts when user declines git fallback" "git clone" $result

###############
# TEST: CDPATH is set and does not include conf/ subdirectories
let result = (nu-run r#'print -n ($env.CDPATH | str join ":")'#)
assert-contains "nu CDPATH contains HOME" $"($env.TESTDIR)/nufakehome" $result
assert-not-contains "nu CDPATH does not contain conf" $"($env.TESTDIR)/nufakehome/conf" $result

###############
# TEST: trailing-slash autocd is provided by nushell's native REPL path
# handling, not by any command_not_found hook of ours. We do install a
# pre_execution hook for command-duration tracking (covered separately
# below); the assertion here is just that no autocd hook is installed.
let result = (nu-run r#'print -n ($env.config.hooks.command_not_found | describe)'#)
assert-equal "nu command_not_found hook is not set" r#'nothing'# $result

# TEST: `cd` into a trailing-slash path works (sanity check for the
# `cd ./foo/` fallback users can type explicitly).
let result = (nu-run r#'
let base = ($env.HOME | path expand)
mkdir ([$base "cdtest" "sub"] | path join)
cd ([$base "cdtest"] | path join)
cd ./sub/
print -n $env.PWD'#)
assert-contains "nu cd with trailing slash enters directory" r#'cdtest/sub'# $result

###############
# TEST: last-job-info shows nothing when no command has run
let result = (nu-run r#'
hide-env --ignore-errors CMD_DURATION
print -n (last-job-info)'#)
assert-equal "nu last-job-info empty when CMD_DURATION unset" r#''# $result

# And nothing when the duration is below the display threshold.
let result = (nu-run r#'
$env.CMD_DURATION = 0sec
print -n (last-job-info)'#)
assert-equal "nu last-job-info empty for 0sec" r#''# $result

let result = (nu-run r#'
$env.CMD_DURATION = 1sec
print -n (last-job-info)'#)
assert-equal "nu last-job-info empty for 1sec (rounds down)" r#''# $result

# With a meaningful duration it should contain the formatted text.
let result = (nu-run r#'
$env.CMD_DURATION = 5sec
print -n (last-job-info)'#)
assert-contains "nu last-job-info shows took for 5sec" r#'took 5 seconds'# $result

let result = (nu-run r#'
$env.CMD_DURATION = 1hr
print -n (last-job-info)'#)
assert-contains "nu last-job-info shows hours for 1hr" r#'1 hours'# $result

###############
# TEST: title-escape wraps the title in an OSC 0 sequence for xterm,
# and returns empty for non-xterm-family terminals.
let result = (nu-run r#'
$env.TERM = "xterm-256color"
print -n (title-escape "my title")'#)
assert-contains "nu title-escape includes OSC 0 on xterm" r#']0;my title'# $result

let result = (nu-run r#'
$env.TERM = "dumb"
print -n (title-escape "my title")'#)
assert-equal "nu title-escape empty on dumb terminal" r#''# $result

let result = (nu-run r#'
$env.TERM = "rxvt-unicode"
print -n (title-escape "hi")'#)
assert-contains "nu title-escape supports rxvt" r#']0;hi'# $result

###############
# TEST: flash-terminal returns the BEL char on xterm, empty elsewhere.
let result = (nu-run r#'
$env.TERM = "xterm-256color"
print -n (flash-terminal)
print -n "END"'#)
# BEL is char 07 -- assert it appears before the END marker.
assert-true "nu flash-terminal rings bell on xterm" ($result | str ends-with $"((char bel))END")

let result = (nu-run r#'
$env.TERM = "dumb"
print -n (flash-terminal)'#)
assert-equal "nu flash-terminal empty on dumb terminal" r#''# $result

###############
# TEST: render-prompt includes the title escape and bell when TERM=xterm.
let result = (nu-run r#'
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
$env.UID = 1000
$env.TERM = "xterm-256color"
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
$env.PATH = []
cd $env.HOME
print -n (render-prompt)'#)
assert-contains "nu render-prompt sets xterm title" r#']0;'# $result

# And the duration line when CMD_DURATION is populated.
let result = (nu-run r#'
$env.HOSTNAME = "mikel-laptop"
$env.USERNAME = "mikel"
$env.UID = 1000
$env.TERM = "dumb"
$env.CMD_DURATION = 5sec
hide-env --ignore-errors TMUX
hide-env --ignore-errors SHPOOL_SESSION_NAME
$env.PATH = []
cd $env.HOME
print -n (render-prompt)'#)
assert-contains "nu render-prompt includes duration line" r#'took 5 seconds'# $result

###############
# TEST: pre_execution / pre_prompt hooks are installed and track timing.
let result = (nu-run r#'print -n ($env.config.hooks.pre_execution | length)'#)
assert-equal "nu pre_execution hook list has one entry" r#'1'# $result

let result = (nu-run r#'print -n ($env.config.hooks.pre_prompt | length)'#)
assert-equal "nu pre_prompt hook list has one entry" r#'1'# $result

# Invoke the hook closures directly and verify CMD_DURATION gets set to
# a non-zero duration when pre_execution has recorded a start time.
# do --env propagates the closure's $env mutations back to the caller,
# matching how nushell itself invokes hooks.
let result = (nu-run r#'
do --env ($env.config.hooks.pre_execution | first)
sleep 2100ms
do --env ($env.config.hooks.pre_prompt | first)
print -n (format-duration $env.CMD_DURATION)'#)
assert-contains "nu timing hooks populate CMD_DURATION" r#'seconds'# $result

# When pre_execution did not fire, pre_prompt zeroes CMD_DURATION.
let result = (nu-run r#'
hide-env --ignore-errors CMD_START_TIME
hide-env --ignore-errors CMD_DURATION
do --env ($env.config.hooks.pre_prompt | first)
print -n ($env.CMD_DURATION | into int)'#)
assert-equal "nu pre_prompt clears stale CMD_DURATION" r#'0'# $result

###############
# TEST: auth helpers respond to ssh-add's exit status.
let authstub_ok = ([$env.TESTDIR "auth_stub_ok"] | path join)
let authstub_fail = ([$env.TESTDIR "auth_stub_fail"] | path join)
mkexec ([$authstub_ok "ssh-add"] | path join) r##'#!/bin/sh
exit 0
'##
mkexec ([$authstub_fail "ssh-add"] | path join) r##'#!/bin/sh
echo "no agent" >&2
exit 2
'##

let ssh_valid_ok = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
print -n (is-ssh-valid)'# | str replace "__STUBDIR__" $authstub_ok)
let result = (nu-run $ssh_valid_ok)
assert-equal "nu is-ssh-valid true when ssh-add succeeds" "true" $result

let ssh_valid_fail = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
print -n (is-ssh-valid)'# | str replace "__STUBDIR__" $authstub_fail)
let result = (nu-run $ssh_valid_fail)
assert-equal "nu is-ssh-valid false when ssh-add fails" "false" $result

let need_auth_ok = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
print -n (need-auth)'# | str replace "__STUBDIR__" $authstub_ok)
let result = (nu-run $need_auth_ok)
assert-equal "nu need-auth false when ssh-add succeeds" "false" $result

let need_auth_fail = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
print -n (need-auth)'# | str replace "__STUBDIR__" $authstub_fail)
let result = (nu-run $need_auth_fail)
assert-equal "nu need-auth true when ssh-add fails" "true" $result

# auth-info should include the "SSH" token on failure (ANSI-wrapped).
let auth_info_fail = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
print -n (auth-info)'# | str replace "__STUBDIR__" $authstub_fail)
let result = (nu-run $auth_info_fail)
assert-contains "nu auth-info reports SSH on failure" "SSH" $result

# And be empty on success.
let auth_info_ok = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
print -n (auth-info)'# | str replace "__STUBDIR__" $authstub_ok)
let result = (nu-run $auth_info_ok)
assert-equal "nu auth-info empty on success" "" $result

###############
# TEST: overridable hook points.
# config.nu exposes four hooks as closures in $env so that autoload files
# can override them and have the change propagate through every caller
# inside config.nu (nushell resolves def-to-def calls at parse time, so a
# plain `def` redefinition in an autoload file would NOT propagate).
# Each hook is smoke-tested here: override the closure and check that a
# downstream caller sees the new value.

# $env.auth: the `auth` wrapper should dispatch through it.
let result = (nu-run r#'
$env.auth = {|| "custom-auth-called" }
print -n (auth)'#)
assert-equal "nu auth wrapper dispatches through \$env.auth" r#'custom-auth-called'# $result

# $env.with-agent: wsh/wcp are defined in config.nu and should pick up
# the override. Their bodies are `with-agent ssh ...` / `with-agent scp ...`.
let result = (nu-run r#'
$env.with-agent = {|...cmd| print -n ($cmd | str join "|") }
wsh host arg'#)
assert-equal "nu wsh dispatches through \$env.with-agent" r#'ssh|host|arg'# $result

let result = (nu-run r#'
$env.with-agent = {|...cmd| print -n ($cmd | str join "|") }
wcp src dst'#)
assert-equal "nu wcp dispatches through \$env.with-agent" r#'scp|src|dst'# $result

# $env.on-production-host: overriding it must flip the result even on a
# hostname that the default logic would classify as production.
let result = (nu-run r#'
$env.HOSTNAME = "prodhost"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
$env.on-production-host = {|| false }
if (on-production-host) { print -n yes } else { print -n no }'#)
assert-equal "nu on-production-host override wins over default" r#'no'# $result

# And the reverse: flip a workstation hostname to production via the hook.
let result = (nu-run r#'
$env.HOSTNAME = "mikel-workstation"
$env.USERNAME = "mikel"
hide-env --ignore-errors WORKSTATION
$env.on-production-host = {|| true }
if (on-production-host) { print -n yes } else { print -n no }'#)
assert-equal "nu on-production-host override flips workstation to prod" r#'yes'# $result

###############
# TEST: bak / unbak roundtrip. Clear any leftover files first since tests
# share _fakehome.
let result = (nu-run r#'
cd $env.HOME
["baktest" "baktest.bak"] | each {|f| if ($f | path exists) { ^rm -f $f } } | ignore
"hello" | save --force baktest
bak "baktest"
print -n (ls baktest* | get name | path basename | str join ",")'#)
assert-equal "nu bak creates .bak file" r#'baktest.bak'# $result

let result = (nu-run r#'
cd $env.HOME
["baktest" "baktest.bak"] | each {|f| if ($f | path exists) { ^rm -f $f } } | ignore
"hello" | save --force baktest
bak "baktest"
unbak "baktest.bak"
print -n (ls baktest* | get name | path basename | str join ",")
print -n "|"
print -n (open baktest)'#)
assert-equal "nu unbak restores original" r#'baktest|hello'# $result

# unbak handles short names: the old `0..(-4)` substring math was
# off-by-one and dropped only three chars. This tests a short filename
# where the old and new implementations differ.
let result = (nu-run r#'
cd $env.HOME
["shortbak" "shortbak.bak"] | each {|f| if ($f | path exists) { ^rm -f $f } } | ignore
"x" | save --force shortbak
bak "shortbak"
unbak "shortbak.bak"
print -n (open shortbak)'#)
assert-equal "nu unbak short filename roundtrip" r#'x'# $result

###############
# TEST: log-history appends timestamped entries to HISTORY_FILE
let result = (nu-run r#'
$env.HISTORY_FILE = ([$env.HOME "history.log"] | path join)
$env.TTY = "/dev/pts/42"
log-history "hello world"
open --raw $env.HISTORY_FILE | str trim'#)
assert-contains "nu log-history writes argv" r#'hello world'# $result
assert-contains "nu log-history writes tty" r#'/dev/pts/42'# $result

# log-history no-ops when HISTORY_FILE is empty
let result = (nu-run r#'
$env.HISTORY_FILE = ""
log-history "ignored"
print -n "done"'#)
assert-equal "nu log-history no-op when HISTORY_FILE empty" r#'done'# $result

# log-history also no-ops when HISTORY_FILE unset entirely
let result = (nu-run r#'
hide-env --ignore-errors HISTORY_FILE
log-history "ignored"
print -n "done"'#)
assert-equal "nu log-history no-op when HISTORY_FILE unset" r#'done'# $result

###############
# TEST: inside-project / want-shpool / maybe-start-shpool-and-exit
# Override projectroot to "" so these tests are independent of whether
# the `vcs` binary happens to be installed on the host or whether $PWD
# happens to sit inside a repo.
let result = (nu-run r#'
$env.projectroot = {|| "" }
if (inside-project) { print -n yes } else { print -n no }'#)
assert-equal "nu inside-project false when projectroot is empty" r#'no'# $result

# want-shpool: false when neither remote nor inside project.
let result = (nu-run r#'
$env.projectroot = {|| "" }
hide-env --ignore-errors SSH_CONNECTION
if (want-shpool) { print -n yes } else { print -n no }'#)
assert-equal "nu want-shpool false when not remote and not in project" r#'no'# $result

# want-shpool: true when SSH_CONNECTION is set (remote).
let result = (nu-run r#'
$env.SSH_CONNECTION = "1.2.3.4 22 5.6.7.8 22"
if (want-shpool) { print -n yes } else { print -n no }'#)
assert-equal "nu want-shpool true when remote" r#'yes'# $result

# Overriding `$env.projectroot` propagates through the whole
# inside-project/want-shpool/projectname/buildroot chain because
# config.nu defines `projectroot` as `do $env.projectroot` (see the
# comment block at the bottom of config.nu for the full explanation).
let result = (nu-run r#'
$env.projectroot = {|| "/fake/project" }
if (inside-project) { print -n yes } else { print -n no }'#)
assert-equal "nu inside-project true when projectroot override returns non-empty" r#'yes'# $result

let result = (nu-run r#'
$env.projectroot = {|| "/fake/project" }
hide-env --ignore-errors SSH_CONNECTION
if (want-shpool) { print -n yes } else { print -n no }'#)
assert-equal "nu want-shpool true when projectroot override is non-empty" r#'yes'# $result

let result = (nu-run r#'
$env.projectroot = {|| "/srv/code/myrepo" }
print -n (projectname)'#)
assert-equal "nu projectname picks up projectroot override" r#'myrepo'# $result

let result = (nu-run r#'
$env.projectroot = {|| "/srv/code/myrepo" }
print -n (buildroot)'#)
assert-equal "nu buildroot picks up projectroot override" r#'/srv/code/myrepo'# $result

# maybe-start-shpool-and-exit is a no-op when shpool is not on PATH, even if
# the other conditions would otherwise fire. The test simply asserts that
# calling it returns normally (no exit/crash).
let result = (nu-run r#'
$env.PATH = []
$env.SSH_CONNECTION = "1.2.3.4 22"
hide-env --ignore-errors SHPOOL_SESSION_NAME
maybe-start-shpool-and-exit
print -n "returned"'#)
assert-equal "nu maybe-start-shpool-and-exit no-op without shpool" r#'returned'# $result

###############
# TEST: projectroot default behavior
# When the `vcs` helper binary is on PATH, projectroot shells out to
# `vcs rootdir` and returns its stdout. Stub `vcs` so the test doesn't
# depend on the real binary being checked out.
let vcs_root_stub = ([$env.TESTDIR "vcs_root_stub"] | path join)
mkexec ([$vcs_root_stub "vcs"] | path join) r##'#!/bin/sh
case "$1" in
    rootdir) echo /fake/from/vcs/binary ;;
    *) exit 1 ;;
esac
'##
let vcs_root_snippet = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
print -n (projectroot)'# | str replace "__STUBDIR__" $vcs_root_stub)
let result = (nu-run $vcs_root_snippet)
assert-equal "nu projectroot shells out to vcs rootdir when binary present" "/fake/from/vcs/binary" $result

# When `vcs rootdir` exits nonzero (not inside a project), projectroot
# returns "" rather than surfacing the error.
let vcs_fail_stub = ([$env.TESTDIR "vcs_fail_stub"] | path join)
mkexec ([$vcs_fail_stub "vcs"] | path join) r##'#!/bin/sh
exit 1
'##
let vcs_fail_snippet = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
print -n (projectroot)'# | str replace "__STUBDIR__" $vcs_fail_stub)
let result = (nu-run $vcs_fail_snippet)
assert-equal "nu projectroot empty when vcs rootdir exits nonzero" "" $result

# Fallback: when `vcs` is not on PATH, walk parent directories looking
# for a VCS marker. .git in the current dir should be found.
let result = (nu-run r#'
$env.PATH = []
let base = ($env.HOME | path expand)
let proj = ([$base "pr-git"] | path join)
mkdir ([$proj ".git"] | path join)
cd $proj
print -n (projectroot)'#)
assert-contains "nu projectroot fallback finds .git in cwd" r#'pr-git'# $result

# And should walk up through subdirectories to find the marker.
let result = (nu-run r#'
$env.PATH = []
let base = ($env.HOME | path expand)
let proj = ([$base "pr-jj"] | path join)
mkdir ([$proj ".jj"] | path join)
mkdir ([$proj "sub" "deeper"] | path join)
cd ([$proj "sub" "deeper"] | path join)
print -n (projectroot)'#)
assert-contains "nu projectroot fallback walks up to find .jj" r#'pr-jj'# $result

# Each of the five supported markers should be recognised.
for marker in [.jj .hg .git .citc .p4config] {
    let marker_name = ($marker | str replace -a "." "")
    let marker_snippet = ((r#'
$env.PATH = []
let base = ($env.HOME | path expand)
let proj = ([$base '__PROJ__'] | path join)
mkdir ([$proj '__MARKER__'] | path join)
cd $proj
print -n (projectroot)'# | str replace "__PROJ__" $"pr-marker-($marker_name)") | str replace "__MARKER__" $marker)
    let result = (nu-run $marker_snippet)
    assert-contains $"nu projectroot fallback recognises ($marker)" "pr-marker" $result
}

# inside-project, projectname, buildroot all propagate the fallback result.
let result = (nu-run r#'
$env.PATH = []
let base = ($env.HOME | path expand)
let proj = ([$base "pr-chain"] | path join)
mkdir ([$proj ".git"] | path join)
cd $proj
if (inside-project) { print -n yes } else { print -n no }'#)
assert-equal "nu inside-project true under fallback-detected repo" r#'yes'# $result

let result = (nu-run r#'
$env.PATH = []
let base = ($env.HOME | path expand)
let proj = ([$base "pr-name"] | path join)
mkdir ([$proj ".git"] | path join)
cd $proj
print -n (projectname)'#)
assert-equal "nu projectname picks up fallback projectroot" r#'pr-name'# $result

###############
# TEST: shift-options rearranges leading flags to come before the target.
# Nushell's parser only lets flags flow through via spread from wrappers,
# matching how fish aliases and shrc functions actually use shift_options.
let result = (nu-run r#'
def wrap [...args: string] { shift-options echo target ...$args }
wrap "-a" "-b" "rest" | str trim'#)
assert-equal "nu shift-options moves options before target" r#'-a -b target rest'# $result

let result = (nu-run r#'
def wrap [...args: string] { shift-options echo target ...$args }
wrap "rest" | str trim'#)
assert-equal "nu shift-options no options" r#'target rest'# $result

let result = (nu-run r#'
def wrap [...args: string] { shift-options echo target ...$args }
wrap "-x" | str trim'#)
assert-equal "nu shift-options option only" r#'-x target'# $result

let result = (nu-run r#'
def wrap [...args: string] { shift-options echo target ...$args }
wrap "--" "-b" | str trim'#)
assert-equal "nu shift-options stops at --" r#'target -- -b'# $result

###############
# TEST: first-arg-last guards against short arg lists.
# Before the guard, `first-arg-last echo` errored with
# nu::shell::access_beyond_end because `$args | get 1` on a 1-element
# list is out of range. 0 args is a usage error (previously a silent
# no-op, which masked caller bugs); 1 arg runs the command as-is;
# 2+ args rearrange first-to-last.
let result = (nu-run r#'try { first-arg-last; print -n noerror } catch { |e| print -n $e.msg }'#)
assert-contains "nu first-arg-last 0 args raises usage error" r#'usage'# $result
assert-not-contains "nu first-arg-last 0 args does not silently pass" r#'noerror'# $result

let result = (nu-run r#'first-arg-last echo | str trim'#)
assert-equal "nu first-arg-last 1 arg runs the command" r#''# $result

let result = (nu-run r#'first-arg-last echo only | str trim'#)
assert-equal "nu first-arg-last 2 args runs command with arg" r#'only'# $result

let result = (nu-run r#'first-arg-last echo history.file tail | str trim'#)
assert-equal "nu first-arg-last moves first positional to end" r#'tail history.file'# $result

###############
# TEST: which-path handles empty `which` results without crashing.
# Before the is-empty guard, `get 0.path?` on an empty list errored
# with nu::shell::access_beyond_end (the `?` only makes the column
# optional, not the row index).
let result = (nu-run r#'which-path sh'#)
assert-contains "nu which-path prints path for a known command" r#'sh'# $result

# An unknown command should not crash; it reports via the error stream.
let result = (nu-run r#'which-path zzzz-not-a-real-command-xyz'# --stderr)
assert-contains "nu which-path reports missing command" r#'not found'# $result

# And explicit regression: the command should no longer raise
# nu::shell::access_beyond_end on a missing name.
let result = (nu-run r#'which-path zzzz-not-a-real-command-xyz'# --stderr)
assert-not-contains "nu which-path does not raise access_beyond_end" r#'access_beyond_end'# $result

###############
# TEST: `what` prints the definition of a command, mirroring shrc's
# `whence -f` / fish's `type`. Before the fix it just delegated to
# `which`, which prints the type/path but not the definition.

# Custom def: body should appear in the output.
let result = (nu-run r#'what have-command'#)
assert-contains "nu what prints body of a custom def" r#'path exists'# $result

# Alias: the alias target should appear in the output.
let result = (nu-run r#'alias xecho = echo hello; what xecho'#)
assert-contains "nu what prints the target of an alias" r#'echo hello'# $result

# External: the absolute path should appear in the output.
let result = (nu-run r#'what sh'#)
assert-contains "nu what prints path of an external command" r#'/sh'# $result

# Missing command: reports via the error helper (stderr), doesn't crash.
let result = (nu-run r#'what zzzz-not-a-real-command-xyz'# --stderr)
assert-contains "nu what reports missing command" r#'not found'# $result

###############
# TEST: rerc is defined and its body exec's a new nushell.
# Can't actually call rerc in the test harness (exec would replace the
# process), so verify structurally via `view source`.
let result = (nu-run r#'(which rerc | get 0.type)'#)
assert-equal "nu rerc is defined as a custom command" r#'custom'# $result

let result = (nu-run r#'print ((view source rerc) | str contains "exec nu")'#)
assert-equal "nu rerc body exec's nu" r#'true'# $result

###############
# TEST: delline removes the given line in place
let result = (nu-run r#'
cd $env.HOME
"line1
line2
line3" | save --force lines.txt
delline 2 lines.txt
open lines.txt | str trim'#)
assert-equal "nu delline removes line 2" r#'line1
line3'# $result

###############
# TEST: body forwards the first N header lines then runs the command on the
# remaining body. Default is 1 header line.
let result = (nu-run r#'
"HEAD
c
a
b" | body sort | str trim'#)
assert-equal "nu body default 1-line header" r#'HEAD
a
b
c'# $result

# --lines 2 keeps a two-line header.
let result = (nu-run r#'
"H1
H2
y
x
z" | body --lines 2 sort | str trim'#)
assert-equal "nu body --lines 2 preserves two headers" r#'H1
H2
x
y
z'# $result

###############
# TEST: trydiff runs the command on the file, diffs the result, leaves the
# original untouched. Using `sort` on unsorted input guarantees a diff.
let result = (nu-run r#'
cd $env.HOME
"b
a
c" | save --force t.txt
trydiff sort t.txt
print "==="
open t.txt | str trim'#)
# diff output should mention the sorted rearrangement
assert-contains "nu trydiff emits a diff" r#'> '# $result
# And the file should be unchanged afterwards.
assert-contains "nu trydiff leaves file untouched" r#'b
a
c'# $result

###############
# TEST: VCS aliases are defined even when the vcs binary is missing.
# The stubs shouldn't fail to parse and `which` should find them.
# `clone` remains a custom command (has real logic). The rest are now
# aliases after the def->alias conversion.
for name in [add amend annotate base branch branches changed changelog changes checkout commit commitforce diffs fix graph incoming lint map outgoing pending precommit presubmit pull push recommit revert review reword submit submitforce unknown upload uploadchain clone st ci di gr lg ma am] {
    let result = (nu-run $"which ($name) | get 0.type? | default nothing" --stderr)
    assert-true $"nu vcs alias ($name) is defined" (($result | str contains "custom") or ($result | str contains "alias"))
}

# Explicit: clone is the only vcs wrapper that should still be a custom
# command (it has real dispatch logic). Everything else is an alias.
let result = (nu-run r#'which clone | get 0.type'#)
assert-equal "nu clone remains a custom command" r#'custom'# $result

for name in [add commit diffs graph push pull st ci di gr] {
    let result = (nu-run $"which ($name) | get 0.type")
    assert-equal $"nu ($name) is an alias after def->alias conversion" "alias" $result
}

###############
# TEST: vcs aliases pass flags through to ^vcs without the wrapper's
# flag parser catching them.
#
# Regression: the previous `def <cmd> [...args] { vcs "<cmd>" ...$args }`
# pattern caused nushell's parser to reject unknown flags on the
# wrapper, so typing `ci -m "fix"` errored with `unknown flag -m`.
# Aliases are parse-time substitutions, so flags flow directly to the
# external command and never see the wrapper's signature.
let vcs_stub = ([$env.TESTDIR "vcs_stub"] | path join)
mkexec ([$vcs_stub "vcs"] | path join) r##'#!/bin/sh
# Echo all args so tests can see what the alias dispatched.
printf 'vcs-stub:'
printf ' %s' "$@"
printf '\n'
'##

# Long-form: commit -m "message"
let vcs_commit_snippet = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
commit -m fix'# | str replace "__STUBDIR__" $vcs_stub)
let result = (nu-run $vcs_commit_snippet)
assert-contains "nu commit alias passes -m through to ^vcs" "vcs-stub: commit -m fix" $result

# Short alias: ci -m "message" (the classic case that used to fail)
let vcs_ci_snippet = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
ci -m fix'# | str replace "__STUBDIR__" $vcs_stub)
let result = (nu-run $vcs_ci_snippet)
assert-contains "nu ci alias passes -m through to ^vcs" "vcs-stub: commit -m fix" $result

# Long flag: diffs --stat
let vcs_di_snippet = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
di --stat'# | str replace "__STUBDIR__" $vcs_stub)
let result = (nu-run $vcs_di_snippet)
assert-contains "nu di alias passes --stat through to ^vcs" "vcs-stub: diffs --stat" $result

# Positional + flag combo: graph --limit 10
let vcs_gr_snippet = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
gr --limit 10'# | str replace "__STUBDIR__" $vcs_stub)
let result = (nu-run $vcs_gr_snippet)
assert-contains "nu gr alias passes --limit N through to ^vcs" "vcs-stub: graph --limit 10" $result

# Bare `vcs` at the REPL falls through to the external automatically
# (no `alias vcs = ^vcs` needed — nushell auto-resolves unknown names).
let vcs_detect_snippet = (r#'
$env.PATH = ['__STUBDIR__' '/usr/bin' '/bin']
vcs detect some/arg'# | str replace "__STUBDIR__" $vcs_stub)
let result = (nu-run $vcs_detect_snippet)
assert-contains "nu bare vcs resolves to ^vcs via PATH" "vcs-stub: detect some/arg" $result

###############
# TEST: is-env-set handles missing, empty, and set values.
# Regression coverage for the `get -o` flag that used to break on nu 0.105+.
let result = (nu-run r#'
hide-env --ignore-errors NU_TOTALLY_UNSET
if (is-env-set "NU_TOTALLY_UNSET") { print -n y } else { print -n n }'#)
assert-equal "nu is-env-set false when missing from env" r#'n'# $result

###############
# TEST: config.nu does not ship a manual `source` for local overrides;
# users drop files in ~/.config/nushell/autoload/, which nushell
# auto-sources. Missing directory is not an error -- covered implicitly
# by every other test in this file (no autoload dir under the fake HOME).
assert-true "nu config.nu has no manual source statement" (not ((open --raw $env.CONFIG_NU | lines) | any {|line| $line | str starts-with "source "}))

    let ok = (test-summary "nushell shrc_nushell_test")
    ^rm -rf $env.TESTDIR
    if not $ok {
        exit 1
    }
}
