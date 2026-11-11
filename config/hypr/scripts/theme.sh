#!/bin/sh
#
# Time-based light/dark theming, SHARED by the Hyprland and Sway desktops
# (it lives under config/hypr/scripts for historical reasons).
# Light from 07:00 to 18:59, dark otherwise. Drives:
#   - the freedesktop colour-scheme preference (kitty and GTK apps follow it)
#   - waybar   (relaunched with -s style.css / style-light.css), unless
#              tide's own bar is the bar (TIDE_BAR=quickshell,
#              set by tide-shell), which themes itself; run by hand
#              in tide, only a waybar that's already up
#   - swaync   (relaunched with --style style.css / style-light.css),
#              unless tide's shell is the notification server
#              (TIDE_NOTIFICATIONS=1 with TIDE_BAR=quickshell)
#   - window border colors under Sway (Hyprland draws none)
#   - the wallpaper, when per-mode images exist (swww / swaybg)
#   - a mode marker read by launch-fuzzel.sh
#
# In tide with its Quickshell shell (TIDE_BAR=quickshell), the shell owns the
# light/dark schedule and sets the color scheme itself (tide SPEC.md §15).
# There the rest follows it instead of the clock (`follow`, run by the daemon
# at startup and by config/tide/appearance-hook at each change), leaving the
# color scheme alone.
#
# Usage:
#   theme.sh mode                print "light" or "dark" for the current time
#   theme.sh sleep               print seconds until the next 07:00/19:00 edge
#   theme.sh scheme              print "light" or "dark" for the color scheme
#                                set now, or nothing when it can't be read
#   theme.sh follow              apply the color scheme's mode to the rest,
#                                without setting the color scheme
#   theme.sh [auto|light|dark]   apply a theme (auto = by time; the default)

LIGHT_START=7     # first hour of light mode
DARK_START=19     # first hour of dark mode

cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
marker="${XDG_RUNTIME_DIR:-/tmp}/theme-mode"

current_mode() {
    # %H is zero-padded (00-23); strip the leading zero so "08"/"09" aren't
    # treated as octal in the arithmetic comparison below (POSIX-safe).
    h=$(date +%H)
    h=${h#0}
    h=${h:-0}
    if test "$h" -ge "$LIGHT_START" && test "$h" -lt "$DARK_START"; then
        echo light
    else
        echo dark
    fi
}

seconds_until_boundary() {
    now=$(date +%s)
    today=$(date +%Y-%m-%d)
    tomorrow=$(date -d 'tomorrow' +%Y-%m-%d 2>/dev/null)
    # First upcoming boundary among today's two edges and tomorrow's light edge.
    for t in "$today ${LIGHT_START}:00:00" \
             "$today ${DARK_START}:00:00" \
             "$tomorrow ${LIGHT_START}:00:00"; do
        ts=$(date -d "$t" +%s 2>/dev/null) || continue
        if test "$ts" -gt "$now"; then
            echo $((ts - now))
            return
        fi
    done
    echo 3600   # fallback: re-check in an hour
}

# scheme_mode: "dark" or "light" for the color scheme set now; GNOME's
# 'default' (no preference) is light, as apps show it. Nothing when it
# can't be read.
scheme_mode() {
    case "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)" in
        *"'prefer-dark'"*) echo dark ;;
        *"'prefer-light'"* | *"'default'"*) echo light ;;
    esac
}

