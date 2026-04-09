#!/usr/bin/env nu
# Tests for config/nushell/config.nu.
# Native Nushell port of shrc_nushell_test.sh.
#
# Run with:
#   echo | nu shrc_nushell_test.nu
# (Stdin must not be a terminal so config.nu's is-interactive guard fires.
#  The Makefile pipes an empty line automatically.)

const script_dir = (path self | path dirname)
const config_path = ($script_dir | path join "config" "nushell" "config.nu")

source $config_path

# ── Test helpers ──────────────────────────────────────────────────────────────

$env.NU_TEST_PASSES = 0
$env.NU_TEST_FAILURES = 0

def --env assert-equal [label: string, expected: any, actual: any] {
    if $expected == $actual {
        $env.NU_TEST_PASSES += 1
    } else {
        print $"FAIL: ($label)"
        print $"  expected: ($expected)"
        print $"  actual:   ($actual)"
        $env.NU_TEST_FAILURES += 1
    }
}

def --env assert-contains [label: string, needle: string, haystack: string] {
    if ($haystack | str contains $needle) {
        $env.NU_TEST_PASSES += 1
    } else {
        print $"FAIL: ($label)"
        print $"  expected to contain: ($needle)"
        print $"  actual:   ($haystack)"
        $env.NU_TEST_FAILURES += 1
    }
}

def --env assert-not-contains [label: string, needle: string, haystack: string] {
    if not ($haystack | str contains $needle) {
        $env.NU_TEST_PASSES += 1
    } else {
        print $"FAIL: ($label)"
        print $"  expected not to contain: ($needle)"
        print $"  actual:   ($haystack)"
        $env.NU_TEST_FAILURES += 1
    }
}

def --env assert-true [label: string, condition: bool] {
    if $condition {
        $env.NU_TEST_PASSES += 1
    } else {
        print $"FAIL: ($label)"
        $env.NU_TEST_FAILURES += 1
    }
}

def test-summary [name: string] {
    let f = $env.NU_TEST_FAILURES
    let p = $env.NU_TEST_PASSES
    print ""
    if $f == 0 {
        print $"($name): all ($p) tests passed."
    } else {
        print $"($name): ($f) test(s) failed, ($p) passed."
        exit 1
    }
}

# Shared temp directory.
let _testdir = (mktemp -d | str trim)

# Helper: run a snippet via a fresh nu subprocess with stdin piped in.
# Used for tests that interact with stdin (confirm, clone fallback) or
# that need to capture `print` output from internal commands.
# The full path to config.nu is baked in via $config_path.
def nu-run-stdin [snippet: string, stdin_text: string] {
    $stdin_text | NO_COLOR=1 TERM=dumb SHPOOL_SESSION_NAME= TMUX= SSH_CONNECTION= DISPLAY= ^nu --no-config-file --stdin --commands $"source ($config_path); ($snippet)"
}

# Helper: run a snippet with no stdin (empty pipe so is-interactive fires false).
def nu-run [snippet: string] {
    nu-run-stdin $snippet ""
}

# Helper: run a snippet capturing both stdout and stderr (merged).  Used for
# tests that check error messages sent to stderr.
def nu-run-2>&1 [snippet: string] {
    "" | NO_COLOR=1 TERM=dumb SHPOOL_SESSION_NAME= TMUX= SSH_CONNECTION= DISPLAY= ^nu --no-config-file --stdin --commands $"source ($config_path); ($snippet)" e>| str join
}

# ── Tests ─────────────────────────────────────────────────────────────────────

###############
# TEST: bar prints N separator characters
assert-equal "nu bar prints N separators" "―――――" (bar 5)
assert-equal "nu bar 0 prints empty" "" (bar 0)

###############
# TEST: maybe-space
assert-equal "nu maybe-space with content" " hello" (maybe-space "hello")
assert-equal "nu maybe-space with empty" "" (maybe-space "")
assert-equal "nu maybe-space with no args" "" (maybe-space)

###############
# TEST: format-duration
assert-equal "nu format-duration 0s is empty" "" (format-duration 0sec)
assert-equal "nu format-duration 1s is empty (shrc rounds down)" "" (format-duration 1sec)
assert-equal "nu format-duration 5s" "5 seconds" (format-duration 5sec)
assert-equal "nu format-duration 2m5s" "2 minutes 5 seconds" (format-duration 125sec)
assert-equal "nu format-duration 1h2m3s" "1 hours 2 minutes 3 seconds" (format-duration 3723sec)

###############
# TEST: ps1-character
# When not root, shows '>'. When root (UID=0), shows '#'.
assert-equal "nu ps1-character non-root" ">" (do { $env.UID = 1000; ps1-character })
assert-equal "nu ps1-character root" "#" (do { $env.UID = 0; ps1-character })

###############
# TEST: have-command / is-runnable
assert-equal "nu have-command sh is true" "yes" (if (have-command "sh") { "yes" } else { "no" })
assert-equal "nu have-command bogus is false" "no" (if (have-command "zzzzznotacommand") { "yes" } else { "no" })
assert-equal "nu is-runnable custom command" "yes" (if (is-runnable "bar") { "yes" } else { "no" })

# have-command must also reject a non-executable file that happens to sit
# in a PATH directory with the right name. The earlier `path exists`-only
# implementation returned true here, masking the fact that the file
# isn't runnable.
let _hcdir = ($_testdir | path join "have_cmd_nonexec")
mkdir $_hcdir
touch ($_hcdir | path join "fakecmd")
^chmod 644 ($_hcdir | path join "fakecmd")
assert-equal "nu have-command rejects non-executable file in PATH" "no" (do {
    $env.PATH = [$_hcdir]
    if (have-command "fakecmd") { "yes" } else { "no" }
})
^chmod +x ($_hcdir | path join "fakecmd")
assert-equal "nu have-command accepts executable file in PATH" "yes" (do {
    $env.PATH = [$_hcdir]
    if (have-command "fakecmd") { "yes" } else { "no" }
})

