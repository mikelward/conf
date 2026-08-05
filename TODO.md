# TODO

## Run the prompt and VCS suites under zsh

`test-prompt` and `test-vcs` are bash-only, so `shrc`'s prompt code and
`shrc.vcs` — both of which run on every zsh prompt — have no zsh coverage at
all. That gap is why removing `emulate sh` could break `x` / `xa` / `f` with a
fully green suite (reverted in #259): the option contract is now asserted in
`shrc_zsh_test.sh`, but the code paths themselves are still only exercised
under bash.

The blocker is the drivers, not the code under test. The Makefile notes they
use "bash/zsh-only syntax (here-strings, arrays)" — arrays are the real
problem, since `shrc`'s `emulate sh` turns `KSH_ARRAYS` on and a driver
written for bash's 0-based arrays reads differently under zsh. Auditing
`shrc_prompt_test.sh` and `shrc_vcs_test.sh` for indexing and `${#arr}` is
most of the work; `shrc_test.sh` already runs under both, so the harness
itself is fine.

Worth doing before any further zsh work, not after: every silent failure in
that attempt was in a path some suite didn't reach.

## Add mesh to CI once it stabilizes

`make test` runs `mesh_test.sh` (378 tests over `config/mesh/env.mesh` and
`config/mesh/rc.mesh`) only when `mesh` is on PATH, so on the CI runner it
prints `SKIP: test-mesh (mesh not installed)` and the job still goes green.
`install-ci-shells.sh` installs zsh, fish and nu but deliberately leaves mesh
out.

The reason is that mesh has no releases to pin. The other three are fixed to a
version and a checksum, which is what makes a CI failure mean "the config
broke" rather than "upstream moved". mesh is pre-1.0 and its language is still
being designed in `docs/DESIGN.md`, so tracking its `main` would put the config
tests at the mercy of an in-progress language — a mesh change could turn CI red
here with nothing wrong in this repo. That is a worse signal than the skip.

When it settles enough to pin — a tagged release, or a commit worth holding
still — add it alongside the others:

```sh
cargo install --git https://github.com/mikelward/mesh --tag "$MESH_VERSION" mesh
```

with `MESH_VERSION` in `test-tool-versions.sh` like the rest. A `cargo install`
build costs a few minutes per run, so cache it on that pin rather than
rebuilding every job.

Two things to check when it lands, because both are exercised by the current
config and neither is old: `:bool` (mikelward/mesh#394) is what
`config/mesh/env.mesh` reads `FAILSAFE` with, and the suite needs `mesh -c` to
stay able to source a config non-interactively.

## Up without atuin's search UI

`config/atuin/config.toml` draws the history search in a nine-row inline
pane rather than full-screen. Up still opens a search UI, just a small
one. The alternative is a per-shell widget that queries atuin
non-interactively and replaces the line in place, so Up behaves exactly
like readline's prefix search while still reading atuin's database:

```
atuin search --cmd-only --search-mode prefix --filter-mode host \
    --limit 1 --offset $n -- "$prefix"
```

Deferred until the inline pane has been lived with — it may be enough.

Cost if picked up: roughly 120 lines across the shells, plus a fork and a
SQLite query per keypress (single-digit ms locally, no network) where
readline's own search is in-memory and free.

Per shell, in increasing order of pain:

* **fish** — `commandline -r` and a `bind` on the up key. Clean.
* **zsh** — ZLE supplies `$BUFFER`, `$CURSOR` and `$LASTWIDGET`, the last
  being exactly the "is this a repeat press" state the walk back through
  matches needs.
* **bash** — `bind -x` with `READLINE_LINE` / `READLINE_POINT`, but
  readline has no `$LASTWIDGET`, so repeat-press state has to be
  reconstructed from the buffer. `bind -x` widgets already need care
  around shrc's DEBUG trap.
* **nushell** — may not be possible. reedline keybindings dispatch to a
  fixed set of edit events or `executehostcommand`; feeding a command's
  output back into the line buffer isn't exposed the way ZLE exposes it.

Unverified, because atuin wasn't installed where this was written:
whether `atuin search` takes `--offset` (fallback: `--limit $n | tail -1`,
which re-queries n rows per press), and whether offset 0 is the most
recent match.

Two design decisions to settle first, both of which outlast the code:

* A widget that takes Up outright loses moving up a line inside a
  multi-line buffer. zsh's `up-line-or-beginning-search` handles that and
  the widget would need the same guard.
* If nushell can't do this, AGENTS.md's parity rule needs an explicit
  carve-out for line-editor capability — otherwise nushell keeps atuin's
  pane while the other shells don't, and the rule says that isn't allowed.

## Let `$SHELL` switch a login shell into Elvish

`shrc`'s `want_reexec` re-execs into `$SHELL` when the login shell sshd started
differs from the one wanted, which is how `echo 'export SHELL=/bin/bash' >>
~/.env` changes shells without `chsh`. It only recognises bash and zsh:

```sh
case "${SHELL:-}" in
    */bash|bash) test "$shell" = bash && return 1;;
    */zsh|zsh)   test "$shell" = zsh && return 1;;
    *) return 1;;
esac
```

So `SHELL=/usr/local/bin/elvish` falls through the `*)` arm and nothing
happens; reaching Elvish as a login shell needs `chsh` today. Adding an
`*/elvish|elvish)` arm would make `~/.env` enough, which is the point of the
mechanism.

Two things to settle first. `$shell` is set from `$ZSH_VERSION` / `$BASH_VERSION`
and only ever holds bash/zsh/ksh/sh, so the "already in it" guard needs a
different test for a shell that never sources `shrc` at all. And the re-exec
runs `exec "$SHELL" -l`: Elvish accepts `-l` but treats it as a no-op, so a
login Elvish would rely on `rc.elv` alone — which is fine today only because
there is nothing an Elvish login shell reads that an interactive one doesn't.

## Install Elvish in the agent container too

`install-ci-shells.sh` builds Elvish on the CI runner, but
`.claude/hooks/session-start.sh` installs only shellcheck and nu, so an agent
session starts without it and `make test` prints `SKIP: test-elvish` — the same
silently-covers-less problem the CI installer exists to close, one environment
over.

The pin is already shared (`ELVISH_VERSION` in `test-tool-versions.sh`), so
this is the `go install` from the CI installer plus the hook's report-the-
version wrapper. The one thing to check is whether the container image ships a
Go toolchain; the CI runner does, since `make` builds the vcs submodule with
it, but the hook runs somewhere else and would need a fallback message rather
than a failed install if it doesn't.
