#!/bin/bash
#
# Run a command with the login-shell PATH. Hyprland's exec binds inherit the
# compositor's environment, and a session started from a display manager or
# uwsm never ran .profile/.shrc -- so bare helper-script names (browser1,
# home, irc, ...) wouldn't resolve. Sourcing .shrc rebuilds PATH via its
# add_path calls -- the single source of truth, including the per-machine
# ~/scripts.* override globs -- rather than duplicating a directory list
# here. Same pattern as the scripts repo's browser1.
. "$HOME/.shrc"
exec "$@"
