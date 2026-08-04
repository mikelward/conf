#!/bin/bash
#
# Tests for config/elvish/rc.elv and config/elvish/lib/interactive.elv.
# Mirrors mesh_test.sh but exercises the Elvish implementation.
# Skips gracefully when elvish is not installed.
#
# How the harness reaches the config: Elvish reads rc.elv only when it starts
# interactively, and "interactively" for Elvish means "no script argument and
# no -c" -- reading a program on stdin counts. So the snippets below are piped
# in with XDG_CONFIG_HOME pointed at the repo's config directory, which is
# where Elvish looks for both elvish/rc.elv and elvish/lib.
#
# Two consequences shape the assertions:
#
#   * `$edit:` doesn't exist without a terminal, so rc.elv's interactive block
#     (which is gated on stdin-is-tty) never runs here -- exactly as mesh_test
#     stops at rc.mesh's interactive section. The one test that needs a real
#     terminal runs under `script` at the bottom and is skipped without it.
#
#   * The stand-in line editor prints its prompt on *stderr*, so stdout is
#     clean and the helpers below capture the two streams separately.
#
# Stubbing note: `fn have-command ...` at the prompt creates a *new* variable
# rather than reassigning rc.elv's, and the functions compiled against the old
# one keep it -- so every stub here is written as `set have-command~ = {...}`.
#

. "$(dirname "$0")/shrc_test_lib.sh"

if ! command -v elvish >/dev/null 2>&1; then
    skip_all "elvish not installed"
    test_summary "elvish_test"
    exit 0
fi

_fakehome="$_testdir/fakehome"
mkdir -p "$_fakehome"

# Stub commands the tests need to be deterministic about. Prepended to PATH so
# rc.elv's own PATH setup (which only prepends directories that exist under the
# fake HOME) can't push them aside.
_stubs="$_testdir/stubs"
mkdir -p "$_stubs"
cat > "$_stubs/ssh" <<'STUB'
#!/bin/sh
printf 'ssh %s\n' "$*"
printf 'LC_CLIENT_HOST=%s\n' "${LC_CLIENT_HOST-unset}"
STUB
cat > "$_stubs/failing-tool" <<'STUB'
#!/bin/sh
echo "tool broke" >&2
exit 1
STUB
cat > "$_stubs/upper" <<'STUB'
#!/bin/sh
tr a-z A-Z < "$1"
STUB
# A working agent, so the interactive tests below don't end up calling the real
# `ssh-add` (or reporting that the host hasn't got one).
cat > "$_stubs/ssh-add" <<'STUB'
#!/bin/sh
echo "ssh-rsa AAAA test@example.com"
STUB
# Enough of atuin to exercise the session and the two history calls without a
# database behind them.
cat > "$_stubs/atuin" <<'STUB'
#!/bin/sh
case "$1 $2" in
"uuid ")       echo test-session-id ;;
# ATUIN_EMPTY_ID reproduces a `history start` that succeeds but prints nothing.
"history start") test -n "$ATUIN_EMPTY_ID" || echo test-history-id ;;
"history end")   exit 0 ;;
*)             exit 1 ;;
esac
STUB
chmod +x "$_stubs/ssh" "$_stubs/failing-tool" "$_stubs/upper" "$_stubs/ssh-add" \
         "$_stubs/atuin"

# A `cat` that always fails, in a directory of its own so a test can put it in
# front of the real one for the length of a single snippet. Stubbing the tool
# rather than chmod-ing the file keeps the test deterministic when the suite
# runs as root, where mode 000 still reads.
_badcat="$_testdir/badcat"
mkdir -p "$_badcat"
cat > "$_badcat/cat" <<'STUB'
#!/bin/sh
echo "cat: permission denied" >&2
exit 1
STUB
chmod +x "$_badcat/cat"

# A `vcs` that answers the calls preprompt makes, in a directory of its own so
# only the tests that want a repo see one. `unmerged` writes to both streams so
# a test can tell which of them the prompt keeps.
_vcsdir="$_testdir/vcsstub"
mkdir -p "$_vcsdir"
cat > "$_vcsdir/vcs" <<'STUB'
#!/bin/sh
case "$1" in
unmerged)
    echo "UNMERGED-WARNING"
    echo "vcs: a diagnostic" >&2
    ;;
auto-fetch) exit 0 ;;
*)          exit 1 ;;
esac
STUB
chmod +x "$_vcsdir/vcs"

# A `diff` that exits 2 -- "something went wrong", as opposed to the 1 that
# just means the files differ. In its own directory so only the test that wants
# a broken diff sees it.
_baddiff="$_testdir/baddiff"
mkdir -p "$_baddiff"
cat > "$_baddiff/diff" <<'STUB'
#!/bin/sh
echo "diff: cannot read file" >&2
exit 2
STUB
chmod +x "$_baddiff/diff"

# Run an Elvish snippet with rc.elv loaded, returning only its stdout.
#
# $1 is a preamble evaluated after rc.elv has been read (so it can replace a
# function the config defines), $2 the snippet under test. Either may be empty.
_elvish_run() {
    _elvish_stdin "$1" "$2" 2>/dev/null
}

# Same, with stderr folded into stdout, for the assertions about warnings. The
# line editor's own prompt lands on stderr too, so these assertions use
# assert_contains rather than assert_equal.
_elvish_run_all() {
    _elvish_stdin "$1" "$2" 2>&1
}

_elvish_stdin() {
    HOME="$_fakehome" \
        TERM=dumb \
        NO_COLOR=1 \
        HOSTNAME=host1 \
        USERNAME=bob \
        SHPOOL_SESSION_NAME= \
        TMUX= \
        SSH_CONNECTION= \
        WANT_SHPOOL= \
        WANT_TMUX= \
        SESSION_BACKEND= \
        BREW= \
        PATH="$_stubs:$PATH" \
        XDG_CONFIG_HOME="$_srcdir/config" \
        run_with_timeout 30 elvish <<EOF
$1
$2
EOF
}

