#!/bin/sh

set -eu

for instructions in AGENTS.md agents/AGENTS.md; do
	tr '\n' ' ' <"$instructions" | tr -s '[:space:]' ' ' |
		grep -F "sandbox intentionally provides no remote Git support" >/dev/null
	tr '\n' ' ' <"$instructions" | tr -s '[:space:]' ' ' |
		grep -F "continue from the provided checkout on its current branch without fetching, pushing, or opening a PR" >/dev/null
done
