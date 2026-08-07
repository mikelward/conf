#!/bin/bash
# Install the shells `make test` needs on the CI runner.
#
# Without this the job silently covers bash and dash only -- every other
# target prints "SKIP: ... not installed" and still exits 0, so the check goes
# green having run a fraction of the suite. That is how two shrc tests sat
# broken under zsh on main: nothing in CI ever ran zsh to notice.
#
# Where each one comes from is decided by what upstream actually publishes,
# not by a blanket preference:
#
#   zsh   apt. There is no upstream binary release to pin, and the distro
#         package is a normal zsh.
#   fish  a pinned release binary. Ubuntu ships 3.x while config.fish is
#         written against 4.x, so the distro copy would test the wrong shell.
#   nu    a pinned release binary. Not packaged by Ubuntu at all, and the
#         version matters -- see the note in test-tool-versions.sh.
#   elvish a pinned `go install`. Upstream publishes no GitHub release asset to
#         pin, and the checksum beside its tarball is served by the same host
#         it would be checking; the Go checksum database is the independent one.
#
# mesh is deliberately absent; see TODO.md.
set -euo pipefail

cd "$(dirname "$0")"
# shellcheck source=test-tool-versions.sh
. ./test-tool-versions.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Bounded so a mirror outage fails with a message in a couple of minutes
# rather than hanging until the job's own timeout kills it with no clue why.
#
# Retried because these are large downloads over a link nobody controls -- nu
# alone is ~76 MB -- and a reset mid-transfer is a fact of the network, not a
# signal about the code. One did exactly that here: `curl: (35) Recv failure:
# Connection reset by peer` reddened a run in which nothing was wrong. That is
# the opposite of what this script is for, since a CI failure has to mean the
# config broke. --retry-all-errors is what covers a connection reset;
# --retry alone would not, since curl does not count that as retryable.
# The checksum still decides what gets installed, so a retry cannot smuggle in
# a corrupt download.
curl_opts=(--fail --silent --show-error --location
           --connect-timeout 10 --max-time 300
           --retry 3 --retry-delay 2 --retry-all-errors)

verify_sha256() {
    if ! echo "$2  $1" | sha256sum --check --strict -; then
        echo "install-ci-shells: ${1##*/} failed its checksum; refusing to install it" >&2
        return 1
    fi
}

# Prove the binary runs before publishing it to PATH. A file that is present
# but cannot execute -- wrong architecture, truncated download -- would satisfy
# the Makefile's `command -v` gate and take the run branch, turning a clean
# skip into a suite-wide failure that names the wrong cause.
verify_runs() {
    if ! "$1" --version >/dev/null 2>&1; then
        echo "install-ci-shells: the downloaded $2 does not run; not installing it" >&2
        return 1
    fi
}

# Every step is checked: `set -e` does not apply inside a function called as
# `if ! install_x`, so an unchecked tar would fall through to `install` and
# could publish a truncated binary.
install_fish() {
    url="https://github.com/fish-shell/fish-shell/releases/download/$FISH_VERSION/fish-$FISH_VERSION-linux-x86_64.tar.xz"
    curl "${curl_opts[@]}" "$url" -o "$tmp/fish.tar.xz" || return 1
    verify_sha256 "$tmp/fish.tar.xz" "$FISH_SHA256" || return 1
    tar -xf "$tmp/fish.tar.xz" -C "$tmp" || return 1
    verify_runs "$tmp/fish" fish || return 1
    install -m 755 "$tmp/fish" /usr/local/bin/fish || return 1
}

install_nu() {
    url="https://github.com/nushell/nushell/releases/download/$NU_VERSION/nu-$NU_VERSION-x86_64-unknown-linux-gnu.tar.gz"
    curl "${curl_opts[@]}" "$url" -o "$tmp/nu.tar.gz" || return 1
    verify_sha256 "$tmp/nu.tar.gz" "$NU_SHA256" || return 1
    tar -xzf "$tmp/nu.tar.gz" -C "$tmp" || return 1
    verify_runs "$tmp/nu-$NU_VERSION-x86_64-unknown-linux-gnu/nu" nushell || return 1
    install -m 755 "$tmp/nu-$NU_VERSION-x86_64-unknown-linux-gnu/nu" /usr/local/bin/nu || return 1
}

# Go is at /usr/local/go/bin on the runner image, which sudo's secure_path
# does not include -- so `command -v go` inside this script comes up empty even
# though the job's own steps can run it. $GOROOT is what names a Go
# installation somewhere else again, so it decides where to look before the
# default does. Kept identical to the session-start hook's copy: two installers
# disagreeing about where Go lives is the drift test-tool-versions.sh exists to
# prevent, one field over.
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

install_elvish() {
    _go=$(find_go) || {
        echo "install-ci-shells: no go toolchain; cannot build elvish" >&2
        return 1
    }
    # GOBIN rather than the default $HOME/go/bin: this runs under sudo, so the
    # default would land in root's home, which is on nobody's PATH.
    GOBIN=/usr/local/bin "$_go" install "src.elv.sh/cmd/elvish@v$ELVISH_VERSION" || return 1
}

install_zsh() {
    # -qq and DEBIAN_FRONTEND keep a failure visible instead of buried under
    # progress output, and stop a package asking a question no one can answer.
    DEBIAN_FRONTEND=noninteractive apt-get update -qq || return 1
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends zsh || return 1
}

# Anything already present is left alone: a runner image that grows its own zsh
# is not ours to replace, and the version that ran is printed either way so a
# result disagreeing with a local run has its explanation in the job log.
#
# The version probe's status is checked rather than interpolated straight into
# the message. A binary that is present but cannot run -- wrong architecture, a
# half-written file -- fails inside `$( )`, and `echo` would still succeed, so
# install_tool would return 0 and hand `make test` an interpreter that does not
# work. The session-start hook checks the same way, for the same reason.
install_tool() {
    _name=$1
    _installer=$2
    if command -v "$_name" >/dev/null 2>&1; then
        if ! _version=$("$_name" --version 2>/dev/null | head -1); then
            echo "install-ci-shells: $_name is on PATH but will not run" >&2
            return 1
        fi
        echo "install-ci-shells: using the installed $_name: $_version"
        return 0
    fi
    if "$_installer"; then
        if ! _version=$("$_name" --version 2>/dev/null | head -1); then
            echo "install-ci-shells: the installed $_name will not run" >&2
            return 1
        fi
        echo "install-ci-shells: installed $_name: $_version"
        return 0
    fi
    return 1
}

# Failing loudly is the point. A missing shell here does not break `make test`
# -- it skips, and the job passes having tested less than it claims -- which is
# exactly the silent hole this script was written to close.
status=0
for entry in "zsh install_zsh" "fish install_fish" "nu install_nu" "elvish install_elvish"; do
    # shellcheck disable=SC2086 # the pair is two fields on purpose
    set -- $entry
    if ! install_tool "$1" "$2"; then
        echo "install-ci-shells: $1 install failed; its suite would silently skip" >&2
        status=1
    fi
done
exit "$status"
