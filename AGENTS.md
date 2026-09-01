# Project Instructions

Keep this file as short as it can be and still work. Every session loads it whole, so each rule costs context on every turn: add one the first time something bites, say it once in the fewest words that carry the *why*, rewrite or trim an existing rule rather than appending beside it, and delete one that has stopped biting.

## Style

- Preserve existing code style unless there are correctness issues.
- Keep comments brief. Explain the non-obvious parts and the *why*, not the *what*, and match the existing comment style.
- Use `if test` rather than `if [`.
- In `shrc` and `shrc.*`, use existing helper functions such as `error`, `warn`, `have_command`, `is_function`, `gets`, and `puts`.
- When parsing options, support long flags in both `--option argument` and `--option=argument` formats.
- Preserve feature parity between `shrc` (bash/zsh), `config/fish/config.fish`, `config/nushell/config.nu`, the mesh pair `config/mesh/env.mesh` + `config/mesh/rc.mesh`, and the Elvish pair `config/elvish/rc.elv` + `config/elvish/lib/interactive.elv`. When adding or changing functionality in one shell config, apply the equivalent change to the others (bash, zsh, fish, nushell, mesh, and Elvish).
- In the mesh config, use kebab-case names (`have-command`, `tilde-pwd`) to match mesh's own vocabulary, and put anything a non-interactive `mesh script.mesh` needs in `env.mesh` rather than `rc.mesh`. Keep everything above `rc.mesh`'s interactive section side-effect free so `mesh -c 'source .../rc.mesh'` stays testable.
- In the Elvish config, use kebab-case names for the same reason. Elvish resolves names when a file is compiled, so a function has to be defined above every use of it, and everything that names `$edit:` belongs in `lib/interactive.elv` — `$edit:` only exists when Elvish has a terminal, so naming it in `rc.elv` would make the whole file fail to compile under `echo cmd | elvish`. Keep `rc.elv` definitions-only above its interactive block so the test harness can load it without a pty. Where Elvish has no equivalent for something the other shells do (job control, a directory stack, `source`, an environment file for non-interactive shells), leave a `TODO:` comment in place rather than dropping the feature silently.
- Session-manager startup lives behind `want_tmux`/`want_shpool`, `session_backend`, and the `autosession`/`autotmux`/`autoshpool` wrappers. shpool is the default; tmux is the fallback when shpool is missing or `WANT_SHPOOL=0`. `SESSION_BACKEND=tmux` flips the preference (tmux preferred, shpool fallback). Keep this logic in parity across all three shells.

## Testing