apply() {
    mode="$1"
    # Only this user's programs are stopped and waited for: another user's
    # swaync isn't this one's to signal, and would be waited on for 5 s.
    uid=$(id -u)
    # "no" when following tide's shell, which sets the color scheme itself.
    set_scheme="${2:-yes}"

    # 1) System colour-scheme preference. kitty (via its *.auto.conf themes)
    #    and GTK apps follow this through xdg-desktop-portal.
    if test "$set_scheme" = yes && command -v gsettings >/dev/null 2>&1; then
        if test "$mode" = light; then
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
            gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
        else
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
            gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
        fi
    fi

    # 2) waybar: relaunch with the matching style.
    if test "$mode" = light; then
        wstyle="$cfg/waybar/style-light.css"
    else
        wstyle="$cfg/waybar/style.css"
    fi
    # In tide, tide-shell says which bar it runs; its theme
    # daemon gets TIDE_BAR. Run by hand there (no TIDE_BAR), only
    # a waybar that's already up is restarted, so none starts beside the
    # Quickshell bar.
    want_waybar=yes
    if test "${TIDE_BAR:-}" = quickshell; then
        want_waybar=no
    elif test -z "${TIDE_BAR:-}"; then
        case ":${XDG_CURRENT_DESKTOP:-}:" in
            *:tide:*) want_waybar=running ;;
        esac
    fi
    if test "$want_waybar" != no && command -v waybar >/dev/null 2>&1; then
        if pkill -u "$uid" -x waybar 2>/dev/null || test "$want_waybar" = yes; then
            waybar -s "$wstyle" >/dev/null 2>&1 8>&- &
        fi
    fi

    # 3) swaync: relaunch with the matching style.
    if test "$mode" = light; then
        sstyle="$cfg/swaync/style-light.css"
    else
        sstyle="$cfg/swaync/style.css"
    fi
    # Following tide's shell, a swaync that's already up in this mode is left
    # alone: the daemon's first run and the shell's hook both style the same
    # scheme at login, and restarting it leaves a gap with no notifications.
    # The marker alone can't say so: one left by an earlier session names a
    # mode with no swaync running.
    if test "${TIDE_NOTIFICATIONS:-}" = 1 && test "${TIDE_BAR:-}" = quickshell; then
        # tide's Quickshell shell serves notifications itself (tide-shell
        # says so with TIDE_NOTIFICATIONS=1), and a swaync started here
        # would take org.freedesktop.Notifications from it.
        :
    elif test "$set_scheme" = no && test "$(cat "$marker" 2>/dev/null)" = "$mode" &&
        pgrep -u "$uid" -x swaync >/dev/null 2>&1; then
        :
    elif command -v swaync >/dev/null 2>&1; then
        # pkill doesn't wait. A swaync started while the old one still holds
        # org.freedesktop.Notifications can't take it, and once the old one
        # exits there's none, so the old one is waited for, 5 s at most.
        if pkill -u "$uid" -x swaync 2>/dev/null; then
            _waited=0
            while pgrep -u "$uid" -x swaync >/dev/null 2>&1 && test "$_waited" -lt 50; do
                sleep 0.1
                _waited=$((_waited + 1))
            done
            if test "$_waited" -ge 50; then
                echo "$0: the old swaync was still running 5 s after it was told to stop; starting the new one anyway" >&2
            fi
        fi
        # Its chatter on stdout is dropped; its warnings and errors go to
        # the journal (`journalctl --user -t swaync`), so one that fails to
        # start says why. Not to this script's stderr: run by tide's shell
        # that's a pipe, closed once the hook exits, and swaync runs on, to
        # lose what it writes there or die of SIGPIPE. systemd-cat execs sh,
        # which execs swaync, so no process is left between, and none holds
        # fd 8. It's tried with `true` first: with no journal it fails
        # without running its command, and an old one lacks the option.
        if systemd-cat -t swaync --stderr-priority=warning true >/dev/null 2>&1 8>&-; then
            # shellcheck disable=SC2016  # $1 is for the inner sh.
            systemd-cat -t swaync --stderr-priority=warning \
                sh -c 'exec swaync --style "$1" >/dev/null' sh "$sstyle" 8>&- &
        else
            # No systemd-cat, or no journal: where this script's errors go.
            swaync --style "$sstyle" >/dev/null 8>&- &
        fi
    else
        echo "$0: swaync isn't installed, so there are no notifications" >&2
    fi

    # 4) Window border colors under Sway. Hyprland draws no borders (the
    #    focus cue is the dim), so there is nothing to recolor there.
    if test -n "$SWAYSOCK" && command -v swaymsg >/dev/null 2>&1; then
        if test "$mode" = light; then
            active=5e81ac; active_text=eceff4
            inactive=d8dee9; inactive_text=4c566a
        else
            active=88c0d0; active_text=2e3440
            inactive=3b4252; inactive_text=d8dee9
        fi
        # client.<class> <border> <background> <text> <indicator> <child_border>
        swaymsg "client.focused #$active #$active #$active_text #$active #$active" >/dev/null 2>&1
        swaymsg "client.focused_inactive #$inactive #$inactive #$inactive_text #$inactive #$inactive" >/dev/null 2>&1
        swaymsg "client.unfocused #$inactive #$inactive #$inactive_text #$inactive #$inactive" >/dev/null 2>&1
    fi

    # 5) Optional wallpaper swap if you keep per-mode wallpapers (shared by
    #    both desktops): swww under Hyprland, swaybg under Sway.
    #    >>> PLACEHOLDER: drop wallpaper-light.jpg / wallpaper-dark.jpg in
    #    ~/.config/hypr, or delete this block. <<<
    wall="$HOME/.config/hypr/wallpaper-$mode.jpg"
    if test -f "$wall"; then
        if test -n "$SWAYSOCK" && command -v swaybg >/dev/null 2>&1; then
            pkill -u "$uid" -x swaybg 2>/dev/null
            swaybg -i "$wall" -m fill >/dev/null 2>&1 8>&- &
        elif command -v swww >/dev/null 2>&1; then
            swww img "$wall" >/dev/null 2>&1
        fi
    fi

    # Record the active mode for launch-fuzzel.sh.
    printf '%s\n' "$mode" > "$marker"
}

case "${1:-auto}" in
    mode)  current_mode ;;
    sleep) seconds_until_boundary ;;
    scheme) scheme_mode ;;
    follow)
        # The scheme is read under a lock, held until it's applied, so when
        # the daemon's first run and the shell's hook overlap at login, the
        # one that runs last applies the scheme as it is by then. What apply
        # starts in the background closes fd 8, so it doesn't hold the lock.
        # A run that never lets go of it (stuck, or stopped) mustn't hold
        # up every later one, and tide's unit with them: 5 s, then unlocked.
        _lock="${XDG_RUNTIME_DIR:-/tmp}/theme.lock"
        if command -v flock >/dev/null 2>&1; then
            # `command` so a lock file that can't be opened is an error
            # here, not the end of the script (exec is a special builtin).
            if command exec 8>"$_lock"; then
                flock -w 5 8 ||
                    echo "$0: $_lock was still locked by another run after 5 s; styling unlocked" >&2
            else
                echo "$0: couldn't open $_lock; styling unlocked" >&2
            fi
        fi
        _mode=$(scheme_mode)
        if test -z "$_mode"; then
            # swaync still has to start, so the clock stands in.
            _mode=$(current_mode)
            echo "$0: couldn't read the color scheme; styling for $_mode by the clock" >&2
        fi
        apply "$_mode" no
        ;;
    light) apply light ;;
    dark)  apply dark ;;
    auto)  apply "$(current_mode)" ;;
    *)     echo "usage: $0 [mode|sleep|scheme|follow|auto|light|dark]" >&2; exit 1 ;;
esac
