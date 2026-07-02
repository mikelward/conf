#
# zsh-specific commands for all sessions.
#

# Red Hat and Debian's /etc/zshrc and /etc/zprofile break things
unsetopt GLOBAL_RCS

# Shared environment (~/.env, from the conf repo: PATH and other exports)
# and per-host overrides (~/.env.local). Both are sourced for *every* zsh
# (zshenv runs for interactive, non-interactive, scripts, and the outer
# `ssh host cmd` shell), so they must contain only variable assignments --
# no output, no `exec`, no interactive side effects -- or they will corrupt
# scp/rsync/git-over-ssh. This is the earliest hook, so a `SHELL` set here
# is visible before .zshrc runs and can drive the shrc re-exec (letting
# `echo 'export SHELL=/bin/bash' >> ~/.env.local` switch shells without
# chsh).
#
# DOTENV_SOURCED is an exported sentinel so the files are applied exactly
# once per process tree: children (the bash we re-exec into, tmux/shpool
# shells, subshells) inherit the exported values and must not re-source
# them, or self-referential assignments like `PATH=$HOME/bin:$PATH` would
# stack. profile (.zlogin/.bash_profile) and shrc check the same sentinel.
#
# `set -a` makes every assignment automatically exported, so the files can
# use the plain `VAR=val` format that gcloud and other deployment tools
# expect when reading .env for secrets, while still tolerating an explicit
# `export VAR=val`.
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

#  vim: set ts=4 sw=4 tw=0 et:
