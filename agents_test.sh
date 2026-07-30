#!/bin/sh

set -eu

for instructions in AGENTS.md agents/AGENTS.md; do
	tr '\n' ' ' <"$instructions" | tr -s '[:space:]' ' ' |
		grep -F "Choose the Git workflow based on remote support" >/dev/null
	tr '\n' ' ' <"$instructions" | tr -s '[:space:]' ' ' |
		grep -F "If the sandbox intentionally has no remote Git support" >/dev/null
	tr '\n' ' ' <"$instructions" | tr -s '[:space:]' ' ' |
		grep -F "continue on the provided checkout and current branch without fetching, pushing, or opening a PR" >/dev/null
	tr '\n' ' ' <"$instructions" | tr -s '[:space:]' ' ' |
		grep -F 'Otherwise: - Require an `origin` remote' >/dev/null
	grep -F "    - On a merge cue" "$instructions" >/dev/null
	grep -F "    - Before relying on Git history" "$instructions" >/dev/null
done
