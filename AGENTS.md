# Project Instructions

## Style

- Preserve existing code style unless there are correctness issues.
- Keep comments brief. Explain the non-obvious parts and the *why*, not the *what*, and match the existing comment style.
- Use `if test` rather than `if [`.
- In `shrc` and `shrc.*`, use existing helper functions such as `error`, `warn`, `have_command`, `is_function`, `gets`, and `puts`.
- When parsing options, support long flags in both `--option argument` and `--option=argument` formats.
- Preserve feature parity between `shrc` (bash/zsh), `config/fish/config.fish`, `config/nushell/config.nu`, and the mesh pair `config/mesh/env.mesh` + `config/mesh/rc.mesh`. When adding or changing functionality in one shell config, apply the equivalent change to the others (bash, zsh, fish, nushell, and mesh).
- In the mesh config, use kebab-case names (`have-command`, `tilde-pwd`) to match mesh's own vocabulary, and put anything a non-interactive `mesh script.mesh` needs in `env.mesh` rather than `rc.mesh`. Keep everything above `rc.mesh`'s interactive section side-effect free so `mesh -c 'source .../rc.mesh'` stays testable.
- Session-manager startup lives behind `want_tmux`/`want_shpool`, `session_backend`, and the `autosession`/`autotmux`/`autoshpool` wrappers. shpool is the default; tmux is the fallback when shpool is missing or `WANT_SHPOOL=0`. `SESSION_BACKEND=tmux` flips the preference (tmux preferred, shpool fallback). Keep this logic in parity across all three shells.

## Testing