###############
# TEST: the config parses

start_test "elvish rc.elv compiles"
result="$(run_with_timeout 30 elvish -compileonly "$_srcdir/config/elvish/rc.elv" 2>&1)"
assert_equal "" "$result"

start_test "elvish rc.elv is loaded by a piped session"
result="$(_elvish_run '' 'echo loaded')"
assert_equal "loaded" "$result"

###############
# TEST: failsafe

start_test "elvish FAILSAFE=1 bails out before touching the environment"
result="$(HOME="$_fakehome" FAILSAFE=1 TERM=dumb NO_COLOR=1 \
    XDG_CONFIG_HOME="$_srcdir/config" \
    run_with_timeout 30 elvish 2>&1 <<'EOF'
echo mode=(to-string $failsafe-mode)
echo history=(env-or HISTORY_FILE unset)
EOF
)"
assert_contains "failsafe mode" "$result"
assert_contains "mode=\$true" "$result"
assert_contains "history=unset" "$result"

start_test "elvish FAILSAFE=true is accepted"
result="$(_elvish_run '' 'echo (to-string (failsafe-flag FAILSAFE true))')"
assert_equal '$true' "$result"

start_test "elvish FAILSAFE=0 is off"
result="$(_elvish_run '' 'echo (to-string (failsafe-flag FAILSAFE 0))')"
assert_equal '$false' "$result"

start_test "elvish an unknown FAILSAFE spelling is reported and read as false"
result="$(_elvish_run_all '' 'echo (to-string (failsafe-flag FAILSAFE yes))')"
assert_contains "FAILSAFE=yes is not 1/0/true/false" "$result"
assert_contains '$false' "$result"

start_test "elvish LC_FAILSAFE is honored"
result="$(HOME="$_fakehome" LC_FAILSAFE=1 TERM=dumb \
    XDG_CONFIG_HOME="$_srcdir/config" \
    run_with_timeout 30 elvish 2>&1 <<'EOF'
echo mode=(to-string $failsafe-mode)
EOF
)"
assert_contains "mode=\$true" "$result"

###############
# TEST: basic helpers

start_test "elvish env-or falls back only when unset"
result="$(_elvish_run '' 'echo (env-or HOSTNAME fallback) (env-or NO_SUCH_VAR_HERE fallback)')"
assert_equal "host1 fallback" "$result"

start_test "elvish fields splits on runs of whitespace"
result="$(_elvish_run '' 'echo (str:join , (fields "  1: eth0    inet 10.0.0.1 "))')"
assert_equal "1:,eth0,inet,10.0.0.1" "$result"

start_test "elvish one-line collapses blank lines"
result="$(_elvish_run '' 'echo (one-line "a\n\n b \nc\n")')"
assert_equal "a b c" "$result"

start_test "elvish int-div truncates rather than yielding a rational"
result="$(_elvish_run '' 'echo (int-div 7 2) (int-div 125 60) (int-div 1 2)')"
assert_equal "3 2 0" "$result"

start_test "elvish capture-or-empty is empty when the command fails"
result="$(_elvish_run '' 'echo "["(capture-or-empty failing-tool &quiet=$true)"]"')"
assert_equal "[]" "$result"

start_test "elvish capture-word trims the captured output"
result="$(_elvish_run '' 'echo "["(capture-word echo "  spaced  ")"]"')"
assert_equal "[spaced]" "$result"

start_test "elvish as-command resolves a name and passes a closure through"
result="$(_elvish_run 'fn marker { echo from-closure }' \
    'echo (kind-of (as-command echo)) (kind-of (as-command $marker~))')"
assert_equal "fn fn" "$result"

###############
# TEST: env-run

start_test "elvish env-run sets a variable for one call only"
result="$(_elvish_run '' 'env-run [TZ UTC] sh -c "echo TZ=$TZ"; echo after=(env-or TZ unset)')"
assert_equal "TZ=UTC
after=unset" "$result"

start_test "elvish env-run restores an existing value"
result="$(_elvish_run 'set-env FOO original' \
    'env-run [FOO temporary] sh -c "echo $FOO"; echo after=$E:FOO')"
assert_equal "temporary
after=original" "$result"

start_test "elvish env-run restores the environment when the command fails"
result="$(_elvish_run '' 'try { env-run [TZ UTC] failing-tool } catch _ { }; echo after=(env-or TZ unset)' 2>/dev/null)"
assert_equal "after=unset" "$result"

###############
# TEST: PATH functions

start_test "elvish add-path start puts the directory first"
result="$(_elvish_run '' 'set paths = [/usr/bin]; add-path /tmp &where=start; echo (str:join , $paths)')"
assert_equal "/tmp,/usr/bin" "$result"

start_test "elvish add-path end puts the directory last"
result="$(_elvish_run '' 'set paths = [/usr/bin]; add-path /tmp &where=end; echo (str:join , $paths)')"
assert_equal "/usr/bin,/tmp" "$result"

start_test "elvish add-path start moves an existing entry rather than duplicating it"
result="$(_elvish_run '' 'set paths = [/usr/bin /tmp]; add-path /tmp &where=start; echo (str:join , $paths)')"
assert_equal "/tmp,/usr/bin" "$result"

start_test "elvish add-path with no position leaves an existing entry alone"
result="$(_elvish_run '' 'set paths = [/tmp /usr/bin]; add-path /tmp; echo (str:join , $paths)')"
assert_equal "/tmp,/usr/bin" "$result"

start_test "elvish add-path ignores a directory that does not exist"
result="$(_elvish_run '' 'set paths = [/usr/bin]; add-path /no/such/dir &where=start; echo (str:join , $paths)')"
assert_equal "/usr/bin" "$result"

