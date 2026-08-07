#!/bin/bash
# Install the tools `make test` needs but the container does not ship.
#
# Of the three, shellcheck is the blocking one: without it the lint target dies
# with exit 127 and the whole suite fails. nushell and Elvish are optional —
# their absence only skips config/nushell/config_test.nu and elvish_test.sh, but
# AGENTS.md asks for those tests to run when their configs are touched, and a
# suite that skips is one that silently covers less than the job claims.
#
# apt is off-limits here, so shellcheck and nushell come from GitHub releases.
# Elvish is built with `go install`, for the reason spelled out beside
# ELVISH_VERSION in test-tool-versions.sh: upstream publishes no release asset
# to pin, and the Go checksum database is the independent check its own host
# cannot provide.
#
# Anything already on PATH is left alone — an environment that ships its own
# build is not ours to overwrite, and the hook re-runs on every SessionStart.
# What is installed gets printed rather than checked against the pin, so the
# version the tests actually ran against is on the record and a result that
# disagrees with CI has its explanation in the session log.
set -euo pipefail

if test "${CLAUDE_CODE_REMOTE:-}" != "true"; then
    exit 0
fi

# The pins live in one file shared with install-ci-shells.sh, so a bump lands
# in both environments at once. Two copies of a version is how CI and a session
# end up testing different builds of the same shell.
# `${0%/*}` rather than `dirname`: the hook's own tests run it under a PATH
# that deliberately excludes /usr/bin, symlinking in one coreutil at a time, so
# reaching for a binary here would make sourcing the pins the thing that fails.
# shellcheck source=../../test-tool-versions.sh
. "${0%/*}/../../test-tool-versions.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# This runs before the session is usable, so an unbounded download holds up
# startup with nothing on screen to say why. Bound both: a GitHub outage should
# fail in a couple of minutes with a message, not hang until something upstream
# gives up. --max-time covers the transfer, which for nu is ~76 MB.
#
# Retried for the same reason install-ci-shells.sh is: a reset mid-transfer on
# a download that size is the network's doing, not a signal, and losing nu to
# one costs the session its nu-native tests. --retry-all-errors is the part
# that covers a connection reset; curl does not count that as retryable on its
# own. The checksum still decides what gets installed.
curl_opts=(--fail --silent --show-error --location
           --connect-timeout 10 --max-time 300
           --retry 3 --retry-delay 2 --retry-all-errors)

report_version() {
    echo "session-start: using the installed $1: $2" >&2
}

# Both probes run the tool for real, so a binary that is present but cannot
# execute — wrong architecture, missing loader, truncated file — fails here
# rather than being silently accepted by `command -v`.
#
# `shellcheck --version` prints a banner then a "version: x.y.z" line.
shellcheck_version() {
    shellcheck --version | sed -n 's/^version: *//p'
}

nu_version() {
    nu --version | head -1
}

elvish_version() {
    elvish --version | head -1
}

verify_sha256() {
    if ! echo "$2  $1" | sha256sum --check --strict -; then
        echo "session-start: ${1##*/} failed its checksum; refusing to install it" >&2
        return 1
    fi
}

# Prove the binary runs before publishing it. Once a broken file is in
# /usr/local/bin, `command -v` succeeds forever after: this hook stops
# retrying and the Makefile's `command -v nu` gate picks the run branch, so
# `make test` fails on the leftover instead of skipping cleanly.
verify_runs() {
    if ! "$1" --version >/dev/null 2>&1; then
        echo "session-start: the downloaded $2 does not run; not installing it" >&2
        return 1
    fi
}

# Every step is checked: `set -e` does not apply inside a function called as
# `if ! install_x`, so a bare `tar` that fails would fall through to `install`
# and a partial archive could ship a truncated binary.
install_shellcheck() {
    version="v$SHELLCHECK_VERSION"
    url="https://github.com/koalaman/shellcheck/releases/download/$version/shellcheck-$version.linux.x86_64.tar.xz"
    curl "${curl_opts[@]}" "$url" -o "$tmp/shellcheck.tar.xz" || return 1
    verify_sha256 "$tmp/shellcheck.tar.xz" "$SHELLCHECK_SHA256" || return 1
    tar -xf "$tmp/shellcheck.tar.xz" -C "$tmp" || return 1
    verify_runs "$tmp/shellcheck-$version/shellcheck" shellcheck || return 1
    install -m 755 "$tmp/shellcheck-$version/shellcheck" /usr/local/bin/shellcheck || return 1
}

install_nu() {
    url="https://github.com/nushell/nushell/releases/download/$NU_VERSION/nu-$NU_VERSION-x86_64-unknown-linux-gnu.tar.gz"
    curl "${curl_opts[@]}" "$url" -o "$tmp/nu.tar.gz" || return 1
    verify_sha256 "$tmp/nu.tar.gz" "$NU_SHA256" || return 1
    tar -xzf "$tmp/nu.tar.gz" -C "$tmp" || return 1
    verify_runs "$tmp/nu-$NU_VERSION-x86_64-unknown-linux-gnu/nu" nushell || return 1
    install -m 755 "$tmp/nu-$NU_VERSION-x86_64-unknown-linux-gnu/nu" /usr/local/bin/nu || return 1
}

