#!/bin/sh
# Deepen a shallow clone, so anything that counts commits gets a real answer.
#
# The sandbox clones shallow. `git rev-list --count`, `git log` past the
# boundary and blame then return wrong answers with no error and no warning —
# the failure mode is a confident wrong number, which is why this runs at
# session start rather than being left to whoever needs the count to remember.
#
# Best-effort: an unreachable remote leaves the clone as it was and says so.
# `git fetch --unshallow` exits 0 even when it deepened nothing, so the check
# afterwards is the real one.
set -eu

# Print the repository's shallow flag ("true"/"false"), or report the failure
# and return non-zero if git cannot be asked -- a missing git, the wrong
# directory, or a corrupt repo must not be reported as a complete (or a
# deepened) history, since callers run this as a precondition before trusting
# commit counts and blame. One helper for both the initial and the post-fetch
# probe so neither can mask an inspection failure. The session-start hook runs
# this best-effort (`... || true`), so a non-zero exit there is swallowed and
# never blocks startup.
report_shallow() {
  _flag=$(git rev-parse --is-shallow-repository 2>&1) || {
    echo "unshallow: cannot inspect the repository: $_flag" >&2
    return 1
  }
  printf '%s\n' "$_flag"
}

is_shallow=$(report_shallow) || exit 1
if test "$is_shallow" != "true"; then
  echo "unshallow: already complete"
  exit 0
fi

# Best-effort has to mean *bounded*. This runs at session start, so a fetch
# that waits on an unreachable remote — or sits at a credential or host-key
# prompt with no terminal to answer it — delays or blocks the whole session,
# and the `|| true` below is only reached once the process returns.
#
# This script touches NOTHING auth-related, and the absolutism is the fix.
# Six review rounds each found another configuration route a "fill in a safe
# default when unconfigured" branch would override — GIT_SSH_COMMAND, GIT_SSH,
# core.sshCommand, GIT_ASKPASS over core.askPass, GIT_ASKPASS over SSH_ASKPASS
# — and the routes do not end there (ssh_config, GIT_CONFIG_* …). The class
# only closes by having no such branch: modify nothing, and there is nothing
# to override. What the defaults bought was a fast fail on a prompting fetch;
# forgoing them costs, worst case, one deadline-bounded wait below in an
# already-broken setup, and buys a surface no edge case can regrow on.
#
# The one export is git's own no-terminal switch. It shadows no configured
# alternative — askpass helpers and ssh wrappers still run — it only stops
# the interactive prompt nothing at session start could ever answer.
export GIT_TERMINAL_PROMPT=0

# Put a deadline on the network, using whatever this host has. `timeout` is
# coreutils, absent from a default macOS; `gtimeout` is the name Homebrew
# gives it; perl ships with macOS. With none of them the fetch is *skipped*
# rather than run unbounded — a shallow clone plus a warning is the degraded
# state this script already documents, and a session that never starts is not.
#
# All three have to kill a process *group* and escalate to KILL, and that is
# the whole difficulty. `git fetch` spawns a transport — ssh, or
# git-remote-https — which inherits this script's stdout; killing git alone
# leaves that child holding the pipe, so a caller capturing our output waits
# for it however promptly the deadline fired. GNU `timeout` puts the command
# in its own group and signals the group, so it needs no help there. Perl has
# to be told: fork, `setpgrp` the child, and signal `-$pid`.
#
# TERM alone is not enough either way: a transport that ignores it stays put.
# `-k 5` is what makes `timeout` follow up with KILL, and `-k` rather than
# `--kill-after` because BusyBox's timeout takes the short form and not the
# long one — a rejected flag would turn every fetch into a failure, which is
# the same session-wide loss by a quieter route.
#
# None of that is sufficient on its own, and this is the part that is easy to
# get wrong: `timeout` returns as soon as its *direct* child exits, so when
# git dies on TERM and its transport does not, the escalation never fires and
# the orphan keeps our stdout. What actually protects the session is not
# holding the descriptor it could inherit — the fetch writes to a log file,
# which is then relayed. A surviving child then holds that file, which blocks
# nobody, and git's own error text still reaches the reader.
#
# The log lives under `.git`, not `/tmp`. A predictable name in a shared
# `/tmp` is a symlink trap — anyone on the host can pre-create it and the
# redirect follows it onto any file we can write — and its contents (remote
# URLs, auth errors) would sit there world-readable. `.git` is ours, carries
# the repository's own permissions, and needs no `mktemp`, which would be one
# more tool to find on the narrow-PATH hosts this script already survives.
tmp="$(git rev-parse --git-dir)/unshallow-log.$$"
# The trap covers every exit, including ones between here and the explicit
# cleanup below; `rm` may be missing on a PATH narrow enough to have hidden
# `timeout`, and a leaked log inside our own `.git` is not worth dying over.
trap 'rm -f "$tmp" 2>/dev/null || true' EXIT
# Owner-only: `.git` is commonly 0755 and a redirect creates under the
# process umask, so on a multi-user host the log's fetch diagnostics (remote
# URLs, auth errors) would be world-readable while it exists. Created here in
# a subshell so the narrowed umask touches nothing else; later redirects
# truncate the file and keep its mode. Builtins only, as everywhere in this
# script.
( umask 077; : > "$tmp" )
# A non-positive or non-numeric deadline would disable the bound entirely
# (perl `alarm 0` cancels the alarm; GNU `timeout 0` means "no timeout"),
# letting a stalled fetch hang the session -- the opposite of best-effort. Fall
# back to the default for anything that is not a positive integer.
deadline="${UNSHALLOW_TIMEOUT:-120}"
case "$deadline" in
  '' | *[!0-9]*) deadline=120 ;;
