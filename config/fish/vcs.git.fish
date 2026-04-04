# register git VCS
#
# --oneline is used intentionally in several functions below.
# It respects color settings and can be customized via
# pretty.oneline in .gitconfig.
function git_absorb
    git absorb $argv
end

function git_add
    git add --intent-to-add $argv
end

function git_addremove
    git add --all $argv
end

function git_amend
    set flags
    while test (count $argv) -gt 0
        switch $argv[1]
        case --
            set --append flags $argv[1]
            set --erase argv[1]
            break
        case -m -C -c -F -t
            set --append flags $argv[1] $argv[2]
            set --erase argv[1..2]
        case '-*'
            set --append flags $argv[1]
            set --erase argv[1]
        case '*'
            break
        end
    end
    # no files given, commit them all
    test (count $argv) -eq 0; and set --append flags --all
    git commit --amend --no-edit $flags $argv
end

function git_base
    if test (git rev-parse --abbrev-ref HEAD) = "HEAD"
        printf '(detached) '
    end
    git --no-pager log -1 --oneline $argv
end

function git_at_tip
    test (git rev-parse --abbrev-ref HEAD) != "HEAD"
end

function git_map
    if git_at_tip
        git_base $argv
    else
        git_graph
    end
end

function git_annotate
    git blame $argv
end

function git_blame
    git blame $argv
end

# print the name of the currently active git branch
function git_branch
    git branch 2>/dev/null | while read star branch
        if test "$star" = "*"
            printf '%s\n' $branch
            break
        end
    end
end

# print the name of all (local by default) git branches
function git_branches
    git branch $argv
end

function git_changed
    git diff --name-only $argv
end

function git_changelog
    git log --oneline $argv
end

function git_changes
    git diff $argv
end

function git_checkout
    git checkout $argv
end

function git_goto
    git checkout $argv
end

function git_commit
    set flags
    while test (count $argv) -gt 0
        switch $argv[1]
        case --
            set --append flags $argv[1]
            set --erase argv[1]
            break
        case -m -C -c -F -t
            set --append flags $argv[1] $argv[2]
            set --erase argv[1..2]
        case '-*'
            set --append flags $argv[1]
            set --erase argv[1]
        case '*'
            break
        end
    end
    # no files given, commit them all
    test (count $argv) -eq 0; and set --append flags --all
    git commit $flags $argv
end

function git_commitforce
    git_commit --no-verify $argv
end

function git_diffedit
    git rebase --interactive $argv
end

function git_drop
    git rebase --onto "$argv[1]~" $argv[1]
end

function git_describe
    git commit --amend --only --allow-empty $argv
end

function git_diffs
    git diff $argv
end

function git_diffstat
    git diff --stat $argv
end

function git_evolve
    warn "no automatic evolve in git; use: git rebase --onto <new> <old> <branch>"
    return 1
end

function git_fastforward
    git pull --ff-only
end

function git_fetchtime
    set fetch_head (git rev-parse --git-dir)/FETCH_HEAD
    if test -f $fetch_head
        stat -c %Y $fetch_head 2>/dev/null; or stat -f %m $fetch_head 2>/dev/null
    end
end

function git_fix
    git fix $argv
end

function git_graft
    git cherry-pick $argv
end

function git_graph
    if test (count $argv) -eq 0
        git --no-pager log --graph --pretty=format:'%C(auto)%h%C(auto)%d %s' "@{upstream}..HEAD" 2>/dev/null
        or git --no-pager log --graph --pretty=format:'%C(auto)%h%C(auto)%d %s'
    else
        git --no-pager log --graph --pretty=format:'%C(auto)%h%C(auto)%d %s' $argv
    end
end

function git_histedit
    git rebase --interactive
end

function git_ignore
    set _root (git root)
    printf '%s\n' "$argv" >> $_root/.gitignore
end

# print commits that would be pulled
function git_incoming
    git log --oneline HEAD..@\{upstream\}
end

function git_move
    git mv $argv
end

function git_next
    set head (git rev-parse HEAD)
    set child (git rev-list --children --all | awk -v h=$head '$1 == h {print $2; exit}')
    if test -z "$child"
        warn "no next commit"
        return 1
    end
    git checkout $child
end

function git_copy
    command cp $argv; and git add $argv[-1]
end

function git_mv
    git mv $argv
end

function git_lint
    git lint $argv
end

# print commits that would be pushed
function git_outgoing
    git --no-pager log --oneline @\{upstream\}..HEAD
end

function git_pending
    git --no-pager log --oneline @\{upstream\}..HEAD 2>/dev/null; or git status --short
end

function git_pick
    git cherry-pick $argv
end

function git_precommit
    git_hook pre-commit
end

function git_prereview
    git_hook pre-commit
end

function git_prev
    git checkout HEAD~
end

function git_presubmit
    git_hook pre-push
end

function git_projectroot
    git root
end

function git_pull
    git pull --rebase $argv
end

function git_push
    git push $argv
end

function git_hook
    set script (git rev-parse --git-dir)/hooks/$argv[1]
    set --erase argv[1]
    if test -x $script
        $script $argv
    else
        warn "No $script hook"
    end
end

function git_rebase
    git rebase $argv
end

function git_resolve
    git mergetool $argv
end

function git_mergetool
    git mergetool $argv
end

function git_recommit
    git amend $argv
end

function git_remove
    git rm $argv
end

function git_rename
    git mv $argv
end

function git_rm
    git rm $argv
end

function git_restore
    git checkout -- $argv
end

function git_revert
    if test (count $argv) -eq 0
        git reset --hard HEAD
    else
        git checkout -- $argv
    end
end

function _git_github_review
    set _reviewers
    set _push_flags
    set _hosting (vcs_hosting)

    while test (count $argv) -gt 0
        switch $argv[1]
        case -r -m --reviewer
            set --append _reviewers $argv[2]
            set --erase argv[1..2]
        case '--reviewer=*'
            set --append _reviewers (string replace --regex '^--reviewer=' '' $argv[1])
            set --erase argv[1]
        case '*'
            set --append _push_flags $argv[1]
            set --erase argv[1]
        end
    end

    if test "$_hosting" = "gerrit"
        set _reviewer_suffix ''
        for _r in $_reviewers
            set _reviewer_suffix "$_reviewer_suffix%r=$_r"
        end
        git push origin "HEAD:refs/for/master/"(git_branch)"$_reviewer_suffix" $_push_flags
    else if test "$_hosting" = "github"
        git push $_push_flags; or return
        set _review_flags
        for _r in $_reviewers
            set --append _review_flags -r $_r
        end
        _github_review $_review_flags
    else
        git push $_push_flags
    end
end

# send the current change for review
function git_review
    _git_github_review $argv
end

function git_reword
    git commit --amend --only --allow-empty
end

function git_rootdir
    git rootdir
end

function git_status
    git status --short --untracked-files=all $argv
end

function git_show
    git show $argv
end

function git_split
    git rebase -i $argv
end

function git_squash
    git merge --squash $argv
end

function git_submit
    git push $argv
end

function git_submitforce
    git push --no-verify $argv
end

function git_track
    git add --intent-to-add $argv
end

function git_undo
    git reset --mixed HEAD~
end

function git_unamend
    git reset --mixed HEAD@\{1\}
end

function git_uncommit
    git reset --soft HEAD~
end

function git_unknown
    set _root (git rootdir)
    cd $_root
    git ls-files -od --exclude-standard
end

function git_untrack
    git rm --cached $argv
end

function git_upload
    _git_github_review $argv
end

function git_uploadchain
    _git_github_review $argv
end
