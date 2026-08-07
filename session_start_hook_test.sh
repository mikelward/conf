#!/bin/sh
#
# Tests for .claude/hooks/session-start.sh, the SessionStart hook that installs
# the tools `make test` needs but the container image does not ship.
#
# The hook installs to /usr/local/bin and needs the network, so these tests
# never run it for real. Each case puts a fake curl/tar/install on PATH and
# checks the hook's decisions: does it exit early, does it install, does it
# report a failure rather than swallowing it.
#

. "$(dirname "$0")/shrc_test_lib.sh"

_hook="$_srcdir/.claude/hooks/session-start.sh"

if ! test -x "$_hook"; then
    skip_all "session-start.sh missing or not executable"
    test_summary "session-start hook"
    exit 0
fi

# Build a PATH containing stubs for everything the hook shells out to, so a
# test run never reaches the network or writes outside its own temp dir.
#
# The stubs append to a `calls` log, and the assertions below read it with
# `cat ... 2>/dev/null`. That redirect is deliberate: a missing log is the
# expected state whenever the hook correctly downloads nothing, so `cat`
# failing there is the passing path, not a swallowed error. An empty `actual:`
# in the failure output already says the log was not written.
#
# "$1" is the exit status curl should report.
#
# The PATH this yields is the *whole* PATH — the real /usr/bin is deliberately
# absent, so the coreutils the hook needs are symlinked in one at a time. A
# test PATH that keeps /usr/bin is not hermetic: CI installs shellcheck there,
# `command -v shellcheck` then succeeds, and every "when it is missing" case
# silently asserts the already-installed branch instead.
# The stubbed tar has to lay the binaries down where the installers expect to
# find them, which means knowing the pinned versions. Read from the same file
# the hook sources rather than copied: hard-coded here, a bump in
# test-tool-versions.sh sent the hook looking in one directory while the stub
# wrote to another, and the failure named the download rather than the pin.
SC_DIR=$(sed -n 's/^SHELLCHECK_VERSION=//p' "$_srcdir/test-tool-versions.sh")
NU_DIR=$(sed -n 's/^NU_VERSION=//p' "$_srcdir/test-tool-versions.sh")
_elvish_pin=$(sed -n 's/^ELVISH_VERSION=//p' "$_srcdir/test-tool-versions.sh")

_stub_dir() {
    _curl_status=$1
    _dir=$(mktemp -d)

    # Symlink only what stays real. A name that is also stubbed below must not
    # be linked first: the stub is written with `>`, which follows the symlink
    # and overwrites the system binary it points at.
    for _real_cmd in mktemp mkdir rm sed head cat chmod; do
        if _real_path=$(command -v "$_real_cmd" 2>/dev/null); then
            ln -sf "$_real_path" "$_dir/$_real_cmd"
        fi
    done

    cat >"$_dir/curl" <<EOF
#!/bin/sh
echo "curl \$*" >>"$_dir/calls"
exit $_curl_status
EOF

    # A real extraction leaves a runnable binary, and the hook probes it
    # before publishing anything — so the stub has to produce one at the path
    # each installer looks for.
    cat >"$_dir/tar" <<EOF
#!/bin/sh
echo "tar \$*" >>"$_dir/calls"
_out=
while test \$# -gt 0; do
    if test "\$1" = "-C"; then shift; _out=\$1; fi
    shift
done
test -n "\$_out" || exit 0
for _f in "\$_out/shellcheck-v$SC_DIR/shellcheck" "\$_out/nu-$NU_DIR-x86_64-unknown-linux-gnu/nu"; do
    mkdir -p "\${_f%/*}"
    printf '#!/bin/sh\nprintf "version: 9.9.9\\\\n"\n' >"\$_f"
    chmod +x "\$_f"
done
exit 0
EOF

    # A real `install` leaves a runnable binary behind, and the hook probes it
    # for a version afterwards — so the stub has to produce one, not just
    # report success.
    #
    # Where it lands matters. A destination inside the sandbox is honored as
    # given, so a test can watch the hook overwrite a specific file; anything
    # else is a real system path (/usr/local/bin) and gets mapped into the stub
    # dir, which stands in for it. Mapping *everything* to the basename was the
    # bug in the first version of this stub: it made "publish to /usr/local/bin"
    # and "overwrite the copy that resolved" write to the same file, so a hook
    # that published to the wrong path still passed.
    cat >"$_dir/install" <<EOF
#!/bin/sh
echo "install \$*" >>"$_dir/calls"
for _arg in "\$@"; do _dest=\$_arg; done
case "\$_dest" in
    ${TMPDIR:-/tmp}/*) ;;
    *) _dest="$_dir/\${_dest##*/}" ;;
