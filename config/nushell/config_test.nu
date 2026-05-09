#!/usr/bin/env nu
#
# Nu-native tests for config/nushell/config.nu.
# Run with:    nu --no-config-file config/nushell/config_test.nu
#
# Each case runs inside a `do { ... }` block so env mutations are
# isolated from later cases.
#

use std/assert

# Keep config.nu from touching the real $HOME (autoload dirs, history,
# local overrides) by pointing HOME at a throwaway temp dir before we
# source it. NO_COLOR/TERM match what the bash harness sets so assertions
# don't have to strip ANSI escapes.
$env.HOME = (mktemp -d -t "nushell-test.XXXXXX")
$env.NO_COLOR = "1"
$env.TERM = "dumb"
hide-env --ignore-errors SHPOOL_SESSION_NAME
hide-env --ignore-errors TMUX
hide-env --ignore-errors SSH_CONNECTION
hide-env --ignore-errors DISPLAY

# `path self <rel>` resolves relative to THIS script's directory.
const CONFIG = path self "config.nu"
source $CONFIG

# Run one test case in an isolated env. Plain `do { ... }` does NOT
# propagate $env mutations back to the caller, so a case can freely set
# $env.UID, $env.HOSTNAME, etc. without bleeding into the next one.
# Returns "PASS: <label>" or "FAIL: <label>: <error>" so the caller can
# count failures at the end instead of aborting on the first one.
def run-test [label: string, body: closure]: nothing -> string {
    try {
        do $body
        $"PASS: ($label)"
    } catch {|e|
        $"FAIL: ($label): ($e.msg)"
    }
}

