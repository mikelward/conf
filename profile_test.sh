#!/bin/bash
#
# Tests for `profile` (~/.profile, ~/.bash_profile and ~/.zlogin): a login
# with no terminal, as a display manager's, says in the journal which
# session it starts and how far it got.

. "$(dirname "$0")/shrc_test_lib.sh"

_tmp=$(mktemp -d)
trap 'rm -rf "$_tmp"' EXIT
_home="$_tmp/home"
_bin="$_tmp/bin"
_log="$_tmp/log"
mkdir "$_home" "$_bin"
ln -s "$_srcdir/profile" "$_home/.bash_profile"
# logger records what it's asked to log, in place of the journal.
cat > "$_bin/logger" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$LOGGER_OUT"
STUB
chmod +x "$_bin/logger"

# login [ENV=VALUE...]: a bash login shell with no terminal, as a display
# manager starts one; prints what it logged.
login() {
    : > "$_log"
    env -i HOME="$_home" PATH="$_bin:/usr/bin:/bin" LOGGER_OUT="$_log" \
        SHELL=/bin/bash "$@" bash -l -c 'type profile_log >/dev/null 2>&1 && echo LEFT_DEFINED' \
        </dev/null >"$_tmp/out" 2>&1
    cat "$_log"
}

start_test "a login with no terminal logs the session it starts"
_out=$(login XDG_SESSION_DESKTOP=plasma)
assert_contains "-t profile -- starting plasma session as bash login" "$_out"
assert_contains "-t profile -- starting the session after " "$_out"

start_test "the session name falls back to DESKTOP_SESSION"
_out=$(login DESKTOP_SESSION=tide-tidewm)
assert_contains "starting tide-tidewm session" "$_out"

start_test "a login with no session named says so"
_out=$(login)
assert_contains "starting unnamed session" "$_out"

start_test "reading .shrc is logged on both sides"
printf 'true\n' > "$_home/.shrc"
_out=$(login XDG_SESSION_DESKTOP=plasma)
assert_contains "reading .shrc" "$_out"
assert_contains "read .shrc" "$_out"
rm "$_home/.shrc"

start_test "a .shrc that never returns shows where the login stopped"
printf 'exit 7\n' > "$_home/.shrc"
_out=$(login XDG_SESSION_DESKTOP=plasma)
assert_contains "reading .shrc" "$_out"
assert_not_contains "starting the session" "$_out"
rm "$_home/.shrc"

start_test "the logging helper doesn't outlive the profile"
login >/dev/null
assert_not_contains "LEFT_DEFINED" "$(cat "$_tmp/out")"

test_summary "profile_test"