start_test "elvish delete-path removes every copy"
result="$(_elvish_run '' 'set paths = [/tmp /usr/bin /tmp]; delete-path /tmp; echo (str:join , $paths)')"
assert_equal "/usr/bin" "$result"

start_test "elvish inpath reports membership"
result="$(_elvish_run '' 'set paths = [/usr/bin]; echo (to-string (inpath /usr/bin)) (to-string (inpath /tmp))')"
assert_equal '$true $false' "$result"

start_test "elvish setup-path orders ~/scripts ahead of ~/bin ahead of /usr/local/bin"
mkdir -p "$_fakehome/scripts" "$_fakehome/bin"
result="$(_elvish_run '' 'set paths = [/usr/local/bin]; setup-path
var order = []
for d $paths { if (has-value [$E:HOME/scripts $E:HOME/bin /usr/local/bin] $d) { set order = [$@order $d] } }
echo (str:join , $order)')"
assert_equal "$_fakehome/scripts,$_fakehome/bin,/usr/local/bin" "$result"

###############
# TEST: shell-env generators

start_test "elvish unquoted-head takes the leading quoted run"
result="$(_elvish_run '' 'echo (unquoted-head "\"/a/b\":$PATH") (unquoted-head plain)')"
assert_equal '/a/b plain' "$result"

start_test "elvish shellenv-entry splits an export line"
result="$(_elvish_run '' 'echo (str:join , (shellenv-entry "export FNM_DIR=\"/a/b\";"))')"
assert_equal "FNM_DIR,/a/b" "$result"