###############
# TEST: inpath
assert-equal "nu inpath true when in PATH" "yes" (do {
    $env.PATH = ["/usr/bin" "/bin"]
    if (inpath "/usr/bin") { "yes" } else { "no" }
})
assert-equal "nu inpath false when not in PATH" "no" (do {
    $env.PATH = ["/usr/bin" "/bin"]
    if (inpath "/tmp") { "yes" } else { "no" }
})

###############
# TEST: prepend-path / append-path / delete-path / add-path
# Use /tmp and /var as existing directories.
assert-equal "nu prepend-path existing dir" "/tmp:/usr/bin" (do {
    $env.PATH = ["/usr/bin"]
    prepend-path "/tmp"
    $env.PATH | str join ":"
})
assert-equal "nu prepend-path ignores missing" "/usr/bin" (do {
    $env.PATH = ["/usr/bin"]
    prepend-path "/definitely/not/a/real/dir"
    $env.PATH | str join ":"
})
assert-equal "nu append-path existing dir" "/usr/bin:/tmp" (do {
    $env.PATH = ["/usr/bin"]
    append-path "/tmp"
    $env.PATH | str join ":"
})
assert-equal "nu delete-path removes entry" "/usr/bin:/bin" (do {
    $env.PATH = ["/usr/bin" "/tmp" "/bin"]
    delete-path "/tmp"
    $env.PATH | str join ":"
})
assert-equal "nu add-path moves existing to start" "/tmp:/usr/bin" (do {
    $env.PATH = ["/usr/bin" "/tmp"]
    add-path "/tmp" "start"
    $env.PATH | str join ":"
})
assert-equal "nu add-path moves existing to end" "/usr/bin:/tmp" (do {
    $env.PATH = ["/tmp" "/usr/bin"]
    add-path "/tmp" "end"
    $env.PATH | str join ":"
})
assert-equal "nu add-path default appends if missing" "/usr/bin:/var" (do {
    $env.PATH = ["/usr/bin"]
    add-path "/var"
    $env.PATH | str join ":"
})
assert-equal "nu add-path default no-op when present" "/var:/usr/bin" (do {
    $env.PATH = ["/var" "/usr/bin"]
    add-path "/var"
    $env.PATH | str join ":"
})

###############
# TEST: short-hostname
assert-equal "nu short-hostname strips user prefix and domain" "workstation" (do {
    $env.HOSTNAME = "mikel-workstation.example.com"
    $env.USERNAME = "mikel"
    short-hostname
})
assert-equal "nu short-hostname without user prefix" "edgehost" (do {
    $env.HOSTNAME = "edgehost.example.com"
    $env.USERNAME = "mikel"
    short-hostname
})

###############
# TEST: is-env-set
assert-equal "nu is-env-set false when unset" "no" (do {
    hide-env --ignore-errors NU_TEST_VAR
    if (is-env-set "NU_TEST_VAR") { "yes" } else { "no" }
})
assert-equal "nu is-env-set false when empty string" "no" (do {
    $env.NU_TEST_VAR = ""
    if (is-env-set "NU_TEST_VAR") { "yes" } else { "no" }
})
assert-equal "nu is-env-set true when set to non-empty" "yes" (do {
    $env.NU_TEST_VAR = "value"
    if (is-env-set "NU_TEST_VAR") { "yes" } else { "no" }
})

###############
# TEST: in-shpool
assert-equal "nu in-shpool false when unset" "no" (do {
    hide-env --ignore-errors SHPOOL_SESSION_NAME
    if (in-shpool) { "yes" } else { "no" }
})
assert-equal "nu in-shpool true when SHPOOL_SESSION_NAME set" "yes" (do {
    $env.SHPOOL_SESSION_NAME = "main"
    if (in-shpool) { "yes" } else { "no" }
})

###############
# TEST: session-name
assert-equal "nu session-name empty when no pool/tmux" "" (do {
    hide-env --ignore-errors SHPOOL_SESSION_NAME
    hide-env --ignore-errors TMUX
    session-name
})
assert-equal "nu session-name returns shpool session" "edge1 " (do {
    $env.SHPOOL_SESSION_NAME = "edge1"
    session-name
})

###############
# TEST: on-my-workstation / on-my-laptop / on-production-host
assert-equal "nu on-my-workstation user-prefixed host" "yes" (do {
    $env.HOSTNAME = "mikel-workstation"
    $env.USERNAME = "mikel"
    hide-env --ignore-errors WORKSTATION
    if (on-my-workstation) { "yes" } else { "no" }
})
assert-equal "nu on-my-workstation laptop is false" "no" (do {
    $env.HOSTNAME = "mikel-laptop"
    $env.USERNAME = "mikel"
    hide-env --ignore-errors WORKSTATION
    if (on-my-workstation) { "yes" } else { "no" }
})
assert-equal "nu on-my-laptop laptop hostname" "yes" (do {
    $env.HOSTNAME = "mikel-laptop"
    if (on-my-laptop) { "yes" } else { "no" }
})
assert-equal "nu on-production-host true for unknown host" "yes" (do {
    $env.HOSTNAME = "prodhost"
    $env.USERNAME = "mikel"
    hide-env --ignore-errors WORKSTATION
    if (on-production-host) { "yes" } else { "no" }
})
assert-equal "nu on-production-host false on my workstation" "no" (do {
    $env.HOSTNAME = "mikel-workstation"
    $env.USERNAME = "mikel"
    hide-env --ignore-errors WORKSTATION
    if (on-production-host) { "yes" } else { "no" }
})

###############
# TEST: title respects inside-tmux
# Outside tmux/shpool, show "<host> <pwd_basename>".
let _titlebase = ($_testdir | path join "nufakehome")
mkdir $_titlebase
mkdir ($_titlebase | path join "titletest")
assert-equal "nu title shows hostname outside tmux" "laptop titletest" (do {
    $env.HOME = $_titlebase
    $env.HOSTNAME = "mikel-laptop"
    $env.USERNAME = "mikel"
    hide-env --ignore-errors TMUX
    hide-env --ignore-errors SHPOOL_SESSION_NAME
    cd ($_titlebase | path join "titletest")
    title
})
let _title_in_tmux = (do {
    $env.HOME = $_titlebase
    $env.HOSTNAME = "mikel-laptop"
    $env.USERNAME = "mikel"
    $env.TMUX = "/fake/tmux/socket"
    $env.SHPOOL_SESSION_NAME = "main"
    cd ($_titlebase | path join "titletest")
    title
})
assert-contains "nu title hides hostname in tmux" "main" $_title_in_tmux
assert-not-contains "nu title hides hostname in tmux - no host" "laptop " $_title_in_tmux

