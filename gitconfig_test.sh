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
start_test "submodule.recurse is true"
_recurse=$(git config --file "$_gitconfig" submodule.recurse)
assert_equal "true" "$_recurse"

# Core directives we rely on across scripts.
start_test "core.excludesfile points at gitexclude"
assert_equal \
    "~/.gitexclude" "$(git config --file "$_gitconfig" core.excludesfile)"
start_test "init.defaultBranch is main"
assert_equal \
    "main" "$(git config --file "$_gitconfig" init.defaultBranch)"
start_test "pull.rebase is true"
assert_equal \
    "true" "$(git config --file "$_gitconfig" pull.rebase)"
start_test "push.default is current"
assert_equal \
    "current" "$(git config --file "$_gitconfig" push.default)"
start_test "status.showUntrackedFiles is all"
assert_equal \
    "all" "$(git config --file "$_gitconfig" status.showUntrackedFiles)"
start_test "rerere.enabled is true"
assert_equal \
    "true" "$(git config --file "$_gitconfig" rerere.enabled)"
start_test "diff.algorithm is patience"
assert_equal \
    "patience" "$(git config --file "$_gitconfig" diff.algorithm)"
start_test "merge.conflictstyle is zdiff3"
assert_equal \
    "zdiff3" "$(git config --file "$_gitconfig" merge.conflictstyle)"
start_test "diff.renames is true"
assert_equal \
    "true" "$(git config --file "$_gitconfig" diff.renames)"
# init.templatedir wires our commit-msg / pre-commit hook scaffolding
# into every newly created repo. Losing this silently drops hooks.
start_test "init.templatedir points at gittemplates"
assert_equal \
    "~/.gittemplates" "$(git config --file "$_gitconfig" init.templatedir)"
# branch.autoSetupMerge/Rebase make newly created branches track upstream
# and rebase-pull by default; regressions here silently change pull/push
# semantics across every repo.
start_test "branch.autoSetupMerge is always"
assert_equal \
    "always" "$(git config --file "$_gitconfig" branch.autoSetupMerge)"
start_test "branch.autoSetupRebase is always"
assert_equal \
    "always" "$(git config --file "$_gitconfig" branch.autoSetupRebase)"
# color.ui=auto is what makes git commands colorize stdout in terminals;
# "false"/"never" would silently strip colors from the entire workflow.
start_test "color.ui is auto"
assert_equal \
    "auto" "$(git config --file "$_gitconfig" color.ui)"
# log.date sets the format used by history aliases. A regression would
# silently reformat the `history` alias output.
start_test "log.date is format-local with YYYY-MM-DD HH:MM:SS"
assert_contains \
    "format-local:%Y-%m-%d %H:%M:%S" \
    "$(git config --file "$_gitconfig" log.date)"
# difftool.prompt=no keeps `git difftool` from asking before every file.
start_test "difftool.prompt is no"
assert_equal \
    "no" "$(git config --file "$_gitconfig" difftool.prompt)"
# user.name/email must be non-empty -- otherwise every first commit on a
# new machine would either prompt or (worse) be attributed to the shell
# user's default identity.
_user_name=$(git config --file "$_gitconfig" user.name)
_user_email=$(git config --file "$_gitconfig" user.email)
start_test "user.name is set"
assert_true test -n "$_user_name"
start_test "user.email is set"
assert_true test -n "$_user_email"
# The local-override include is what lets per-host tweaks live outside
# the checked-in config. Without it, corporate overrides silently fall
# back to the upstream defaults.
start_test "include.path points at local overrides"
assert_equal \
    "~/.gitconfig.local" "$(git config --file "$_gitconfig" include.path)"

# A sampling of aliases used by the shrc wrappers and muscle memory.
# These are the ones whose absence would quietly break daily workflow.
    start_test "alias.$_alias_name"
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
    assert_equal "$_alias_value" "$_got"
done

# The config should parse cleanly as a whole under `git config --list`.
start_test "gitconfig parses cleanly"
git config --file "$_gitconfig" --list >/dev/null 2>&1
assert_equal "0" "$?"

test_summary "gitconfig"
