# register hg VCS
#
# {onelinesummary} is used intentionally in several functions below.
# It can be customized via command-templates.oneline-summary in
# .hgrc.local.

function hg_absorb
    command hg --config extensions.absorb= absorb --apply-changes $argv
end

function hg_add
    command hg add $argv
end

function hg_addremove
    command hg addremove $argv
end

function hg_amend
    command hg amend $argv
end

function hg_base
    command hg --pager never log -r . --template '{onelinesummary}\n' $argv
end

function hg_at_tip
    test -n (command hg --pager never log -r '. and last(heads(branch(.)))' --template x 2>/dev/null)
end

function hg_map
    if hg_at_tip
        hg_base $argv
    else
        hg_graph
    end
end

function hg_annotate
    command hg annotate $argv
end

function hg_blame
    command hg blame $argv
end

# print the name of the currently active mercurial branch
function hg_branch
    command hg branch 2>/dev/null
end

# print the name of all mercurial branches
function hg_branches
    command hg branches
end

function hg_change
    if test (count $argv) -eq 0
        command hg commit --amend -e
    else
        command hg commit --amend $argv
    end
end

function hg_changed
    if test (count $argv) -eq 0
        command hg status --no-status
    else
        command hg log $argv --template "{files}\n"
    end
end

function hg_changelog
    command hg log --template '{onelinesummary}\n' $argv
end

function hg_changes
    command hg diff $argv
end

function hg_checkout
    command hg checkout $argv
end

function hg_goto
    command hg update $argv
end

function hg_commit
    command hg commit $argv
end

function hg_commitforce
    command hg --config hooks.precommit= --config hooks.pre-commit= commit $argv
end

function hg_diffedit
    command hg histedit $argv
end

function hg_drop
    command hg prune $argv
end

function hg_describe
    if test (count $argv) -eq 0
        command hg commit --amend -e
    else
        command hg commit --amend $argv
    end
end

function hg_diffs
    command hg diff $argv
end

function hg_diffstat
    command hg diff --stat $argv
end

function hg_evolve
    command hg evolve $argv
end

function hg_fastforward
    if command hg sync --tool=internal:fail
        true
    else
        command hg rebase --abort
        false
    end
end

function hg_fetchtime
    set changelog (command hg root)/.hg/store/00changelog.i
    if test -f $changelog
        stat -c %Y $changelog 2>/dev/null; or stat -f %m $changelog 2>/dev/null
    end
end

function hg_fix
    command hg fix $argv
end

function hg_graft
    command hg graft $argv
end

function hg_graph
    if test (count $argv) -eq 0
        command hg --pager never log --graph --template oneline -r 'draft() and not obsolete()'
    else
        command hg --pager never log --graph --template oneline $argv
    end
end

function hg_histedit
    command hg histedit
end

function hg_ignore
    set _root (command hg root)
    printf '%s\n' "$argv" >> $_root/.hgignore
end

# show changesets that would be fetched
function hg_incoming
    command hg incoming --template '{onelinesummary}\n' $argv
end

function hg_move
    command hg rename $argv
end

function hg_next
    command hg update -r "min(children(.))" $argv
end

function hg_copy
    command hg copy $argv
end

function hg_mv
    command hg rename $argv
end

function hg_lint
    command hg lint $argv
end

# show changesets that would be pushed
function hg_outgoing
    command hg --pager never --quiet log -r "draft() and not obsolete()" --template '{onelinesummary}\n' $argv
end

function hg_pending
    command hg --pager never status
end

function hg_pick
    command hg graft $argv
end

function hg_precommit
    command hg precommit $argv
end

function hg_prereview
    command hg prereview $argv
end

function hg_prev
    command hg update -r ".^" $argv
end

function hg_presubmit
    command hg presubmit $argv
end

function hg_projectroot
    command hg root
end

function hg_pull
    command hg pull --update --rebase $argv
end

function hg_push
    command hg push $argv
end

function hg_rebase
    command hg rebase $argv
end

function hg_resolve
    command hg resolve $argv
end

function hg_mergetool
    command hg resolve $argv
end

function hg_recommit
    command hg commit --amend $argv
end

function hg_remove
    command hg remove $argv
end

function hg_rename
    command hg rename $argv
end

function hg_rm
    command hg remove $argv
end

function hg_restore
    command hg revert $argv
end

function hg_revert
    command hg revert $argv
end

function hg_review
    warn "hg review not supported"
    false
end

function hg_reword
    if test (count $argv) -eq 0
        command hg commit --amend -e
    else
        command hg commit --amend $argv
    end
end

function hg_rootdir
    command hg root
end

function hg_show
    command hg export $argv
end

function hg_split
    command hg split $argv
end

function hg_squash
    command hg fold $argv
end

function hg_submit
    command hg submit
end

function hg_submitforce
    command hg --config hooks.preoutgoing= --config hooks.pre-push= submit
end

function hg_status
    command hg status $argv
end

function hg_track
    command hg add $argv
end

function hg_unamend
    command hg unamend $argv
end

function hg_uncommit
    command hg --config extensions.uncommit= uncommit $argv
end

function hg_undo
    command hg undo $argv
end

function hg_unknown
    command hg status --unknown --deleted
end

function hg_untrack
    command hg forget $argv
end

function hg_upload
    if test (count $argv) -eq 0
        command hg push -r .
    else
        command hg push $argv
    end
end

function hg_uploadchain
    command hg uploadchain $argv
end
