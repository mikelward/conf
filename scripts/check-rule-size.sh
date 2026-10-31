#!/bin/sh
# Fail when an agent rule file reaches Antigravity's per-file cap.
#
# Antigravity silently truncates a rule file's tail at 24,000 bytes, so a
# rule added at the bottom would vanish without an error anywhere. CI runs
# this on every pull request, docs-only ones included, since those are the
# ones that grow AGENTS.md.
#
# Usage: check-rule-size.sh [file...]   (default: AGENTS.md agents/AGENTS.md)
set -eu

limit=24000

if test $# -eq 0; then
  set -- AGENTS.md agents/AGENTS.md
fi

status=0
for file in "$@"; do
  if ! test -f "$file"; then
    echo "check-rule-size: $file: not a file" >&2
    status=1
    continue
  fi
  if ! size=$(wc -c < "$file"); then
    echo "check-rule-size: $file: cannot read it" >&2
    status=1
    continue
  fi
  # BSD wc pads the count with spaces.
  size=$(echo "$size" | tr -d ' ')
  if test "$size" -ge "$limit"; then
    echo "check-rule-size: $file is $size bytes; keep it under $limit (Antigravity truncates the rest)" >&2
    status=1
  fi
done
exit "$status"