esac
printf '#!/bin/sh\nprintf "version: 9.9.9\\\\n"\n' >"\$_dest"
chmod +x "\$_dest"
exit 0
EOF

    # The stubbed curl writes nothing, so the real sha256sum would fail every
    # happy-path case. Stubbed to pass; the checksum-mismatch case overrides it.
    #
    # It drains stdin, which is not decoration. The hook pipes the expected sum
    # in -- `echo "$2  $1" | sha256sum --check --strict -` -- under `set -o
    # pipefail`, so a stub that exits without reading can close the pipe before
    # `echo` writes to it. `echo` then fails with EPIPE and pipefail makes the
    # whole pipeline fail, turning a fine checksum into `failed its checksum`
    # and the install into a spurious error. It is a race, so it showed up as
    # this suite failing under parallel `make test` and naming a different test
    # each time. A real sha256sum reads its input; so does this.
    cat >"$_dir/sha256sum" <<EOF
#!/bin/sh
echo "sha256sum \$*" >>"$_dir/calls"
cat >/dev/null
exit 0
EOF

    # `go install` is the elvish path, and it is stubbed for the same reason as
    # curl: unstubbed, the hook would build from the network on every case here.
    # It has to exist even in the cases that are about shellcheck, since
    # find_go's fallback would otherwise reach the real toolchain this image
    # ships at /usr/local/go/bin and start a build nobody asked for.
    #
    # GOBIN is obeyed as well as logged. A real build leaves a runnable binary
    # there and the hook probes it before publishing, so a stub that only
    # logged would fail the probe and never reach `install`.
    cat >"$_dir/go" <<EOF
#!/bin/sh
echo "go GOBIN=\${GOBIN-unset} \$*" >>"$_dir/calls"
test -n "\${GOBIN-}" || exit 1
printf '#!/bin/sh\nprintf "9.9.9\\\\n"\n' >"\$GOBIN/elvish"
chmod +x "\$GOBIN/elvish"
exit 0
EOF

    # Passes the build through so the bound is observable without a real wait.
    # Exit 124 -- what a real timeout reports when it fires -- gets its own case
    # below rather than being simulated here.
    cat >"$_dir/timeout" <<EOF
#!/bin/sh
echo "timeout \$*" >>"$_dir/calls"
shift
exec "\$@"
EOF

    chmod +x "$_dir/curl" "$_dir/tar" "$_dir/install" "$_dir/sha256sum" \
             "$_dir/go" "$_dir/timeout"
    puts "$_dir"
}

# Stub a tool as already installed, so a case about one tool is not also
# exercising another's install path.
_present() {
    for _p in "$@"; do
        printf '#!/bin/sh\nexit 0\n' >"$_p"
        chmod +x "$_p"
    done
}

# The container is the only place that starts bare — a local checkout already
# has its tools, so the hook must do nothing at all there.
start_test "does nothing when not in a remote container"
_stubs=$(_stub_dir 0)
CLAUDE_CODE_REMOTE='' PATH="$_stubs" "$_hook" >/dev/null 2>&1
assert_equal "0" "$?"
start_test "makes no calls when not in a remote container"
assert_false test -e "$_stubs/calls"
rm -rf "$_stubs"

# Re-running a session must not re-download tools that are already present.
start_test "skips install when shellcheck, nu and elvish are already present"
_stubs=$(_stub_dir 0)
_present "$_stubs/shellcheck" "$_stubs/nu" "$_stubs/elvish"
CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" >/dev/null 2>&1
assert_equal "0" "$?"
start_test "downloads nothing when the tools are already present"
assert_false test -e "$_stubs/calls"
rm -rf "$_stubs"