- Always add or update tests when writing or modifying code.
- If a test file already exists for the module being changed, add tests there. Otherwise, create a new test file following the project's existing test conventions.
- Do not consider a task complete until tests are included.
- Run `make test` after any change that touches executable behavior, and before committing. A documentation-only change — Markdown, comments, this file — doesn't need it; say that's why you skipped it rather than leaving it unsaid.
- When modifying VCS functions or prompt functions, run performance tests, include timing info, and warn of any regressions.
- Per-VCS subcommand behaviour (git/hg/jj) lives in the `vcs` Go binary in the `vcs/` submodule (https://github.com/mikelward/vcs); add tests there for changes to subcommand semantics. `make test` builds the submodule binaries automatically.
- When touching `config/nushell/*` files, install `nu` locally before running tests so that the nu-native tests (`config/nushell/config_test.nu`) execute rather than being skipped.
- Do not use `apt-get` or `apt` to install tools. Use direct binary downloads (e.g. from GitHub releases) or `cargo install` instead.
- Fix any preexisting test failures as the *first* commit of the series. Don't stack new work on a red baseline. If the failure is genuinely unrelated and out of scope, say so up front and confirm before skipping it.
- Don't paper over flaky/racy tests with `sleep`, retry loops, or bumped timeouts. Make the ordering explicit, or fix the underlying race. A test that passes "most of the time" is broken.
- Don't disable a failing check to make it pass — fix the underlying issue.

## Talking to the user

- One question at a time. Never stack multiple questions in a single turn — ask the most important one, wait for the answer, then ask the next if you still need it. A wall of bundled questions is harder to answer than a short back-and-forth.
- Don't interrupt. Never fire off a question while the user is still typing. Let them finish; a half-typed message is not an invitation to jump in.
- Keep replies short — don't dump a full page. Lead with the single most important point and stop. If there is more, say the first point and ask whether they are ready for the next one rather than emptying everything at once.
- End the turn by restating any pending decision. If you are waiting on an answer — a question you asked, or a guess autopilot recorded for review — the last line of the reply is that question, written out in about a sentence. A back-reference ("as asked above") is not actionable when the question is pages back or was never actually put into words; restate it every turn until it is answered. Nothing pending, no line.

## Asking questions

- Ask questions as plain chat messages. Claude specifically: never use `AskUserQuestion`, Claude Code's multiple-choice question prompt — it is broken in the Claude mobile app, so a question asked through it may be unanswerable. Chat also keeps the question, its context, and the answer in one readable thread.
- After asking, stop and wait for the answer. Do not proceed on an assumed answer, pick a "recommended" option yourself, or keep working on the part the question affects.

## Git

- Use `git worktree` when it is available. Give each branch its own worktree instead of switching branches in place, so work in progress on one branch is not disturbed by work on another.
- One commit per logical change. Rewrite unmerged commits freely — amend, `git commit --fixup` + autosquash, squash, reorder, split — so each commit that lands is one coherent change. Fold fix-ups and review responses into the commit they belong to; `wip` / `fix typo` / `address review` churn doesn't survive into `main`.
- These rules assume an `origin` remote. Without one you can't fetch, branch from `origin/main`, push, or open a PR — say so and stop rather than improvising a local substitute. Exception: in a sandbox that intentionally provides no remote Git support (Codex cloud, say), follow the normal branch rules from the current `HEAD` — a pre-created working branch counts — commit locally, and report that fetch, push, and pull requests are unavailable, using the sandbox's own PR handoff if it has one. That exception outranks every `origin`-dependent step below it — the merge-cue fetch, cutting a branch off `origin/main` — so work from the current `HEAD` and name what wasn't possible instead of faking it. One limit: a merge cue needs a base that *contains* the merge, and an offline sandbox can't fetch one. Say the follow-up needs a fresh sandbox or a synced checkout rather than branching off a `HEAD` whose commits just landed upstream.
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
- Opening the PR includes wiring up the watch. In the same step, subscribe to the PR's activity (`subscribe_pr_activity`) *and* arm the first scheduled check. Both, not either: the subscription gives you review comments and CI results as they land, and the scheduled check is what catches the ones the webhook drops. A PR that is only subscribed looks watched and silently isn't.
- Poll your own open PRs every 5 minutes — the ones you opened or were explicitly asked to watch — for new review comments, CI status, approvals, and the Codex thumbs up. Webhooks drop events, so a PR nobody is polling stalls silently. Never end a turn by going idle with one of yours still open: arm the next check with whatever the client offers (`send_later`, a scheduled task / cron, `/loop`), and arm it *without asking*. Scheduling your own follow-up is routine hygiene, not a decision that needs approval. Someone else's open PR is not your polling job — adopt one only when asked. Keep polling until the PR state is final: merged, with CI and Codex both reported on the final PR head — or closed unmerged. Then run one last reply-or-resolve pass and cancel the watch. Open a follow-up PR (with its own watch) for anything a merged PR still needs.
- What the polling costs. Twelve wake-ups an hour per PR, each a model turn plus a few GitHub API calls — roughly a dollar an hour on a large context. The scheduler is the single point of failure: one missed re-arm ends the watch silently, with no error anywhere. If you can't arm the next check, say so in the reply rather than leaving a PR that looks watched and isn't.
- One pending check per PR, not one per wake-up. A webhook event can start a turn while a scheduled check is still pending; arming another there leaves two chains, each re-arming itself, and the cost doubles every time it happens. Before arming, reuse or cancel the pending one (`update_trigger`, or `delete_trigger` then re-arm) so exactly one check is outstanding.
- "Drive" means run the loop automatically: pick the next task, implement it, open the PR, send it for review, address every comment, merge once CI is green and Codex has left its thumbs up — then pick the next task and go around again. Driving ends when the work runs out or the user says stop, not when one PR merges.
- A red baseline is the next task. Before pulling anything from `TODO.md`, run the suite and get it green. A preexisting failure is work to do, not a thing to classify as "unrelated" and step around — deciding it is out of scope is exactly the call that goes wrong, and the cost is every later PR merged onto an unverified tree. Fix it first, then pick the task.
- "Autopilot" is drive without blocking on the user. Wherever drive would stop and ask, autopilot takes its best guess and keeps going, preferring the option that is cheapest to undo or change later. Record each guess in `TODO.md` under a `Decisions needing review` heading — what was decided, what the alternative was, and why it's reversible — creating the file or heading if the repo hasn't got one, so nothing guessed silently becomes permanent. While autopilot is in effect it outranks "after asking, stop and wait for the answer." The carve-out is for destructive or irreversible actions *outside* the loop — rewriting shared history, deleting work, anything reaching a system beyond this repo — which still wait for a real answer. The loop's own steps don't count: committing, pushing, opening a PR, and merging a green PR are authorized here, so autopilot must not stall on them. Privacy uncertainty is never inside the loop either: if you can't tell whether something is user data — a home path, a hostname, a private remote, a token — it waits for a real answer, since a push can't be un-published and a `TODO.md` note doesn't retract it.

## Pull requests

- On every push, update the PR title and body so they describe the full, latest state of the branch — re-read the diff against `origin/main` and patch whatever drifted — and post the PR link in the chat reply for that push, not only at the end of the conversation.
- When a feature has multiple open PRs, list every open PR by URL, one per line — the "View PR" chip sticks to the first link and hides the rest (anthropics/claude-code#46625).
- "Drive to merge" is the PR stretch of *drive* (see Autonomy above): open the PR, wait for the automatic Codex review, address every review comment — fix it if you agree, reply on the thread saying why if you don't — and merge once CI is green and Codex has left its thumbs up.
- Codex is the automated reviewer on this repo — not Copilot. Its reviews are triggered automatically; you don't request them. Address its comments without being asked, folding each fix into the commit it belongs to rather than tacking on an "address review" commit.
- Judge every review comment on merit, whoever wrote it. Verify the claim before acting; if it doesn't hold up, reply saying why and decline.
- Never leave a review comment thread silently dismissed. Either reply on the thread or resolve it. When you think a comment is a false positive, say why on the thread (one or two sentences). Acknowledgement noise is fine and preferred over silence. `resolve_review_thread` works — pass the `PRRT_*` thread node ID from `pull_request_read` / `get_review_comments` (`review_threads[].id`); a comment's `PRRC_*` ID fails. Push the fix first, then reply citing the new sha, then resolve.
- Skip echo events silently. Replies posted via the GitHub MCP come back moments later as webhook events authored by the same identity; if the body matches a comment you just posted, it's your own echo — continue without comment.
- Canceling the watch: see the polling bullet under Autonomy.