start_test "elvish shellenv-entry ignores comments and blank lines"
result="$(_elvish_run '' 'echo "["(str:join , (shellenv-entry "# hi"))"]["(str:join , (shellenv-entry "   "))"]"')"
assert_equal "[][]" "$result"

start_test "elvish shellenv-entry ignores a line that is not an assignment"
result="$(_elvish_run '' 'echo "["(str:join , (shellenv-entry "eval something"))"]"')"
assert_equal "[]" "$result"

start_test "elvish fnm-default-path prefers FNM_PATH"
result="$(_elvish_run 'set-env FNM_PATH /custom/fnm' 'echo (fnm-default-path)')"
assert_equal "/custom/fnm" "$result"

start_test "elvish fnm-default-path falls back to XDG_DATA_HOME"
result="$(_elvish_run 'unset-env FNM_PATH; set-env XDG_DATA_HOME /xdg' 'echo (fnm-default-path)')"
assert_equal "/xdg/fnm" "$result"

###############
# TEST: host predicates

start_test "elvish short-hostname drops the domain and the username prefix"
result="$(_elvish_run 'set-env HOSTNAME bob-desktop.example.com' 'echo (short-hostname)')"
assert_equal "desktop" "$result"

start_test "elvish on-my-workstation matches ~/.workstation"
result="$(_elvish_run 'set-env WORKSTATION_CACHED 1; set-env WORKSTATION host1' \
    'echo (to-string (on-my-workstation))')"
assert_equal '$true' "$result"

start_test "elvish on-my-workstation is false for a laptop name"
result="$(_elvish_run 'set-env WORKSTATION_CACHED 1; set-env WORKSTATION other
set-env HOSTNAME bob-laptop' 'echo (to-string (on-my-workstation))')"
assert_equal '$false' "$result"

start_test "elvish on-my-laptop reads ~/.laptop"
touch "$_fakehome/.laptop"
result="$(_elvish_run '' 'echo (to-string (on-my-laptop))')"
assert_equal '$true' "$result"
rm -f "$_fakehome/.laptop"

start_test "elvish on-production-host is false on a test or dev host"
result="$(_elvish_run 'set-env WORKSTATION_CACHED 1; set-env WORKSTATION other
set-env HOSTNAME db-test-1' 'echo (to-string (on-production-host))')"
assert_equal '$false' "$result"

start_test "elvish on-production-host is true for an unrecognized host"
result="$(_elvish_run 'set-env WORKSTATION_CACHED 1; set-env WORKSTATION other
set-env HOSTNAME db1' 'echo (to-string (on-production-host))')"
assert_equal '$true' "$result"

start_test "elvish show-hostname-in-title is false inside tmux"
result="$(_elvish_run 'set-env TMUX /tmp/tmux-0/default,1,0' \
    'echo (to-string (show-hostname-in-title))')"
assert_equal '$false' "$result"

start_test "elvish ssh-client-host prefers LC_CLIENT_HOST"
result="$(_elvish_run 'set-env LC_CLIENT_HOST laptop1' 'echo (ssh-client-host)')"
assert_equal "laptop1" "$result"

start_test "elvish ssh-client-host is empty outside an ssh session"
result="$(_elvish_run '' 'echo "["(ssh-client-host)"]"')"
assert_equal "[]" "$result"

###############
# TEST: session management

_session_stub='set stdin-is-tty~ = { put $true }
set inside-project~ = { put $true }
set have-command~ = {|name| has-value [shpool autoshpool tmux autotmux] $name }'

start_test "elvish session-backend prefers shpool by default"
result="$(_elvish_run "$_session_stub" 'echo (session-backend)')"
assert_equal "shpool" "$result"

start_test "elvish SESSION_BACKEND=tmux flips the preference"
result="$(_elvish_run "$_session_stub
set-env SESSION_BACKEND tmux" 'echo (session-backend)')"
assert_equal "tmux" "$result"

start_test "elvish WANT_SHPOOL=0 falls back to tmux"
result="$(_elvish_run "$_session_stub
set-env WANT_SHPOOL 0" 'echo (session-backend)')"
assert_equal "tmux" "$result"

start_test "elvish session-backend is empty when neither backend is installed"
result="$(_elvish_run 'set have-command~ = {|name| put $false }' 'echo "["(session-backend)"]"')"
assert_equal "[]" "$result"

start_test "elvish want-shpool is true inside a project"
result="$(_elvish_run "$_session_stub" 'echo (to-string (want-shpool))')"
assert_equal '$true' "$result"

start_test "elvish want-shpool is false without a tty"
result="$(_elvish_run "$_session_stub
set stdin-is-tty~ = { put \$false }" 'echo (to-string (want-shpool))')"
assert_equal '$false' "$result"

start_test "elvish want-shpool is false when already in shpool"
result="$(_elvish_run "$_session_stub
set-env SHPOOL_SESSION_NAME work" 'echo (to-string (want-shpool))')"
assert_equal '$false' "$result"

start_test "elvish want-tmux is false when already in shpool"
result="$(_elvish_run "$_session_stub
set-env SHPOOL_SESSION_NAME work" 'echo (to-string (want-tmux))')"
assert_equal '$false' "$result"

start_test "elvish want-shpool is true over ssh outside a project"
result="$(_elvish_run "$_session_stub
set inside-project~ = { put \$false }
set-env SSH_CONNECTION '10.0.0.1 22 10.0.0.2 22'" 'echo (to-string (want-shpool))')"
assert_equal '$true' "$result"

start_test "elvish session-shell is empty at SHLVL 1"
result="$(_elvish_run 'set-env SHLVL 1' 'echo "["(session-shell)"]"')"
assert_equal "[]" "$result"

start_test "elvish session-shell names elvish with -l from a nested shell"
result="$(_elvish_run 'set-env SHLVL 2; unset-env SESSION_SHELL' 'echo (session-shell)')"
assert_equal "$(command -v elvish) -l" "$result"

start_test "elvish session-shell keeps an inherited value"
result="$(_elvish_run 'set-env SESSION_SHELL "/bin/bash -l"' 'echo (session-shell)')"
assert_equal "/bin/bash -l" "$result"

start_test "elvish session-name reports the shpool session"
result="$(_elvish_run 'set-env SHPOOL_SESSION_NAME work' 'echo (session-name)')"
assert_equal "work" "$result"

start_test "elvish apply-shpool-initial-pwd is a no-op outside shpool"
result="$(_elvish_run 'set-env SHPOOL_INITIAL_PWD /tmp' \
    'apply-shpool-initial-pwd; echo (env-or SHPOOL_INITIAL_PWD unset)')"
assert_equal "/tmp" "$result"

start_test "elvish apply-shpool-initial-pwd cds and clears the variable"
result="$(_elvish_run 'set-env SHPOOL_SESSION_NAME work; set-env SHPOOL_INITIAL_PWD /tmp' \
    'apply-shpool-initial-pwd; echo (path:base $pwd) "["(env-or SHPOOL_INITIAL_PWD unset)"]"')"
assert_equal "tmp []" "$result"

start_test "elvish apply-shpool-initial-pwd keeps the variable when the cd fails"
result="$(_elvish_run_all 'set-env SHPOOL_SESSION_NAME work; set-env SHPOOL_INITIAL_PWD /no/such/dir' \
    'apply-shpool-initial-pwd; echo kept=(env-or SHPOOL_INITIAL_PWD unset)')"
assert_contains "cannot enter /no/such/dir" "$result"
assert_contains "kept=/no/such/dir" "$result"

###############
# TEST: ssh

start_test "elvish ssh-option-takes-value classifies a short-option cluster"
result="$(_elvish_run '' 'echo (to-string (ssh-option-takes-value -p)) (to-string (ssh-option-takes-value -vp)) (to-string (ssh-option-takes-value -v)) (to-string (ssh-option-takes-value -p2222))')"
assert_equal '$true $true $false $false' "$result"

start_test "elvish ssh-to moves flags in front of the host"
result="$(_elvish_run '' 'ssh-to host1 -v uptime')"
assert_contains "ssh -t -oSendEnv=LC_CLIENT_HOST -v host1 uptime" "$result"

start_test "elvish ssh-to keeps a value-taking flag with its value"
result="$(_elvish_run '' 'ssh-to host1 -p 2222 uptime')"
assert_contains "ssh -t -oSendEnv=LC_CLIENT_HOST -p 2222 host1 uptime" "$result"

start_test "elvish ssh-to rotates -- ahead of the host"
result="$(_elvish_run '' 'ssh-to host1 -- -x')"
assert_contains "ssh -t -oSendEnv=LC_CLIENT_HOST -- host1 -x" "$result"

start_test "elvish ssh-to tells the far end who is connecting"
result="$(_elvish_run '' 'ssh-to host1 uptime')"
assert_contains "LC_CLIENT_HOST=host1" "$result"

start_test "elvish ssh-to does not leave LC_CLIENT_HOST behind"
result="$(_elvish_run '' 'ssh-to host1 uptime >/dev/null; echo after=(env-or LC_CLIENT_HOST unset)')"
assert_equal "after=unset" "$result"

start_test "elvish ssh-config-hosts keeps identifiers and drops patterns"
mkdir -p "$_fakehome/.ssh"
cat > "$_fakehome/.ssh/config" <<'EOF'
Host host1 host2
    User bob
Host *.example.com
    User bob
Host build-1
    User bob
host lowercase1
    User bob
Host my.host
    User bob
EOF
result="$(_elvish_run '' 'echo (str:join , [(ssh-config-hosts)])')"
assert_equal "host1,host2,lowercase1" "$result"

start_test "elvish ssh-alias-vars keys the map by function name"
result="$(_elvish_run '' 'echo (str:join , [(keys (ssh-alias-vars) | order)])')"
assert_equal "host1~,host2~,lowercase1~" "$result"

start_test "elvish ssh-config-hosts reports a config it cannot read"
result="$(_elvish_run_all "set paths = [$_badcat \$@paths]" \
    'echo hosts=(str:join , [(ssh-config-hosts)])')"
assert_contains "ssh aliases: cannot read the ssh config" "$result"
assert_contains "hosts=" "$result"

start_test "elvish ssh-config-hosts is empty with no ssh config"
rm -f "$_fakehome/.ssh/config"
result="$(_elvish_run '' 'echo "["(str:join , [(ssh-config-hosts)])"]"')"
assert_equal "[]" "$result"

###############
# TEST: general functions

start_test "elvish find-up finds a marker in a parent directory"
mkdir -p "$_testdir/proj/sub/deeper"
touch "$_testdir/proj/marker"
result="$(_elvish_run "cd $_testdir/proj/sub/deeper" 'echo (find-up marker)')"
assert_equal "$_testdir/proj/marker" "$result"

start_test "elvish find-up is empty when there is no marker"
result="$(_elvish_run "cd $_testdir/proj/sub/deeper" 'echo "["(find-up no-such-marker)"]"')"
assert_equal "[]" "$result"

start_test "elvish find-test-file names the sibling test file"
touch "$_testdir/proj/thing.go" "$_testdir/proj/thing_test.go"
result="$(_elvish_run '' "echo (find-test-file $_testdir/proj/thing.go)")"
assert_equal "$_testdir/proj/thing_test.go" "$result"

start_test "elvish find-test-file is empty when there is no test file"
touch "$_testdir/proj/lonely.go"
result="$(_elvish_run '' "echo \"[\"(find-test-file $_testdir/proj/lonely.go)\"]\"")"
assert_equal "[]" "$result"

