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
    # ps1-character: '>' when not root, '#' when root.
    (run-test "nu ps1-character non-root" {
        $env.UID = 1000
        assert equal (ps1-character) ">"
    })
    (run-test "nu ps1-character root" {
        $env.UID = 0
        assert equal (ps1-character) "#"
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
