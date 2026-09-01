# Coding

- Sync to main HEAD before starting a new change.
- When making any major change, or changing any documented behavior (including
  SPEC.md, TODO.md, IMPLEMENTATION_PLAN.md, README.md, or user-facing help
  pages), update all relevant docs.
- When introducing a new library, API call, service, or infrastructure change,
  advise on the reliability, latency, cost, and any other relevant info. If
  the cost or reliability impact is effectively zero, say so explicitly rather
  than omitting the note.
- Consider portability. Note when something is not portable. Generally, target
  Debian, Ubuntu, Fedora, and macOS; Android and iOS; Chrome, Safari, and
  Firefox; bash and zsh.
- Create tests before implementing.
- Verify tests are passing as you go and when committing.
- Proactively run lint and presubmit tests and proactively fix them.
- Check applicable coding conventions and apply them proactively.
- Do not introduce extra newlines all on their own. Check all added newlines
  and ensure they're in blocks we need to be touching.
- If preexisting tests are already red when you start a task, fix them as the
  *first* commit of the series — don't stack new work on a broken baseline.
  If the failure is genuinely unrelated and out of scope, say so up front and
  confirm before skipping past it.
- Don't paper over flaky/racy tests with `sleep`, retry loops, or bumped
  timeouts. Make the ordering explicit (controlled promises, fake timers,
  `act(...)`, gated fetches) or fix the underlying race.
- Don't disable a failing check (lint, typecheck, test, hook) to make it pass
  — fix the underlying issue.
- To create .Makefile, run "makemakefile".
- When running in a sandbox, make sure to install necessary dependencies locally.
- When iterating on something in a single session or branch, rebase/squash/absorb
  changes if they relate to something else in the same session or branch.
- If you make a mistake, suggest changes to AGENTS.md or skills to improve
  future results. Add a new rule the first time something bites, not the third.
- Let me know if we're getting close to the context window and should compact.

# Talking to me

- One question at a time, in plain chat — not a structured multiple-choice
  picker (broken on some mobile clients). Wait for the answer before
  proceeding on an assumed one, and don't interrupt while I'm still typing.
- Respond to anything I send mid-task in your very next output, before
  continuing other tool calls.
- Keep replies short — lead with the one thing that matters, then ask
  before unloading more.
- Don't narrate routine machinery — a check run flipping, a re-run, a
  scheduled check re-arming, a resolved thread, an echo of your own reply —
  just act on it.
- Don't report your own caught-and-fixed mistakes. Flag it only when it
  cost me something, is still outstanding, or would change a decision I'd
  make knowing about it.
- If you're waiting on an answer — a question, or a guess autopilot
  recorded for review — end the turn by restating it in one sentence.
  Nothing pending, no line.

# Autonomy

- "Drive" = keep looping without stopping to ask each time: implement,
  open the PR, address review, merge once green and reviewed, pick the
  next task, repeat — until the work runs out or I say stop.
- "Autopilot" = drive without blocking on me. Take the reversible,
  cheapest-to-undo guess and keep going; log each one in TODO.md under a
  "Decisions needing review" heading (what, the alternative, why it's
  reversible) so nothing guessed becomes permanent silently. The loop's
  own steps don't count as something to stop for — committing, pushing,
  opening a PR, and merging a green PR are authorized here. What still
  waits for a real answer, even under autopilot: destructive or
  irreversible actions *outside* the normal loop (rewriting shared
  history, deleting work, anything reaching a system beyond this repo)
  and anything privacy-uncertain.
- A red baseline (failing tests/lint) is the next task before picking up
  anything else from TODO.md — fix it first rather than building on top,
  unless it's genuinely unrelated and I confirm skipping it.

# Branching and commits

- **These rules assume an `origin` remote.** Without one you can't fetch,
  branch from `origin/main`, push, or open a PR — say so and stop rather than
  improvising a local substitute.
- Develop on `<agent>/<short-topic>` branches off `origin/main`, where
  `<agent>` is your own short name (`claude/...` for Claude Code, `codex/...`
  for Codex, `cursor/...` for Cursor). Don't hard-code `claude/` unless you
  *are* Claude Code. Never commit directly to `main` / `master`. One topic per
  branch.
- Use standard commit message formatting. Imperative/present mood. "Fix", not
  "Fixed". First line is <66 chars and has no trailing dot. Remainder of the
  commit message should cover both the what and they why.
- One logical surviving change per commit. Rewrite unmerged commits freely
  (squash, amend, reorder, split) so each landing commit is one coherent
  change. Review-fix noise shouldn't survive into `main`.
- `git push --force-with-lease` to your own live feature branch after a
  rebase is routine hygiene — don't ask. Confirm before any destructive
  action on shared/merged branches: force-pushing `main`, dropping commits
  already on `main`, rewriting another author's branch.