start_test "elvish join places the separator between the words"
result="$(_elvish_run '' 'join - a b c')"
assert_equal "a-b-c" "$result"

start_test "elvish first-arg-last moves the first argument to the end"
result="$(_elvish_run '' 'first-arg-last echo LAST one two')"
assert_equal "one two LAST" "$result"

start_test "elvish shift-options moves options in front of the target"
result="$(_elvish_run '' 'shift-options echo target -v --flag=1 arg')"
assert_equal "-v --flag=1 target arg" "$result"

start_test "elvish shift-options stops shifting at --"
result="$(_elvish_run '' 'shift-options echo target -- -b')"
assert_equal "target -- -b" "$result"

printf 'HEADER\nbbb\nccc\n' > "$_testdir/body1.txt"
start_test "elvish body prints the header and pipes the rest"
result="$(_elvish_run '' "body grep c < $_testdir/body1.txt")"
assert_equal "HEADER
ccc" "$result"

printf 'H1\nH2\nbbb\nccc\n' > "$_testdir/body2.txt"
start_test "elvish body takes a leading -<number> as the header size"
result="$(_elvish_run '' "body -2 grep c < $_testdir/body2.txt")"
assert_equal "H1
H2
ccc" "$result"

printf 'H1\nH2\nbbb\n' > "$_testdir/body3.txt"
start_test "elvish body takes --lines=<number>"
result="$(_elvish_run '' "body --lines=2 grep b < $_testdir/body3.txt")"
assert_equal "H1
H2
bbb" "$result"

printf 'ONLY\n' > "$_testdir/body4.txt"
start_test "elvish body still runs the command when the input is shorter than the header"
result="$(_elvish_run '' "body -3 echo ran < $_testdir/body4.txt")"
assert_equal "ONLY


ran" "$result"

printf 'a\nb\n' > "$_testdir/lines.txt"
start_test "elvish each-line runs the command per input line"
result="$(_elvish_run '' "each-line echo prefix < $_testdir/lines.txt")"
assert_equal "prefix a
prefix b" "$result"

start_test "elvish bak and unbak round-trip a file"
result="$(_elvish_run "cd $_testdir; echo original > roundtrip.txt" \
    'bak roundtrip.txt; echo after-bak=(to-string (os:exists roundtrip.txt.bak))
unbak roundtrip.txt; echo after-unbak=(to-string (os:exists roundtrip.txt))')"
assert_equal "after-bak=\$true
after-unbak=\$true" "$result"

start_test "elvish mcd makes the directory and enters it"
result="$(_elvish_run "cd $_testdir" 'mcd made-by-mcd; echo (path:base $pwd)')"
assert_equal "made-by-mcd" "$result"

start_test "elvish mcd refuses an existing directory"
result="$(_elvish_run "cd $_testdir" 'mcd made-by-mcd')"
assert_contains "already exists" "$result"

start_test "elvish isort sorts a file in place"
printf 'b\na\n' > "$_testdir/sortme.txt"
result="$(_elvish_run '' "isort $_testdir/sortme.txt; cat $_testdir/sortme.txt")"
assert_equal "a
b" "$result"

start_test "elvish applydiff replaces the file when the command succeeds"
printf 'hello\n' > "$_testdir/apply.txt"
result="$(_elvish_run '' "applydiff upper $_testdir/apply.txt; cat $_testdir/apply.txt")"
assert_equal "HELLO" "$result"

start_test "elvish applydiff leaves the file alone when the command fails"
printf 'hello\n' > "$_testdir/keep.txt"
result="$(_elvish_run_all '' "try { applydiff failing-tool $_testdir/keep.txt } catch _ { }
echo kept=(slurp < $_testdir/keep.txt)
echo staged=(to-string (os:exists $_testdir/keep.txt.new))")"
assert_contains "applydiff: failing-tool failed" "$result"
assert_contains "kept=hello" "$result"
assert_contains "staged=\$false" "$result"

start_test "elvish trydiff shows the change without applying it"
printf 'hello\n' > "$_testdir/preview.txt"
result="$(_elvish_run '' "trydiff upper $_testdir/preview.txt; echo still=(slurp < $_testdir/preview.txt)")"
assert_contains "HELLO" "$result"
assert_contains "still=hello" "$result"