let results = [
    ###############
    # bar prints N separator characters
    (run-test "nu bar prints N separators" { assert equal (bar 5) "―――――" })
    (run-test "nu bar 0 prints empty" { assert equal (bar 0) "" })

    ###############
    # maybe-space
    (run-test "nu maybe-space with content" { assert equal (maybe-space "hello") " hello" })
    (run-test "nu maybe-space with empty" { assert equal (maybe-space "") "" })
    (run-test "nu maybe-space with no args" { assert equal (maybe-space) "" })

    ###############
    # format-duration
    (run-test "nu format-duration 0s is empty" { assert equal (format-duration 0sec) "" })
    (run-test "nu format-duration 1s is empty (shrc rounds down)" { assert equal (format-duration 1sec) "" })
    (run-test "nu format-duration 5s" { assert equal (format-duration 5sec) "5 seconds" })
    (run-test "nu format-duration 2m5s" { assert equal (format-duration 125sec) "2 minutes 5 seconds" })
    (run-test "nu format-duration 1h2m3s" { assert equal (format-duration 3723sec) "1 hours 2 minutes 3 seconds" })

    ###############
    # ps1-character: always '>' (nushell's native glyph, flagging
    # which-shell-am-I-in). When root it's still '>' but returned
    # via red(), so colour (not shape) is the root cue. The [root]
    # prefix in host-info carries the visible-without-colour cue.
    (run-test "nu ps1-character non-root" {
        $env.UID = 1000
        assert equal (ps1-character) ">"
    })
    (run-test "nu ps1-character root wraps in red" {
        $env.UID = 0
        assert str contains (ps1-character) ">"
    })

    ###############
    # have-command / is-runnable
    (run-test "nu have-command sh is true" { assert (have-command "sh") })
    (run-test "nu have-command bogus is false" { assert (not (have-command "zzzzznotacommand")) })
    (run-test "nu is-runnable custom command" { assert (is-runnable "bar") })

    ###############
    # short-hostname
    (run-test "nu short-hostname strips user prefix and domain" {
        $env.HOSTNAME = "mikel-workstation.example.com"
        $env.USERNAME = "mikel"
        assert equal (short-hostname) "workstation"
    })
    (run-test "nu short-hostname without user prefix" {
        $env.HOSTNAME = "edgehost.example.com"
        $env.USERNAME = "mikel"
        assert equal (short-hostname) "edgehost"
    })

    ###############
    # is-env-set
    (run-test "nu is-env-set false when unset" {
        hide-env --ignore-errors NU_TEST_VAR
        assert (not (is-env-set "NU_TEST_VAR"))
    })
    (run-test "nu is-env-set false when empty string" {
        $env.NU_TEST_VAR = ""
        assert (not (is-env-set "NU_TEST_VAR"))
    })
    (run-test "nu is-env-set true when set to non-empty" {
        $env.NU_TEST_VAR = "value"
        assert (is-env-set "NU_TEST_VAR")
    })

    ###############
    # in-shpool
    (run-test "nu in-shpool false when unset" {
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        assert (not (in-shpool))
    })
    (run-test "nu in-shpool true when SHPOOL_SESSION_NAME set" {
        $env.SHPOOL_SESSION_NAME = "main"
        assert (in-shpool)
    })

    ###############
    # session-name
    (run-test "nu session-name empty when no pool/tmux" {
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        hide-env --ignore-errors TMUX
        assert equal (session-name) ""
    })
    (run-test "nu session-name returns shpool session" {
        $env.SHPOOL_SESSION_NAME = "edge1"
        assert equal (session-name) "edge1 "
    })

    ###############
    # have-command: rejects non-executable file in PATH
    (run-test "nu have-command rejects non-executable file in PATH" {
        let dir = (mktemp -d)
        "not executable" | save ($dir | path join "fakecmd")
        $env.PATH = [$dir]
        assert (not (have-command "fakecmd"))
    })
    (run-test "nu have-command accepts executable file in PATH" {
        let dir = (mktemp -d)
        "#!/bin/sh" | save ($dir | path join "fakecmd")
        ^chmod +x ($dir | path join "fakecmd")
        $env.PATH = [$dir]
        assert (have-command "fakecmd")
    })

    ###############
    # inpath
    (run-test "nu inpath true when in PATH" {
        $env.PATH = ["/usr/bin" "/bin"]
        assert (inpath "/usr/bin")
    })
    (run-test "nu inpath false when not in PATH" {
        $env.PATH = ["/usr/bin" "/bin"]
        assert (not (inpath "/tmp"))
    })

    ###############
    # prepend-path / append-path / delete-path / add-path
    (run-test "nu prepend-path existing dir" {
        $env.PATH = ["/usr/bin"]
        prepend-path "/tmp"
        assert equal $env.PATH ["/tmp" "/usr/bin"]
    })
    (run-test "nu prepend-path ignores missing" {
        $env.PATH = ["/usr/bin"]
        prepend-path "/definitely/not/a/real/dir"
        assert equal $env.PATH ["/usr/bin"]
    })
    (run-test "nu append-path existing dir" {
        $env.PATH = ["/usr/bin"]
        append-path "/tmp"
        assert equal $env.PATH ["/usr/bin" "/tmp"]
    })
    (run-test "nu delete-path removes entry" {
        $env.PATH = ["/usr/bin" "/tmp" "/bin"]
        delete-path "/tmp"
        assert equal $env.PATH ["/usr/bin" "/bin"]
    })
    (run-test "nu add-path moves existing to start" {
        $env.PATH = ["/usr/bin" "/tmp"]
        add-path "/tmp" "start"
        assert equal $env.PATH ["/tmp" "/usr/bin"]
    })
    (run-test "nu add-path moves existing to end" {
        $env.PATH = ["/tmp" "/usr/bin"]
        add-path "/tmp" "end"
        assert equal $env.PATH ["/usr/bin" "/tmp"]
    })
    (run-test "nu add-path default appends if missing" {
        $env.PATH = ["/usr/bin"]
        add-path "/var"
        assert equal $env.PATH ["/usr/bin" "/var"]
    })
    (run-test "nu add-path default no-op when present" {
        $env.PATH = ["/var" "/usr/bin"]
        add-path "/var"
        assert equal $env.PATH ["/var" "/usr/bin"]
    })

    ###############
    # on-my-workstation / on-my-laptop / on-production-host
    (run-test "nu on-my-workstation user-prefixed host" {
        $env.HOSTNAME = "mikel-workstation"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors WORKSTATION
        assert (on-my-workstation)
    })
    (run-test "nu on-my-workstation laptop is false" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors WORKSTATION
        assert (not (on-my-workstation))
    })
    (run-test "nu on-my-laptop laptop hostname" {
        $env.HOSTNAME = "mikel-laptop"
        assert (on-my-laptop)
    })
    (run-test "nu on-production-host true for unknown host" {
        $env.HOSTNAME = "prodhost"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors WORKSTATION
        assert (on-production-host)
    })
    (run-test "nu on-production-host false on my workstation" {
        $env.HOSTNAME = "mikel-workstation"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors WORKSTATION
        assert (not (on-production-host))
    })

    ###############
    # is-env-set handles missing env (regression for get -o flag)
    (run-test "nu is-env-set false when missing from env" {
        hide-env --ignore-errors NU_TOTALLY_UNSET
        assert (not (is-env-set "NU_TOTALLY_UNSET"))
    })

    ###############
    # find-up climbs the tree
    (run-test "nu find-up finds ancestor file" {
        let base = ($env.HOME | path expand)
        mkdir ([$base "a" "b" "c"] | path join)
        "marker" | save --force ([$base "a" "marker"] | path join)
        cd ([$base "a" "b" "c"] | path join)
        assert str contains (find-up "marker") "marker"
    })

    ###############
    # mcd creates and enters a directory
    (run-test "nu mcd enters the new directory" {
        let base = ($env.HOME | path expand)
        cd $base
        mcd newdir
        assert str contains $env.PWD "newdir"
    })

    ###############
    # mtd creates a temp dir and cds into it
    (run-test "nu mtd cds into a /tmp subdirectory" {
        let start = $env.PWD
        mtd
        assert str contains $env.PWD "/tmp"
        assert ($env.PWD != $start)
    })

    ###############
    # cdfile / realdir resolve symlinks to the real containing directory
    (run-test "nu realdir resolves symlink to real dir" {
        let base = ($env.HOME | path expand)
        mkdir ([$base "target"] | path join)
        "hello" | save --force ([$base "target" "file.txt"] | path join)
        ^ln -s ([$base "target"] | path join) ([$base "link"] | path join)
        assert str contains (realdir ([$base "link" "file.txt"] | path join)) "/target"
    })
    (run-test "nu cdfile cds to the file's real directory" {
        let base = ($env.HOME | path expand)
        mkdir ([$base "cdfile-target"] | path join)
        "x" | save --force ([$base "cdfile-target" "file.txt"] | path join)
        cdfile ([$base "cdfile-target" "file.txt"] | path join)
        assert str contains $env.PWD "cdfile-target"
    })

    ###############
    # gh-search / rh
    (run-test "nu gh-search finds a matching line" {
        "one two three\nalpha beta gamma\none four five" | save --force ([$env.HOME ".history"] | path join)
        let out = (gh-search "alpha" | str trim)
        assert str contains $out "alpha beta gamma"
    })
    (run-test "nu rh limits gh-search output to 20 lines" {
        let lines = (1..25 | each {|i| $"match line ($i)" } | str join (char newline))
        $lines | save --force ([$env.HOME ".history"] | path join)
        let count = (rh "match" | length)
        assert equal $count 20
    })

    ###############
    # confirm: reads from ^head (process stdin), so we spawn a sub-nu
    # process with controlled stdin to test all paths.
    (run-test "nu confirm yes on y" {
        let out = ("y" | nu --no-config-file -c $"source ($CONFIG); print \(confirm go\)")
        assert str contains $out "true"
    })
    (run-test "nu confirm yes on Y (uppercase)" {
        let out = ("Y" | nu --no-config-file -c $"source ($CONFIG); print \(confirm go\)")
        assert str contains $out "true"
    })
    (run-test "nu confirm yes on yes" {
        let out = ("yes" | nu --no-config-file -c $"source ($CONFIG); print \(confirm go\)")
        assert str contains $out "true"
    })
    (run-test "nu confirm no on n" {
        let out = ("n" | nu --no-config-file -c $"source ($CONFIG); print \(confirm go\)")
        assert str contains $out "false"
    })
    (run-test "nu confirm no on no" {
        let out = ("no" | nu --no-config-file -c $"source ($CONFIG); print \(confirm go\)")
        assert str contains $out "false"
    })
    (run-test "nu confirm defaults to yes on empty reply" {
        let out = ("" | nu --no-config-file -c $"source ($CONFIG); print \(confirm go\)")
        assert str contains $out "true"
    })
    (run-test "nu confirm treats non-y reply as no" {
        let out = ("maybe" | nu --no-config-file -c $"source ($CONFIG); print \(confirm go\)")
        assert str contains $out "false"
    })

    ###############
    # CDPATH is set and does not include conf/ subdirectories
    (run-test "nu CDPATH contains HOME" {
        assert ($env.CDPATH | any {|it| $it == $env.HOME })
    })

    ###############
    # command_not_found hook is not set
    (run-test "nu command_not_found hook is not set" {
        assert equal ($env.config.hooks.command_not_found | describe) "nothing"
    })

    ###############
    # cd with trailing slash works (direct path; nu's built-in cd does
    # not consult $env.CDPATH, so the path must exist relative to PWD)
    (run-test "nu cd with trailing slash enters directory" {
        let base = ($env.HOME | path expand)
        mkdir ([$base "cdtest" "sub"] | path join)
        cd ([$base "cdtest"] | path join)
        cd ./sub/
        assert str contains $env.PWD "cdtest/sub"
    })
    (run-test "nu cd absolute path works" {
        let abs = (mktemp -d)
        cd $abs
        assert equal ($env.PWD | path expand) ($abs | path expand)
    })
    (run-test "nu cd - returns to previous directory" {
        let a = (mktemp -d)
        let b = (mktemp -d)
        cd $a
        cd $b
        cd -
        assert equal ($env.PWD | path expand) ($a | path expand)
    })
    (run-test "nu cd errors on missing dir" {
        cd (mktemp -d)
        let caught = (try { cd no-such-dir-zzzz; false } catch { true })
        assert $caught "cd should error when name does not exist in PWD"
    })

    ###############
    # No Enter keybinding: overriding Enter via reedline's
    # ExecuteHostCommand loses the user's buffer, so `ls<Enter>`
    # would do nothing. Regression guard against ever wiring one up
    # (we tried for CDPATH-aware autocd once and it broke everything).
    (run-test "nu does not override Enter" {
        let overrides = ($env.config.keybindings | where keycode == "enter")
        assert equal ($overrides | length) 0 $"Enter must not be overridden, found: ($overrides | to nuon)"
    })

    ###############
    # End-to-end: a command typed at the REPL and submitted with
    # Enter actually runs. Drives a real nu REPL under a Python pty
    # (script+expect aren't allowed/installed) and checks a marker
    # file that the submitted command should touch.
    #
    # Regression guard: we once installed an ExecuteHostCommand
    # Enter keybinding trying to add CDPATH-aware trailing-slash
    # autocd. ExecuteHostCommand exits reedline and discards the
    # user's buffer, so `ls<Enter>` did nothing. This test catches
    # that class of regression.
    (run-test "nu REPL runs a command submitted via Enter" {
        if not (have-command "python3") { return }
        let marker = (^mktemp -u --suffix=.nutest | str trim)
        let driver = (^mktemp --suffix=.py | str trim)
        # Minimal pty driver: fork a child, send lines after idle
        # pauses, answer DSR-6 cursor queries so reedline doesn't
        # block on terminal negotiation.
        'import os, pty, select, sys, time
timeout = float(sys.argv[1])
sep = sys.argv.index("--")
cmd = sys.argv[2:sep]
lines = [l + "\r" for l in sys.argv[sep+1:]]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
buf = b""
sent = 0
start = time.time()
last_send = 0
while time.time() - start < timeout:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try: data = os.read(fd, 4096)
        except OSError: break
        if not data: break
        buf += data
        while b"\x1b[6n" in buf:
            buf = buf.replace(b"\x1b[6n", b"", 1)
            try: os.write(fd, b"\x1b[24;1R")
            except OSError: pass
    else:
        now = time.time()
        if sent < len(lines) and now - last_send > 0.4:
            try: os.write(fd, lines[sent].encode())
            except OSError: break
            sent += 1
            last_send = now
try: os.close(fd)
except OSError: pass
' | save --force $driver
        # Run nu with the real config loaded. Force SHPOOL_SESSION_NAME
        # so maybe-start-shpool-and-exit is skipped (in-shpool returns
        # true). Use COLUMNS/LINES so term size doesn't block. Send
        # the command, then exit.
        with-env {
            SHPOOL_SESSION_NAME: fake
            COLUMNS: "80"
            LINES: "24"
            TERM: "xterm-256color"
        } {
            (^python3 $driver "12" "nu" "--config" $CONFIG "--env-config" "/dev/null" "--" $"touch ($marker)" "exit") | ignore
        }
        assert ($marker | path exists) $"REPL did not execute the submitted command; expected marker ($marker) to be created"
    })

    ###############
    # last-job-info
    (run-test "nu last-job-info empty when CMD_DURATION unset" {
        hide-env --ignore-errors CMD_DURATION
        hide-env --ignore-errors CMD_EXIT_CODE
        assert equal (last-job-info) ""
    })
    (run-test "nu last-job-info empty for 0sec" {
        $env.CMD_EXIT_CODE = 0
        $env.CMD_DURATION = 0sec
        assert equal (last-job-info) ""
    })
    (run-test "nu last-job-info empty for 1sec (rounds down)" {
        $env.CMD_EXIT_CODE = 0
        $env.CMD_DURATION = 1sec
        assert equal (last-job-info) ""
    })
    (run-test "nu last-job-info shows took for 5sec" {
        $env.CMD_EXIT_CODE = 0
        $env.CMD_DURATION = 5sec
        assert str contains (last-job-info) "took 5 seconds"
    })
    (run-test "nu last-job-info shows hours for 1hr" {
        $env.CMD_EXIT_CODE = 0
        $env.CMD_DURATION = 1hr
        assert str contains (last-job-info) "1 hours"
    })
    (run-test "nu last-job-info shows error status" {
        $env.CMD_EXIT_CODE = 1
        $env.CMD_DURATION = 0sec
        assert str contains (last-job-info) "status 1"
    })
    (run-test "nu last-job-info shows interrupted for exit 130" {
        $env.CMD_EXIT_CODE = 130
        $env.CMD_DURATION = 0sec
        assert str contains (last-job-info) "interrupted"
    })
    (run-test "nu last-job-info skips suspended exit 148" {
        $env.CMD_EXIT_CODE = 148
        $env.CMD_DURATION = 0sec
        assert equal (last-job-info) ""
    })
    (run-test "nu last-job-info shows error and duration together" {
        $env.CMD_EXIT_CODE = 1
        $env.CMD_DURATION = 5sec
        let out = (last-job-info)
        assert str contains $out "status 1"
        assert str contains $out "took 5 seconds"
    })
    (run-test "nu last-job-info error and duration on same line" {
        $env.CMD_EXIT_CODE = 2
        $env.CMD_DURATION = 125sec
        let out = (last-job-info)
        # Both parts should be on the same line (separated by space, ending in newline)
        let lines = ($out | str trim | lines)
        assert equal ($lines | length) 1
        assert str contains ($lines | first) "status 2"
        assert str contains ($lines | first) "took 2 minutes 5 seconds"
    })

    ###############
    # title-escape
    (run-test "nu title-escape includes OSC 0 on xterm" {
        $env.TERM = "xterm-256color"
        assert str contains (title-escape "my title") "]0;my title"
    })
    (run-test "nu title-escape empty on dumb terminal" {
        $env.TERM = "dumb"
        assert equal (title-escape "my title") ""
    })
    (run-test "nu title-escape supports rxvt" {
        $env.TERM = "rxvt-unicode"
        assert str contains (title-escape "hi") "]0;hi"
    })

    ###############
    # flash-terminal
    (run-test "nu flash-terminal rings bell on xterm" {
        $env.TERM = "xterm-256color"
        assert equal (flash-terminal) (char bel)
    })
    (run-test "nu flash-terminal empty on dumb terminal" {
        $env.TERM = "dumb"
        assert equal (flash-terminal) ""
    })

    ###############
    # title respects inside-tmux
    (run-test "nu title shows hostname outside tmux" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors TMUX
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        mkdir ([$env.HOME "titletest"] | path join)
        cd ([$env.HOME "titletest"] | path join)
        assert equal (title) "laptop titletest"
    })
    (run-test "nu title hides hostname in tmux" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        $env.TMUX = "/fake/tmux/socket"
        $env.SHPOOL_SESSION_NAME = "main"
        mkdir ([$env.HOME "titletest"] | path join)
        cd ([$env.HOME "titletest"] | path join)
        let t = (title)
        assert str contains $t "main"
        assert (not ($t | str starts-with "laptop "))
    })

    ###############
    # prompt-line fallback when vcs is missing
    (run-test "nu prompt-line fallback has hostname" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors TMUX
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.PATH = []
        cd $env.HOME
        assert str contains (prompt-line) "laptop"
    })

    ###############
    # render-prompt structure
    (run-test "nu render-prompt contains separator" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        $env.UID = 1000
        hide-env --ignore-errors TMUX
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.PATH = []
        cd $env.HOME
        assert str contains (render-prompt) "―"
    })
    (run-test "nu render-prompt contains hostname in prompt line" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        $env.UID = 1000
        hide-env --ignore-errors TMUX
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.PATH = []
        cd $env.HOME
        assert str contains (render-prompt) "laptop"
    })
    (run-test "nu render-prompt ends with > prompt" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        $env.UID = 1000
        hide-env --ignore-errors TMUX
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.PATH = []
        cd $env.HOME
        assert str contains (render-prompt) "> "
    })
    (run-test "nu render-prompt as root ends with red > prompt" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        $env.UID = 0
        hide-env --ignore-errors TMUX
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.PATH = []
        cd $env.HOME
        assert str contains (render-prompt) (red ">")
    })

    ###############
    # render-prompt sets xterm title
    (run-test "nu render-prompt sets xterm title" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        $env.UID = 1000
        $env.TERM = "xterm-256color"
        hide-env --ignore-errors TMUX
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.PATH = []
        cd $env.HOME
        assert str contains (render-prompt) "]0;"
    })
    (run-test "nu render-prompt includes duration line" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        $env.UID = 1000
        $env.TERM = "dumb"
        $env.CMD_DURATION = 5sec
        $env.CMD_EXIT_CODE = 0
        hide-env --ignore-errors TMUX
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.PATH = []
        cd $env.HOME
        assert str contains (render-prompt) "took 5 seconds"
    })
    (run-test "nu render-prompt includes error status" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        $env.UID = 1000
        $env.TERM = "dumb"
        $env.CMD_DURATION = 0sec
        $env.CMD_EXIT_CODE = 1
        hide-env --ignore-errors TMUX
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.PATH = []
        cd $env.HOME
        assert str contains (render-prompt) "status 1"
    })

    ###############
    # pre_execution / pre_prompt hooks
    (run-test "nu pre_execution hook list has one entry" {
        assert equal ($env.config.hooks.pre_execution | length) 1
    })
    (run-test "nu pre_prompt hook list has one entry" {
        assert equal ($env.config.hooks.pre_prompt | length) 1
    })
    # Invoke the hook closures directly and verify CMD_DURATION gets set.
    (run-test "nu timing hooks populate CMD_DURATION" {
        do --env ($env.config.hooks.pre_execution | first)
        sleep 2100ms
        do --env ($env.config.hooks.pre_prompt | first)
        assert str contains (format-duration $env.CMD_DURATION) "seconds"
    })
    # When pre_execution did not fire, pre_prompt zeroes CMD_DURATION.
    (run-test "nu pre_prompt clears stale CMD_DURATION" {
        hide-env --ignore-errors CMD_START_TIME
        hide-env --ignore-errors CMD_DURATION
        do --env ($env.config.hooks.pre_prompt | first)
        assert equal ($env.CMD_DURATION | into int) 0
    })
    # pre_prompt captures LAST_EXIT_CODE into CMD_EXIT_CODE.
    (run-test "nu pre_prompt captures CMD_EXIT_CODE" {
        $env.LAST_EXIT_CODE = 42
        do --env ($env.config.hooks.pre_execution | first)
        do --env ($env.config.hooks.pre_prompt | first)
        assert equal $env.CMD_EXIT_CODE 42
    })
    # When no command ran, CMD_EXIT_CODE is zeroed.
    (run-test "nu pre_prompt clears stale CMD_EXIT_CODE" {
        hide-env --ignore-errors CMD_START_TIME
        hide-env --ignore-errors CMD_EXIT_CODE
        do --env ($env.config.hooks.pre_prompt | first)
        assert equal $env.CMD_EXIT_CODE 0
    })

    ###############
    # bak / unbak roundtrip
    (run-test "nu bak creates .bak file" {
        cd $env.HOME
        ["baktest" "baktest.bak"] | each {|f| if ($f | path exists) { ^rm -f $f } } | ignore
        "hello" | save --force baktest
        bak "baktest"
        let files = (ls baktest* | get name | path basename | str join ",")
        assert equal $files "baktest.bak"
    })
    (run-test "nu unbak restores original" {
        cd $env.HOME
        ["baktest" "baktest.bak"] | each {|f| if ($f | path exists) { ^rm -f $f } } | ignore
        "hello" | save --force baktest
        bak "baktest"
        unbak "baktest.bak"
        let files = (ls baktest* | get name | path basename | str join ",")
        let content = (open baktest)
        assert equal $files "baktest"
        assert equal $content "hello"
    })
    (run-test "nu unbak short filename roundtrip" {
        cd $env.HOME
        ["shortbak" "shortbak.bak"] | each {|f| if ($f | path exists) { ^rm -f $f } } | ignore
        "x" | save --force shortbak
        bak "shortbak"
        unbak "shortbak.bak"
        assert equal (open shortbak) "x"
    })

    ###############
    # log-history
    (run-test "nu log-history writes argv and tty" {
        $env.HISTORY_FILE = ([$env.HOME "history.log"] | path join)
        $env.TTY = "/dev/pts/42"
        log-history "hello world"
        let content = (open --raw $env.HISTORY_FILE | str trim)
        assert str contains $content "hello world"
        assert str contains $content "/dev/pts/42"
    })
    (run-test "nu log-history no-op when HISTORY_FILE empty" {
        $env.HISTORY_FILE = ""
        log-history "ignored"
        # no crash is the assertion
    })
    (run-test "nu log-history no-op when HISTORY_FILE unset" {
        hide-env --ignore-errors HISTORY_FILE
        log-history "ignored"
        # no crash is the assertion
    })

    ###############
    # inside-project / want-shpool
    (run-test "nu inside-project false when projectroot is empty" {
        $env.projectroot = {|| "" }
        assert (not (inside-project))
    })
    (run-test "nu want-shpool false when not remote and not in project" {
        $env.projectroot = {|| "" }
        hide-env --ignore-errors SSH_CONNECTION
        assert (not (want-shpool))
    })
    (run-test "nu want-shpool true when remote" {
        $env.SSH_CONNECTION = "1.2.3.4 22 5.6.7.8 22"
        assert (want-shpool)
    })
    (run-test "nu inside-project true when projectroot override returns non-empty" {
        $env.projectroot = {|| "/fake/project" }
        assert (inside-project)
    })
    (run-test "nu want-shpool true when projectroot override is non-empty" {
        $env.projectroot = {|| "/fake/project" }
        hide-env --ignore-errors SSH_CONNECTION
        assert (want-shpool)
    })
    (run-test "nu projectname picks up projectroot override" {
        $env.projectroot = {|| "/srv/code/myrepo" }
        assert equal (projectname) "myrepo"
    })
    (run-test "nu buildroot picks up projectroot override" {
        $env.projectroot = {|| "/srv/code/myrepo" }
        assert equal (buildroot) "/srv/code/myrepo"
    })

    ###############
    # maybe-start-shpool-and-exit is a no-op without shpool on PATH
    (run-test "nu maybe-start-shpool-and-exit no-op without shpool" {
        $env.PATH = []
        $env.SSH_CONNECTION = "1.2.3.4 22"
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        maybe-start-shpool-and-exit
        # no crash/exit is the assertion
    })

    ###############
    # projectroot fallback: walks parents for VCS markers
    (run-test "nu projectroot fallback finds .git in cwd" {
        $env.PATH = []
        let base = ($env.HOME | path expand)
        let proj = ([$base "pr-git"] | path join)
        mkdir ([$proj ".git"] | path join)
        cd $proj
        assert str contains (projectroot) "pr-git"
    })
    (run-test "nu projectroot fallback walks up to find .jj" {
        $env.PATH = []
        let base = ($env.HOME | path expand)
        let proj = ([$base "pr-jj"] | path join)
        mkdir ([$proj ".jj"] | path join)
        mkdir ([$proj "sub" "deeper"] | path join)
        cd ([$proj "sub" "deeper"] | path join)
        assert str contains (projectroot) "pr-jj"
    })
    (run-test "nu projectroot empty when vcs rootdir exits nonzero" {
        # Stub vcs to exit 1
        let dir = (mktemp -d)
        "#!/bin/sh\nexit 1" | save ($dir | path join "vcs")
        ^chmod +x ($dir | path join "vcs")
        $env.PATH = [$dir]
        cd $env.HOME
        assert equal (projectroot) ""
    })

    ###############
    # shift-options
    (run-test "nu shift-options moves options before target" {
        let out = (shift-options echo target "-a" "-b" "rest" | str trim)
        assert equal $out "-a -b target rest"
    })
    (run-test "nu shift-options no options" {
        let out = (shift-options echo target "rest" | str trim)
        assert equal $out "target rest"
    })
    (run-test "nu shift-options option only" {
        let out = (shift-options echo target "-x" | str trim)
        assert equal $out "-x target"
    })
    (run-test "nu shift-options stops at --" {
        let out = (shift-options echo target "--" "-b" | str trim)
        assert equal $out "target -- -b"
    })

    ###############
    # first-arg-last
    (run-test "nu first-arg-last 0 args raises usage error" {
        let caught = (try { first-arg-last; false } catch { true })
        assert $caught
    })
    (run-test "nu first-arg-last 2 args runs command with arg" {
        let out = (first-arg-last echo only | str trim)
        assert equal $out "only"
    })
    (run-test "nu first-arg-last moves first positional to end" {
        let out = (first-arg-last echo history.file tail | str trim)
        assert equal $out "tail history.file"
    })

    ###############
    # which-path: uses `print` so output can't be captured as a return
    # value in a closure. Test that it doesn't crash.
    (run-test "nu which-path does not crash for known command" {
        which-path sh
    })
    (run-test "nu which-path does not crash for missing command" {
        which-path zzzz-not-a-real-command-xyz
    })

    ###############
    # what: uses `print` so output can't be captured as a return value
    # in a closure. Test that it doesn't crash.
    (run-test "nu what does not crash for custom def" {
        what have-command
    })
    (run-test "nu what does not crash for external command" {
        what sh
    })
    (run-test "nu what does not crash for missing command" {
        what zzzz-not-a-real-command-xyz
    })

    ###############
    # rerc is defined and exec's nu
    (run-test "nu rerc is defined as a custom command" {
        assert equal (which rerc | get 0.type) "custom"
    })
    (run-test "nu rerc body exec's nu" {
        assert ((view source rerc) | str contains "exec nu")
    })

    ###############
    # delline removes the given line in place
    (run-test "nu delline removes line 2" {
        cd $env.HOME
        "line1\nline2\nline3" | save --force lines.txt
        delline 2 lines.txt
        assert equal (open lines.txt | str trim) "line1\nline3"
    })

    ###############
    # body: headers are printed to stdout, body goes through the command.
    # In a closure we can't capture the printed headers, so just verify
    # the body portion is sorted and the command doesn't crash.
    (run-test "nu body does not crash with default header" {
        "HEAD\nc\na\nb" | body sort | ignore
    })
    (run-test "nu body does not crash with --lines 2" {
        "H1\nH2\ny\nx\nz" | body --lines 2 sort | ignore
    })

    ###############
    # trydiff: diff output is printed, not returned. Verify the file is
    # untouched afterwards.
    (run-test "nu trydiff leaves file untouched" {
        cd $env.HOME
        "b\na\nc" | save --force t.txt
        trydiff sort t.txt
        assert equal (open t.txt | str trim) "b\na\nc"
    })

    ###############
    # overridable hook points
    (run-test "nu auth wrapper dispatches through env.auth" {
        $env.auth = {|| "custom-auth-called" }
        assert equal (auth) "custom-auth-called"
    })
    (run-test "nu wsh dispatches through env.with-agent" {
        $env.with-agent = {|...cmd| ($cmd | str join "|") }
        assert equal (wsh host arg | str trim) "ssh|host|arg"
    })
    (run-test "nu wcp dispatches through env.with-agent" {
        $env.with-agent = {|...cmd| ($cmd | str join "|") }
        assert equal (wcp src dst | str trim) "scp|src|dst"
    })
    (run-test "nu on-production-host override wins over default" {
        $env.HOSTNAME = "prodhost"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors WORKSTATION
        $env.on-production-host = {|| false }
        assert (not (on-production-host))
    })
    (run-test "nu on-production-host override flips workstation to prod" {
        $env.HOSTNAME = "mikel-workstation"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors WORKSTATION
        $env.on-production-host = {|| true }
        assert (on-production-host)
    })

    ###############
    # auth helpers: stub ssh-add to control exit status
    (run-test "nu is-ssh-valid true when ssh-add succeeds" {
        let dir = (mktemp -d)
        "#!/bin/sh\nexit 0" | save ($dir | path join "ssh-add")
        ^chmod +x ($dir | path join "ssh-add")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        assert (is-ssh-valid)
    })
    (run-test "nu is-ssh-valid false when ssh-add fails" {
        let dir = (mktemp -d)
        "#!/bin/sh\nexit 2" | save ($dir | path join "ssh-add")
        ^chmod +x ($dir | path join "ssh-add")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        assert (not (is-ssh-valid))
    })
    (run-test "nu need-auth false when ssh-add succeeds" {
        let dir = (mktemp -d)
        "#!/bin/sh\nexit 0" | save ($dir | path join "ssh-add")
        ^chmod +x ($dir | path join "ssh-add")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        assert (not (need-auth))
    })
    (run-test "nu need-auth true when ssh-add fails" {
        let dir = (mktemp -d)
        "#!/bin/sh\nexit 2" | save ($dir | path join "ssh-add")
        ^chmod +x ($dir | path join "ssh-add")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        assert (need-auth)
    })
    (run-test "nu auth-info reports SSH on failure" {
        let dir = (mktemp -d)
        "#!/bin/sh\nexit 2" | save ($dir | path join "ssh-add")
        ^chmod +x ($dir | path join "ssh-add")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        assert str contains (auth-info) "SSH"
    })
    (run-test "nu auth-info empty on success" {
        let dir = (mktemp -d)
        "#!/bin/sh\nexit 0" | save ($dir | path join "ssh-add")
        ^chmod +x ($dir | path join "ssh-add")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        assert equal (auth-info) ""
    })

    ###############
    # Sourcing config.nu under an interactive tty (via `script`) runs the
    # startup `if (need-auth) { auth }` block. If ssh-add isn't on PATH
    # (a minimal container, a BSD without OpenSSH client tools, ...),
    # that call would raise and abort the whole shell startup unless
    # wrapped in `try`. Matches shrc semantics where a missing ssh-add
    # just prints "command not found" and continues.
    (run-test "nu startup tolerates missing ssh-add under interactive tty" {
        if (not (have-command "script")) {
            return
        }
        let dir = (mktemp -d)
        # PATH with no ssh-add, no shpool, no autoshpool -- isolates the
        # auth failure from the other interactive-startup branches.
        let cmd = $"nu --no-config-file -c 'with-env {PATH: [(char dq)($dir)(char dq) (char dq)/usr/bin(char dq) (char dq)/bin(char dq)]} { source ($CONFIG); print READY }'"
        let r = (^script -qc $cmd /dev/null | complete)
        assert ($r.stdout | str contains "READY") $"startup should finish despite missing ssh-add: ($r.stdout) stderr=($r.stderr)"
    })

    ###############
    # VCS aliases are defined
    (run-test "nu vcs aliases are defined" {
        let names = [add amend annotate base branch branches changed changelog
             changes checkout commit commitforce diffs fix graph incoming
             lint map outgoing pending precommit presubmit pull push
             recommit revert review reword submit submitforce unknown
             upload uploadchain clone st ci di gr lg ma am]
        for name in $names {
            let matches = (which $name)
            assert ($matches | is-not-empty) $"($name) should be defined"
        }
    })
    (run-test "nu clone remains a custom command" {
        assert equal (which clone | get 0.type) "custom"
    })
    (run-test "nu vcs short aliases are aliases" {
        let names = [add commit diffs graph push pull st ci di gr]
        for name in $names {
            assert equal (which $name | get 0.type) "alias" $"($name) should be alias"
        }
    })

    ###############
    # VCS aliases pass flags through to ^vcs (regression: old def wrappers
    # rejected unknown flags like -m; aliases are parse-time substitutions
    # so flags flow through to the external command).
    (run-test "nu commit alias passes -m through to ^vcs" {
        let dir = (mktemp -d)
        "#!/bin/sh\nprintf 'vcs-stub:'; for a; do printf ' %s' \"$a\"; done; printf '\\n'" | save ($dir | path join "vcs")
        ^chmod +x ($dir | path join "vcs")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        let out = (commit -m fix | str trim)
        assert str contains $out "vcs-stub: commit -m fix"
    })
    (run-test "nu ci alias passes -m through to ^vcs" {
        let dir = (mktemp -d)
        "#!/bin/sh\nprintf 'vcs-stub:'; for a; do printf ' %s' \"$a\"; done; printf '\\n'" | save ($dir | path join "vcs")
        ^chmod +x ($dir | path join "vcs")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        let out = (ci -m fix | str trim)
        assert str contains $out "vcs-stub: commit -m fix"
    })
    (run-test "nu di alias passes --stat through to ^vcs" {
        let dir = (mktemp -d)
        "#!/bin/sh\nprintf 'vcs-stub:'; for a; do printf ' %s' \"$a\"; done; printf '\\n'" | save ($dir | path join "vcs")
        ^chmod +x ($dir | path join "vcs")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        let out = (di --stat | str trim)
        assert str contains $out "vcs-stub: diffs --stat"
    })
    (run-test "nu gr alias passes --limit N through to ^vcs" {
        let dir = (mktemp -d)
        "#!/bin/sh\nprintf 'vcs-stub:'; for a; do printf ' %s' \"$a\"; done; printf '\\n'" | save ($dir | path join "vcs")
        ^chmod +x ($dir | path join "vcs")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        let out = (gr --limit 10 | str trim)
        assert str contains $out "vcs-stub: graph --limit 10"
    })
    (run-test "nu bare vcs resolves to ^vcs via PATH" {
        let dir = (mktemp -d)
        "#!/bin/sh\nprintf 'vcs-stub:'; for a; do printf ' %s' \"$a\"; done; printf '\\n'" | save ($dir | path join "vcs")
        ^chmod +x ($dir | path join "vcs")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        let out = (^vcs detect some/arg | str trim)
        assert str contains $out "vcs-stub: detect some/arg"
    })

    ###############
    # clone dispatch: stub jj/git/hg to verify which command is invoked
    (run-test "nu clone .git uses jj git clone when jj available" {
        let dir = (mktemp -d)
        for cmd in [jj git hg] {
            $"#!/bin/sh\necho ($cmd) $*" | save ($dir | path join $cmd)
            ^chmod +x ($dir | path join $cmd)
        }
        $env.PATH = [$dir "/usr/bin" "/bin"]
        let out = (clone "https://github.com/foo/bar.git" | str trim)
        assert equal $out "jj git clone https://github.com/foo/bar.git"
    })
    (run-test "nu clone /hg/ uses hg clone" {
        let dir = (mktemp -d)
        for cmd in [jj git hg] {
            $"#!/bin/sh\necho ($cmd) $*" | save ($dir | path join $cmd)
            ^chmod +x ($dir | path join $cmd)
        }
        $env.PATH = [$dir "/usr/bin" "/bin"]
        let out = (clone "https://hg.example.com/hg/repo" | str trim)
        assert equal $out "hg clone https://hg.example.com/hg/repo"
    })
    # clone fallback when jj is missing requires confirm (process stdin),
    # so we spawn a sub-nu process.
    (run-test "nu clone falls back to git when jj missing and user says yes" {
        let dir = (mktemp -d)
        for cmd in [git hg] {
            $"#!/bin/sh\necho ($cmd) $*" | save ($dir | path join $cmd)
            ^chmod +x ($dir | path join $cmd)
        }
        let out = ("y" | nu --no-config-file -c $"
            source ($CONFIG)
            $env.PATH = [($dir) /usr/bin /bin]
            clone https://github.com/foo/bar.git
        " | str trim)
        assert str contains $out "git clone https://github.com/foo/bar.git"
    })
    (run-test "nu clone aborts when user declines git fallback" {
        let dir = (mktemp -d)
        for cmd in [git hg] {
            $"#!/bin/sh\necho ($cmd) $*" | save ($dir | path join $cmd)
            ^chmod +x ($dir | path join $cmd)
        }
        let out = ("n" | nu --no-config-file -c $"
            source ($CONFIG)
            $env.PATH = [($dir) /usr/bin /bin]
            clone https://github.com/foo/bar.git
        " | str trim)
        assert (not ($out | str contains "git clone"))
    })

    ###############
    # error / warn / puts: output helpers
    (run-test "nu puts prints to stdout" {
        # puts uses `print` which writes to terminal, not pipeline. Spawn a
        # sub-nu and capture its combined stdout.
        let out = (nu --no-config-file -c $"source ($CONFIG); puts 'hello world'" | str trim)
        assert equal $out "hello world"
    })
    (run-test "nu error prints to stderr" {
        # error writes to stderr; capture via a sub-nu so we can read stderr
        let r = (nu --no-config-file -c $"source ($CONFIG); error 'oops'" | complete)
        assert str contains $r.stderr "oops"
    })
    (run-test "nu warn prints to stderr" {
        let r = (nu --no-config-file -c $"source ($CONFIG); warn 'heads up'" | complete)
        assert str contains $r.stderr "heads up"
    })

    ###############
    # quiet: silences output
    (run-test "nu quiet does not crash on valid command" {
        quiet echo hi
    })
    (run-test "nu quiet does not crash on failing command" {
        quiet false
    })

    ###############
    # connected-via-ssh / connected-remotely
    (run-test "nu connected-via-ssh true when SSH_CONNECTION set" {
        $env.SSH_CONNECTION = "1.2.3.4 22 5.6.7.8 22"
        assert (connected-via-ssh)
    })
    (run-test "nu connected-via-ssh false when SSH_CONNECTION unset" {
        hide-env --ignore-errors SSH_CONNECTION
        assert (not (connected-via-ssh))
    })
    (run-test "nu connected-remotely delegates to connected-via-ssh" {
        $env.SSH_CONNECTION = "1.2.3.4 22 5.6.7.8 22"
        assert (connected-remotely)
    })

    ###############
    # inside-tmux
    (run-test "nu inside-tmux true when TMUX set" {
        $env.TMUX = "/tmp/tmux-1000/default"
        assert (inside-tmux)
    })
    (run-test "nu inside-tmux false when TMUX unset" {
        hide-env --ignore-errors TMUX
        assert (not (inside-tmux))
    })

    ###############
    # i-am-root
    (run-test "nu i-am-root true when UID is 0" {
        $env.UID = 0
        assert (i-am-root)
    })
    (run-test "nu i-am-root false when UID is 1000" {
        $env.UID = 1000
        assert (not (i-am-root))
    })

    ###############
    # workstation: reads ~/.workstation file, caches in $env.WORKSTATION
    (run-test "nu workstation returns file contents" {
        hide-env --ignore-errors WORKSTATION
        "myhost" | save --force ([$env.HOME ".workstation"] | path join)
        assert equal (workstation) "myhost"
    })
    (run-test "nu workstation returns empty when file missing" {
        hide-env --ignore-errors WORKSTATION
        let ws_file = ([$env.HOME ".workstation"] | path join)
        if ($ws_file | path exists) { ^rm $ws_file }
        assert equal (workstation) ""
    })
    (run-test "nu workstation caches in WORKSTATION env var" {
        hide-env --ignore-errors WORKSTATION
        "cached" | save --force ([$env.HOME ".workstation"] | path join)
        workstation | ignore
        assert equal $env.WORKSTATION "cached"
    })

    ###############
    # on-my-machine: true when workstation or laptop
    (run-test "nu on-my-machine true on workstation" {
        $env.HOSTNAME = "mikel-workstation"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors WORKSTATION
        assert (on-my-machine)
    })
    (run-test "nu on-my-machine true on laptop" {
        $env.HOSTNAME = "mikel-laptop"
        assert (on-my-machine)
    })
    (run-test "nu on-my-machine false on unknown host" {
        $env.HOSTNAME = "prodserver"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors WORKSTATION
        let ws_file = ([$env.HOME ".workstation"] | path join)
        if ($ws_file | path exists) { ^rm $ws_file }
        let lp_file = ([$env.HOME ".laptop"] | path join)
        if ($lp_file | path exists) { ^rm $lp_file }
        assert (not (on-my-machine))
    })

    ###############
    # on-test-host / on-dev-host
    (run-test "nu on-test-host true when hostname contains test" {
        $env.HOSTNAME = "test-server-01"
        assert (on-test-host)
    })
    (run-test "nu on-test-host false for prod host" {
        $env.HOSTNAME = "prodhost"
        assert (not (on-test-host))
    })
    (run-test "nu on-dev-host true when hostname contains dev" {
        $env.HOSTNAME = "dev-vm-03"
        assert (on-dev-host)
    })
    (run-test "nu on-dev-host false for prod host" {
        $env.HOSTNAME = "prodhost"
        assert (not (on-dev-host))
    })

    ###############
    # show-hostname-in-title: true outside tmux, false inside
    (run-test "nu show-hostname-in-title true outside tmux" {
        hide-env --ignore-errors TMUX
        assert (show-hostname-in-title)
    })
    (run-test "nu show-hostname-in-title false inside tmux" {
        $env.TMUX = "/tmp/tmux-1000/default"
        assert (not (show-hostname-in-title))
    })

    ###############
    # short-pwd / project-or-pwd
    (run-test "nu short-pwd returns projectname when in project" {
        $env.projectroot = {|| "/fake/myproject" }
        assert equal (short-pwd) "myproject"
    })
    (run-test "nu short-pwd returns basename when no project" {
        $env.projectroot = {|| "" }
        let base = ($env.HOME | path expand)
        mkdir ([$base "somedir"] | path join)
        cd ([$base "somedir"] | path join)
        assert equal (short-pwd) "somedir"
    })
    (run-test "nu project-or-pwd returns projectname when in project" {
        $env.projectroot = {|| "/fake/myrepo" }
        assert equal (project-or-pwd) "myrepo"
    })
    (run-test "nu project-or-pwd returns basename when no project" {
        $env.projectroot = {|| "" }
        let base = ($env.HOME | path expand)
        mkdir ([$base "adir"] | path join)
        cd ([$base "adir"] | path join)
        assert equal (project-or-pwd) "adir"
    })

    ###############
    # render-transient-prompt / render-right-prompt
    (run-test "nu render-transient-prompt shows > for non-root" {
        $env.UID = 1000
        assert equal (render-transient-prompt) $"(ansi reset)> "
    })
    (run-test "nu render-transient-prompt shows red > for root" {
        $env.UID = 0
        assert equal (render-transient-prompt) $"(ansi reset)(red '>') "
    })
    (run-test "nu render-transient-prompt starts with ansi reset" {
        # Reedline wraps PROMPT_COMMAND output in a default green
        # SGR; the leading reset defeats that so the prompt picks up
        # whatever color the user set (or terminal default).
        $env.UID = 1000
        assert str contains (render-transient-prompt) (ansi reset)
    })
    (run-test "nu render-prompt contains ansi reset to defeat reedline default color" {
        # Without a reset, the hostname and separator bar come out
        # green (reedline's DEFAULT_PROMPT_COLOR).
        $env.HOME = (mktemp -d)
        $env.UID = 1000
        hide-env --ignore-errors CMD_DURATION
        hide-env --ignore-errors CMD_EXIT_CODE
        assert str contains (render-prompt) (ansi reset)
    })
    (run-test "nu render-right-prompt is empty" {
        assert equal (render-right-prompt) ""
    })

    ###############
    # builddir: path from buildroot to PWD
    (run-test "nu builddir returns dot at project root" {
        let base = ($env.HOME | path expand)
        let proj = ([$base "bd-proj"] | path join)
        mkdir $proj
        $env.projectroot = {|| $proj }
        cd $proj
        assert equal (builddir) "."
    })
    (run-test "nu builddir returns relative path in subdir" {
        let base = ($env.HOME | path expand)
        let proj = ([$base "bd-proj2"] | path join)
        mkdir ([$proj "src" "lib"] | path join)
        $env.projectroot = {|| $proj }
        cd ([$proj "src" "lib"] | path join)
        assert equal (builddir) "src/lib"
    })

    ###############
    # isort: sort a file in place
    (run-test "nu isort sorts file contents" {
        cd $env.HOME
        "cherry\napple\nbanana" | save --force sortme.txt
        isort sortme.txt
        assert equal (open sortme.txt | str trim) "apple\nbanana\ncherry"
    })
    (run-test "nu isort preserves trailing newline" {
        cd $env.HOME
        "cherry\napple\nbanana\n" | save --force sortme2.txt
        isort sortme2.txt
        assert (open --raw sortme2.txt | str ends-with (char newline))
    })

    ###############
    # projectroot: with working vcs binary
    (run-test "nu projectroot uses vcs rootdir when available" {
        let dir = (mktemp -d)
        "#!/bin/sh\necho /vcs/reported/root" | save ($dir | path join "vcs")
        ^chmod +x ($dir | path join "vcs")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        assert equal (projectroot) "/vcs/reported/root"
    })

    ###############
    # clone: URL matching neither .git nor /hg/
    (run-test "nu clone does nothing for unrecognized URL" {
        let dir = (mktemp -d)
        for cmd in [jj git hg] {
            $"#!/bin/sh\necho ($cmd) $*" | save ($dir | path join $cmd)
            ^chmod +x ($dir | path join $cmd)
        }
        $env.PATH = [$dir "/usr/bin" "/bin"]
        let out = (clone "https://example.com/plain-repo")
        assert equal $out null
    })

    ###############
    # auth-info override via $env.auth-info
    (run-test "nu auth-info override dispatches through env" {
        $env.auth-info = {|| "KERBEROS" }
        assert equal (auth-info) "KERBEROS"
    })
    (run-test "nu need-auth picks up auth-info override" {
        $env.auth-info = {|| "EXPIRED" }
        assert (need-auth)
    })
    (run-test "nu need-auth false when auth-info override returns empty" {
        $env.auth-info = {|| "" }
        assert (not (need-auth))
    })

    ###############
    # config settings
    (run-test "nu edit_mode is emacs" {
        assert equal $env.config.edit_mode "emacs"
    })
    (run-test "nu show_banner is false" {
        assert equal $env.config.show_banner false
    })
    (run-test "nu history file_format is plaintext" {
        assert equal $env.config.history.file_format "plaintext"
    })
    (run-test "nu history max_size is 100000" {
        assert equal $env.config.history.max_size 100000
    })

    ###############
    # PROMPT_COMMAND and related env closures are set
    (run-test "nu PROMPT_COMMAND is set" {
        assert (($env.PROMPT_COMMAND | describe) == "closure")
    })
    (run-test "nu PROMPT_INDICATOR is empty string" {
        assert equal $env.PROMPT_INDICATOR ""
    })
    (run-test "nu TRANSIENT_PROMPT_COMMAND is set" {
        assert (($env.TRANSIENT_PROMPT_COMMAND | describe) == "closure")
    })

    ###############
    # on-my-workstation via .workstation file
    (run-test "nu on-my-workstation true via .workstation file" {
        hide-env --ignore-errors WORKSTATION
        $env.HOSTNAME = "specialbox"
        $env.USERNAME = "someone"
        "specialbox" | save --force ([$env.HOME ".workstation"] | path join)
        assert (on-my-workstation)
    })

    ###############
    # on-my-laptop via .laptop file
    (run-test "nu on-my-laptop true via .laptop file" {
        $env.HOSTNAME = "specialbox"
        "yes" | save --force ([$env.HOME ".laptop"] | path join)
        assert (on-my-laptop)
    })

    ###############
    # find-project-root
    (run-test "nu find-project-root finds .hg marker" {
        let base = ($env.HOME | path expand)
        let proj = ([$base "hg-proj"] | path join)
        mkdir ([$proj ".hg"] | path join)
        mkdir ([$proj "sub"] | path join)
        cd ([$proj "sub"] | path join)
        assert str contains (find-project-root [".hg"]) "hg-proj"
    })
    (run-test "nu find-project-root returns empty at root" {
        cd /
        assert equal (find-project-root [".nonexistent-marker"]) ""
    })

    ###############
    # retry: calls the command again after failure
    (run-test "nu retry succeeds immediately when command passes" {
        let dir = (mktemp -d)
        let counter = ($dir | path join "count")
        # Stub that always succeeds and records each call.
        $"#!/bin/sh\nc=$\(cat ($counter) 2>/dev/null || echo 0\)\nc=$\(\(c + 1\)\)\necho $c > ($counter)\nexit 0" | save ($dir | path join "retrystub")
        ^chmod +x ($dir | path join "retrystub")
        nu --no-config-file -c $"
            source ($CONFIG)
            $env.TERM = 'dumb'
            $env.PATH = [($dir) /usr/bin /bin]
            retry --sleep 0sec retrystub
        "
        assert equal (open ($counter) | str trim) "1"
    })
    (run-test "nu retry retries after failure then stops on success" {
        let dir = (mktemp -d)
        let counter = ($dir | path join "count")
        # Stub that fails on the first call, succeeds on the second.
        $"#!/bin/sh\nc=$\(cat ($counter) 2>/dev/null || echo 0\)\nc=$\(\(c + 1\)\)\necho $c > ($counter)\nif [ $c -lt 2 ]; then exit 1; fi\nexit 0" | save ($dir | path join "retrystub")
        ^chmod +x ($dir | path join "retrystub")
        nu --no-config-file -c $"
            source ($CONFIG)
            $env.TERM = 'dumb'
            $env.PATH = [($dir) /usr/bin /bin]
            retry --sleep 0sec retrystub
        "
        assert equal (open ($counter) | str trim) "2"
    })

    ###############
    # recent: calls ls -t -1 and limits output
    (run-test "nu recent returns newest files first" {
        let dir = (mktemp -d)
        # Stub ls to print a known ordering so the test doesn't depend on
        # real filesystem mtime races.
        $"#!/bin/sh\necho new\necho mid\necho old" | save ($dir | path join "ls")
        ^chmod +x ($dir | path join "ls")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        cd $dir
        let out = (recent | lines)
        assert equal ($out | first) "new"
        assert equal ($out | length) 3
    })
    (run-test "nu recent respects count argument" {
        let dir = (mktemp -d)
        $"#!/bin/sh\necho a\necho b\necho c\necho d\necho e" | save ($dir | path join "ls")
        ^chmod +x ($dir | path join "ls")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        cd $dir
        let out = (recent 2 | lines)
        assert equal ($out | length) 2
        assert equal ($out | first) "a"
    })
    (run-test "nu recent passes extra args to ls" {
        let dir = (mktemp -d)
        # Stub ls that echoes its arguments so we can verify flags.
        "#!/bin/sh\necho \"$*\"" | save ($dir | path join "ls")
        ^chmod +x ($dir | path join "ls")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        cd $dir
        let out = (recent 5 "-a" "/some/dir" | first)
        assert str contains $out "-t"
        assert str contains $out "-1"
        assert str contains $out "-a"
        assert str contains $out "/some/dir"
    })

    ###############
    # session-name with tmux: stub tmux display-message
    (run-test "nu session-name returns tmux session name" {
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.TMUX = "/tmp/tmux-1000/default"
        let dir = (mktemp -d)
        "#!/bin/sh\necho mysession" | save ($dir | path join "tmux")
        ^chmod +x ($dir | path join "tmux")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        assert equal (session-name) "mysession "
    })
    (run-test "nu session-name prefers shpool over tmux" {
        $env.SHPOOL_SESSION_NAME = "poolname"
        $env.TMUX = "/tmp/tmux-1000/default"
        assert equal (session-name) "poolname "
    })

    ###############
    # maybe-start-shpool-and-exit: stub autoshpool
    (run-test "nu maybe-start-shpool-and-exit calls autoshpool when warranted" {
        let dir = (mktemp -d)
        let marker = ($dir | path join "called")
        # Stub autoshpool that records it was called but exits non-zero
        # so the test process doesn't actually exit.
        $"#!/bin/sh\ntouch ($marker)\nexit 1" | save ($dir | path join "autoshpool")
        ^chmod +x ($dir | path join "autoshpool")
        # Stub shpool so have-command returns true for it.
        "#!/bin/sh" | save ($dir | path join "shpool")
        ^chmod +x ($dir | path join "shpool")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        $env.SSH_CONNECTION = "1.2.3.4 22 5.6.7.8 22"
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        maybe-start-shpool-and-exit
        assert ($marker | path exists) "autoshpool should have been called"
    })
    (run-test "nu maybe-start-shpool-and-exit skips when already in shpool" {
        let dir = (mktemp -d)
        let marker = ($dir | path join "called")
        $"#!/bin/sh\ntouch ($marker)" | save ($dir | path join "autoshpool")
        ^chmod +x ($dir | path join "autoshpool")
        "#!/bin/sh" | save ($dir | path join "shpool")
        ^chmod +x ($dir | path join "shpool")
        $env.PATH = [$dir "/usr/bin" "/bin"]
        $env.SSH_CONNECTION = "1.2.3.4 22 5.6.7.8 22"
        $env.SHPOOL_SESSION_NAME = "already"
        maybe-start-shpool-and-exit
        assert (not ($marker | path exists)) "autoshpool should NOT have been called"
    })
    (run-test "nu maybe-start-shpool-and-exit exits on autoshpool success" {
        # Run in a sub-nu because exit terminates the process.
        let dir = (mktemp -d)
        "#!/bin/sh\nexit 0" | save ($dir | path join "autoshpool")
        ^chmod +x ($dir | path join "autoshpool")
        "#!/bin/sh" | save ($dir | path join "shpool")
        ^chmod +x ($dir | path join "shpool")
        let r = (nu --no-config-file -c $"
            source ($CONFIG)
            $env.PATH = [($dir) /usr/bin /bin]
            $env.SSH_CONNECTION = '1.2.3.4 22 5.6.7.8 22'
            hide-env --ignore-errors SHPOOL_SESSION_NAME
            maybe-start-shpool-and-exit
            print 'did-not-exit'
        " | str trim)
        # If autoshpool succeeds, exit is called and 'did-not-exit' is never printed.
        assert (not ($r | str contains "did-not-exit"))
    })
    (run-test "nu maybe-start-shpool-and-exit does not exit on autoshpool failure" {
        # Non-zero exit from autoshpool must not kill the shell, so the
        # user can see the error and fix it.
        let dir = (mktemp -d)
        "#!/bin/sh\nexit 1" | save ($dir | path join "autoshpool")
        ^chmod +x ($dir | path join "autoshpool")
        "#!/bin/sh" | save ($dir | path join "shpool")
        ^chmod +x ($dir | path join "shpool")
        let r = (nu --no-config-file -c $"
            source ($CONFIG)
            $env.PATH = [($dir) /usr/bin /bin]
            $env.SSH_CONNECTION = '1.2.3.4 22 5.6.7.8 22'
            hide-env --ignore-errors SHPOOL_SESSION_NAME
            maybe-start-shpool-and-exit
            print 'did-not-exit'
        " | str trim)
        assert ($r | str contains "did-not-exit") $"autoshpool failure must not exit the shell: got ($r)"
    })
    (run-test "nu maybe-start-shpool-and-exit inherits stdout to autoshpool" {
        # Regression: previously used `^autoshpool | complete`, which
        # captured stdout/stderr and broke interactive `shpool attach`
        # (it would hang waiting to use the terminal).
        let dir = (mktemp -d)
        # Stub prints a unique marker to stdout. If stdio is inherited,
        # the marker reaches the sub-nu's stdout; if it's piped/captured,
        # it's swallowed inside maybe-start-shpool-and-exit.
        "#!/bin/sh\necho MARKER_STDOUT_XYZ\nexit 1" | save ($dir | path join "autoshpool")
        ^chmod +x ($dir | path join "autoshpool")
        "#!/bin/sh" | save ($dir | path join "shpool")
        ^chmod +x ($dir | path join "shpool")
        let r = (nu --no-config-file -c $"
            source ($CONFIG)
            $env.PATH = [($dir) /usr/bin /bin]
            $env.SSH_CONNECTION = '1.2.3.4 22 5.6.7.8 22'
            hide-env --ignore-errors SHPOOL_SESSION_NAME
            maybe-start-shpool-and-exit
        " | complete)
        assert ($r.stdout | str contains "MARKER_STDOUT_XYZ") $"stub stdout should pass through: ($r.stdout)"
    })
    (run-test "nu maybe-start-shpool-and-exit inherits stderr to autoshpool" {
        # stderr inheritance matters too: shpool prints status and errors
        # to stderr; capturing it would hide them from the user.
        let dir = (mktemp -d)
        "#!/bin/sh\necho MARKER_STDERR_XYZ >&2\nexit 1" | save ($dir | path join "autoshpool")
        ^chmod +x ($dir | path join "autoshpool")
        "#!/bin/sh" | save ($dir | path join "shpool")
        ^chmod +x ($dir | path join "shpool")
        let r = (nu --no-config-file -c $"
            source ($CONFIG)
            $env.PATH = [($dir) /usr/bin /bin]
            $env.SSH_CONNECTION = '1.2.3.4 22 5.6.7.8 22'
            hide-env --ignore-errors SHPOOL_SESSION_NAME
            maybe-start-shpool-and-exit
        " | complete)
        assert ($r.stderr | str contains "MARKER_STDERR_XYZ") $"stub stderr should pass through: ($r.stderr)"
    })
    (run-test "nu maybe-start-shpool-and-exit inherits a tty to autoshpool when one is present" {
        # Real regression: with `| complete`, autoshpool's stdout was a
        # pipe, so shpool attach saw no tty and hung. Spawn sub-nu under
        # `script` (pty) and have the stub record whether its stdout is
        # a tty.
        if (not (have-command "script")) {
            return
        }
        let dir = (mktemp -d)
        let marker = ($dir | path join "tty-status")
        $"#!/bin/sh\nif [ -t 1 ]; then echo tty > ($marker); else echo pipe > ($marker); fi\nexit 1" | save ($dir | path join "autoshpool")
        ^chmod +x ($dir | path join "autoshpool")
        "#!/bin/sh" | save ($dir | path join "shpool")
        ^chmod +x ($dir | path join "shpool")
        # ssh-add stub: exits 0 so need-auth returns false and config.nu's
        # interactive auth block does not hang waiting for a passphrase under
        # the pty. Must be in PATH before `source` so the startup block sees it.
        "#!/bin/sh\nexit 0" | save ($dir | path join "ssh-add")
        ^chmod +x ($dir | path join "ssh-add")
        # Set PATH and SSH_CONNECTION via with-env so they're visible during
        # source; this prevents the interactive auth block from using the real
        # ssh-add and hanging on a passphrase prompt.
        let cmd = $"nu --no-config-file -c 'with-env {PATH: [\"($dir)\" /usr/bin /bin], SSH_CONNECTION: \"1.2.3.4 22 5.6.7.8 22\"} { source ($CONFIG); hide-env --ignore-errors SHPOOL_SESSION_NAME; maybe-start-shpool-and-exit }'"
        ^script -qc $cmd /dev/null out+err> (["/dev/null"] | path join)
        let status = (open $marker | str trim)
        assert equal $status "tty" $"autoshpool stdout should be a tty when nu runs under a pty, got: ($status)"
    })

    # TODO: add package manager wrapper tests (update, search, install,
    # versions, upgrade, etc.) once the defs are moved out of `if` blocks.
    # Nushell scopes `def` inside `if`, so the current yum/apt-get
    # wrappers are invisible to callers.

    ###############
    # host-info / dir-info / prompt-line composition
    (run-test "nu host-info includes short hostname" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.on-production-host = {|| false }
        assert str contains (host-info) "laptop"
    })
    (run-test "nu host-info paints hostname red on production" {
        $env.HOSTNAME = "prodhost"
        $env.USERNAME = "mikel"
        $env.UID = 1000
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.on-production-host = {|| true }
        let out = (host-info)
        assert str contains $out "prodhost"
        assert str contains $out (ansi red)
    })
    (run-test "nu host-info prepends [root] when root" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        $env.UID = 0
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.on-production-host = {|| false }
        let out = (host-info)
        assert str contains ($out | ansi strip) "[root]"
        assert str contains $out "laptop"
    })
    (run-test "nu host-info shows yellow shpool warning off shpool" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.on-production-host = {|| false }
        let out = (host-info)
        assert str contains $out "shpool"
        assert str contains $out (ansi yellow)
    })
    (run-test "nu host-info shows [session] in shpool" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        $env.SHPOOL_SESSION_NAME = "edge1"
        $env.on-production-host = {|| false }
        let out = (host-info)
        assert str contains $out $"[(ansi green)edge1(ansi reset)]"
    })
    (run-test "nu tilde-pwd at \$HOME" {
        let d = (mktemp -d)
        $env.HOME = $d
        cd $d
        assert equal (tilde-pwd) "~"
    })
    (run-test "nu tilde-pwd inside \$HOME" {
        let d = (mktemp -d)
        mkdir ([$d "documents"] | path join)
        $env.HOME = $d
        cd ([$d "documents"] | path join)
        assert equal (tilde-pwd) "~/documents"
    })
    (run-test "nu tilde-pwd outside \$HOME" {
        let d = (mktemp -d)
        $env.HOME = "/nonexistent/home/mikel"
        cd $d
        assert equal (tilde-pwd) $d
    })
    (run-test "nu dir-info uses prompt-info when non-empty" {
        $env.prompt-info = {|flags| "myproject main" }
        assert str contains (dir-info) "myproject main"
    })
    (run-test "nu dir-info falls back to tilde-pwd when prompt-info empty" {
        let d = (mktemp -d)
        $env.HOME = $d
        cd $d
        $env.prompt-info = {|flags| "" }
        assert str contains (dir-info) "~"
    })
    (run-test "nu dir-info passes --color=never when NO_COLOR set" {
        $env.prompt-info = {|flags| ($flags | str join " ") }
        $env.NO_COLOR = "1"
        assert str contains (dir-info) "--color=never"
    })
    (run-test "nu dir-info passes --color=always when NO_COLOR unset" {
        $env.prompt-info = {|flags| ($flags | str join " ") }
        hide-env --ignore-errors NO_COLOR
        assert str contains (dir-info) "--color=always"
    })
    (run-test "nu prompt-line composes host + dir + auth" {
        let d = (mktemp -d)
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        $env.HOME = $d
        cd $d
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.on-production-host = {|| false }
        $env.prompt-info = {|flags| "" }
        $env.auth-info = {|| "SSH" }
        let out = (prompt-line)
        assert str contains $out "laptop"
        assert str contains $out "shpool"
        assert str contains $out "~"
        assert str contains $out "SSH"
    })
    (run-test "nu prompt-line omits auth suffix when no auth needed" {
        let d = (mktemp -d)
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        $env.HOME = $d
        cd $d
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.on-production-host = {|| false }
        $env.prompt-info = {|flags| "" }
        $env.auth-info = {|| "" }
        assert (not ((prompt-line) | str contains "SSH"))
    })

    ###############
    # color helpers: verify ANSI escapes
    (run-test "nu red wraps text in red ANSI escapes" {
        let out = (red "error msg")
        assert str contains $out "error msg"
        # ansi red = ESC[31m, ansi reset = ESC[0m
        assert str contains $out (ansi red)
        assert str contains $out (ansi reset)
    })
    (run-test "nu green wraps text in green ANSI escapes" {
        let out = (green "ok")
        assert str contains $out "ok"
        assert str contains $out (ansi green)
        assert str contains $out (ansi reset)
    })
    (run-test "nu yellow wraps text in yellow ANSI escapes" {
        let out = (yellow "warn")
        assert str contains $out "warn"
        assert str contains $out (ansi yellow)
        assert str contains $out (ansi reset)
    })
    (run-test "nu blue wraps text in blue ANSI escapes" {
        let out = (blue "info")
        assert str contains $out "info"
        assert str contains $out (ansi blue)
        assert str contains $out (ansi reset)
    })
    (run-test "nu color helpers join multiple args with space" {
        let out = (red "hello" "world")
        assert str contains $out "hello world"
    })

    ###############
    # prompt-line shows session in shpool tag; otherwise uses yellow warning
    (run-test "nu prompt-line includes session name in shpool tag" {
        let d = (mktemp -d)
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors TMUX
        $env.SHPOOL_SESSION_NAME = "main"
        $env.HOME = $d
        cd $d
        $env.on-production-host = {|| false }
        $env.prompt-info = {|flags| "" }
        $env.auth-info = {|| "" }
        assert str contains (prompt-line) "main"
    })
    (run-test "nu prompt-line uses prompt-info output in-project" {
        $env.HOSTNAME = "mikel-laptop"
        $env.USERNAME = "mikel"
        hide-env --ignore-errors TMUX
        hide-env --ignore-errors SHPOOL_SESSION_NAME
        $env.on-production-host = {|| false }
        $env.prompt-info = {|flags| "myproject main" }
        $env.auth-info = {|| "" }
        assert str contains (prompt-line) "myproject"
    })

    ###############
    # PROMPT_MULTILINE_INDICATOR
    (run-test "nu PROMPT_MULTILINE_INDICATOR is set to underscore-space" {
        assert equal $env.PROMPT_MULTILINE_INDICATOR "_ "
    })

    ###############
    # config.nu has no manual source statement
    (run-test "nu config.nu has no manual source statement" {
        let content = (open --raw $CONFIG)
        let lines = ($content | lines | where ($it | str starts-with "source "))
        # The only source line should be in comments, not bare
        # Actually check for bare source lines (not "source $CONFIG" from test)
        let bare = ($content | lines | where {|l|
            ($l | str starts-with "source ") and (not ($l | str starts-with "source $"))
        })
        assert ($bare | is-empty)
    })

    ###############
    # find-up: returns empty when file not found
    (run-test "nu find-up returns empty when file not found" {
        cd /
        assert equal (find-up "this_file_does_not_exist_anywhere") ""
    })

    ###############
    # mcd: when directory already exists, does not cd
    (run-test "nu mcd prints message when directory exists" {
        let base = ($env.HOME | path expand)
        mkdir ([$base "existing-dir"] | path join)
        let start = $env.PWD
        cd $base
        mcd "existing-dir"
        # mcd should NOT cd into the existing directory (matches shrc/fish)
        assert (not ($env.PWD | str ends-with "existing-dir"))
    })

    ###############
    # short-hostname: bare hostname without domain
    (run-test "nu short-hostname with bare hostname" {
        $env.HOSTNAME = "myhost"
        $env.USERNAME = "mikel"
        assert equal (short-hostname) "myhost"
    })
    (run-test "nu short-hostname with empty hostname" {
        $env.HOSTNAME = ""
        $env.USERNAME = "mikel"
        assert equal (short-hostname) ""
    })

    ###############
    # format-duration: boundary values
    (run-test "nu format-duration 2s shows seconds" {
        assert equal (format-duration 2sec) "2 seconds"
    })
    (run-test "nu format-duration 60s shows 1 minutes 0 seconds" {
        assert equal (format-duration 60sec) "1 minutes 0 seconds"
    })
    (run-test "nu format-duration 3600s shows 1 hours 0 minutes 0 seconds" {
        assert equal (format-duration 3600sec) "1 hours 0 minutes 0 seconds"
    })
    (run-test "nu format-duration 61s shows 1 minutes 1 seconds" {
        assert equal (format-duration 61sec) "1 minutes 1 seconds"
    })

    ###############
    # projectname: when not in a project
    (run-test "nu projectname returns empty when no project" {
        $env.projectroot = {|| "" }
        assert equal (projectname) ""
    })

    ###############
    # unbak: when .bak file doesn't exist, silent no-op
    (run-test "nu unbak no-op when .bak file does not exist" {
        cd $env.HOME
        "content" | save --force unbaktest
        let before = (open unbaktest)
        if ("unbaktest.bak" | path exists) { ^rm unbaktest.bak }
        unbak "unbaktest"
        # File should be unchanged since no .bak existed
        assert equal (open unbaktest) $before
    })

    ###############
    # unbak: called with .bak name when source .bak doesn't exist
    (run-test "nu unbak with .bak name when file missing" {
        cd $env.HOME
        if ("ghost.bak" | path exists) { ^rm ghost.bak }
        if ("ghost" | path exists) { ^rm ghost }
        unbak "ghost.bak"
        # No crash and no file created
        assert (not ("ghost" | path exists))
    })

    ###############
    # on-my-workstation: with empty username
    (run-test "nu on-my-workstation false with empty username" {
        $env.HOSTNAME = "somehost"
        $env.USERNAME = ""
        hide-env --ignore-errors WORKSTATION
        assert (not (on-my-workstation))
    })

    ###############
    # bell: just verify it doesn't crash
    (run-test "nu bell does not crash" {
        bell
    })

    ###############
    # package manager aliases are defined
    (run-test "nu package manager aliases are defined" {
        let names = [update search install installed uninstall reinstall
             autoremove upgrade versions info files listfiles depends rdepends]
        for name in $names {
            let matches = (which $name)
            assert ($matches | is-not-empty) $"($name) should be defined"
            assert equal ($matches | get 0.type) "alias" $"($name) should be alias"
        }
    })

    ###############
    # what: for alias type
    (run-test "nu what does not crash for alias" {
        what st
    })

    ###############
    # age: verify it returns a non-negative number
    (run-test "nu age returns non-negative seconds" {
        cd $env.HOME
        "test" | save --force agefile
        let a = (age agefile)
        assert ($a >= 0) "age should be non-negative"
    })

    ###############
    # rmkey: verify it removes a line from known_hosts
    (run-test "nu rmkey removes line from known_hosts" {
        mkdir ([$env.HOME ".ssh"] | path join)
        "host1 key1\nhost2 key2\nhost3 key3" | save --force ([$env.HOME ".ssh" "known_hosts"] | path join)
        rmkey 2
        let content = (open ([$env.HOME ".ssh" "known_hosts"] | path join) | str trim)
        assert equal $content "host1 key1\nhost3 key3"
    })

    ###############
    # first-arg-last: single arg (command with no positionals)
    (run-test "nu first-arg-last single arg runs command bare" {
        let out = (first-arg-last echo | str trim)
        assert equal $out ""
    })

    ###############
    # shift-options: stops at bare - (dash)
    (run-test "nu shift-options stops at bare dash" {
        let out = (shift-options echo target "-a" "-" "rest" | str trim)
        assert equal $out "-a target - rest"
    })

    ###############
    # GOPATH is set
    (run-test "nu GOPATH is set to HOME" {
        assert equal $env.GOPATH $env.HOME
    })

    ###############
    # LESS is set
    (run-test "nu LESS is set to -R" {
        assert equal $env.LESS "-R"
    })

    ###############
    # BLOCKSIZE is set
    (run-test "nu BLOCKSIZE is set to 1024" {
        assert equal $env.BLOCKSIZE "1024"
    })

    ###############
    # prompt env vars: vi indicators
    (run-test "nu PROMPT_INDICATOR_VI_INSERT is empty" {
        assert equal $env.PROMPT_INDICATOR_VI_INSERT ""
    })
    (run-test "nu PROMPT_INDICATOR_VI_NORMAL is empty" {
        assert equal $env.PROMPT_INDICATOR_VI_NORMAL ""
    })
    (run-test "nu TRANSIENT_PROMPT_INDICATOR is empty" {
        assert equal $env.TRANSIENT_PROMPT_INDICATOR ""
    })

    ###############
    # x / xa: exit the shell (match zsh's `x` alias)
    (run-test "nu x is defined" { assert (which x | is-not-empty) })
    (run-test "nu xa is defined" { assert (which xa | is-not-empty) })

    ###############
    # rd: cd to project root
    (run-test "nu rd cds to project root" {
        let base = ($env.HOME | path expand)
        let proj = ([$base "rd-proj"] | path join)
        mkdir ([$proj ".git"] | path join)
        mkdir ([$proj "src" "lib"] | path join)
        $env.projectroot = {|| $proj }
        cd ([$proj "src" "lib"] | path join)
        rd
        assert equal $env.PWD $proj
    })

    ###############
    # maybe-background-fetch: nu version. The vcs binary owns per-VCS
    # detection, marker mtime, and the detached spawn; this shell only
    # owns the auth gate (the PWD-change gate is provided externally
    # by hooks.env_change.PWD). Each test overrides $env.vcs-auto-fetch
    # with a recorder that writes to a file, then asserts whether the
    # fetch fired.
    (run-test "nu maybe-background-fetch fires when gates pass" {
        let base = ($env.HOME | path expand)
        let dir = ([$base "bgfetch-fires"] | path join)
        mkdir $dir
        cd $dir
        let log = ([$dir "fetch.log"] | path join)
        $env.vcs-auto-fetch = {|| "called" | save -f $log }
        $env.auth-info = {|| "" }
        maybe-background-fetch
        assert (($log | path exists) and ((open $log | str trim) == "called"))
    })

    (run-test "nu maybe-background-fetch no-op when auth-info reports problems" {
        let base = ($env.HOME | path expand)
        let dir = ([$base "bgfetch-noauth"] | path join)
        mkdir $dir
        cd $dir
        let log = ([$dir "fetch.log"] | path join)
        $env.vcs-auto-fetch = {|| "called" | save -f $log }
        # Override auth-info to simulate missing SSH identity.
        $env.auth-info = {|| "SSH" }
        maybe-background-fetch
        assert (not ($log | path exists))
    })
]

for r in $results { print $r }

let fails = ($results | where ($it | str starts-with "FAIL:"))
print ""
if ($fails | is-empty) {
    print $"nu config_test: all ($results | length) tests passed."
} else {
    let passed = (($results | length) - ($fails | length))
    print $"nu config_test: ($fails | length) test\(s\) failed, ($passed) passed."
    exit 1
}
