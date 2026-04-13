#!/bin/sh
#
# Tests for gitconfig.
#

. "$(dirname "$0")/shrc_test_lib.sh"

_gitconfig="$_srcdir/gitconfig"

if ! command -v git >/dev/null 2>&1; then
    skip_all "git not installed"
    test_summary "gitconfig"
    exit 0
fi

# submodule.recurse is enabled so that git clone automatically
# initializes submodules (e.g. the vcs submodule).
_recurse=$(git config --file "$_gitconfig" submodule.recurse)
assert_equal "submodule.recurse is true" "true" "$_recurse"

# Core directives we rely on across scripts.
assert_equal "core.excludesfile points at gitexclude" \
    "~/.gitexclude" "$(git config --file "$_gitconfig" core.excludesfile)"
assert_equal "init.defaultBranch is main" \
    "main" "$(git config --file "$_gitconfig" init.defaultBranch)"
assert_equal "pull.rebase is true" \
    "true" "$(git config --file "$_gitconfig" pull.rebase)"
assert_equal "push.default is current" \
    "current" "$(git config --file "$_gitconfig" push.default)"
assert_equal "status.showUntrackedFiles is all" \
    "all" "$(git config --file "$_gitconfig" status.showUntrackedFiles)"
assert_equal "rerere.enabled is true" \
    "true" "$(git config --file "$_gitconfig" rerere.enabled)"
assert_equal "diff.algorithm is patience" \
    "patience" "$(git config --file "$_gitconfig" diff.algorithm)"
assert_equal "merge.conflictstyle is zdiff3" \
    "zdiff3" "$(git config --file "$_gitconfig" merge.conflictstyle)"
assert_equal "diff.renames is true" \
    "true" "$(git config --file "$_gitconfig" diff.renames)"
# init.templatedir wires our commit-msg / pre-commit hook scaffolding
# into every newly created repo. Losing this silently drops hooks.
assert_equal "init.templatedir points at gittemplates" \
    "~/.gittemplates" "$(git config --file "$_gitconfig" init.templatedir)"
# branch.autoSetupMerge/Rebase make newly created branches track upstream
# and rebase-pull by default; regressions here silently change pull/push
# semantics across every repo.
assert_equal "branch.autoSetupMerge is always" \
    "always" "$(git config --file "$_gitconfig" branch.autoSetupMerge)"
assert_equal "branch.autoSetupRebase is always" \
    "always" "$(git config --file "$_gitconfig" branch.autoSetupRebase)"
# color.ui=auto is what makes git commands colorize stdout in terminals;
# "false"/"never" would silently strip colors from the entire workflow.
assert_equal "color.ui is auto" \
    "auto" "$(git config --file "$_gitconfig" color.ui)"
# log.date sets the format used by history aliases. A regression would
# silently reformat the `history` alias output.
assert_contains "log.date is format-local with YYYY-MM-DD HH:MM:SS" \
    "format-local:%Y-%m-%d %H:%M:%S" \
    "$(git config --file "$_gitconfig" log.date)"
# difftool.prompt=no keeps `git difftool` from asking before every file.
assert_equal "difftool.prompt is no" \
    "no" "$(git config --file "$_gitconfig" difftool.prompt)"
# user.name/email must be non-empty -- otherwise every first commit on a
# new machine would either prompt or (worse) be attributed to the shell
# user's default identity.
_user_name=$(git config --file "$_gitconfig" user.name)
_user_email=$(git config --file "$_gitconfig" user.email)
assert_true "user.name is set" test -n "$_user_name"
assert_true "user.email is set" test -n "$_user_email"
# The local-override include is what lets per-host tweaks live outside
# the checked-in config. Without it, corporate overrides silently fall
# back to the upstream defaults.
assert_equal "include.path points at local overrides" \
    "~/.gitconfig.local" "$(git config --file "$_gitconfig" include.path)"

# A sampling of aliases used by the shrc wrappers and muscle memory.
# These are the ones whose absence would quietly break daily workflow.
for _alias_pair in \
    "st=status --short" \
    "co=checkout" \
    "ci=commit" \
    "br=branch" \
    "amend=commit --amend" \
    "graph=log --graph --pretty=format:'%C(auto)%h%C(auto)%d %s'" \
    "rootdir=rev-parse --show-toplevel"
do
    _alias_name="${_alias_pair%%=*}"
    _alias_value="${_alias_pair#*=}"
    _got=$(git config --file "$_gitconfig" "alias.$_alias_name")
    assert_equal "alias.$_alias_name" "$_alias_value" "$_got"
done

# The config should parse cleanly as a whole under `git config --list`.
git config --file "$_gitconfig" --list >/dev/null 2>&1
assert_equal "gitconfig parses cleanly" "0" "$?"

test_summary "gitconfig"