start_test "elvish trydiff passes a real diff failure through"
printf 'hello\n' > "$_testdir/preview3.txt"
result="$(_elvish_run "set paths = [$_baddiff \$@paths]" \
    "try { trydiff upper $_testdir/preview3.txt; echo NOT-REACHED } catch e { echo status=(exit-status \$e) }")"
assert_equal "status=2" "$result"

start_test "elvish trydiff still succeeds when the files merely differ"
printf 'hello\n' > "$_testdir/preview4.txt"
result="$(_elvish_run '' "try { trydiff upper $_testdir/preview4.txt >/dev/null; echo ok } catch e { echo raised }")"
assert_equal "ok" "$result"

start_test "elvish trydiff cleans up after a failing command"
printf 'hello\n' > "$_testdir/preview2.txt"
result="$(_elvish_run_all '' "try { trydiff failing-tool $_testdir/preview2.txt } catch _ { }
echo leftovers=(count [(put $_testdir/preview2.txt.trydiff.*[nomatch-ok])])")"
assert_contains "trydiff: failing-tool failed" "$result"
assert_contains "leftovers=0" "$result"

start_test "elvish recent defaults to ten and takes a leading count"
result="$(_elvish_run "cd $_testdir/proj" 'recent -1 | wc -l')"
assert_equal "1" "$result"

start_test "elvish recent takes --count=<number>"
result="$(_elvish_run "cd $_testdir/proj" 'recent --count=2 | wc -l')"
assert_equal "2" "$result"

start_test "elvish psgrep reports a pattern that matches nothing"
result="$(_elvish_run_all '' 'try { psgrep no-such-process-pattern-here } catch _ { }')"
assert_contains "No processes matching no-such-process-pattern-here" "$result"

printf '\n' > "$_testdir/enter.txt"
printf 'n\n' > "$_testdir/no.txt"
start_test "elvish confirm treats a bare Enter as yes"
result="$(_elvish_run '' "echo (to-string (confirm proceed < $_testdir/enter.txt))")"
assert_equal '$true' "$result"

start_test "elvish confirm treats anything else as no"
result="$(_elvish_run '' "echo (to-string (confirm proceed < $_testdir/no.txt))")"
assert_equal '$false' "$result"

start_test "elvish run prints instead of running under SIMULATE"
result="$(_elvish_run 'set-env SIMULATE true' 'run rm -rf /nowhere')"
assert_equal "Would run rm -rf /nowhere" "$result"

start_test "elvish setx announces the command before running it"
result="$(_elvish_run_all '' 'setx echo hello')"
assert_contains "+ echo hello" "$result"
assert_contains "hello" "$result"

start_test "elvish log-history reports an unwritable history file once"
result="$(_elvish_run_all "set-env HISTORY_FILE $_testdir/nodir/hist" \
    'log-history first; log-history second; echo done')"
assert_contains "history: cannot append to" "$result"
assert_contains "done" "$result"
# One warning for two failed appends: this runs from the prompt hook on every
# command, so a message per command would be worse than the problem.
assert_equal "1" "$(printf '%s\n' "$result" | grep -c 'cannot append to')"

start_test "elvish log-history appends a timestamped line"
result="$(_elvish_run '' "set-env HISTORY_FILE $_testdir/hist; log-history a command; var logged = (fields (slurp < $_testdir/hist)); echo (str:join , \$logged[3..])")"
assert_equal "a,command" "$result"

###############
# TEST: colors and prompt

start_test "elvish color-text is plain when color is off"
result="$(_elvish_run 'set color = $false' 'echo (red danger)')"
assert_equal "danger" "$result"

start_test "elvish color-text wraps in an escape when color is on"
result="$(_elvish_run 'set color = $true' 'echo (red danger) | cat -v')"
assert_equal '^[[31mdanger^[[0m' "$result"

start_test "elvish init-colors turns color off for NO_COLOR"
result="$(_elvish_run 'init-colors' 'echo (to-string $color)')"
assert_equal '$false' "$result"

start_test "elvish tilde-pwd shortens the home directory"
result="$(_elvish_run "cd $_fakehome" 'echo (tilde-pwd)')"
assert_equal "~" "$result"

start_test "elvish host-info names the backend that would start"
result="$(_elvish_run 'set i-am-root~ = { put $false }
set on-production-host~ = { put $false }
set have-command~ = {|name| put $false }' 'echo (host-info)')"
assert_equal "host1 shpool" "$result"

start_test "elvish host-info shows the attached session in place of the backend"
result="$(_elvish_run 'set i-am-root~ = { put $false }
set on-production-host~ = { put $false }
set-env SHPOOL_SESSION_NAME work' 'echo (host-info)')"
assert_equal "host1 work" "$result"

start_test "elvish host-info tags a root shell"
result="$(_elvish_run 'set i-am-root~ = { put $true }
set on-production-host~ = { put $false }
set have-command~ = {|name| put $false }' 'echo (host-info)')"
assert_equal "[root] host1 shpool" "$result"

start_test "elvish dir-info falls back to the working directory outside a repo"
result="$(_elvish_run "cd $_fakehome
set have-command~ = {|name| put \$false }" 'echo (dir-info)')"
assert_equal "~" "$result"

start_test "elvish prompt-line joins host, directory and auth"
result="$(_elvish_run "cd $_fakehome
set i-am-root~ = { put \$false }
set on-production-host~ = { put \$false }
set have-command~ = {|name| put \$false }
set auth-info~ = { put SSH }" 'echo (prompt-line)')"
assert_equal "host1 shpool ~ SSH" "$result"

start_test "elvish prompt-line omits the auth tag when nothing needs it"
result="$(_elvish_run "cd $_fakehome
set i-am-root~ = { put \$false }
set on-production-host~ = { put \$false }
set have-command~ = {|name| put \$false }
set auth-info~ = { put '' }" 'echo (prompt-line)')"
assert_equal "host1 shpool ~" "$result"

