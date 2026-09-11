# TODO

## Decisions needing review

Calls autopilot made without asking, each one chosen for being cheap to undo.
Delete an entry once you have agreed with it or reversed it.

- [ ] **The mesh config drops its `status` shortcut.** `status` became a mesh
      builtin (the status-value constructor) in mikelward/mesh#443, and a
      builtin's name is refused as a `func` or an `alias` — so `alias status =
      command vcs status` now fails at startup, printing a diagnostic on every
      shell. It is removed from `config/mesh/rc.mesh` only; shrc, fish, nu and
      Elvish keep both `status` and `st`, and mesh keeps `st`. The alternative
      is asking mesh to unreserve the name, which is its own open question
      (`TODO.md` in the mesh repo, "reserved names in general").
      *Reversible:* one line, the moment mesh has a spelling for it.

- [ ] **The mesh config renames its `title` function to `title-text`.** Same
      cause as the `status` entry above: `title` became a mesh builtin — the
      one that actually names the window — so `func title()` is refused and
      printed a diagnostic on every shell. shrc, fish, nu and Elvish keep a
      user-callable `title` that prints the string; in mesh, typing `title`
      now writes a title rather than printing one, and `title-text()` is what
      prints it. The window title itself is no longer a command to run by
      hand: `title-idle` / `title-busy` are registered on the `preprompt` and
      `preexec` hooks, so mesh names the window like the other four shells do.
      *Reversible:* the hook registrations are two lines, and the builder can
      take any name.

- [ ] **The fork-pull-request gap is documented upstream, not fixed here.**
      The shared setup is taken as-is, with the limitation written into
      `mikelward/codex-review`'s `docs/CONSUMER.md` rather than fixed. The
      alternative was holding this conversion until the shared action
      publishes its check result against `pull_request.head.sha`, so a fork
      pull request could satisfy a required `codex-review-check`. External
      fork pull requests are not a case these repositories take today, and the
      premise is unproven — the head-associated check comes from the `push`
      trigger, which same-repo pull requests always get. The three files here
      are byte-identical template copies, so a local edit would fail the pin;
      the fix belongs upstream once.
      *Reversible:* entirely. When the remedy lands upstream this repository
      re-copies `templates/` and gets it for free, and the remedy is written
      out there in full — the scope to use, the trap to avoid.

## Add the ruleset settings the Codex gate expects

Three settings this repository's ruleset does not have yet, all explained in
the shared `docs/CONSUMER.md`: require `codex` (not `sweep`), require
`codex-review-check / codex-review-check`, and require branches to be up to
date before merging. Deliberately a follow-up — requiring a check in the same
change that installs it would block the change that installs it.

Worth knowing for the next conversion in a sibling repository, since it looks
like a broken gate and is not: until `codex-review.yml` is on the default
branch, the two triggers that sweep unprompted — `schedule` and
`pull_request_target` — resolve their definition *there* and so never fire for
the pull request installing it. What does fire is
`pull_request_review_comment`, which resolves against the merge ref, so a
reply on a review thread runs the sweep and publishes the verdict for the
current head. That is what got this pull request a real `codex: success`
rather than a merge past a permanently `pending` status.

## Replace a broken nu rather than only reporting it

`.claude/hooks/session-start.sh` now rebuilds over an `elvish` that is on
`PATH` but will not run, because `Makefile:240` and `elvish_test.sh:30` gate on
`command -v elvish` alone — so a file that resolves takes the run branch and
fails the suite instead of skipping it.

`Makefile:207` gates nu exactly the same way, so a broken nu has the same
effect. The hook only reports it, and the message was corrected to say the
suite will fail rather than promising a skip.

What is left is the replacement attempt. It was not done alongside elvish's
because the trade is different: elvish is a `go install` measured in seconds,
while nu is a ~76 MB download, and doing that unprompted at session start on
the chance the local copy is broken is a bigger call than it looks. Worth
deciding deliberately rather than by symmetry.

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

`make test` runs `mesh_test.sh` (448 tests over `config/mesh/env.mesh` and
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

That has already happened once, which is the case for the skip rather than
against it: mesh gave `--name` a value type of its own, so a `wrapper func`'s
rest arguments hold flags rather than strings, and `retry`'s and `clone`'s
readers — comparing one against a string, matching another with `~` — started
refusing calls that had worked. The suite caught it locally the next time it
was run against a fresh mesh; pinned CI would have caught it on the commit that
landed, and unpinned CI would have blamed this repo for it.

The second instance is quieter and cuts the other way, so it is worth recording
next to the first: mesh added `job`, `regex`, `glob`, `stream` and `func` to its
return-type vocabulary over two days. Nothing here broke — this config declares
none of them — but `mesh_test.sh`'s sweep for an undeclared value function knew
the vocabulary by hand, so the two words that landed last left it able to miss a
`stream func` while its comment still claimed nothing could escape. A drifting
upstream weakens a test without ever turning it red, which no pin would have
caught either; the sweep now probes each word against the installed mesh and
fails loudly when it matches nothing, which is the half of the problem this repo
can fix on its own. A word mesh *adds* still needs a manual update here.

When it settles enough to pin — a tagged release, or a commit worth holding
still — add it alongside the others:

```sh
cargo install --git https://github.com/mikelward/mesh --tag "$MESH_VERSION" mesh
```

with `MESH_VERSION` in `test-tool-versions.sh` like the rest. A `cargo install`
build costs a few minutes per run, so cache it on that pin rather than
rebuilding every job.

Three things to check when it lands, because all three are exercised by the
current config and none is old: `:bool` (mikelward/mesh#394) is what
`config/mesh/env.mesh` reads `FAILSAFE` with; the suite needs `mesh -c` to stay
able to source a config non-interactively; and **declared return types** have to
be in the pinned mesh, since an undeclared `func` there has no value channel at
all. That last one is the sharpest argument yet for pinning rather than skipping:
the narrowing landed upstream and turned 190 of these 431 tests red in one
commit, with nothing wrong in this repo — a pin would have named the mesh commit
that did it, where the skip meant finding out by hand on the next local run.

## Fan out atuin's fuzzy arrows to fish and nushell

Settled in zsh (#328): Up opens atuin's **prefix** search (its
`atuin-up-search` widget, via `--shell-up-key-binding`, which reads
`search_mode_shell_up_key_binding` = prefix and
`filter_mode_shell_up_key_binding` = host); Down, like Ctrl-R, opens the
**default fuzzy** search. Both open the atuin pane -- Tab inserts the selection
to edit, Enter runs it. `--disable-up-arrow` in `init_atuin` keeps atuin from
binding its own Up, and shrc binds both arrows (on the literal `\e[A`/`\e[B`
forms, so kitty reaches them) to `up-/down-or-atuin-search`, which dispatch to
`atuin-up-search` for Up and `atuin-search` for Down. When atuin is absent --
or its init failed to define the widget -- they fall back to a native
session-local prefix search (`history-beginning-search-{backward,forward}` via
`up-/down-line-or-local-history`). The ghost text stays prefix + host: an
inline completion can only extend what you typed. **bash** keeps readline's Up
(`--disable-up-arrow`; zle is zsh-only, so it gets no arrow widget).

Remaining: **fish**, **nushell**, and **Elvish** bind atuin's own Up (prefix +
host, via the `*_shell_up_key_binding` settings) but no fuzzy Down. Bring them
to the same split as zsh -- Up = prefix, Down = fuzzy -- or record a scoped
deferral:

* **fish** — keep Up on atuin's prefix search; add Down bound to atuin's
  default (fuzzy) search.
* **nushell** — same, via reedline's atuin keybindings; may be limited by what
  reedline exposes. Tier 2, so it can lag.
* **Elvish** — currently binds only Ctrl-R to atuin (`config/elvish/lib/
  interactive.elv`); add Up = prefix and Down = fuzzy there too. Tier 2.
* **mesh** — a separate session owns mesh's own ghost + dropdown model;
  nothing to rebind from here.

The `*_shell_up_key_binding` settings in `config/atuin/config.toml` are now
live -- they shape zsh's prefix Up as well as fish's and nushell's -- so they
stay.

### Follow-ups from the fuzzy-arrows review

* **Exercise the arrow widgets, not just their bindings.** The zsh test asserts
  which widget each arrow binds to, not that pressing the arrow dispatches to
  the right atuin-search variant / native fallback. Real coverage needs a pty
  or an instrumented `zle`, and multiline-buffer zle tests here have been
  flaky, so it's deferred. Add it if a non-flaky harness is worked out.

## Ghost text: fan out beyond zsh

`init_zsh_autosuggestions` in `shrc` sources zsh-autosuggestions and, when
atuin is present, points its strategy at atuin's database via a local
backend (`set_zsh_autosuggest_strategy`: `ZSH_AUTOSUGGEST_STRATEGY=(atuin_host
history)` behind an `eval` so `dash -n shrc` doesn't choke on the array
literal; `_zsh_autosuggest_strategy_atuin_host` runs `atuin search
--search-mode prefix --filter-mode host`), so the ghost is deduped and
host-scoped, falling back to zsh's own history when atuin is absent.
right-arrow/End accept the whole suggestion, Alt-F a word, Enter runs only
the line. zsh only. Remaining:

* **Decide: host or global scope for the ghost.** Currently host-scoped
  (`--filter-mode host`), matching the Up-key binding and the local zsh
  history it replaced, so it won't ghost commands from other machines on a
  synced atuin (the Codex P2 on mikelward/conf#317 that prompted the current
  code). The alternative is global -- a ghost that draws on everything ever
  run anywhere, which may be what's wanted for cross-host recall. Reversible:
  one flag in `_zsh_autosuggest_strategy_atuin_host` (drop or change
  `--filter-mode`); the regression test in `shrc_test.sh` pins whichever is
  chosen, so decide deliberately rather than by the default.
* **Verify the atuin strategy on a real box.** Written where atuin wasn't
  installed, so `_zsh_autosuggest_strategy_atuin_host`'s `atuin search` flags
  follow atuin's documented CLI -- confirm the ghost actually comes from
  atuin, host-scoped, on a machine that has it.
* **Other shells (accepted disparity, not a blocker).** fish and nushell
  have native history autosuggestions, but from their own history, not
  atuin's, and not easily repointed; bash would need ble.sh; mesh and
  elvish have nothing off the shelf -- mesh is the one wanted most and is
  to be built by hand. Same mental model everywhere (ghost + right-arrow
  accepts + Enter runs the line), different machinery, uneven coverage.

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

## Review and merge gates

- [ ] **Add `zizmor` to the ruleset's required set** once it has reported
      on a pull request: the new zizmor workflow runs unfiltered on every
      PR precisely so it can be required (a paths-filtered workflow
      creates no check run at all on a non-matching PR, which a ruleset
      waits on forever) — the posture piloted in mikelward/lanes and
      mikelward/ci-commit-artifact. `repo-rules mikelward/conf` with
      no arguments applies the standard `lanes codex zizmor` set.
- [ ] Add a CI gate (`ci.yml`) running whatever checks this repository
      supports, so the ruleset has a test gate to require — or record
      here that there is deliberately nothing to run.
- [ ] Verify the settings half of the fleet's bar — every repository
      works the same: comprehensive automated review, required merge
      gates, and auto-merge. A ruleset on the default branch requiring
      the gates, the `codex` status, conversation resolution and
      up-to-date branches, with the auto-merge setting enabled.

## Ship `vcs` with dotfiles for ephemeral boxes

The prompt shows git/hg/jj *state* via the `vcs` binary and degrades to a plain
path prompt when it's absent — never re-growing the status logic `vcs` factors
out (project-root *detection* by marker dirs is the allowed exception; see the
shell-tier rule in `AGENTS.md`). So an ephemeral box that has the dotfiles but
not `vcs` (SSH into a throwaway host where `setup` never ran) gets no git-state
in the prompt.

Lever: make the `vcs` binary travel with the dotfiles so "dotfiles present"
implies "vcs present" — vendor the static Go binary, selected by OS *and* arch
(linux-amd64/arm64, darwin-amd64/arm64 — the repo supports macOS, so arch alone
would ship a Linux binary to a Mac), which keeps shell startup offline. A fetch-and-cache-on-first-start variant
instead puts a network call on the startup hot path, so it needs the full
cost/reliability treatment before it's chosen: latency and $ per fetch,
rate-limit/outage behavior, a pinned checksum, and a guarantee that an offline
or failed fetch silently keeps the plain prompt rather than blocking or
erroring startup. Weigh all that against just accepting a plain prompt on hosts
where `vcs` wasn't installed.

## Handle atuin's enter_accept in Elvish's hand-rolled Ctrl-R

`config/atuin/config.toml` sets `enter_accept = true` (shared by every shell).
For the shells with a shipped `atuin init` integration (zsh, bash, fish) that
makes Enter run the selection and Tab insert-for-edit. But Elvish's Ctrl-R is
hand-rolled (`config/elvish/lib/interactive.elv`'s `-atuin-search`): it slurps
`atuin search -i`'s stdout into the buffer and treats any nonzero exit as a
cancel (the `catch`). It doesn't set `ATUIN_SHELL`, so it may receive atuin's
accept signal (an `__atuin_accept__:` output prefix and/or a nonzero "execute"
exit status) and either insert the literal prefix or discard the line.

Verify on a box with atuin + elvish which signal atuin emits when `ATUIN_SHELL`
is unset, then update the wrapper to handle it: strip an `__atuin_accept__:`
prefix, and distinguish the execute status from a real cancel (run the line
rather than dropping it). Tier 2 fast-follow, so it lags the zsh change rather
than gating it.