- Always add or update tests when writing or modifying code.
- If a test file already exists for the module being changed, add tests there. Otherwise, create a new test file following the project's existing test conventions.
- Do not consider a task complete until tests are included.
- Run `make test` after any change that touches executable behavior, and before committing. A documentation-only change — Markdown, comments, this file — doesn't need it; say that's why you skipped it rather than leaving it unsaid.
- When modifying VCS functions or prompt functions, run performance tests, include timing info, and warn of any regressions.
- Per-VCS subcommand behaviour (git/hg/jj) lives in the `vcs` Go binary in the `vcs/` submodule (https://github.com/mikelward/vcs); add tests there for changes to subcommand semantics. `make test` builds the submodule binaries automatically.
- When touching `config/nushell/*` files, install `nu` locally before running tests so that the nu-native tests (`config/nushell/config_test.nu`) execute rather than being skipped.
- Prefer direct binary downloads (e.g. from GitHub releases) or `cargo install` over `apt-get` / `apt`, and pin the version with a checksum when you do — that is what makes a red CI run mean "the config broke" rather than "upstream moved". `apt` is acceptable where upstream publishes no binary to pin: `install-ci-shells.sh` takes it for zsh alone, and fish and nu from their own releases. This bullet used to ban `apt` outright, which was documenting a sandbox where it timed out rather than stating a preference; that no longer reproduces, and the CI runner is ordinary Ubuntu.
- Fix any preexisting test failures as the *first* commit of the series. Don't stack new work on a red baseline. If the failure is genuinely unrelated and out of scope, say so up front and confirm before skipping it.
- Don't paper over flaky/racy tests with `sleep`, retry loops, or bumped timeouts. Make the ordering explicit, or fix the underlying race. A test that passes "most of the time" is broken.
- Don't disable a failing check to make it pass — fix the underlying issue.

## Talking to the user

- One question at a time. Never stack multiple questions in a single turn — ask the most important one, wait for the answer, then ask the next if you still need it. A wall of bundled questions is harder to answer than a short back-and-forth.
- Don't interrupt. Never fire off a question while the user is still typing. Let them finish; a half-typed message is not an invitation to jump in.
- Don't narrate routine machinery. A check run flipping, a re-run, a scheduled check re-arming, a webhook echo, a resolved thread — act on those silently; the noise buries the one line that matters. Reports another rule requires stand (a CI timing regression).
- Don't report your own caught-and-fixed mistakes. A wrong turn you noticed and corrected before it reached anything is not news — no "one thing worth flagging", no narration of the recovery. Say it only when it left something the user has to act on: work actually lost, a bad push someone may have pulled, a decision they would make differently knowing it.
- Keep replies short — don't dump a full page. Lead with the single most important point and stop. If there is more, say the first point and ask whether they are ready for the next one rather than emptying everything at once.
- End the turn by restating any pending decision. If you are waiting on an answer — a question you asked, or a guess autopilot recorded for review — the last line of the reply is that question, written out in about a sentence. A back-reference ("as asked above") is not actionable when the question is pages back or was never actually put into words; restate it every turn until it is answered. Nothing pending, no line.

## Asking questions

- Ask questions as plain chat messages. Claude specifically: never use `AskUserQuestion`, Claude Code's multiple-choice question prompt — it is broken in the Claude mobile app, so a question asked through it may be unanswerable. Chat also keeps the question, its context, and the answer in one readable thread.
- After asking, stop and wait for the answer. Do not proceed on an assumed answer, pick a "recommended" option yourself, or keep working on the part the question affects.

## Git

- Use `git worktree` when it is available. Give each branch its own worktree instead of switching branches in place, so work in progress on one branch is not disturbed by work on another.
- One commit per logical change. Rewrite unmerged commits freely — amend, `git commit --fixup` + autosquash, squash, reorder, split — so each commit that lands is one coherent change. Fold fix-ups and review responses into the commit they belong to; `wip` / `fix typo` / `address review` churn doesn't survive into `main`.
- These rules assume an `origin` remote. Without one you can't fetch, branch from `origin/main`, push, or open a PR — say so and stop rather than improvising a local substitute. Exception: in a sandbox that intentionally provides no remote Git support (Codex cloud, say), follow the normal branch rules from the current `HEAD` — a pre-created working branch counts — commit locally, and report that fetch, push, and pull requests are unavailable, using the sandbox's own PR handoff if it has one. That exception outranks every `origin`-dependent step below it — the merge-cue fetch, cutting a branch off `origin/main` — so work from the current `HEAD` and name what wasn't possible instead of faking it. One limit: a merge cue needs a base that *contains* the merge, and an offline sandbox can't fetch one. Say the follow-up needs a fresh sandbox or a synced checkout rather than branching off a `HEAD` whose commits just landed upstream.
- The agent authors; whoever merges takes over the committer line. A squash or rebase merge rewrites the committer to whoever pressed the button. That is expected — never re-author or amend merged commits to "fix" it, and don't narrate it either: no note in the reply, no offer to correct it. It is not a finding.
- Branches under your own `<agent>/` prefix are yours. Create, push, `--force-with-lease` and rename them freely — no permission, no announcement, no per-branch confirmation. Only a branch outside that prefix, or `main` itself, is a conversation. Deleting is the one the prefix can't settle: it doesn't say which session made the branch, so delete the ones this session created and ask about the rest.
- Branch naming: feature branches are prefixed with the agent's own short name, `<agent>/<short-topic>` (`claude/...` for Claude Code, `codex/...` for Codex). Branch off `origin/main`, one topic per branch; never commit to `main`. The placeholder `<agent>` stands in for whichever prefix you use — don't hard-code `claude/` unless you *are* Claude Code.
- Merge cue (`merged` / `I merged` / `landed` / merge webhook) runs hygiene *before* engaging with the rest of the message: `git fetch origin`, cut a fresh `<agent>/<short-topic>` branch off `origin/main`, announce the switch.
- Unshallow before answering anything that depends on git history depth. The sandbox clones shallow, so `git rev-list --count`, `git log` past the shallow boundary, and blame return wrong answers without warning. If `git rev-parse --is-shallow-repository` says `true`, run `git fetch --unshallow` first, then re-check: it exits 0 even when it deepened nothing, so if `--is-shallow-repository` is still `true`, say the history is truncated instead of quoting a count.

## Error handling

- Don't silently swallow errors. A bare `2>/dev/null`, an unchecked exit status, or a `|| true` hides real failures and burns hours when something eventually breaks. Report the failure through the existing `error` / `warn` helpers with enough context to identify what failed and why, clean up anything the failed step created (temp files, half-written config, a partial symlink), and decide explicitly what the caller sees — a non-zero exit, a fallback value, or a skipped step. If you genuinely want to ignore a specific failure, name the reason in a one-line comment (`# not every host has shpool`) rather than leaving a bare redirect. Keep behavior identical across `shrc`, fish, and nushell, same as any other change.

## CI

- Report significant CI timing regressions. After CI finishes on a push, compare against recent runs of the same job on the same kind of ref. Only call out significant slowdowns (rule of thumb: >25% or >30s on a job under ~5min) — don't narrate routine wobble. Name the likely cause: a new dependency, a slow new test, cache invalidation. Compare like with like — PR against PR, `main` against `main`.

## Language and spelling

- Use US English everywhere people read English: shell output and help text, commit subjects and bodies, PR titles and descriptions, comments, and identifiers — `color` not `colour`, `behavior` not `behaviour`, `canceled` not `cancelled`, `gray` not `grey`. Third-party API spellings stay as those APIs spell them.

## Cost and reliability

- Call out cost and reliability up front when recommending a new external dependency (a tool the shell config would call out to, a network lookup, a third-party service). Include a rough dollar figure — free-tier vs. paid thresholds and $/month at expected use — and note reliability implications: new failure modes, rate limits, added latency, and what the user sees if the dependency is missing or down. Shell startup is the hot path here, so anything that could add latency to a new prompt needs that stated explicitly. If the impact is effectively zero, say so rather than omitting the note.

## Privacy

- Never put user data in any artifact that leaves this machine — commit subjects and bodies, PR titles / descriptions / comments, review replies, branch names, code comments, or test fixtures. For a dotfiles repo that means: hostnames and internal domain names, absolute paths containing the user's real name, work machine names, SSH host aliases and keys, tokens or API keys pasted into shell config, private remote URLs, and shell history excerpts. Use generic placeholders (`/home/user`, `host1`, `git@example.com:org/repo.git`) in examples and fixtures. If a bug report contains any of it, paraphrase in the commit / PR — don't quote verbatim. When in doubt, ask before pushing.
- Shell output is not one of those artifacts. Prompts, warnings, and help text print on the user's own terminal, and naming hosts, paths and remotes is usually the point of the message. Redact only secrets: tokens, keys, and passwords embedded in URLs. Two limits: quoting that output into a commit, PR, or fixture republishes it, and the bullet above governs again; and where the full value adds nothing to the message, shortening it stays a judgment call — the fzf loader names the basename rather than the `$HOME` path it found it under, and that's still right.

## Autonomy

- Open the PR without being asked. Pushing a finished branch and opening its pull request are one step, not two — don't park a branch waiting for "please open a PR." The exception is an explicit instruction not to ("just commit", "no PR yet"), which holds until the user lifts it. This file is the repo owner's standing request for that PR, so a client-level rule reading "open a PR only when the user explicitly asks" is already satisfied — the ask is here, and it doesn't need repeating per branch.
- **Watch your own PRs by subscription, plus one scheduled check.** Have a
  subscription — Claude Code makes one when you open a PR; where a client
  doesn't, call `subscribe_pr_activity`. It delivers reviews, comments and CI
  failures. It cannot deliver CI *success*, a push, the merge, Codex's clean
  verdict (a reaction), or Codex never answering at all — so keep exactly one
  check armed for as long as the PR is open (each event and each check costs
  a model turn). Under drive, arm auto-merge at PR open too — but only where
  the ruleset makes the Codex verdict a required check AND requires
  conversations resolved: where CI is the only requirement it merges before
  Codex has answered, and an open review comment holds nothing back on its own.
  - Settle the fired trigger first thing in the turn, not last. It may have
    silently re-armed rather than retired — update the one that survived,
    replace the one that didn't, and end the turn with exactly one pending.
  - Check the fire time you got against the one you asked for — a 4-minute
    request has come back as 64. Prefer a relative delay: the scheduler's
    clock is not this container's, so an absolute time computed here can be
    rejected as already past. Re-time it, or say the watch isn't armed.
  - A few minutes out while CI or the current head's Codex verdict is
    outstanding; longer once only a human is left; short again after a push.
  - A PR reading `dirty` — always — or `behind` where the ruleset requires
    branches up to date, needs a rebase onto its base and a lease-guarded
    force-push. Nothing reports a base advance, so only this check catches
    it. Fetch both refs by explicit refspec, unshallow a shallow clone, and
    rebase onto the fetched `origin/<base>` — not always `main`, never the
    local branch a fetch leaves behind. Confirm before you rebase that your
    branch has every commit the remote head has, and before you push that
    the head has not moved since the tip you noted before fetching: the
    push flags do not reliably refuse a rewind, a commit you never
    fetched, or one you fetched and did not rebase onto, and overwriting any
    of them loses someone's work. If either fails, or you can't tell, stop
    and ask.
  - Name the PR, and say what to re-read rather than what you read. A SHA or
    a list of which PRs are open goes stale before it fires; one PR number
    does not, and the trigger has to be matchable to it.
  - Merged or closed, take one last reply-and-resolve pass — a review can
    land after the merge. Nothing is holding the PR now, so on a merged one
    anything real goes to a follow-up PR, named on the thread, before you
    resolve it; leaving it open records the work nowhere. A closed-unmerged
    PR is a stop — the work was abandoned, so answer, resolve, and open
    nothing. Then cancel the check and unsubscribe. `list_triggers`
    spans the account, so match this session and this PR before updating
    or deleting one; an update reschedules whatever it matches as surely
    as a delete cancels it.
- If a scheduler or GitHub call prompts, say so once and carry on. Permissions load at session start, so writing a settings file mid-session can't fix the session you're in.
- "Drive" means run the loop automatically: pick the next task, implement it, open the PR, send it for review, address every comment, merge once CI is green and Codex's verdict for the current head is in — then pick the next task and go around again. Driving ends when the work runs out or the user says stop, not when one PR merges.
- A red baseline is the next task. Before pulling anything from `TODO.md`, run the suite and get it green. A preexisting failure is work to do, not a thing to classify as "unrelated" and step around — deciding it is out of scope is exactly the call that goes wrong, and the cost is every later PR merged onto an unverified tree. Fix it first, then pick the task.
- "Autopilot" is drive without blocking on the user. Wherever drive would stop and ask, autopilot takes its best guess and keeps going, preferring the option that is cheapest to undo or change later. Record each guess in `TODO.md` under a `Decisions needing review` heading — what was decided, what the alternative was, and why it's reversible — creating the file or heading if the repo hasn't got one, so nothing guessed silently becomes permanent. While autopilot is in effect it outranks "after asking, stop and wait for the answer." The carve-out is for destructive or irreversible actions *outside* the loop — rewriting shared history, deleting work, anything reaching a system beyond this repo — which still wait for a real answer. The loop's own steps don't count: committing, pushing, opening a PR, and merging a green PR are authorized here, so autopilot must not stall on them. Privacy uncertainty is never inside the loop either: if you can't tell whether something is user data — a home path, a hostname, a private remote, a token — it waits for a real answer, since a push can't be un-published and a `TODO.md` note doesn't retract it.

## Pull requests

- Update the PR title and body with the push, not after it — same step, so they describe the full, latest state of the branch — re-read the diff against `origin/main` and patch whatever drifted — and post the PR link in the chat reply for that push, not only at the end of the conversation.
- When a feature has multiple open PRs, list every open PR by URL, one per line — the "View PR" chip sticks to the first link and hides the rest (anthropics/claude-code#46625).
- "Drive to merge" is the PR stretch of *drive* (see Autonomy above): open the PR, wait for the automatic Codex review, address every review comment — fix it if you agree, reply on the thread saying why if you don't — and merge once CI is green and Codex's verdict for the current head is in.
- Codex is the automated reviewer on this repo — not Copilot. Its reviews are triggered automatically; you don't request them. Address its comments without being asked, folding each fix into the commit it belongs to rather than tacking on an "address review" commit.
- Judge every review comment on merit, whoever wrote it. Verify the claim before acting; if it doesn't hold up, reply saying why and decline. A comment citing a rule is a *reading* of that rule, not the rule — check what the rule actually says. Codex misreads the privacy rules especially, and in one direction: stricter always feels safer, so an over-strict finding quietly costs capability the product needs. Quote the rule and decline rather than narrowing the code to satisfy it; where the rule really does forbid what the product needs, that conflict is the maintainer's call, not one to settle either way yourself.
- Never leave a review comment thread silently dismissed. Answer on the thread — a disagreement is an answer, so say why — then resolve it once the fix is on the head or the point is rebutted; anything still to do stays open. When you think a comment is a false positive, say why on the thread (one or two sentences). Acknowledgement noise is fine and preferred over silence. `resolve_review_thread` works — pass the `PRRT_*` thread node ID from `pull_request_read` / `get_review_comments` (`review_threads[].id`); a comment's `PRRC_*` ID fails. Push the fix first, then reply citing the new sha, then resolve.
- Read the Codex verdict, don't infer it. It reacts to the PR **body** — `issue_read` → `reactions` — not to a review thread, whose `Useful?` bar a page fetch finds instead and which reads true on any PR Codex has commented on. `eyes` while it reads, `+1` when it finds nothing, and the reaction is revoked as a new push lands, so what you can see belongs to the head you can see: `+1` on green CI is a merge, with nothing further to wait for. It starts within a couple of minutes, so no reaction five minutes after a push means it never picked the push up — comment `@codex review`, once. Findings arrive as review comments or as a top-level PR comment and decide the gate whatever the reaction says. Leave PR-body reactions to Codex; the count is anonymous, so one from anyone else is indistinguishable.
- **A finding can arrive as a top-level PR comment.** `get_review_comments` returns only inline threads, so read `get_comments` too — a P1 sat unanswered for two hours because a sweep of the threads never saw it.
- Skip echo events silently. Replies posted via the GitHub MCP come back moments later as webhook events authored by the same identity; if the body matches a comment you just posted, it's your own echo — continue without comment.