#!/bin/bash
# Install the tools `make test` needs but the container does not ship.
#
# Of the two, shellcheck is the blocking one: without it the lint target dies
# with exit 127 and the whole suite fails. nushell is optional — its absence only
# skips config/nushell/config_test.nu, but AGENTS.md asks for those tests to run
# when the nushell config is touched.
#
# apt is off-limits here, so both come from GitHub releases.
#
# Anything already on PATH is left alone — an environment that ships its own
# build is not ours to overwrite, and the hook re-runs on every SessionStart.
# What is installed gets printed rather than checked against the pin, so the
# version the tests actually ran against is on the record and a result that
# disagrees with CI has its explanation in the session log.
set -euo pipefail

# Bump a version and its checksum together. The pin fixes *which* release is
# wanted; the checksum is what makes the downloaded bytes actually that
# release, so a replaced asset or a compromised publisher account cannot hand
# this hook a binary it then installs and every later test executes.
SHELLCHECK_VERSION=0.10.0
SHELLCHECK_SHA256=6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87
# Matches the version on the maintainer's machine. 0.101.0 could not parse
# config/nushell/config.nu at all, so the whole nu-native suite died on a
# parser error rather than running.
NU_VERSION=0.113.1
NU_SHA256=9008d309aaa35e29ed5d5985306a83e2bf5093e31677d4cd969914552d12b8fb

if test "${CLAUDE_CODE_REMOTE:-}" != "true"; then
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# This runs before the session is usable, so an unbounded download holds up
# startup with nothing on screen to say why. Bound both: a GitHub outage should
# fail in a couple of minutes with a message, not hang until something upstream
# gives up. --max-time covers the transfer, which for nu is ~76 MB.
curl_opts=(--fail --silent --show-error --location
           --connect-timeout 10 --max-time 300)

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
        echo "session-start: nu is on PATH but will not run; config/nushell tests will skip" >&2
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
