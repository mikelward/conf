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
