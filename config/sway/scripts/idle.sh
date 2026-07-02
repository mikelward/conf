#!/bin/sh
#
# Start (or restart) swayidle with the session's idle policy. Run via
# exec_always in ~/.config/sway/config so that `swaymsg reload` picks up
# config.local changes to the $idle_* variables -- sway only re-runs
# exec_always lines on reload, and a plain `exec` would leave the old
# swayidle running with the old timeouts/commands (e.g. a desktop that just
# set `set $idle_suspend_cmd true` would still suspend until re-login).
#
# Usage: idle.sh <dim-secs> <lock-secs> <dpms-secs> <suspend-secs> <suspend-cmd>
#
# Mirrors hypridle.conf: dim -> lock -> screen off -> suspend, with the lock
# wired to loginctl's lock signal, and locking before sleep so you always
# wake to a lock screen. On a desktop with no backlight the dim step is a
# harmless no-op. Defaults match config/sway/config's $idle_* defaults.

dim="${1:-150}"
lock_after="${2:-300}"
dpms="${3:-330}"
suspend_after="${4:-1800}"
suspend_cmd="${5:-systemctl suspend}"

# Same lock command as the SUPER+L bind: never stack swaylock instances.
lock_cmd='pidof swaylock || swaylock -f'

# `output * dpms` rather than `output * power`: power only exists on Sway
# >= 1.8, while dpms works everywhere (native on 1.7, a deprecated-but-
# functional alias on newer versions -- expect a deprecation note in the
# log there).

# Replace any previous instance (reload-safe; -x matches the exact name so
# this script's own process is not a candidate).
pkill -x swayidle 2>/dev/null

exec swayidle -w \
    timeout "$dim" 'brightnessctl -s set 10%' resume 'brightnessctl -r' \
    timeout "$lock_after" 'loginctl lock-session' \
    timeout "$dpms" 'swaymsg "output * dpms off"' resume 'swaymsg "output * dpms on"' \
    timeout "$suspend_after" "$suspend_cmd" \
    before-sleep 'loginctl lock-session' \
    after-resume 'swaymsg "output * dpms on"' \
    lock "$lock_cmd"
