#!/bin/sh

set -eu

for instructions in AGENTS.md agents/AGENTS.md; do
	tr '\n' ' ' <"$instructions" | tr -s '[:space:]' ' ' |
		grep -F "sandbox intentionally provides no remote Git support" >/dev/null
	tr '\n' ' ' <"$instructions" | tr -s '[:space:]' ' ' |
		grep -F "continue from the provided checkout on its current branch without fetching, pushing, or opening a PR" >/dev/null
	remote_exceptions=$(grep -cF "Outside an intentionally remote-free sandbox" "$instructions")
	test "$remote_exceptions" -eq 2
	tr '\n' ' ' <"$instructions" | tr -s '[:space:]' ' ' |
		grep -F "remote-free sandbox, keep using the provided checkout instead" >/dev/null
	tr '\n' ' ' <"$instructions" | tr -s '[:space:]' ' ' |
		grep -F "only when remote Git support is available" >/dev/null
done