# Go is not always on PATH even where it is installed: this image keeps it at
# /usr/local/go/bin, which the hook's own environment does not include, and the
# CI runner has the same layout with sudo's secure_path leaving it out. $GOROOT
# is what names a Go installation somewhere else again, so it decides where to
# look before the default does.
find_go() {
    if command -v go >/dev/null 2>&1; then
        command -v go
        return 0
    fi
    if test -x "${GOROOT:-/usr/local/go}/bin/go"; then
        echo "${GOROOT:-/usr/local/go}/bin/go"
        return 0
    fi
    return 1
}

# There is no download to checksum here and no extract step: the module proxy
# and the Go checksum database have already done that job by the time anything
# lands. Everything after that is the same shape as the other two installers,
# and for the same reasons.
#
# GOBIN points at $tmp rather than /usr/local/bin so the build lands somewhere
# unpublished and verify_runs gets its say first. Building straight into
# /usr/local/bin would put a binary on PATH before anything had run it, and
# `command -v elvish` succeeding is irreversible in practice: this hook stops
# retrying, and the Makefile's own `command -v elvish` gate picks the run
# branch, so `make test` fails on the leftover instead of skipping cleanly.
#
# Bounded for the same reason the curl transfers are. This runs before the
# session is usable and `go install` has no duration flag of its own, so a
# proxy that accepts the connection and then stalls would hold up startup
# indefinitely rather than letting Elvish drop out as the optional tool it is.
# The budget matches curl's --max-time; a build here is ~8s against a warm
# module cache and well under a minute cold.
ELVISH_BUILD_TIMEOUT=300

# $1 is where to publish, defaulting to /usr/local/bin. It is a parameter
# because replacing a broken elvish means overwriting *the file that resolved*,
# which is not always this one: env:34 puts five dirs ($HOME/scripts.local,
# $HOME/scripts, $HOME/bin, $HOME/.cargo/bin, $HOME/.local/bin) ahead of
# /usr/local/bin, so publishing here would leave the broken copy still winning
# the PATH lookup and the re-probe still failing.
install_elvish() {
    _dest=${1:-/usr/local/bin/elvish}
    _go=$(find_go) || {
        echo "session-start: no go toolchain; cannot build elvish" >&2
        return 1
    }
    # Status captured rather than tested inside `if !`, which would report the
    # negation's status and lose the 124 that says it was the clock, not the
    # build.
    _build=0
    GOBIN="$tmp" timeout "$ELVISH_BUILD_TIMEOUT" "$_go" \
        install "src.elv.sh/cmd/elvish@v$ELVISH_VERSION" || _build=$?
    if test "$_build" -ne 0; then
        if test "$_build" -eq 124; then
            echo "session-start: the elvish build did not finish within ${ELVISH_BUILD_TIMEOUT}s; giving up on it" >&2
        fi
        return 1
    fi
    verify_runs "$tmp/elvish" elvish || return 1
    install -m 755 "$tmp/elvish" "$_dest" || return 1
}

if command -v shellcheck >/dev/null 2>&1; then
    if _version=$(shellcheck_version); then
        report_version shellcheck "$_version"
    else
        echo "session-start: shellcheck is on PATH but will not run; \`make test\` will fail at lint" >&2
    fi
elif install_shellcheck; then
    # Report on the install path too, or a first run — the case this hook
    # exists for — is the one session with no version in its log.
    if _version=$(shellcheck_version); then
        report_version shellcheck "$_version"
    else
        echo "session-start: installed shellcheck will not run; \`make test\` will fail at lint" >&2
        exit 1
    fi
else
    echo "session-start: shellcheck install failed; \`make test\` will fail at lint" >&2
    exit 1
fi

# Not fatal: every other test still runs, the nu-native ones just skip.
if command -v nu >/dev/null 2>&1; then
    if _version=$(nu_version); then
        report_version nushell "$_version"
    else
        # Not "will skip": Makefile:207 gates on `command -v nu` alone, so a nu
        # that resolves but will not run takes the run branch. Reported rather
        # than rebuilt over — unlike elvish, replacing it is a 76 MB download.
        echo "session-start: nu is on PATH but will not run; the nushell suite will fail rather than skip" >&2
    fi
elif install_nu; then
    if _version=$(nu_version); then
        report_version nushell "$_version"
    else
        echo "session-start: installed nu will not run; config/nushell tests will skip" >&2
    fi
else
    echo "session-start: nushell install failed; config/nushell tests will skip" >&2
fi

# Also not fatal, and for the same reason as nushell: without it elvish_test.sh
# skips and everything else still runs.
#
# The present-but-broken case is the exception, and it does not skip. Makefile:240
# and elvish_test.sh:30 both gate on `command -v elvish` alone, so a file that
# resolves but will not run takes the run branch and fails the suite. Building
# over it is the only outcome that leaves the container usable — and cheap
# enough to be worth trying, since this build is seconds rather than a 76 MB
# download.
if _elvish=$(command -v elvish 2>/dev/null); then
    if _version=$(elvish_version); then
        report_version elvish "$_version"
    elif install_elvish "$_elvish" && _version=$(elvish_version); then
        report_version elvish "$_version"
    else
        echo "session-start: elvish is on PATH but will not run and could not be replaced; the elvish suite will fail rather than skip" >&2
    fi
elif install_elvish; then
    if _version=$(elvish_version); then
        report_version elvish "$_version"
    else
        echo "session-start: installed elvish will not run; config/elvish tests will skip" >&2
    fi
else
    echo "session-start: elvish install failed; config/elvish tests will skip" >&2
fi
