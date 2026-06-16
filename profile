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

# Per-host environment overrides, sourced before .shrc so that anything set
# here (e.g. SHELL) is visible to the shrc re-exec and the rest of startup.
# Covers bash and other login shells; zsh already picked this up via .zshenv.
# The DOTENV_SOURCED sentinel (set there too) keeps a zsh login from applying
# ~/.env a second time via .zlogin, and keeps the zsh-to-bash re-exec from
# re-applying it on top of the inherited values. Keep ~/.env to plain
# variable assignments only; `set -a` auto-exports them so the file can use
# the bare `VAR=val` format that gcloud and other tools expect.
if test -z "${DOTENV_SOURCED:-}" && test -f "$HOME/.env"; then
    set -a
    . "$HOME/.env"
    set +a
    export DOTENV_SOURCED=1
fi

# zsh will have already read .shrc via the .zshrc symlink if it's interactive,
# source .shrc for other shells here
if { ! is_zsh; } || { is_zsh && ! is_interactive; }; then
    test -f "$HOME"/.shrc && . "$HOME"/.shrc
fi

# set a script that will be sourced on exiting the shell
# XXX temporarily disabled due to https://github.com/kovidgoyal/kitty/issues/1867
#test -f "$HOME"/.exitrc && trap '. "$HOME/.exitrc"' EXIT

# Build and install vcs tools from the submodule if present and Go is available.
# make is a no-op (~30ms) when sources haven't changed, so this is safe on every login.
if test -f "$HOME/conf/vcs/Makefile" && command -v go >/dev/null 2>&1; then
    make -C "$HOME/conf/vcs" install PREFIX="$HOME/.local" >/dev/null 2>&1
fi

if test -t 0; then
    # disable flow control so applications can use ^Q and ^S
    type stty >/dev/null 2>/dev/null && stty -ixon
fi

# finish with a zero exit status so the first prompt is '$' rather than '?'
true
