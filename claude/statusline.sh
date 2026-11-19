#!/bin/sh
#
# Claude Code status line: model, working directory and session title.
#
# Claude Code pipes a JSON description of the session to stdin and shows the
# first line printed. The default UI doesn't show the session title anywhere.
#
# Requires jq. Without it, print a short notice instead of failing silently.
#

if ! command -v jq >/dev/null 2>&1; then
    echo "statusline: jq not installed"
    exit 0
fi

jq -r '
    # Abbreviate $HOME to ~ as a literal path prefix, not a regex.
    def tilde:
        (env.HOME // "") as $h
        | if $h == "" then .
          elif . == $h then "~"
          elif startswith($h + "/") then "~" + .[($h | length):]
          else . end;
    [
        (.model.display_name // .model.id // "?"),
        ((.workspace.current_dir // .cwd // "?") | tilde),
        (.session_name // empty)
    ] | join(" · ")
'