# A missing shellcheck is the case the hook exists for: without it `make test`
# dies at the lint stage with exit 127.
start_test "installs shellcheck when it is missing"
_stubs=$(_stub_dir 0)
cat >"$_stubs/nu" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$_stubs/nu"
CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" >/dev/null 2>&1
assert_equal "0" "$?"
start_test "fetches the shellcheck release when it is missing"
assert_contains "shellcheck" "$(cat "$_stubs/calls" 2>/dev/null)"
rm -rf "$_stubs"

# A failed shellcheck download is fatal: continuing would leave the session
# reporting a spurious test failure later instead of the real cause now.
start_test "exits non-zero when the shellcheck download fails"
_stubs=$(_stub_dir 1)
cat >"$_stubs/nu" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$_stubs/nu"
_err=$(CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" 2>&1 >/dev/null)
_status=$?
assert_equal "1" "$_status"
start_test "says why the shellcheck download failure matters"
assert_contains "shellcheck" "$_err"
rm -rf "$_stubs"

# nushell is the soft one — losing it only skips the nu-native tests, so the
# hook reports the failure and lets the session continue.
start_test "a failed nushell install is reported but not fatal"
_stubs=$(_stub_dir 0)
cat >"$_stubs/shellcheck" <<'EOF'
#!/bin/sh
exit 0
EOF
# curl succeeds for shellcheck and fails for nushell, so only the soft
# dependency is missing.
cat >"$_stubs/curl" <<EOF
#!/bin/sh
case "\$*" in
    *nushell*) exit 1 ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$_stubs/shellcheck" "$_stubs/curl"