###############
# TEST: prompt-line fallback when vcs is missing
# With no `vcs` command, prompt-line should fall back to a simple
# "hostname [session ]pwd" string.
assert-contains "nu prompt-line fallback has hostname" "laptop" (do {
    $env.HOSTNAME = "mikel-laptop"
    $env.USERNAME = "mikel"
    $env.HOME = $_titlebase
    hide-env --ignore-errors TMUX
    hide-env --ignore-errors SHPOOL_SESSION_NAME
    $env.PATH = []
    cd $_titlebase
    prompt-line
})

###############
# TEST: render-prompt structure matches shrc preprompt
# A leading newline, a separator bar, a CR, the prompt line, newline, and
# the prompt character followed by a space. Drive it with empty PATH so
# prompt-line uses its fallback (no `vcs` binary on PATH).
let _rp1 = (do {
    $env.HOSTNAME = "mikel-laptop"
    $env.USERNAME = "mikel"
    $env.UID = 1000
    $env.HOME = $_titlebase
    hide-env --ignore-errors TMUX
    hide-env --ignore-errors SHPOOL_SESSION_NAME
    $env.PATH = []
    cd $_titlebase
    render-prompt
})
assert-contains "nu render-prompt contains separator" "―" $_rp1
assert-contains "nu render-prompt contains hostname in prompt line" "laptop" $_rp1
assert-contains "nu render-prompt ends with > prompt" "> " $_rp1

# And with UID=0, the prompt character should be #.
let _rp_root = (do {
    $env.HOSTNAME = "mikel-laptop"
    $env.USERNAME = "mikel"
    $env.UID = 0
    $env.HOME = $_titlebase
    hide-env --ignore-errors TMUX
    hide-env --ignore-errors SHPOOL_SESSION_NAME
    $env.PATH = []
    cd $_titlebase
    render-prompt
})
assert-contains "nu render-prompt as root ends with # prompt" "# " $_rp_root

###############
# TEST: find-up climbs the tree
let _fu_base = ($_testdir | path join "nufakehome2")
mkdir $_fu_base
mkdir ($_fu_base | path join "a" "b" "c")
"marker" | save --force ($_fu_base | path join "a" "marker")
let _fu_result = (do {
    $env.HOME = $_fu_base
    cd ($_fu_base | path join "a" "b" "c")
    find-up "marker"
})
assert-contains "nu find-up finds ancestor file" "marker" $_fu_result

###############
# TEST: mcd creates and enters a directory
let _mcd_base = ($_testdir | path join "mcd_home")
mkdir $_mcd_base
assert-contains "nu mcd enters the new directory" "newdir" (do {
    $env.HOME = $_mcd_base
    cd $_mcd_base
    mcd newdir
    $env.PWD
})