start_test "elvish terminal-width falls back to 80 without a terminal"
result="$(_elvish_run '' 'echo (terminal-width)')"
assert_equal "80" "$result"

start_test "elvish bar draws a rule of the requested width"
result="$(_elvish_run '' 'echo (count [(str:split "" (bar 5))])')"
assert_equal "5" "$result"

start_test "elvish title names the project when there is one"
result="$(_elvish_run 'set show-hostname-in-title~ = { put $true }
set session-name~ = { put "" }
set projectname~ = { put myproj }' 'echo (title)')"
assert_equal "host1 myproj" "$result"

start_test "elvish title falls back to the directory name"
result="$(_elvish_run "cd $_testdir/proj
set show-hostname-in-title~ = { put \$false }
set session-name~ = { put \"\" }
set projectname~ = { put \"\" }" 'echo (title)')"
assert_equal "proj" "$result"

start_test "elvish set-title writes nothing for a dumb terminal"
result="$(_elvish_run '' 'set-title anything | cat -v')"
assert_equal "" "$result"

start_test "elvish set-title writes an xterm title escape"
# `cat -v` renders the escape and the bell as ^[ and ^G, so this compares the
# printable rendering rather than the raw bytes.
result="$(_elvish_run 'set-env TERM xterm-256color' 'set-title mytitle | cat -v')"
assert_equal '^[]0;mytitle^G' "$result"

###############
# TEST: command reporting

start_test "elvish preprompt keeps the unmerged warning and drops its diagnostics"
result="$(_elvish_run "set paths = [$_vcsdir \$@paths]" 'preprompt')"
assert_contains "UNMERGED-WARNING" "$result"
assert_not_contains "a diagnostic" "$result"

start_test "elvish format-duration says nothing under two seconds"
result="$(_elvish_run '' 'echo "["(format-duration 1.4)"]"')"
assert_equal "[]" "$result"

start_test "elvish format-duration reports seconds, minutes and hours"
result="$(_elvish_run '' 'echo (format-duration 5) / (format-duration 125) / (format-duration 3725)')"
assert_equal "5 seconds / 2 minutes 5 seconds / 1 hours 2 minutes 5 seconds" "$result"

start_test "elvish describe-error says nothing for a command that succeeded"
result="$(_elvish_run '' 'echo "["(describe-error $nil)"]"')"
assert_equal "[]" "$result"

start_test "elvish describe-error reports a non-zero exit status"
result="$(_elvish_run '' 'var err = $nil
try { failing-tool 2>/dev/null } catch e { set err = $e }
echo (describe-error $err)')"
assert_equal "status 1" "$result"

start_test "elvish describe-error reports an interrupt as interrupted"
result="$(_elvish_run '' 'var err = $nil; try { sh -c "kill -INT $$" } catch e { set err = $e }; echo (describe-error $err)')"
assert_equal "interrupted" "$result"

start_test "elvish exit-status extracts the number atuin needs"
result="$(_elvish_run '' 'var err = $nil
try { sh -c "exit 7" } catch e { set err = $e }
echo (exit-status $nil) (exit-status $err)')"
assert_equal "0 7" "$result"

start_test "elvish command-finished reports a failure and a slow command"
result="$(_elvish_run 'set color = $false' 'var err = $nil
try { sh -c "exit 3" } catch e { set err = $e }
command-finished [&error=$err &duration=(num 5) &src=[&]]')"
assert_equal "status 3 took 5 seconds" "$result"

start_test "elvish command-finished says nothing about a quick success"
result="$(_elvish_run '' 'command-finished [&error=$nil &duration=(num 0.1) &src=[&]]')"
assert_equal "" "$result"

start_test "elvish command-started logs the command line"
result="$(_elvish_run "set-env HISTORY_FILE $_testdir/hist2" "command-started \"ls -l\"; var logged = (fields (slurp < $_testdir/hist2)); echo (str:join , \$logged[3..])")"
assert_equal "ls,-l" "$result"

###############
# TEST: tool integrations

start_test "elvish eval-tool-init reports a generator that fails"
result="$(_elvish_run_all '' 'eval-tool-init faketool failing-tool')"
assert_contains "faketool: shell integration skipped" "$result"

start_test "elvish eval-tool-init reports output it cannot evaluate"
result="$(_elvish_run_all '' 'eval-tool-init faketool echo "this is ) not elvish"')"
assert_contains "faketool: shell integration may be incomplete" "$result"

start_test "elvish eval-tool-init is silent on a generator it can evaluate"
result="$(_elvish_run_all '' 'eval-tool-init faketool echo "echo generated"')"
assert_contains "generated" "$result"
assert_not_contains "shell integration" "$result"

start_test "elvish init-atuin mints a session when atuin has none"
result="$(_elvish_run 'unset-env ATUIN_SESSION' 'init-atuin; echo (env-or ATUIN_SESSION unset)')"
assert_equal "test-session-id" "$result"

start_test "elvish init-atuin keeps a session it was given"
result="$(_elvish_run 'set-env ATUIN_SESSION inherited' 'init-atuin; echo $E:ATUIN_SESSION')"
assert_equal "inherited" "$result"

start_test "elvish atuin-wanted is true once a session is open"
result="$(_elvish_run 'set-env ATUIN_SESSION inherited' 'echo (to-string (atuin-wanted))')"
assert_equal '$true' "$result"

start_test "elvish atuin-wanted is false without an atuin session"
result="$(_elvish_run 'unset-env ATUIN_SESSION' 'echo (to-string (atuin-wanted))')"
assert_equal '$false' "$result"

start_test "elvish atuin-command-started records the id it is given"
result="$(_elvish_run 'set-env ATUIN_SESSION open' 'atuin-command-started "ls"; echo $atuin-history-id')"
assert_equal "test-history-id" "$result"

