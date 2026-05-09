# TODO

## vcs submodule auto-update on pull

`post-merge` hook runs `git submodule update --remote vcs` but only fires when
conf itself has new commits. When vcs advances independently (no conf pin bump),
`git pull` in conf leaves vcs at the stale pin.

Fix: run the `--remote` update outside of `post-merge` — either via a
`post-fetch` hook (fires after every fetch, even "already up to date") or by
wrapping the shell `pull` function to run `git submodule update --remote vcs`
when in the conf repo.