- Merge cue (`merged` / `I merged` / `landed` / merge webhook) runs hygiene
  *before* engaging with the rest of the message: `git fetch origin`, cut a
  fresh `<agent>/<short-topic>` branch off `origin/main`, announce the switch.
- After a merge, take a fresh `<agent>/<short-topic>` — don't reset the merged
  name onto the new base. Its remote ref still points at the pre-merge tip, so
  `origin/<branch>..HEAD` keeps spanning the merged commits and unpushed-work
  checks report my own merged history back at me. When a sandbox pins the branch
  name, reset it and `--force-with-lease` in the same turn — that's routine on
  merged history, not something to ask about.
- The agent authors and I merge, so a squash or rebase merge rewrites the
  committer to me. That's expected — never re-author or amend already-merged
  commits to "fix" authorship or signing.
- Unshallow before answering anything that depends on git history depth. The
  sandbox clones shallow, so `git rev-list --count`, `git log` past the
  shallow boundary, and blame return wrong answers without warning. If
  `git rev-parse --is-shallow-repository` says `true`, run
  `git fetch --unshallow` first, then re-check — it exits 0 even when
  it deepened nothing, so if `--is-shallow-repository` is still `true`, say the
  history is truncated instead of quoting a count.

# Language and spelling

- Use US English everywhere people read English: user-facing strings, commit
  subjects and bodies, PR titles and descriptions, comments, and identifiers
  — `color` not `colour`, `behavior` not `behaviour`, `canceled` not
  `cancelled`, `gray` not `grey`. Platform and third-party API spellings stay
  as those APIs spell them.

# Pull requests and reviews

- Open PRs ready for review (not draft), without being asked, as soon as
  a branch is ready — don't park a finished branch waiting to be told,
  unless I've said otherwise ("just commit", "no PR yet"), which holds
  until I lift it.
- On every push, update the PR title and body so they describe the full,
  latest state of the branch — not the scope it had when it was opened.
  Re-read the diff against `origin/main` and patch whatever drifted, then
  post the PR link in the chat reply for that push, not only at the end of
  the conversation.
- End every reply with the open-PR link (or `.../compare/main...<branch>`
  until a PR exists). Never link to a closed or merged PR — except when the
  reply *is* post-merge follow-up on that PR, where linking it is correct.
- When a feature has multiple open PRs in a stack, list **every** open PR
  on the feature by URL, one per line — the "View PR" chip sticks to the
  first link and hides the rest
  (anthropics/claude-code#46625).
- **Judge every review comment on merit, whoever wrote it.** Verify the claim
  before acting; if it doesn't hold up, reply saying why and decline.
- Never leave a review comment thread silently dismissed. Reply on the
  thread — a disagreement is an answer, so say why — then resolve it once
  the fix is on the head or the point is rebutted. Acknowledgement noise
  ("good catch, will do") is fine and preferred over silence.
- Where an automated reviewer (Codex or similar) is configured, it runs on
  its own — don't request it manually unless nothing's come back after a
  few minutes. Read its actual verdict for the *current* head (a reaction
  or status tied to that commit — most such tools revoke it on every
  push), not a stale one from before your last push and not a guess; a
  finding blocks merge until fixed or rebutted with reasoning on the
  thread. Findings can land as a top-level PR comment instead of an
  inline thread — check both before merging, not just review threads.
- Skip echoes of your own replies silently — a reply you just posted
  coming back as a new "comment" a moment later isn't new feedback.

# Privacy

- Never put my personal data — a real path with my name in it, a
  hostname, a token, a private remote URL — into anything that leaves
  this machine: commits, PR text, branch names, fixtures, issues. Use
  placeholders, and ask if you're not sure something is safe to include.
- Output on my own terminal is fine to show in full; redact only secrets
  (tokens, keys, passwords) there. Quoting that output into a commit, PR,
  fixture, or reply republishes it — the bullet above governs again, so
  paraphrase or use a placeholder rather than pasting it verbatim.

# Error handling

- Don't silently swallow errors. Report what failed with enough context
  to identify it, clean up whatever the failed step acquired, and decide
  explicitly what I see next (a re-raise, a default, a nonzero exit) —
  don't let it fall through quietly. If you're deliberately ignoring one,
  say why in a one-line comment.

# CI

- After pushing, **wait for CI** before claiming a change works in any
  environment you can't test locally (Android, iOS, Vercel deploy-only
  failures, etc.). Webhooks deliver — don't poll.
- Report significant CI timing regressions after a push (rule of thumb:
  >25% or >30s on a job under ~5min). Don't narrate routine wobble. When
  you do flag one, name the likely cause: heavy new dependency, slow new
  test, cache invalidation.
