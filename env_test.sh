#!/bin/sh
#
# Tests for the shared environment file `env` (installed as ~/.env).
#
# The file is dual-dialect -- sourced by POSIX shells (zshenv, profile,
# shrc, the scripts repo's runenv) AND read by systemd's environment.d via
# the config/environment.d/50-env.conf symlink -- so beyond checking the
# values, these tests enforce the intersection of the two syntaxes: plain
# KEY=VALUE lines with only $VAR/${VAR} expansion.

. "$(dirname "$0")/shrc_test_lib.sh"

_env="$_srcdir/env"
_envd_link="$_srcdir/config/environment.d/50-env.conf"

start_test "env exists"
assert_true test -f "$_env"

start_test "environment.d 50-env.conf is a symlink to env"
assert_true test -L "$_envd_link"
assert_true test "$(readlink -f "$_envd_link")" = "$(readlink -f "$_env")"

start_test "env parses as shell"
assert_true sh -n "$_env"

################################################################################
# Dual-dialect lint: every non-comment line must be KEY=VALUE with no
# quotes, spaces, globs, or command substitution -- the environment.d
# parser treats quotes literally and runs no commands, and sourcing under
# `set -a` must not execute anything.
################################################################################
_lines=$(grep -vE '^(#|$)' "$_env")

start_test "env lines are all KEY=VALUE assignments"
_bad=$(printf '%s\n' "$_lines" | grep -cvE '^[A-Za-z_][A-Za-z0-9_]*=' || true)
assert_true test "$_bad" -eq 0

start_test "env values contain no quotes, spaces, globs, or substitution"
_bad=$(printf '%s\n' "$_lines" | grep -cE "[[:space:]\"'\`*?]|\\\$\(" || true)
assert_true test "$_bad" -eq 0

################################################################################
# Behaviour: sourcing with `set -a` (as zshenv/profile/shrc/runenv do) must
# put the dirs on PATH in login-shell order -- scripts and bin prepended,
# everything else appended (unconditionally: entries for dirs a machine
# lacks are skipped by lookup) -- and export GOPATH=$HOME.
################################################################################
_fakehome="/nonexistent-home-for-env-test"
_before="/usr/bin:/bin"

start_test "sourcing env builds the canonical PATH"
_path=$(HOME="$_fakehome" PATH="$_before" sh -c 'set -a; . "$0"; printf %s "$PATH"' "$_env")
assert_equal "$_fakehome/scripts.local:$_fakehome/scripts:$_fakehome/bin:$_before:/usr/local/bin:$_fakehome/android-sdk-linux/platform-tools:$_fakehome/android-studio/bin:$_fakehome/Android/Sdk/platform-tools:$_fakehome/depot_tools:$_fakehome/google-cloud-sdk/bin:$_fakehome/.cargo/bin:$_fakehome/.local/bin:/sbin:/usr/sbin" "$_path"

start_test "sourcing env exports GOPATH=\$HOME"
_gopath=$(HOME="$_fakehome" PATH="$_before" sh -c 'set -a; . "$0"; env' "$_env" | grep '^GOPATH=')
assert_equal "GOPATH=$_fakehome" "$_gopath"

test_summary "env_test"
