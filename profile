#!/bin/sh
#
# Commands to run for any POSIX shell when the user logs in.
#
# zlogin and bash_profile should be symlinks to this file.
# (zprofile should not exist, or should be empty.)
#
is_interactive() {
    case "$-" in *i*)
        true;;
    *)
        false;;
    esac
}

is_zsh() {
    test -n "${ZSH_VERSION:-}"
}

# A login with no terminal is a display manager's (GDM, SDDM) starting a
# session, and a hang here stops that session with nothing on screen and
# nothing in the log. So such a login says in the journal which session it
# starts and how far it got: `journalctl -t profile`. One `logger` per step,
# a few milliseconds each, and none for a login on a terminal.
_profile_start=$(date +%s 2>/dev/null)
if ! test -t 0 && command -v logger >/dev/null 2>&1; then
    profile_log() {
        # Nothing to report a failed logger to: this is the log.
        logger -t profile -- "$*" 2>/dev/null || true
    }
else
    profile_log() { :; }
fi
profile_log "starting ${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-unnamed}} session as $(basename "${SHELL:-sh}") login"

# Shared environment (~/.env, from the conf repo: PATH and other exports)
# and per-host overrides (~/.env.local, e.g. SHELL or extra PATH dirs),
# sourced before .shrc so that anything set here is visible to the shrc
# re-exec and the rest of startup. Covers bash and other login shells; zsh
# already picked these up via .zshenv. The DOTENV_SOURCED sentinel (set
# there too) keeps a zsh login from applying them a second time via
# .zlogin, and keeps the zsh-to-bash re-exec from re-applying them on top
# of the inherited values (PATH prepends would stack). Keep both files to
# plain variable assignments only; `set -a` auto-exports them so they can
# use the bare `VAR=val` format that gcloud and other tools expect.
if test -z "${DOTENV_SOURCED:-}"; then
    case $- in *a*) _dotenv_had_a=1;; *) _dotenv_had_a=0;; esac
    set -a
    for _dotenv in "$HOME/.env" "$HOME/.env.local"; do
        test -f "$_dotenv" && . "$_dotenv"
    done
    unset _dotenv
    test "$_dotenv_had_a" = 1 || set +a
    unset _dotenv_had_a
    export DOTENV_SOURCED=1
fi

# zsh will have already read .shrc via the .zshrc symlink if it's interactive,
# source .shrc for other shells here
if { ! is_zsh; } || { is_zsh && ! is_interactive; }; then
    if test -f "$HOME"/.shrc; then
        profile_log "reading .shrc"
        . "$HOME"/.shrc
        profile_log "read .shrc"
    fi
fi

# set a script that will be sourced on exiting the shell
# XXX temporarily disabled due to https://github.com/kovidgoyal/kitty/issues/1867
#test -f "$HOME"/.exitrc && trap '. "$HOME/.exitrc"' EXIT

# Build and install vcs tools from the submodule if present and Go is available.
# make is a no-op (~30ms) when sources haven't changed, so this is safe on every login.
if test -f "$HOME/conf/vcs/Makefile" && command -v go >/dev/null 2>&1; then
    profile_log "building vcs"
    make -C "$HOME/conf/vcs" install PREFIX="$HOME/.local" >/dev/null 2>&1 \
        || profile_log "building vcs failed"
fi

if test -t 0; then
    # disable flow control so applications can use ^Q and ^S
    type stty >/dev/null 2>/dev/null && stty -ixon
fi

if test -n "$_profile_start" && _profile_end=$(date +%s 2>/dev/null); then
    profile_log "starting the session after $((_profile_end - _profile_start))s"
else
    profile_log "starting the session"
fi
unset _profile_start _profile_end
unset -f profile_log

# finish with a zero exit status so the first prompt is '$' rather than '?'
true
