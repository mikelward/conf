#!/bin/sh
#
# Tests for install-ci-shells.sh, the step that puts zsh, fish, nu and elvish
# on the CI runner so `make test` covers more than bash and dash.
#
# The script downloads from the network, shells out to apt and go, and installs
# into /usr/local/bin, so these tests never run it for real. Each case puts a
# fake curl/tar/install/apt-get/go on PATH and checks the script's decisions: does it
# skip what is already there, does it fetch the pinned release, does it refuse
# a bad download, does it report a failure rather than exiting 0 on a shell
# whose suite would then silently skip.
#

. "$(dirname "$0")/shrc_test_lib.sh"

_script="$_srcdir/install-ci-shells.sh"

if ! test -x "$_script"; then
    skip_all "install-ci-shells.sh missing or not executable"
    test_summary "install-ci-shells"
    exit 0
fi

# Mirrors the pins the script sources, so the stubbed tar lays the binaries
# down where the installers look for them.
NU_DIR=$(sed -n 's/^NU_VERSION=//p' "$_srcdir/test-tool-versions.sh")

# The PATH this yields is the *whole* PATH — the real /usr/bin is deliberately
# absent, so a tool the script checks for cannot be found by accident. Without
# that, `command -v zsh` finds the runner's own zsh and every "when it is
# missing" case silently asserts the already-installed branch instead.
#
# "$1" is the exit status curl should report.
_stub_dir() {
    _curl_status=$1
    _dir=$(mktemp -d)

    # Symlink only what stays real. A name that is also stubbed below must not
    # be linked first: the stub is written with `>`, which follows the symlink
    # and would overwrite the system binary it points at.
    for _real_cmd in mktemp mkdir rm sed head cat chmod dirname; do
        if _real_path=$(command -v "$_real_cmd" 2>/dev/null); then
            ln -sf "$_real_path" "$_dir/$_real_cmd"
        fi
    done

    cat >"$_dir/curl" <<EOF
#!/bin/sh
echo "curl \$*" >>"$_dir/calls"
exit $_curl_status
EOF

    # A real extraction leaves a runnable binary and the script probes it
    # before publishing anything, so the stub has to produce one at the path
    # each installer looks for. fish extracts to a bare \`fish\`; nu to a
    # versioned directory.
    cat >"$_dir/tar" <<EOF
#!/bin/sh
echo "tar \$*" >>"$_dir/calls"
_out=
while test \$# -gt 0; do
    if test "\$1" = "-C"; then shift; _out=\$1; fi
    shift
done
test -n "\$_out" || exit 0
for _f in "\$_out/fish" "\$_out/nu-$NU_DIR-x86_64-unknown-linux-gnu/nu"; do
    mkdir -p "\${_f%/*}"
    printf '#!/bin/sh\nprintf "9.9.9\\\\n"\n' >"\$_f"
    chmod +x "\$_f"
done
exit 0
EOF

    # A real `install` leaves a runnable binary behind and the script reads a
    # version from it afterwards, so the stub produces one under the
    # destination's name inside the stub dir — which is also on PATH, so the
    # later `command -v` sees it exactly as the real one would.
    cat >"$_dir/install" <<EOF
#!/bin/sh
echo "install \$*" >>"$_dir/calls"
for _arg in "\$@"; do _dest=\$_arg; done
_name=\${_dest##*/}
printf '#!/bin/sh\nprintf "9.9.9\\\\n"\n' >"$_dir/\$_name"
chmod +x "$_dir/\$_name"
exit 0
EOF

    # apt-get is the zsh path. Reports success and leaves a runnable zsh, the
    # same shape a real install has.
    cat >"$_dir/apt-get" <<EOF
#!/bin/sh
echo "apt-get \$*" >>"$_dir/calls"
if test "\$1" = install; then
    printf '#!/bin/sh\nprintf "9.9.9\\\\n"\n' >"$_dir/zsh"
    chmod +x "$_dir/zsh"
fi
exit 0
EOF

    # `go install` is the elvish path. Leaves a runnable binary under GOBIN
    # the way the real one does, so the version probe afterwards finds it.
    cat >"$_dir/go" <<EOF
#!/bin/sh
# GOBIN is logged too: where the build lands is the decision worth asserting,
# since the default would be root's home under sudo.
echo "go GOBIN=\${GOBIN-unset} \$*" >>"$_dir/calls"
printf '#!/bin/sh\nprintf "9.9.9\\n"\n' >"$_dir/elvish"
chmod +x "$_dir/elvish"
exit 0
EOF

    # The stubbed curl writes nothing, so the real sha256sum would fail every
    # happy-path case. Stubbed to pass; the mismatch case overrides it.
    cat >"$_dir/sha256sum" <<EOF
#!/bin/sh
echo "sha256sum \$*" >>"$_dir/calls"
exit 0
EOF

    chmod +x "$_dir/curl" "$_dir/tar" "$_dir/install" "$_dir/apt-get" "$_dir/sha256sum" \
             "$_dir/go"
    puts "$_dir"
}

# A runner image that already ships a shell is not ours to replace, and a
# re-run must not re-download what is already there.
start_test "skips every install when all four shells are present"
_stubs=$(_stub_dir 0)
for _present in zsh fish nu elvish; do
    printf '#!/bin/sh\nprintf "9.9.9\\n"\n' >"$_stubs/$_present"
    chmod +x "$_stubs/$_present"
done
PATH="$_stubs" "$_script" >/dev/null 2>&1
assert_equal "0" "$?"
start_test "downloads nothing when the shells are already present"
assert_false test -e "$_stubs/calls"
rm -rf "$_stubs"

# The case the script exists for. Each shell is fetched from the source that
# actually publishes it, which is the decision worth pinning down: fish and nu
# from their own releases, zsh from apt.
# stderr is kept rather than discarded, and printed when the status is wrong.
# The script names which shell failed and why on every path; throwing that away
# left a CI-only failure here with nothing to go on but "expected 0, actual 1",
# while the call assertions below still passed -- so the run reached every
# installer and something after the logging returned non-zero, and which one it
# was could not be recovered from the job log. A flake nobody can read is a
# flake nobody can fix.
start_test "installs all four when none is present"
_stubs=$(_stub_dir 0)
_err=$(PATH="$_stubs" "$_script" 2>&1 >/dev/null)
_status=$?
if test "$_status" -ne 0; then
    puts "  the script said:" >&2
    puts "$_err" >&2
fi
assert_equal "0" "$_status"
_calls=$(cat "$_stubs/calls" 2>/dev/null)
start_test "fetches fish from its own release rather than apt"
assert_contains "fish-shell/fish-shell/releases" "$_calls"
start_test "fetches nu from its own release rather than apt"
assert_contains "nushell/nushell/releases" "$_calls"
start_test "installs zsh from apt, which is the only source that has it"
assert_contains "apt-get install" "$_calls"
# elvish publishes no release asset to pin, so it is built from source at a
# tagged version and verified by the Go checksum database instead.
start_test "builds elvish from its module at a pinned version"
_elvish_version=$(sed -n 's/^ELVISH_VERSION=//p' "$_srcdir/test-tool-versions.sh")
assert_contains "src.elv.sh/cmd/elvish@v$_elvish_version" "$_calls"
start_test "puts the elvish build somewhere already on PATH"
assert_contains "go GOBIN=/usr/local/bin install" "$_calls"
rm -rf "$_stubs"

# The pins are what make a red CI run mean "the config broke" rather than
# "upstream moved", so the fetched URL has to carry the pinned version.
start_test "fetches the pinned fish version"
_stubs=$(_stub_dir 0)
PATH="$_stubs" "$_script" >/dev/null 2>&1
_fish_version=$(sed -n 's/^FISH_VERSION=//p' "$_srcdir/test-tool-versions.sh")
assert_contains "releases/download/$_fish_version/" "$(cat "$_stubs/calls" 2>/dev/null)"
rm -rf "$_stubs"

# A download that fails has to be reported. Exiting 0 here would leave the
# suite skipping that shell while the job still went green — the exact silent
# hole this script closes.
start_test "exits non-zero when a download fails"
_stubs=$(_stub_dir 1)
PATH="$_stubs" "$_script" >/dev/null 2>&1
assert_equal "1" "$?"

start_test "names the shell whose install failed"
_stubs=$(_stub_dir 1)
_err=$(PATH="$_stubs" "$_script" 2>&1 >/dev/null)
assert_contains "fish install failed" "$_err"
start_test "says a failed install would leave the suite skipping"
assert_contains "silently skip" "$_err"
rm -rf "$_stubs"

# A checksum is only worth having if a mismatch stops the install. Otherwise a
# replaced asset ships a binary every later test executes.
start_test "refuses to install when the checksum does not match"
_stubs=$(_stub_dir 0)
cat >"$_stubs/sha256sum" <<EOF
#!/bin/sh
echo "sha256sum \$*" >>"$_stubs/calls"
exit 1
EOF
chmod +x "$_stubs/sha256sum"
_err=$(PATH="$_stubs" "$_script" 2>&1 >/dev/null)
start_test "reports the checksum failure by name"
assert_contains "failed its checksum" "$_err"
start_test "installs nothing after a checksum failure"
assert_false grep -q "^install " "$_stubs/calls"
rm -rf "$_stubs"

# `command -v` is satisfied by a file that cannot execute — wrong
# architecture, truncated download — and the Makefile's gate would then take
# the run branch, turning a clean skip into a suite-wide failure naming the
# wrong cause.
start_test "refuses a downloaded binary that does not run"
_stubs=$(_stub_dir 0)
cat >"$_stubs/tar" <<EOF
#!/bin/sh
echo "tar \$*" >>"$_stubs/calls"
_out=
while test \$# -gt 0; do
    if test "\$1" = "-C"; then shift; _out=\$1; fi
    shift
done
test -n "\$_out" || exit 0
for _f in "\$_out/fish" "\$_out/nu-$NU_DIR-x86_64-unknown-linux-gnu/nu"; do
    mkdir -p "\${_f%/*}"
    printf '#!/bin/sh\nexit 1\n' >"\$_f"
    chmod +x "\$_f"
done
exit 0
EOF
chmod +x "$_stubs/tar"
_err=$(PATH="$_stubs" "$_script" 2>&1 >/dev/null)
start_test "reports the unrunnable binary rather than installing it"
assert_contains "does not run" "$_err"
rm -rf "$_stubs"

# A reset mid-transfer on a ~76 MB download is the network's doing, not a
# signal about the config, and it reddened a CI run in which nothing was wrong.
# The checksum still decides what gets installed, so retrying cannot smuggle in
# a corrupt file.
start_test "downloads are retried so a transient reset is not a CI failure"
_stubs=$(_stub_dir 0)
PATH="$_stubs" "$_script" >/dev/null 2>&1
_calls=$(cat "$_stubs/calls" 2>/dev/null)
assert_contains "--retry 3" "$_calls"
start_test "a connection reset counts as retryable"
# --retry alone does not cover curl error 35; --retry-all-errors is the flag
# that does, which is the one the failure actually needed.
assert_contains "--retry-all-errors" "$_calls"
rm -rf "$_stubs"

# `command -v` is satisfied by a file that cannot execute, and the version
# probe used to be interpolated into the message -- so the failure happened
# inside `$( )` while `echo` succeeded, and a broken interpreter was reported
# as "using the installed ...". `make test` then ran against it.
start_test "refuses a present shell whose version probe fails"
_stubs=$(_stub_dir 0)
for _broken in zsh fish nu elvish; do
    printf '#!/bin/sh\nexit 1\n' >"$_stubs/$_broken"
    chmod +x "$_stubs/$_broken"
done
PATH="$_stubs" "$_script" >/dev/null 2>&1
assert_equal "1" "$?"

start_test "says the present shell will not run"
_err=$(PATH="$_stubs" "$_script" 2>&1 >/dev/null)
assert_contains "will not run" "$_err"

start_test "does not report a broken shell as usable"
_out=$(PATH="$_stubs" "$_script" 2>/dev/null)
assert_not_contains "using the installed" "$_out"
rm -rf "$_stubs"

test_summary "install-ci-shells"