# And if the target already exists, mcd prints a message and does not crash.
mkdir ($_mcd_base | path join "existing-dir")
assert-contains "nu mcd reports when target already exists" "already exists" (nu-run $"
\$env.HOME = '($_mcd_base)'
cd '($_mcd_base)'
mcd existing-dir")

###############
# TEST: mtd creates a fresh temp dir and cds into it
let _mtd_result = (do {
    let start = $env.PWD
    mtd
    $"($env.PWD)|($start)"
})
let _mtd_parts = $_mtd_result | split row "|"
assert-true "nu mtd cds into a /tmp subdirectory" (($_mtd_parts | first) | str starts-with "/tmp/")

###############
# TEST: cdfile / realdir resolve symlinks to the real containing directory
let _cd_base = ($_testdir | path join "cdfile_home")
mkdir ($_cd_base | path join "target")
"hello" | save --force ($_cd_base | path join "target" "file.txt")
^ln -s ($_cd_base | path join "target") ($_cd_base | path join "link")
let _realdir_result = (do {
    $env.HOME = $_cd_base
    realdir ($_cd_base | path join "link" "file.txt")
})
assert-contains "nu realdir resolves symlink to real dir" "/target" $_realdir_result

let _cdfile_result = (do {
    $env.HOME = $_cd_base
    mkdir ($_cd_base | path join "cdfile-target")
    "x" | save --force ($_cd_base | path join "cdfile-target" "file.txt")
    cdfile ($_cd_base | path join "cdfile-target" "file.txt")
    $env.PWD
})
assert-contains "nu cdfile cds to the file's real directory" "cdfile-target" $_cdfile_result

###############
# TEST: gh-search greps $HOME/.history
let _gh_home = ($_testdir | path join "gh_home")
mkdir $_gh_home
assert-contains "nu gh-search finds a matching line" "alpha beta gamma" (do {
    $env.HOME = $_gh_home
    "one two three\nalpha beta gamma\none four five" | save --force ($_gh_home | path join ".history")
    gh-search "alpha"
})

# rh (gh-search | last 20) should return at most the last 20 matches.
assert-equal "nu rh limits gh-search output to 20 lines" 20 (do {
    $env.HOME = $_gh_home
    let lines = (1..25 | each {|i| $"match line ($i)"} | str join (char newline))
    $lines | save --force ($_gh_home | path join ".history")
    rh "match" | length
})

###############
# TEST: confirm reads a yes/no answer from stdin.
# These tests need subprocess stdin injection.
assert-contains "nu confirm yes on y" "<true>" (nu-run-stdin 'let r = (confirm "go"); print -n $" <($r)>"' "y\n")
assert-contains "nu confirm yes on Y (uppercase)" "<true>" (nu-run-stdin 'let r = (confirm "go"); print -n $" <($r)>"' "Y\n")
assert-contains "nu confirm yes on yes" "<true>" (nu-run-stdin 'let r = (confirm "go"); print -n $" <($r)>"' "yes\n")
assert-contains "nu confirm no on n" "<false>" (nu-run-stdin 'let r = (confirm "go"); print -n $" <($r)>"' "n\n")
assert-contains "nu confirm no on no" "<false>" (nu-run-stdin 'let r = (confirm "go"); print -n $" <($r)>"' "no\n")
assert-contains "nu confirm defaults to yes on empty reply" "<true>" (nu-run-stdin 'let r = (confirm "go"); print -n $" <($r)>"' "\n")
assert-contains "nu confirm treats non-y reply as no" "<false>" (nu-run-stdin 'let r = (confirm "go"); print -n $" <($r)>"' "maybe\n")

###############
# TEST: clone dispatch
# Stub jj/git/hg as scripts on PATH so we can verify which one was invoked.
let _stubdir = ($_testdir | path join "clone_stubs")
let _stubdir_nojj = ($_testdir | path join "clone_stubs_nojj")
mkdir $_stubdir
mkdir $_stubdir_nojj
for _cmd in ["jj" "git" "hg"] {
    $"#!/bin/sh\necho \"($_cmd) \$*\"\n" | save --force ($_stubdir | path join $_cmd)
    ^chmod +x ($_stubdir | path join $_cmd)
}
# nojj variant: same scripts, but no jj
^cp ($_stubdir | path join "git") ($_stubdir_nojj | path join "git")
^cp ($_stubdir | path join "hg") ($_stubdir_nojj | path join "hg")
^chmod +x ($_stubdir_nojj | path join "git")
^chmod +x ($_stubdir_nojj | path join "hg")

assert-equal "nu clone .git uses jj git clone when jj available" "jj git clone https://github.com/foo/bar.git" (do {
    $env.PATH = [$_stubdir "/usr/bin" "/bin"]
    clone "https://github.com/foo/bar.git"
} | str trim | str replace --all "\n" "")

assert-equal "nu clone /hg/ uses hg clone" "hg clone https://hg.example.com/hg/repo" (do {
    $env.PATH = [$_stubdir "/usr/bin" "/bin"]
    clone "https://hg.example.com/hg/repo"
} | str trim | str replace --all "\n" "")

# When jj isn't on PATH, clone should prompt and fall back to git on yes.
let _clone_nojj_yes = (nu-run-stdin $"
\$env.PATH = ['($_stubdir_nojj)' '/usr/bin' '/bin']
clone 'https://github.com/foo/bar.git'" "y")
assert-contains "nu clone falls back to git when jj missing and user says yes" "git clone https://github.com/foo/bar.git" ($_clone_nojj_yes | str trim | str replace --all "\n" "")

# When the user declines the fallback, no clone command runs.
let _clone_nojj_no = (nu-run-stdin $"
\$env.PATH = ['($_stubdir_nojj)' '/usr/bin' '/bin']
clone 'https://github.com/foo/bar.git'" "n")
assert-not-contains "nu clone aborts when user declines git fallback" "git clone" ($_clone_nojj_no | str trim | str replace --all "\n" "")

###############
# TEST: CDPATH is set and does not include conf/ subdirectories
let _cdpath_str = ($env.CDPATH | str join ":")
assert-contains "nu CDPATH contains HOME" $env.HOME $_cdpath_str
assert-not-contains "nu CDPATH does not contain conf" ($"($env.HOME)/conf") $_cdpath_str

###############
# TEST: trailing-slash autocd is provided by nushell's native REPL path
# handling, not by any command_not_found hook of ours. We do install a
# pre_execution hook for command-duration tracking (covered separately
# below); the assertion here is just that no autocd hook is installed.
assert-equal "nu command_not_found hook is not set" "nothing" ($env.config.hooks.command_not_found | describe)

# TEST: `cd` into a trailing-slash path works (sanity check for the
# `cd ./foo/` fallback users can type explicitly).
let _cdtest_base = ($_testdir | path join "cdtest_home")
mkdir ($_cdtest_base | path join "cdtest" "sub")
assert-contains "nu cd with trailing slash enters directory" "cdtest/sub" (do {
    $env.HOME = $_cdtest_base
    cd ($_cdtest_base | path join "cdtest")
    cd ./sub/
    $env.PWD
})

###############
# TEST: last-job-info shows nothing when no command has run
assert-equal "nu last-job-info empty when CMD_DURATION unset" "" (do {
    hide-env --ignore-errors CMD_DURATION
    last-job-info
})

# And nothing when the duration is below the display threshold.
assert-equal "nu last-job-info empty for 0sec" "" (do {
    $env.CMD_DURATION = 0sec
    last-job-info
})
assert-equal "nu last-job-info empty for 1sec (rounds down)" "" (do {
    $env.CMD_DURATION = 1sec
    last-job-info
})

# With a meaningful duration it should contain the formatted text.
assert-contains "nu last-job-info shows took for 5sec" "took 5 seconds" (do {
    $env.CMD_DURATION = 5sec
    last-job-info
})
assert-contains "nu last-job-info shows hours for 1hr" "1 hours" (do {
    $env.CMD_DURATION = 1hr
    last-job-info
})

###############
# TEST: title-escape wraps the title in an OSC 0 sequence for xterm,
# and returns empty for non-xterm-family terminals.
assert-contains "nu title-escape includes OSC 0 on xterm" "]0;my title" (do {
    $env.TERM = "xterm-256color"
    title-escape "my title"
})
assert-equal "nu title-escape empty on dumb terminal" "" (do {
    $env.TERM = "dumb"
    title-escape "my title"
})
assert-contains "nu title-escape supports rxvt" "]0;hi" (do {
    $env.TERM = "rxvt-unicode"
    title-escape "hi"
})

###############
# TEST: flash-terminal returns the BEL char on xterm, empty elsewhere.
let _flash_xterm = (do {
    $env.TERM = "xterm-256color"
    $"(flash-terminal)END"
})
assert-true "nu flash-terminal rings bell on xterm" ($_flash_xterm | str ends-with $"(char bel)END")

assert-equal "nu flash-terminal empty on dumb terminal" "" (do {
    $env.TERM = "dumb"
    flash-terminal
})

###############
# TEST: render-prompt includes the title escape and bell when TERM=xterm.
assert-contains "nu render-prompt sets xterm title" "]0;" (do {
    $env.HOSTNAME = "mikel-laptop"
    $env.USERNAME = "mikel"
    $env.UID = 1000
    $env.HOME = $_titlebase
    $env.TERM = "xterm-256color"
    hide-env --ignore-errors TMUX
    hide-env --ignore-errors SHPOOL_SESSION_NAME
    $env.PATH = []
    cd $_titlebase
    render-prompt
})

# And the duration line when CMD_DURATION is populated.
assert-contains "nu render-prompt includes duration line" "took 5 seconds" (do {
    $env.HOSTNAME = "mikel-laptop"
    $env.USERNAME = "mikel"
    $env.UID = 1000
    $env.HOME = $_titlebase
    $env.TERM = "dumb"
    $env.CMD_DURATION = 5sec
    hide-env --ignore-errors TMUX
    hide-env --ignore-errors SHPOOL_SESSION_NAME
    $env.PATH = []
    cd $_titlebase
    render-prompt
})

###############
# TEST: pre_execution / pre_prompt hooks are installed and track timing.
assert-equal "nu pre_execution hook list has one entry" 1 ($env.config.hooks.pre_execution | length)
assert-equal "nu pre_prompt hook list has one entry" 1 ($env.config.hooks.pre_prompt | length)

# Invoke the hook closures directly and verify CMD_DURATION gets set to
# a non-zero duration when pre_execution has recorded a start time.
# do --env propagates the closure's $env mutations back to the caller,
# matching how nushell itself invokes hooks.
let _timing_result = (do {
    do --env ($env.config.hooks.pre_execution | first)
    ^sleep 2.1
    do --env ($env.config.hooks.pre_prompt | first)
    format-duration $env.CMD_DURATION
})
assert-contains "nu timing hooks populate CMD_DURATION" "seconds" $_timing_result

# When pre_execution did not fire, pre_prompt zeroes CMD_DURATION.
assert-equal "nu pre_prompt clears stale CMD_DURATION" 0 (do {
    hide-env --ignore-errors CMD_START_TIME
    hide-env --ignore-errors CMD_DURATION
    do --env ($env.config.hooks.pre_prompt | first)
    $env.CMD_DURATION | into int
})

###############
# TEST: auth helpers respond to ssh-add's exit status.
let _authstub_ok = ($_testdir | path join "auth_stub_ok")
let _authstub_fail = ($_testdir | path join "auth_stub_fail")
mkdir $_authstub_ok
mkdir $_authstub_fail
"#!/bin/sh\nexit 0\n" | save --force ($_authstub_ok | path join "ssh-add")
"#!/bin/sh\necho \"no agent\" >&2\nexit 2\n" | save --force ($_authstub_fail | path join "ssh-add")
^chmod +x ($_authstub_ok | path join "ssh-add")
^chmod +x ($_authstub_fail | path join "ssh-add")

assert-equal "nu is-ssh-valid true when ssh-add succeeds" "true" (do {
    $env.PATH = [$_authstub_ok "/usr/bin" "/bin"]
    is-ssh-valid | into string
})
assert-equal "nu is-ssh-valid false when ssh-add fails" "false" (do {
    $env.PATH = [$_authstub_fail "/usr/bin" "/bin"]
    is-ssh-valid | into string
})
assert-equal "nu need-auth false when ssh-add succeeds" "false" (do {
    $env.PATH = [$_authstub_ok "/usr/bin" "/bin"]
    need-auth | into string
})
assert-equal "nu need-auth true when ssh-add fails" "true" (do {
    $env.PATH = [$_authstub_fail "/usr/bin" "/bin"]
    need-auth | into string
})

# auth-info should include the "SSH" token on failure (ANSI-wrapped).
assert-contains "nu auth-info reports SSH on failure" "SSH" (do {
    $env.PATH = [$_authstub_fail "/usr/bin" "/bin"]
    do $env.auth-info
})

# And be empty on success.
assert-equal "nu auth-info empty on success" "" (do {
    $env.PATH = [$_authstub_ok "/usr/bin" "/bin"]
    do $env.auth-info
})

###############
# TEST: overridable hook points.
# config.nu exposes four hooks as closures in $env so that autoload files
# can override them and have the change propagate through every caller
# inside config.nu (nushell resolves def-to-def calls at parse time, so a
# plain `def` redefinition in an autoload file would NOT propagate).
# Each hook is smoke-tested here: override the closure and check that a
# downstream caller sees the new value.

# $env.auth: the `auth` wrapper should dispatch through it.
assert-equal "nu auth wrapper dispatches through $env.auth" "custom-auth-called" (do {
    $env.auth = {|| "custom-auth-called" }
    auth
})

# $env.with-agent: wsh/wcp are defined in config.nu and should pick up
# the override. Their bodies are `with-agent ssh ...` / `with-agent scp ...`.
assert-equal "nu wsh dispatches through $env.with-agent" "ssh|host|arg" (do {
    $env."with-agent" = {|...cmd| $cmd | str join "|" }
    wsh host arg
})
assert-equal "nu wcp dispatches through $env.with-agent" "scp|src|dst" (do {
    $env."with-agent" = {|...cmd| $cmd | str join "|" }
    wcp src dst
})

# $env.on-production-host: overriding it must flip the result even on a
# hostname that the default logic would classify as production.
assert-equal "nu on-production-host override wins over default" "no" (do {
    $env.HOSTNAME = "prodhost"
    $env.USERNAME = "mikel"
    hide-env --ignore-errors WORKSTATION
    $env."on-production-host" = {|| false }
    if (on-production-host) { "yes" } else { "no" }
})

# And the reverse: flip a workstation hostname to production via the hook.
assert-equal "nu on-production-host override flips workstation to prod" "yes" (do {
    $env.HOSTNAME = "mikel-workstation"
    $env.USERNAME = "mikel"
    hide-env --ignore-errors WORKSTATION
    $env."on-production-host" = {|| true }
    if (on-production-host) { "yes" } else { "no" }
})

###############
# TEST: bak / unbak roundtrip.
let _bak_home = ($_testdir | path join "bak_home")
mkdir $_bak_home
assert-equal "nu bak creates .bak file" "baktest.bak" (do {
    $env.HOME = $_bak_home
    cd $_bak_home
    if ("baktest" | path exists) { ^rm -f "baktest" }
    if ("baktest.bak" | path exists) { ^rm -f "baktest.bak" }
    "hello" | save --force "baktest"
    bak "baktest"
    ls baktest* | get name | path basename | sort | str join ","
})

assert-equal "nu unbak restores original" "baktest|hello" (do {
    $env.HOME = $_bak_home
    cd $_bak_home
    if ("baktest" | path exists) { ^rm -f "baktest" }
    if ("baktest.bak" | path exists) { ^rm -f "baktest.bak" }
    "hello" | save --force "baktest"
    bak "baktest"
    unbak "baktest.bak"
    let names = (ls baktest* | get name | path basename | sort | str join ",")
    let content = (open "baktest")
    $"($names)|($content)"
})

# unbak handles short names: the old `0..(-4)` substring math was
# off-by-one and dropped only three chars. This tests a short filename
# where the old and new implementations differ.
assert-equal "nu unbak short filename roundtrip" "x" (do {
    $env.HOME = $_bak_home
    cd $_bak_home
    if ("shortbak" | path exists) { ^rm -f "shortbak" }
    if ("shortbak.bak" | path exists) { ^rm -f "shortbak.bak" }
    "x" | save --force "shortbak"
    bak "shortbak"
    unbak "shortbak.bak"
    open "shortbak"
})

###############
# TEST: log-history appends timestamped entries to HISTORY_FILE
let _loghist_home = ($_testdir | path join "loghist_home")
mkdir $_loghist_home
let _log_result = (do {
    $env.HOME = $_loghist_home
    $env.HISTORY_FILE = ($_loghist_home | path join "history.log")
    $env.TTY = "/dev/pts/42"
    log-history "hello world"
    open --raw $env.HISTORY_FILE | str trim
})
assert-contains "nu log-history writes argv" "hello world" $_log_result
assert-contains "nu log-history writes tty" "/dev/pts/42" $_log_result

# log-history no-ops when HISTORY_FILE is empty
assert-equal "nu log-history no-op when HISTORY_FILE empty" "done" (do {
    $env.HISTORY_FILE = ""
    log-history "ignored"
    "done"
})

# log-history also no-ops when HISTORY_FILE unset entirely
assert-equal "nu log-history no-op when HISTORY_FILE unset" "done" (do {
    hide-env --ignore-errors HISTORY_FILE
    log-history "ignored"
    "done"
})

###############
# TEST: inside-project / want-shpool / maybe-start-shpool-and-exit
# Override projectroot to "" so these tests are independent of whether
# the `vcs` binary happens to be installed on the host or whether $PWD
# happens to sit inside a repo.
assert-equal "nu inside-project false when projectroot is empty" "no" (do {
    $env.projectroot = {|| "" }
    if (inside-project) { "yes" } else { "no" }
})

# want-shpool: false when neither remote nor inside project.
assert-equal "nu want-shpool false when not remote and not in project" "no" (do {
    $env.projectroot = {|| "" }
    hide-env --ignore-errors SSH_CONNECTION
    if (want-shpool) { "yes" } else { "no" }
})

# want-shpool: true when SSH_CONNECTION is set (remote).
assert-equal "nu want-shpool true when remote" "yes" (do {
    $env.SSH_CONNECTION = "1.2.3.4 22 5.6.7.8 22"
    if (want-shpool) { "yes" } else { "no" }
})

# Overriding `$env.projectroot` propagates through the whole
# inside-project/want-shpool/projectname/buildroot chain because
# config.nu defines `projectroot` as `do $env.projectroot` (see the
# comment block at the bottom of config.nu for the full explanation).
assert-equal "nu inside-project true when projectroot override returns non-empty" "yes" (do {
    $env.projectroot = {|| "/fake/project" }
    if (inside-project) { "yes" } else { "no" }
})

assert-equal "nu want-shpool true when projectroot override is non-empty" "yes" (do {
    $env.projectroot = {|| "/fake/project" }
    hide-env --ignore-errors SSH_CONNECTION
    if (want-shpool) { "yes" } else { "no" }
})

assert-equal "nu projectname picks up projectroot override" "myrepo" (do {
    $env.projectroot = {|| "/srv/code/myrepo" }
    projectname
})

assert-equal "nu buildroot picks up projectroot override" "/srv/code/myrepo" (do {
    $env.projectroot = {|| "/srv/code/myrepo" }
    buildroot
})

# maybe-start-shpool-and-exit is a no-op when shpool is not on PATH, even if
# the other conditions would otherwise fire. The test simply asserts that
# calling it returns normally (no exit/crash).
assert-equal "nu maybe-start-shpool-and-exit no-op without shpool" "returned" (do {
    $env.PATH = []
    $env.SSH_CONNECTION = "1.2.3.4 22"
    hide-env --ignore-errors SHPOOL_SESSION_NAME
    maybe-start-shpool-and-exit
    "returned"
})

###############
# TEST: projectroot default behavior
# When the `vcs` helper binary is on PATH, projectroot shells out to
# `vcs rootdir` and returns its stdout. Stub `vcs` so the test doesn't
# depend on the real binary being checked out.
let _vcs_root_stub = ($_testdir | path join "vcs_root_stub")
mkdir $_vcs_root_stub
"#!/bin/sh\ncase \"$1\" in\n    rootdir) echo /fake/from/vcs/binary ;;\n    *) exit 1 ;;\nesac\n" | save --force ($_vcs_root_stub | path join "vcs")
^chmod +x ($_vcs_root_stub | path join "vcs")

assert-equal "nu projectroot shells out to vcs rootdir when binary present" "/fake/from/vcs/binary" (do {
    $env.PATH = [$_vcs_root_stub "/usr/bin" "/bin"]
    projectroot
})

# When `vcs rootdir` exits nonzero (not inside a project), projectroot
# returns "" rather than surfacing the error.
let _vcs_fail_stub = ($_testdir | path join "vcs_fail_stub")
mkdir $_vcs_fail_stub
"#!/bin/sh\nexit 1\n" | save --force ($_vcs_fail_stub | path join "vcs")
^chmod +x ($_vcs_fail_stub | path join "vcs")

assert-equal "nu projectroot empty when vcs rootdir exits nonzero" "" (do {
    $env.PATH = [$_vcs_fail_stub "/usr/bin" "/bin"]
    projectroot
})

# Fallback: when `vcs` is not on PATH, walk parent directories looking
# for a VCS marker. .git in the current dir should be found.
let _pr_base = ($_testdir | path join "pr_home")
mkdir $_pr_base
mkdir ($_pr_base | path join "pr-git" ".git")
assert-contains "nu projectroot fallback finds .git in cwd" "pr-git" (do {
    $env.PATH = []
    $env.HOME = $_pr_base
    cd ($_pr_base | path join "pr-git")
    projectroot
})

# And should walk up through subdirectories to find the marker.
mkdir ($_pr_base | path join "pr-jj" ".jj")
mkdir ($_pr_base | path join "pr-jj" "sub" "deeper")
assert-contains "nu projectroot fallback walks up to find .jj" "pr-jj" (do {
    $env.PATH = []
    $env.HOME = $_pr_base
    cd ($_pr_base | path join "pr-jj" "sub" "deeper")
    projectroot
})

# Each of the five supported markers should be recognised.
for _marker in [".jj" ".hg" ".git" ".citc" ".p4config"] {
    let _mname = $_marker | str replace --all "." ""
    let _proj = ($_pr_base | path join $"pr-marker-($_mname)")
    mkdir ($_proj | path join $_marker)
    let _pr_result = (do {
        $env.PATH = []
        $env.HOME = $_pr_base
        cd $_proj
        projectroot
    })
    assert-contains $"nu projectroot fallback recognises ($_marker)" "pr-marker" $_pr_result
}

# inside-project, projectname, buildroot all propagate the fallback result.
mkdir ($_pr_base | path join "pr-chain" ".git")
assert-equal "nu inside-project true under fallback-detected repo" "yes" (do {
    $env.PATH = []
    $env.HOME = $_pr_base
    cd ($_pr_base | path join "pr-chain")
    if (inside-project) { "yes" } else { "no" }
})

mkdir ($_pr_base | path join "pr-name" ".git")
assert-equal "nu projectname picks up fallback projectroot" "pr-name" (do {
    $env.PATH = []
    $env.HOME = $_pr_base
    cd ($_pr_base | path join "pr-name")
    projectname
})

###############
# TEST: shift-options rearranges leading flags to come before the target.
# Nushell's parser only lets flags flow through via spread from wrappers,
# matching how fish aliases and shrc functions actually use shift_options.
assert-equal "nu shift-options moves options before target" "-a -b target rest" (do {
    def wrap [...args: string] { shift-options echo target ...$args }
    wrap "-a" "-b" "rest" | str trim
})
assert-equal "nu shift-options no options" "target rest" (do {
    def wrap [...args: string] { shift-options echo target ...$args }
    wrap "rest" | str trim
})
assert-equal "nu shift-options option only" "-x target" (do {
    def wrap [...args: string] { shift-options echo target ...$args }
    wrap "-x" | str trim
})
assert-equal "nu shift-options stops at --" "target -- -b" (do {
    def wrap [...args: string] { shift-options echo target ...$args }
    wrap "--" "-b" | str trim
})

###############
# TEST: first-arg-last guards against short arg lists.
# Before the guard, `first-arg-last echo` errored with
# nu::shell::access_beyond_end because `$args | get 1` on a 1-element
# list is out of range. 0 args is a usage error (previously a silent
# no-op, which masked caller bugs); 1 arg runs the command as-is;
# 2+ args rearrange first-to-last.
let _fal_0_result = (try { first-arg-last; "noerror" } catch { |e| $e.msg })
assert-contains "nu first-arg-last 0 args raises usage error" "usage" $_fal_0_result
assert-not-contains "nu first-arg-last 0 args does not silently pass" "noerror" $_fal_0_result

assert-equal "nu first-arg-last 1 arg runs the command" "" (first-arg-last echo | str trim)
assert-equal "nu first-arg-last 2 args runs command with arg" "only" (first-arg-last echo only | str trim)
assert-equal "nu first-arg-last moves first positional to end" "tail history.file" (first-arg-last echo history.file tail | str trim)

###############
# TEST: which-path handles empty `which` results without crashing.
# Before the is-empty guard, `get 0.path?` on an empty list errored
# with nu::shell::access_beyond_end (the `?` only makes the column
# optional, not the row index).
# which-path uses `print`, so capture via subprocess.
assert-contains "nu which-path prints path for a known command" "sh" (nu-run "which-path sh")

# An unknown command should not crash; it reports via the error stream.
assert-contains "nu which-path reports missing command" "not found" (nu-run-2>&1 "which-path zzzz-not-a-real-command-xyz")

# And explicit regression: the command should no longer raise
# nu::shell::access_beyond_end on a missing name.
assert-not-contains "nu which-path does not raise access_beyond_end" "access_beyond_end" (nu-run-2>&1 "which-path zzzz-not-a-real-command-xyz")

###############
# TEST: `what` prints the definition of a command, mirroring shrc's
# `whence -f` / fish's `type`. Before the fix it just delegated to
# `which`, which prints the type/path but not the definition.
# what uses `print`, so capture via subprocess.

# Custom def: body should appear in the output.
assert-contains "nu what prints body of a custom def" "path exists" (nu-run "what have-command")

# Alias: the alias target should appear in the output.
assert-contains "nu what prints the target of an alias" "^vcs" (nu-run "what st")

# External: the absolute path should appear in the output.
assert-contains "nu what prints path of an external command" "/sh" (nu-run "what sh")

# Missing command: reports via the error helper (stderr), doesn't crash.
assert-contains "nu what reports missing command" "not found" (nu-run-2>&1 "what zzzz-not-a-real-command-xyz")

###############
# TEST: rerc is defined and its body exec's a new nushell.
# Can't actually call rerc in the test harness (exec would replace the
# process), so verify structurally via `view source`.
assert-equal "nu rerc is defined as a custom command" "custom" (which rerc | get 0.type)
assert-true "nu rerc body exec's nu" ((view source rerc) | str contains "exec nu")

###############
# TEST: delline removes the given line in place
let _del_home = ($_testdir | path join "del_home")
mkdir $_del_home
assert-equal "nu delline removes line 2" "line1\nline3" (do {
    $env.HOME = $_del_home
    cd $_del_home
    "line1\nline2\nline3" | save --force "lines.txt"
    delline 2 "lines.txt"
    open "lines.txt" | str trim
})

###############
# TEST: body forwards the first N header lines then runs the command on the
# remaining body. Default is 1 header line.
# body uses `print $h` for headers so capture via subprocess.
assert-equal "nu body default 1-line header" "HEAD\na\nb\nc" (nu-run '"HEAD\nc\na\nb" | body sort | str trim')

# --lines 2 keeps a two-line header.
assert-equal "nu body --lines 2 preserves two headers" "H1\nH2\nx\ny\nz" (nu-run '"H1\nH2\ny\nx\nz" | body --lines 2 sort | str trim')

###############
# TEST: trydiff runs the command on the file, diffs the result, leaves the
# original untouched. Using `sort` on unsorted input guarantees a diff.
# trydiff emits diff output via an external command pipeline (to stdout);
# capture via subprocess.
let _try_home = ($_testdir | path join "trydiff_home")
mkdir $_try_home
"b\na\nc" | save --force ($_try_home | path join "t.txt")
let _trydiff_result = (nu-run $"
cd '($_try_home)'
trydiff sort t.txt
print '==='
open t.txt | str trim")
# diff output should mention the sorted rearrangement
assert-contains "nu trydiff emits a diff" "> " $_trydiff_result
# And the file should be unchanged afterwards.
assert-contains "nu trydiff leaves file untouched" "b\na\nc" $_trydiff_result

###############
# TEST: VCS aliases are defined even when the vcs binary is missing.
# The stubs shouldn't fail to parse and `which` should find them.
# `clone` remains a custom command (has real logic). The rest are now
# aliases after the def->alias conversion.
for _name in ["add" "amend" "annotate" "base" "branch" "branches" "changed"
              "changelog" "changes" "checkout" "commit" "commitforce" "diffs"
              "fix" "graph" "incoming" "lint" "map" "outgoing" "pending"
              "precommit" "presubmit" "pull" "push" "recommit" "revert"
              "review" "reword" "submit" "submitforce" "unknown" "upload"
              "uploadchain" "clone" "st" "ci" "di" "gr" "lg" "ma" "am"] {
    let _vcs_type = (which $_name | get 0.type? | default "nothing")
    assert-true $"nu vcs alias ($_name) is defined" ($_vcs_type == "custom" or $_vcs_type == "alias")
}

# Explicit: clone is the only vcs wrapper that should still be a custom
# command (it has real dispatch logic). Everything else is an alias.
assert-equal "nu clone remains a custom command" "custom" (which clone | get 0.type)

for _name in ["add" "commit" "diffs" "graph" "push" "pull" "st" "ci" "di" "gr"] {
    assert-equal $"nu ($_name) is an alias after def->alias conversion" "alias" (which $_name | get 0.type)
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
let _vcs_stub = ($_testdir | path join "vcs_stub")
mkdir $_vcs_stub
"#!/bin/sh\n# Echo all args so tests can see what the alias dispatched.\nprintf 'vcs-stub:'\nfor _a; do\n    printf ' %s' \"$_a\"\ndone\nprintf '\\n'\n" | save --force ($_vcs_stub | path join "vcs")
^chmod +x ($_vcs_stub | path join "vcs")

# Long-form: commit -m "message"
assert-contains "nu commit alias passes -m through to ^vcs" "vcs-stub: commit -m fix" (do {
    $env.PATH = [$_vcs_stub "/usr/bin" "/bin"]
    commit -m fix
})

# Short alias: ci -m "message" (the classic case that used to fail)
assert-contains "nu ci alias passes -m through to ^vcs" "vcs-stub: commit -m fix" (do {
    $env.PATH = [$_vcs_stub "/usr/bin" "/bin"]
    ci -m fix
})

# Long flag: diffs --stat
assert-contains "nu di alias passes --stat through to ^vcs" "vcs-stub: diffs --stat" (do {
    $env.PATH = [$_vcs_stub "/usr/bin" "/bin"]
    di --stat
})

# Positional + flag combo: graph --limit 10
assert-contains "nu gr alias passes --limit N through to ^vcs" "vcs-stub: graph --limit 10" (do {
    $env.PATH = [$_vcs_stub "/usr/bin" "/bin"]
    gr --limit 10
})

# Bare `vcs` at the REPL falls through to the external automatically
# (no `alias vcs = ^vcs` needed — nushell auto-resolves unknown names).
assert-contains "nu bare vcs resolves to ^vcs via PATH" "vcs-stub: detect some/arg" (do {
    $env.PATH = [$_vcs_stub "/usr/bin" "/bin"]
    vcs detect some/arg
})

###############
# TEST: is-env-set handles missing, empty, and set values.
# Regression coverage for the `get -o` flag that used to break on nu 0.105+.
assert-equal "nu is-env-set false when missing from env" "n" (do {
    hide-env --ignore-errors NU_TOTALLY_UNSET
    if (is-env-set "NU_TOTALLY_UNSET") { "y" } else { "n" }
})

###############
# TEST: config.nu does not ship a manual `source` for local overrides;
# users drop files in ~/.config/nushell/autoload/, which nushell
# auto-sources. Missing directory is not an error -- covered implicitly
# by every other test in this file (no autoload dir under the fake HOME).
let _has_source = (open --raw $config_path | lines | any {|l| $l | str starts-with "source "})
assert-true "nu config.nu has no manual source statement" (not $_has_source)

rm -rf $_testdir

test-summary "nushell shrc_nushell_test"