esac
test "$deadline" -ge 1 2>/dev/null || deadline=120
status=0
if command -v perl >/dev/null 2>&1; then
  # Perl first even where coreutils exists, because it is the only branch
  # that kills the process *group*: fork, setpgrp the child, signal -$pid
  # with TERM then KILL. `timeout -k` cannot reach a transport that outlives
  # git — it returns the moment its direct child exits, so the escalation
  # never fires and the orphan lives on under init. Perl ships with macOS
  # and effectively every CI image, so this is the common path.
  perl -e '
    my $limit = shift;
    my $pid = fork();
    exit 127 unless defined $pid;
    if ($pid == 0) { setpgrp(0, 0); exec @ARGV; exit 127 }
    # TERM, a grace period, then KILL — matching timeout -k 5. Back-to-back
    # signals let KILL win before git finishes its TERM cleanup, which can
    # leave a stale shallow.lock that blocks every later fetch.
    $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 5; kill "KILL", -$pid; exit 124 };
    alarm $limit;
    waitpid($pid, 0);
    exit($? >> 8);
  ' "$deadline" git fetch --unshallow --quiet >"$tmp" 2>&1 || status=$?
elif command -v timeout >/dev/null 2>&1; then
  # Fallback for a host with coreutils but no perl. `-k 5` escalates to KILL
  # for a direct child that ignores TERM (short form: BusyBox rejects the
  # long one). A transport grandchild that outlives git is an accepted
  # residual here — it holds only the log file, never the session — on a
  # host shape that is already unusual.
  timeout -k 5 "$deadline" git fetch --unshallow --quiet >"$tmp" 2>&1 || status=$?
elif command -v gtimeout >/dev/null 2>&1; then
  gtimeout -k 5 "$deadline" git fetch --unshallow --quiet >"$tmp" 2>&1 || status=$?
else
  echo "unshallow: nothing here can bound the fetch, so skipping it rather than risk hanging the session" >&2
  status=127
fi

# Builtins only, and an `if` rather than an `&&` list: `sed` is not reachable
# on a PATH narrow enough to have hidden `timeout`, and under `set -e` a
# failed `[ -s ]` would end the script on the ordinary quiet-success path.
if test -s "$tmp"; then
  while IFS= read -r line; do
    echo "unshallow: $line" >&2
  done < "$tmp"
fi
# Not silent: the outcome check below reports the *state*, which is what
# matters, but a reader debugging a slow start needs to know the fetch was
# tried and how it ended. 124 is `timeout`'s "deadline hit".
if test "$status" -ne 0; then
  echo "unshallow: fetch did not complete (exit $status)" >&2
fi

is_shallow=$(report_shallow) || exit 1
if test "$is_shallow" = "true"; then
  echo "unshallow: WARNING still shallow — commit counts and blame will be wrong" >&2
  exit 0
fi

# The deepening succeeded; the count is cosmetic, so a rev-list that somehow
# fails here is reported rather than printed as "deepened to  commits".
if ! count=$(git rev-list --count HEAD 2>&1); then
  echo "unshallow: deepened, but could not count commits: $count" >&2
  exit 0
fi
echo "unshallow: deepened to $count commits"