_err=$(CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" 2>&1 >/dev/null)
assert_equal "0" "$?"
start_test "names nushell when its install fails"
assert_contains "nushell" "$_err"
rm -rf "$_stubs"

# Elvish is soft in the same way, so a failed build reports and lets the
# session continue rather than taking the whole hook down with it.
start_test "a failed elvish build is reported but not fatal"
_stubs=$(_stub_dir 0)
_present "$_stubs/shellcheck" "$_stubs/nu"
printf '#!/bin/sh\necho "go $*" >>"%s/calls"\nexit 1\n' "$_stubs" >"$_stubs/go"
chmod +x "$_stubs/go"
_err=$(CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" 2>&1 >/dev/null)
assert_equal "0" "$?"
start_test "names elvish when its build fails"
assert_contains "elvish" "$_err"
rm -rf "$_stubs"

# 124 is what `timeout` reports when it fires, and it says something the
# generic failure does not: the build was cut off rather than broken.
start_test "a build that hits the time bound says so"
_stubs=$(_stub_dir 0)
_present "$_stubs/shellcheck" "$_stubs/nu"
printf '#!/bin/sh\necho "timeout $*" >>"%s/calls"\nexit 124\n' "$_stubs" >"$_stubs/timeout"
chmod +x "$_stubs/timeout"
_err=$(CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" 2>&1 >/dev/null)
assert_equal "0" "$?"
start_test "a build that hits the time bound is not fatal"
assert_contains "did not finish within" "$_err"
start_test "a timed-out build never reaches install"
assert_false grep -q '^install .*elvish' "$_stubs/calls"
rm -rf "$_stubs"

# Same reasoning as the shellcheck/nu case: once a broken elvish is on PATH,
# `command -v` succeeds forever, this hook stops retrying, and the Makefile's
# own `command -v elvish` gate runs the suite against it instead of skipping.
start_test "a built elvish that will not run is never installed"
_stubs=$(_stub_dir 0)
_present "$_stubs/shellcheck" "$_stubs/nu"
cat >"$_stubs/go" <<EOF
#!/bin/sh
echo "go GOBIN=\${GOBIN-unset} \$*" >>"$_stubs/calls"
printf '#!/bin/sh\nexit 127\n' >"\$GOBIN/elvish"
chmod +x "\$GOBIN/elvish"
exit 0
EOF
chmod +x "$_stubs/go"
_err=$(CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" 2>&1 >/dev/null)
assert_equal "0" "$?"
start_test "says the built elvish does not run"
assert_contains "does not run" "$_err"
start_test "an elvish that will not run never reaches install"
assert_false grep -q '^install .*elvish' "$_stubs/calls"
rm -rf "$_stubs"

# A broken elvish already on PATH is the one case that does not skip:
# Makefile:240 and elvish_test.sh:30 gate on `command -v elvish` alone, so the
# suite runs against it. Building over it is the only thing that helps.
#
# The broken copy goes in a directory ahead of the stub dir on PATH, which is
# the layout env:34 actually produces — five dirs ($HOME/scripts.local,
# $HOME/scripts, $HOME/bin, $HOME/.cargo/bin, $HOME/.local/bin) sit ahead of
# /usr/local/bin. Publishing the replacement to /usr/local/bin leaves the
# broken one still winning the lookup, so the test has to place them apart to
# see the difference at all.
start_test "replaces an elvish that is on PATH but will not run"
_stubs=$(_stub_dir 0)
_early=$(mktemp -d)
_present "$_stubs/shellcheck" "$_stubs/nu"
printf '#!/bin/sh\nexit 127\n' >"$_early/elvish"
chmod +x "$_early/elvish"
_err=$(CLAUDE_CODE_REMOTE=true PATH="$_early:$_stubs" "$_hook" 2>&1 >/dev/null)
assert_equal "0" "$?"
start_test "overwrites the elvish that resolved, not /usr/local/bin"
assert_contains "$_early/elvish" "$(cat "$_stubs/calls" 2>/dev/null)"
start_test "leaves a runnable elvish where the broken one was"
assert_true test -x "$_early/elvish"
assert_equal "version: 9.9.9" "$("$_early/elvish" --version)"
start_test "reports the replacement rather than a skip"
assert_contains "installed elvish: version: 9.9.9" "$_err"
rm -rf "$_stubs" "$_early"

# When it cannot be replaced, the message has to say what actually happens.
# Promising a skip here sends someone looking for the wrong thing when the
# suite fails a minute later.
start_test "says the suite will fail when a broken elvish cannot be replaced"
_stubs=$(_stub_dir 0)
_present "$_stubs/shellcheck" "$_stubs/nu"
printf '#!/bin/sh\nexit 127\n' >"$_stubs/elvish"
printf '#!/bin/sh\necho "go $*" >>"%s/calls"\nexit 1\n' "$_stubs" >"$_stubs/go"
chmod +x "$_stubs/elvish" "$_stubs/go"
_err=$(CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" 2>&1 >/dev/null)
assert_equal "0" "$?"
start_test "does not promise a skip it cannot deliver"
assert_contains "will fail rather than skip" "$_err"
rm -rf "$_stubs"

# The one way this container can differ from the CI runner: the runner is known
# to ship Go, and an image here that does not would otherwise fail with `go:
# command not found` and no clue that the toolchain, not the build, was the
# problem. $GOROOT points the search at an empty directory to reach the case
# without depending on this image lacking the real one.
start_test "reports a missing go toolchain rather than failing obscurely"
_stubs=$(_stub_dir 0)
_present "$_stubs/shellcheck" "$_stubs/nu"
rm -f "$_stubs/go"
mkdir -p "$_stubs/nogo"
_err=$(CLAUDE_CODE_REMOTE=true GOROOT="$_stubs/nogo" PATH="$_stubs" "$_hook" 2>&1 >/dev/null)
assert_equal "0" "$?"
start_test "says it is the toolchain that is missing"
assert_contains "no go toolchain" "$_err"
start_test "a missing go toolchain leaves elvish uninstalled rather than half-built"
assert_false test -e "$_stubs/elvish"
rm -rf "$_stubs"

# The other side of that branch, and the one that actually happens: Go is
# installed but off PATH, which is how both this image and the CI runner are
# laid out. Every other case hands the stub over on PATH, so the fallback
# would otherwise only be covered where it fails.
start_test "finds go through GOROOT when it is not on PATH"
_stubs=$(_stub_dir 0)
_present "$_stubs/shellcheck" "$_stubs/nu"
mkdir -p "$_stubs/goroot/bin"
mv "$_stubs/go" "$_stubs/goroot/bin/go"
CLAUDE_CODE_REMOTE=true GOROOT="$_stubs/goroot" PATH="$_stubs" "$_hook" >/dev/null 2>&1
assert_equal "0" "$?"
start_test "builds elvish through the GOROOT fallback"
assert_contains "src.elv.sh/cmd/elvish@v$_elvish_pin" "$(cat "$_stubs/calls" 2>/dev/null)"
rm -rf "$_stubs"

# Whatever is already installed gets reported rather than replaced or
# compared against the pin, so the version the tests ran against is on the
# record. A result that disagrees with CI then has its explanation in the
# session log instead of needing to be rediscovered.
_installed_stubs() {
    _sc_version=$1
    _nu_version=$2
    _elvish_version=$3
    _dir=$(_stub_dir 0)
    cat >"$_dir/shellcheck" <<EOF
#!/bin/sh
echo "ShellCheck - shell script analysis tool"
echo "version: $_sc_version"
EOF
    cat >"$_dir/nu" <<EOF
#!/bin/sh
echo "$_nu_version"
EOF
    cat >"$_dir/elvish" <<EOF
#!/bin/sh
echo "$_elvish_version"
EOF
    chmod +x "$_dir/shellcheck" "$_dir/nu" "$_dir/elvish"
    puts "$_dir"
}

start_test "reports the installed shellcheck version"
_stubs=$(_installed_stubs 0.9.0 0.99.0 0.98.0)
_err=$(CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" 2>&1 >/dev/null)
_status=$?
assert_contains "0.9.0" "$_err"
start_test "reports the installed nushell version"
assert_contains "0.99.0" "$_err"
start_test "reports the installed elvish version"
assert_contains "0.98.0" "$_err"
start_test "an off-pin version is not fatal"
assert_equal "0" "$_status"
start_test "an off-pin version does not trigger a download"
assert_false test -e "$_stubs/calls"
rm -rf "$_stubs"

# A first run is the case this hook exists for, and it is the one that used to
# leave no version in the log — the report only fired on the already-installed
# path.
_stubs=$(_stub_dir 0)
_err=$(CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" 2>&1 >/dev/null)
# Named per tool: asserting only that "9.9.9" appears anywhere would pass on
# the nushell report alone while shellcheck's went missing.
start_test "reports the shellcheck version after installing it"
assert_contains "installed shellcheck: 9.9.9" "$_err"
start_test "reports the nushell version after installing it"
assert_contains "installed nushell: version: 9.9.9" "$_err"
start_test "reports the elvish version after installing it"
assert_contains "installed elvish: version: 9.9.9" "$_err"
# Elvish is the one built rather than downloaded, so the pin has to reach the
# module path -- an unversioned `go install` would silently track upstream's
# latest and put the container on a different Elvish than CI.
start_test "builds elvish from its module at the pinned version"
assert_contains "src.elv.sh/cmd/elvish@v$_elvish_pin" "$(cat "$_stubs/calls" 2>/dev/null)"
start_test "publishes the elvish build somewhere already on PATH"
assert_contains "/usr/local/bin/elvish" "$(cat "$_stubs/calls" 2>/dev/null)"
# The build itself lands unpublished, so nothing reaches PATH before the probe
# below has run it.
start_test "builds elvish somewhere other than its final home"
assert_false grep -q '^go GOBIN=/usr/local/bin ' "$_stubs/calls"
# `go install` has no duration flag, so an outage would otherwise hold up the
# session indefinitely instead of letting the optional tool drop out.
start_test "bounds the elvish build"
assert_contains "timeout 300" "$(cat "$_stubs/calls" 2>/dev/null)"
rm -rf "$_stubs"

# `command -v` only proves a name resolves. A binary that cannot execute —
# wrong architecture, missing loader, truncated file — would otherwise be
# accepted silently and the lint target would fail later with no hint why.
start_test "reports a tool that is on PATH but will not run"
_stubs=$(_stub_dir 0)
printf '#!/bin/sh\nexit 127\n' >"$_stubs/shellcheck"
printf '#!/bin/sh\nexit 0\n' >"$_stubs/nu"
chmod +x "$_stubs/shellcheck" "$_stubs/nu"
_err=$(CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" 2>&1 >/dev/null)
assert_contains "will not run" "$_err"
rm -rf "$_stubs"

# `set -e` does not apply inside a function invoked as `if ! install_x`, so an
# unchecked tar could fall through to `install` and ship a partial binary.
start_test "a failed extraction stops before install"
_stubs=$(_stub_dir 0)
printf '#!/bin/sh\necho "tar $*" >>"%s/calls"\nexit 1\n' "$_stubs" >"$_stubs/tar"
printf '#!/bin/sh\nexit 0\n' >"$_stubs/nu"
chmod +x "$_stubs/tar" "$_stubs/nu"
_err=$(CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" 2>&1 >/dev/null)
_status=$?
assert_equal "1" "$_status"
start_test "a failed extraction never reaches install"
assert_false grep -q '^install ' "$_stubs/calls"
rm -rf "$_stubs"

# A stalled download would otherwise hold up session startup indefinitely.
# The hook is expected to succeed here, so its status is asserted rather than
# discarded: a `|| true` would let a broken install path pass this case on the
# strength of the curl flags alone.
_stubs=$(_stub_dir 0)
printf '#!/bin/sh\nexit 0\n' >"$_stubs/nu"
chmod +x "$_stubs/nu"
CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" >/dev/null 2>&1
start_test "the hook succeeds on the install path"
assert_equal "0" "$?"
start_test "bounds both downloads with timeouts"
assert_contains "--connect-timeout" "$(cat "$_stubs/calls" 2>/dev/null)"
start_test "bounds the transfer, not just the connection"
assert_contains "--max-time" "$(cat "$_stubs/calls" 2>/dev/null)"
rm -rf "$_stubs"

# A replaced release asset or a compromised publisher account would otherwise
# be extracted and installed, and every later test would execute it.
start_test "a checksum mismatch stops before extraction"
_stubs=$(_stub_dir 0)
printf '#!/bin/sh\necho "sha256sum $*" >>"%s/calls"\ncat >/dev/null\nexit 1\n' "$_stubs" >"$_stubs/sha256sum"
printf '#!/bin/sh\nexit 0\n' >"$_stubs/nu"
chmod +x "$_stubs/sha256sum" "$_stubs/nu"
_err=$(CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" 2>&1 >/dev/null)
_status=$?
assert_equal "1" "$_status"
start_test "says the checksum failed"
assert_contains "checksum" "$_err"
start_test "a checksum mismatch never reaches tar or install"
assert_false grep -qE '^(tar|install) ' "$_stubs/calls"
rm -rf "$_stubs"

# Publishing a binary that cannot execute is worse than installing nothing:
# `command -v` then succeeds forever, so this hook stops retrying and the
# Makefile's `command -v nu` gate picks the run branch on the broken leftover.
start_test "a downloaded binary that will not run is never installed"
_stubs=$(_stub_dir 0)
# tar lays down a file that exits non-zero instead of a working binary.
cat >"$_stubs/tar" <<EOF
#!/bin/sh
echo "tar \$*" >>"$_stubs/calls"
_out=
while test \$# -gt 0; do
    if test "\$1" = "-C"; then shift; _out=\$1; fi
    shift
done
test -n "\$_out" || exit 0
for _f in "\$_out/shellcheck-v$SC_DIR/shellcheck" "\$_out/nu-$NU_DIR-x86_64-unknown-linux-gnu/nu"; do
    mkdir -p "\${_f%/*}"
    printf '#!/bin/sh\nexit 127\n' >"\$_f"
    chmod +x "\$_f"
done
exit 0
EOF
chmod +x "$_stubs/tar"
_err=$(CLAUDE_CODE_REMOTE=true PATH="$_stubs" "$_hook" 2>&1 >/dev/null)
_status=$?
assert_equal "1" "$_status"
start_test "says the download does not run"
assert_contains "does not run" "$_err"
start_test "a binary that will not run never reaches install"
assert_false grep -q '^install ' "$_stubs/calls"
rm -rf "$_stubs"

test_summary "session-start hook"
