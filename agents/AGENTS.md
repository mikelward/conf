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

# Branching and commits

- Develop on `claude/<short-topic>` branches off `origin/main`. Never commit
  directly to `main` / `master`. One topic per branch.
- One logical surviving change per commit. Rewrite unmerged commits freely
  (squash, amend, reorder, split) so each landing commit is one coherent
  change. Review-fix noise shouldn't survive into `main`.
- `git push --force-with-lease` to your own live feature branch after a
  rebase is routine hygiene — don't ask. Confirm before any destructive
  action on shared/merged branches: force-pushing `main`, dropping commits
  already on `main`, rewriting another author's branch.
- Stacked PRs: the lower PR (infra) targets `main`; the upper PR (feature)
  targets the lower PR's branch. When the lower PR merges, rebase the upper
  one onto `main`.
- Merge cue (`merged` / `I merged` / `landed` / merge webhook) runs hygiene
  *before* engaging with the rest of the message: `git fetch origin`, cut a
  fresh `claude/<short-topic>` branch off `origin/main`, announce the switch.

# Pull requests

- Open PRs ready for review (not draft) unless I say otherwise.
- End every reply with the open-PR link (or `.../compare/main...<branch>`
  until a PR exists). Never link to a closed or merged PR.
- When a feature has multiple open PRs in a stack, list **every** open PR
  on the feature by URL, one per line — the "View PR" chip sticks to the
  first link and hides the rest
  (anthropics/claude-code#46625).
- Never leave a review comment thread silently dismissed. Either reply on
  the thread *or* resolve it. When you think a comment is a false positive,
  say *why* on the thread (one or two sentences). Acknowledgement noise
  ("good catch, will do") is fine and preferred over silence.

# CI

- After pushing, **wait for CI** before claiming a change works in any
  environment you can't test locally (Android, iOS, Vercel deploy-only
  failures, etc.). Webhooks deliver — don't poll.
- Report significant CI timing regressions after a push (rule of thumb:
  >25% or >30s on a job under ~5min). Don't narrate routine wobble. When
  you do flag one, name the likely cause: heavy new dependency, slow new
  test, cache invalidation.
