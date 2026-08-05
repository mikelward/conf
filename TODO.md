# TODO

## Finish splitting zsh out of shrc into zshrc

`zshrc` is now a real file that sets zsh's improvement options and then sources
`shrc`. The first slice is done; this is the rest.

Why the split exists: `shrc` has to parse under dash, which parses the whole
file including the `zsh)` arm it never runs, so anything dash's parser rejects
is unusable there — `zle_highlight=( ... )` is already over that line, which is
why `shrc:3036` assigns `zle_highlight[1]` instead. `path=( ${path:#$1} )` could
never live in `shrc` at all.

Roughly 250 of `shrc`'s remaining lines are still zsh-only and would move:

| What | Where it is now |
|---|---|
| Interactive prefs (history, `PROMPT_SUBST`, `AUTO_REMOVE_SLASH`) | `shrc:207-233` — see the ordering trap below |
| Interactive setup: `compinit`/`bashcompinit`/`zstyle`/`compctl`, `zle` widgets, `bindkey`, `precmd`/`preexec` hooks | `shrc:3011-3214` (~200 lines) |
| Prompt escape wrapping (`%{`/`%}`) | `shrc:2131` and the `escape_start`/`escape_end` pair |
| The six `emulate -L sh` functions | `delete_path`, `inpath`, `path`, `shift_options`, `psgrep`, `set_up_ssh_aliases` — rewritten zsh-native, not moved verbatim |

**The ordering trap.** The improvement options moved cleanly because they're
plain flags with no ordering constraint — `zshrc` sets them, then sources
`shrc`. The interactive prefs are not like that. `setup_shell_compat_interactive`
is called *after* `maybe_start_session_and_exit` precisely so a shell that
re-execs or hands off to tmux/shpool never pays for setup it's about to throw
away. Hoisting those options to the top of `zshrc` would run them before the
handoff and lose that. They need `shrc` to call back into `zshrc`, not a move.

The six `emulate -L sh` functions are the payoff, because `$path` is a real
array in zsh:

```zsh
inpath()       { (( ${path[(I)$1]} )) }
delete_path()  { path=( ${path:#$1} ) }
prepend_path() { path=( $1 ${path:#$1} ) }
```

That version handles PATH entries containing spaces and parens for free —
two of the cross-shell tests exist only to pin down the quoting the POSIX
version needs. Verified, including a `/a b` entry with a space.

**The quoting trap.** `${arr:#pat}` and `"${arr:#pat}"` are *different
operators*, and the quoted one fails silently:

```zsh
${path:#/second}    # array filter -- drops the matching element
"${path:#/second}"  # joins to a scalar first, so :# becomes
                    # "strip shortest matching prefix" -- a no-op here
```

So `delete_path` above is correct only while that expansion stays unquoted.
That is the opposite of the quoting discipline the rest of `shrc` teaches,
and the failure mode is a `PATH` that silently keeps the entry you asked to
remove. Any test for these must assert on the resulting `PATH`, not just
that the function ran.

**`KSH_ARRAYS` was considered and rejected.** It would make zsh arrays
0-based like ksh/bash, which sounds like it would ease sharing array code
with `shrc.vcs` and `bashrc.fuzzycomplete`. It doesn't, and it breaks the
rewrites above:

- `(( ${path[(I)$1]} ))` works as a boolean *because* zsh is 1-based: 0
  means "not found". Under `KSH_ARRAYS` a match in the first position also
  returns 0, so `inpath` reports the first `PATH` entry as missing.
- `$path` stops being the array and becomes its first element, so
  `path=( ${path:#$1} )` truncates `PATH` to one entry.
- `${#arr}` silently changes from element count to the string length of
  element 0. `$arr` and `${#arr}` both keep working and just mean something
  else, which is worse than an error.

There is also nothing to gain: `shrc.vcs` only uses `+=(...)`,
`"${arr[@]}"` and `${#arr[@]}`, which behave identically either way
(verified). `KSH_ARRAYS` is a compatibility option — turning it on is the
same move as `emulate sh`, which this work removed.

Everything else stays in `shrc` as the portable core for bash and for hosts
without zsh: the basic/general functions, environment setup, the prompt and
VCS code, session management (tmux/shpool), and the tool integrations.

**The load-order problem is the real work.** `zshrc` has to source `shrc`'s
definitions, install its overrides, and only then run the actions — otherwise
`shrc` clobbers the overrides, or calls its own version during startup
(`setup_fnm` calls `add_path` while sourcing). `SHRC_LOAD_FUNCTIONS_ONLY`
already suppresses all three action blocks, but there's no way to run them
afterwards: they're inline `if test -z ...` guards, not callable units. So
the split needs those three blocks wrapped in functions first — something
like `shrc_setup_env` / `shrc_setup_session` / `shrc_setup_interactive`,
called from the tail of `shrc` unless the flag is set. That refactor is
worth landing on its own, before any zsh code moves.

Costs worth weighing before continuing:

- **Another parity target.** `AGENTS.md` requires keeping `shrc`, fish,
  nushell, the mesh pair and the Elvish pair in step; `zshrc` makes zsh a
  separate one again, so anything moved here has to be checked against all
  of them rather than assumed to be zsh's business alone. This cost went up
  while the split was in review — Elvish landed on `main` in the meantime,
  which is itself the point: the list grows, and each addition makes a
  seventh file cheaper to forget.
- **`shrc_test.sh` runs under both bash and zsh** (444 tests each), which is
  what proves the two shells agree. Every option that moves to `zshrc` is one
  that cross-check no longer sees, so `shrc_zsh_test.sh` has to grow to cover
  what it stops proving — as it did for the improvement options.
- **`NO_NOMATCH` is still a deferral.** `shrc` sets it to keep sh's
  literal-glob behavior; auditing every glob so real zsh `NOMATCH` can be
  left on is separate work.

`NO_UNSET` was considered and rejected for now: it aborts the current suite
immediately, `shrc` has 134 bare positional references and none using
`${1:-}`, and `compinit`/`bashcompinit` and third-party completions read
unset parameters routinely. `setopt LOCAL_OPTIONS NO_UNSET` inside
individual functions gets most of the safety without the blast radius.

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