start_test "elvish atuin-command-finished closes the entry and forgets the id"
result="$(_elvish_run 'set-env ATUIN_SESSION open; atuin-command-started "ls"' \
    'atuin-command-finished [&error=$nil &duration=(num 0) &src=[&]]; echo "["$atuin-history-id"]"')"
assert_equal "[]" "$result"

start_test "elvish atuin-command-started rejects an empty id"
result="$(_elvish_run_all 'set-env ATUIN_SESSION open; set-env ATUIN_EMPTY_ID 1' \
    'atuin-command-started "ls"; echo "["$atuin-history-id"]"')"
assert_contains "atuin: history start failed" "$result"
assert_contains "[]" "$result"

start_test "elvish atuin-command-started is a no-op when atuin is not in use"
result="$(_elvish_run 'unset-env ATUIN_SESSION' \
    'atuin-command-started "ls"; echo "["$atuin-history-id"]"')"
assert_equal "[]" "$result"

###############
# TEST: vcs wrappers

start_test "elvish rootdir is empty when the vcs binary is missing"
result="$(_elvish_run 'set have-command~ = {|name| put $false }' 'echo "["(rootdir)"]"')"
assert_equal "[]" "$result"

start_test "elvish inside-project follows rootdir"
result="$(_elvish_run 'set rootdir~ = { put /home/user/proj }' \
    'echo (to-string (inside-project)) (projectname)')"
assert_equal '$true proj' "$result"

start_test "elvish builddir is the path from the project root"
result="$(_elvish_run "cd $_testdir/proj/sub/deeper
set buildroot~ = { put $_testdir/proj }" 'echo (builddir)')"
assert_equal "sub/deeper" "$result"

start_test "elvish builddir is . at the project root"
result="$(_elvish_run "cd $_testdir/proj
set buildroot~ = { put $_testdir/proj }" 'echo (builddir)')"
assert_equal "." "$result"

###############
# TEST: PERFORMANCE
# prompt-line runs on every prompt, so its cost matters. Times 50 calls with
# everything that forks stubbed out -- this measures the shell-composition cost
# (host-info, dir-info, auth-info, color wrapping) rather than the `vcs` and
# `ssh-add` forks around it, the same thing shrc_prompt_test.sh budgets.
#
# Timed inside Elvish: each _elvish_run is a fresh process, so timing it from
# here would measure interpreter startup instead.

_prompt_perf_budget_ms="${PROMPT_PERF_BUDGET_MS:-1000}"
start_test "elvish prompt-line within ${_prompt_perf_budget_ms}ms budget"
result="$(_elvish_run 'set is-ssh-valid~ = { put $true }
set have-command~ = {|name| put $false }
set on-production-host~ = { put $false }
set i-am-root~ = { put $false }
set session-name~ = { put "" }' 'prompt-line >/dev/null
var start = (num (date +%s%N))
var i = 0
while (< $i 50) { prompt-line >/dev/null; set i = (+ $i 1) }
echo (int-div (- (num (date +%s%N)) $start) 1000000)')"
case "$result" in
''|*[!0-9]*)
    skip_block "prompt-line perf check: date +%s%N unavailable"
    ;;
*)
    echo "  50 x prompt-line (shell compose): ${result}ms (budget ${_prompt_perf_budget_ms}ms)"
    # PROMPT_PERF_BUDGET_MS=0 disables the check for manual profiling.
    if test "$_prompt_perf_budget_ms" -gt 0; then
        assert_true test "$result" -le "$_prompt_perf_budget_ms"
    else
        skip_block "prompt-line perf budget disabled"
    fi
    ;;
esac

###############
# TEST: the interactive half
# lib/interactive.elv names $edit:, which only exists when Elvish has a
# terminal, so it can neither be compiled by `elvish -compileonly` nor reached
# by the piped harness above. Running a throwaway Elvish under a pty is the
# only way to compile it at all -- the same reason shrc_bash_test.sh starts a
# real `bash -i`.

if ! command -v script >/dev/null 2>&1; then
    skip_block "interactive setup (script(1) not installed, no way to allocate a pty)"
elif ! script -qec true /dev/null >/dev/null 2>&1; then
    skip_block "interactive setup (script(1) does not take -qec on this platform)"
else
    start_test "elvish the interactive half loads under a real terminal"
    # `script` copies its own stdin to the pty, so the snippet still arrives on
    # what Elvish sees as a terminal. The editor redraws the line as it is
    # typed, so the assertion looks for markers rather than comparing output.
    result="$(printf 'echo INTERACTIVE-MARKER-(to-string $color)\nexit\n' | \
        HOME="$_fakehome" \
        TERM=dumb \
        NO_COLOR=1 \
        XDG_CONFIG_HOME="$_srcdir/config" \
        WANT_SHPOOL=0 \
        WANT_TMUX=0 \
        PATH="$_stubs:$PATH" \
        run_with_timeout 30 script -qec elvish /dev/null 2>&1)"
    assert_contains "INTERACTIVE-MARKER" "$result"
    assert_not_contains "Exception" "$result"
    assert_not_contains "compilation error" "$result"
    assert_not_contains "no such module" "$result"

    start_test "elvish the interactive half draws the configured prompt"
    # The editor redraws the line as each character arrives, so the raw pty
    # output is full of cursor motion; strip the escape sequences and look for
    # the rule preprompt draws and the `$ ` glyph after it.
    result="$(printf 'echo done\nexit\n' | \
        HOME="$_fakehome" \
        TERM=xterm \
        NO_COLOR=1 \
        XDG_CONFIG_HOME="$_srcdir/config" \
        WANT_SHPOOL=0 \
        WANT_TMUX=0 \
        PATH="$_stubs:$PATH" \
        run_with_timeout 30 script -qec elvish /dev/null 2>&1 | \
        sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | tr -d '\r')"
    assert_contains '$ ' "$result"
    assert_contains '―' "$result"
fi

test_summary "elvish_test"
