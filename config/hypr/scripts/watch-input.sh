#!/bin/sh
#
# Runs apply-input.sh again whenever an input device is plugged in, such as
# the mouse a KVM switch hands back, so it gets its handedness and wheel
# speed too. apply-input.sh runs at login and after each reload, but
# Hyprland (0.56) has no event for a new device, so this listens to udev.
#
# hyprland.lua starts it at login outside the tide session; tide's shell
# starts it in the tide session. It ends once Hyprland has gone.
#
# A plugged-in device brings a burst of udev events. Only its event node's
# add counts, and the adds within WATCH_INPUT_DELAY seconds (default 1) of
# the first make one run, which also gives Hyprland time to open the device.
# Every WATCH_INPUT_POLL seconds (default 30) it checks Hyprland is still
# there, so it ends after a logout with nothing plugged in.
# WATCH_INPUT_APPLY replaces apply-input.sh, for tests.

delay="${WATCH_INPUT_DELAY:-1}"
poll="${WATCH_INPUT_POLL:-30}"
apply="${WATCH_INPUT_APPLY:-$(dirname "$0")/apply-input.sh}"

for setting in "WATCH_INPUT_DELAY=$delay" "WATCH_INPUT_POLL=$poll"; do
    case "${setting#*=}" in
        ''|*[!0-9.]*|*.*.*|.)
            echo "watch-input.sh: ${setting%%=*} must be a number of seconds, not '${setting#*=}'" >&2
            exit 1
            ;;
    esac
done
if ! command -v udevadm >/dev/null 2>&1; then
    echo "watch-input.sh: no udevadm, so a device plugged in after login keeps Hyprland's defaults until a reload" >&2
    exit 1
fi

# The state directory holds the events' pipe, and the mark set while a run
# is waiting, so a burst makes one. A run takes the mark away before it
# starts, so a device that comes during it gets a run of its own.
if ! state=$(mktemp -d "${TMPDIR:-/tmp}/watch-input.XXXXXX"); then
    echo "watch-input.sh: couldn't make a directory for its state" >&2
    exit 1
fi
monitor=
guard=
# The guard below is stopped with USR1, which this doesn't trap. A subshell
# starts with this shell's handler for a trapped signal, and loses one that
# comes before it sets its own: a TERM sent as the guard starts would leave
# it running, and the wait at the end waiting on it.
stop() {
    test -z "$guard" || kill -s USR1 "$guard" 2>/dev/null
    test -z "$monitor" || kill "$monitor" 2>/dev/null
    rm -rf "$state"
}
trap stop EXIT
trap 'exit 0' INT TERM HUP
if ! mkfifo "$state/events"; then
    echo "watch-input.sh: couldn't make a pipe for udev's events" >&2
    exit 1
fi

udevadm monitor --udev --subsystem-match=input > "$state/events" &
monitor=$!
# Opening the pipe waits for the monitor to open its end, so the guard below
# can't kill it before the two are joined, which would leave this waiting
# on a pipe nothing will ever open.
exec 3< "$state/events"
# Ends the monitor, and so the loop below, once Hyprland has gone.
(
    while hyprctl version >/dev/null 2>&1; do
        sleep "$poll"
    done
    echo "watch-input.sh: Hyprland has gone; stopping" >&2
    kill "$monitor" 2>/dev/null
) &
guard=$!

while IFS= read -r line; do
    case "$line" in
        *" add "*/event[0-9]*) ;;
        *) continue ;;
    esac
    test -e "$state/pending" && continue
    : > "$state/pending"
    (
        sleep "$delay"
        rm -f "$state/pending"
        "$apply" || echo "watch-input.sh: $apply failed ($?) for a new device" >&2
    ) &
done <&3
exec 3<&-
# The guard is done with; a run still waiting finishes first.
kill -s USR1 "$guard" 2>/dev/null
guard=
wait
if hyprctl version >/dev/null 2>&1; then
    echo "watch-input.sh: udevadm monitor ended, so new devices keep Hyprland's defaults until a reload" >&2
fi
