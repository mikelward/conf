# register jj VCS

function jj_absorb
    command jj absorb $argv
end

function jj_base
    command jj --no-pager log --no-graph -r '@|@-' --template 'if(self.contained_in("@"), if(description.first_line(), "@ " ++ change_id.shortest() ++ " " ++ description.first_line() ++ "\n"), "* " ++ change_id.shortest() ++ " " ++ description.first_line() ++ "\n")' $argv
end

function jj_at_tip
    test -z (command jj --no-pager log --no-graph -r 'children(@) | (children(@-) ~ @)' --template '"x"' 2>/dev/null)
end

function jj_map
    if jj_at_tip
        jj_base $argv
    else
        jj_graph
    end
end

function jj_add
    command jj file track $argv
end

function jj_addremove
    # jj auto-tracks all files; nothing to do
    :
end

function jj_amend
    command jj squash $argv
end

function jj_annotate
    command jj file annotate $argv
end

function jj_blame
    command jj file blame $argv
end

function jj_branch
    # there is no current bookmark in jj
    :
end

# print the name of all bookmarks
function jj_branches
    command jj bookmark list
end

function jj_change
    command jj describe $argv
end

function jj_describe
    command jj describe $argv
end

function jj_changed
    command jj diff --summary $argv
end

function jj_changelog
    command jj log --template=builtin_log_oneline $argv
end

function jj_changes
    command jj diff $argv
end

function jj_checkout
    command jj new $argv
end

function jj_goto
    command jj new $argv
end

function jj_commit
    command jj commit $argv
end

function jj_commitforce
    command jj commit $argv
end

function jj_diffedit
    command jj diffedit $argv
end

function jj_drop
    command jj abandon $argv
end

function jj_diffs
    command jj diff $argv
end

function jj_diffstat
    command jj diff --stat $argv
end

function jj_fastforward
    if test (vcs_backend) = "git"
        command jj git fetch $argv
    else
        command jj piper pull
    end
end

function jj_fetchtime
    set fetch_head (command jj workspace root)/.jj/repo/store/git/FETCH_HEAD
    if test -f $fetch_head
        stat -c %Y $fetch_head 2>/dev/null; or stat -f %m $fetch_head 2>/dev/null
    end
end

function jj_fix
    command jj fix $argv
end

function jj_graft
    command jj duplicate $argv
end

function jj_graph
    if test (count $argv) -eq 0
        command jj log --template 'change_id.shortest() ++ " " ++ if(description, description.first_line(), "(no description set)") ++ if(bookmarks, " [" ++ bookmarks.join(", ") ++ "]", "") ++ "\n"' -r 'mutable() ~ empty() ~ ancestors(remote_bookmarks())'
    else
        command jj log --template 'change_id.shortest() ++ " " ++ if(description, description.first_line(), "(no description set)") ++ if(bookmarks, " [" ++ bookmarks.join(", ") ++ "]", "") ++ "\n"' $argv
    end
end

function jj_histedit
    warn "no interactive histedit in jj; use: jj squash, jj split, jj edit"
    return 1
end

function jj_ignore
    set _root (command jj workspace root)
    printf '%s\n' "$argv" >> $_root/.gitignore
end

function jj_incoming
    command jj op log $argv
end

function jj_move
    jj_rename $argv
end

function jj_next
    command jj next $argv
end

function jj_copy
    command cp $argv
end

function jj_mv
    jj_rename $argv
end

function jj_lint
    command jj fix $argv
end

function jj_outgoing
    command jj --no-pager log --no-graph -r 'mutable() ~ empty() ~ ancestors(remote_bookmarks())' --template 'change_id.shortest() ++ " " ++ description.first_line() ++ "\n"' $argv
end

function jj_pending
    command jj --no-pager log -r 'mutable() ~ empty()' $argv
end

function jj_pick
    command jj duplicate $argv
end

function jj_precommit
    command jj fix $argv
end

function jj_prev
    command jj prev $argv
end

function jj_presubmit
    if test (vcs_backend) = "git"
        warn "no presubmit for git-backed repos; run tests locally"
    else
        command jj piper presubmit $argv
    end
end

function jj_projectroot
    command jj workspace root
end

function jj_pull
    if test (vcs_backend) = "git"
        command jj git fetch $argv
    else
        command jj sync $argv
    end
end

function jj_push
    if test (vcs_backend) = "git"
        command jj git push $argv
    else
        command jj upload $argv
    end
end

function jj_rebase
    command jj rebase $argv
end

function jj_evolve
    warn "jj automatically rebases descendants; nothing to do"
end

function jj_recommit
    command jj describe $argv
end

function jj_remove
    command rm $argv
    command jj file untrack $argv
end

function jj_rm
    jj_remove $argv
end

function jj_rename
    if test (count $argv) -ne 2
        error "usage: rename <source> <dest>"
        return 1
    end
    command mv $argv[1] $argv[2]
end

function _jj_github_review
    set _review_flags
    set _push_flags
    while test (count $argv) -gt 0
        switch $argv[1]
        case -r -m --reviewer
            set --append _review_flags -r $argv[2]
            set --erase argv[1..2]
        case '--reviewer=*'
            set --append _review_flags -r (string replace --regex '^--reviewer=' '' $argv[1])
            set --erase argv[1]
        case '*'
            set --append _push_flags $argv[1]
            set --erase argv[1]
        end
    end

    if test (vcs_backend) = "git"
        command jj git push $_push_flags; or return
        if test (vcs_hosting) = "github"
            set _bookmark (command jj bookmark list -r @ 2>/dev/null | head -1 | cut -d: -f1)
            test -n "$_bookmark"; and set --append _review_flags --head $_bookmark
            _github_review $_review_flags
        end
    else
        command jj upload $_push_flags
    end
end

function jj_review
    _jj_github_review $argv
end

function jj_resolve
    command jj resolve $argv
end

function jj_mergetool
    command jj resolve $argv
end

function jj_restore
    command jj restore $argv
end

function jj_revert
    command jj revert $argv
end

function jj_reword
    if test (count $argv) -eq 0
        command jj describe
    else
        command jj describe -m $argv
    end
end

function jj_rootdir
    command jj workspace root
end

function jj_show
    command jj show $argv
end

function jj_split
    command jj split $argv
end

function jj_squash
    command jj squash $argv
end

function jj_status
    # Only show status for undescribed commits (the jj equivalent of
    # uncommitted changes).  Described commits are "done".
    set desc (command jj log --no-graph -r @ -T 'description' 2>/dev/null); or return
    if test -z "$desc"
        command jj diff --summary $argv
    end
end

function jj_submit
    if test (vcs_backend) = "git"
        command jj git push $argv
    else
        command jj submit $argv
    end
end

function jj_submitforce
    if test (vcs_backend) = "git"
        command jj git push $argv
    else
        command jj submit $argv
    end
end

function jj_track
    command jj file track $argv
end

function jj_unamend
    command jj undo $argv
end

function jj_uncommit
    command jj squash --from @- --into @ $argv
end

function jj_undo
    command jj undo $argv
end

function jj_unknown
    command jj file list --untracked $argv
end

function jj_untrack
    command jj untrack $argv
end

function jj_upload
    _jj_github_review $argv
end

function jj_uploadchain
    _jj_github_review $argv
end
