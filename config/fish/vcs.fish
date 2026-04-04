# Version control additions to config.fish.

# print the name of the version control system in use in $PWD
function vcs
    if test (count $argv) -gt 0
        set _vcs (vcs)
        test -z "$_vcs"; and return 1
        set command $argv[1]
        set --erase argv[1]
        {$_vcs}_{$command} $argv
        return
    end

    # If it's not writable, assume we don't care about vcs here.
    test -w $PWD; or return 1

    # Cache format (2 lines):
    #   line 1: <vcs> <backend> <hosting>  (- for empty fields)
    #   line 2: <rootdir>                  (whole line, may contain spaces)
    set _vcs ''
    set _rootdir ''
    set _backend ''
    set _hosting ''
    if test -f .vcs_cache
        set _line1 (head -1 .vcs_cache)
        set _rootdir (sed -n 2p .vcs_cache)
        set _parts (string split ' ' $_line1)
        set _vcs $_parts[1]
        if test (count $_parts) -ge 2
            set _backend $_parts[2]
        end
        if test (count $_parts) -ge 3
            set _hosting $_parts[3]
        end
        # Sentinels for empty fields.
        test "$_backend" = "-"; and set _backend ''
        test "$_hosting" = "-"; and set _hosting ''
    else if test -w .
        set _found (
            set _dir $PWD
            while test "$_dir" != "/"
                if test -e "$_dir/.jj"
                    printf '%s\n' "jj" "$_dir"
                    break
                else if test -e "$_dir/.hg"
                    printf '%s\n' "hg" "$_dir"
                    break
                else if test -e "$_dir/.git"
                    printf '%s\n' "git" "$_dir"
                    break
                else if test -e "$_dir/.citc"; or test -e "$_dir/.p4config"
                    printf '%s\n' "g4" "$_dir"
                    break
                end
                set _dir (dirname $_dir)
            end
        )
        if test (count $_found) -ge 2
            set _vcs $_found[1]
            set _rootdir $_found[2]
        end
        # Detect backend
        if test "$_vcs" = "jj"; and test -f "$_rootdir/.jj/repo/store/type"
            set _backend (head -1 "$_rootdir/.jj/repo/store/type")
        else if test "$_vcs" = "git"
            set _backend "git"
        end
        # Detect hosting
        if test "$_backend" = "git"
            set _git_dir
            if test "$_vcs" = "jj"
                set _git_dir "$_rootdir/.jj/repo/store/git"
            else
                set _git_dir "$_rootdir/.git"
            end
            set _origin_url (git -C "$_git_dir" remote get-url origin 2>/dev/null)
            switch "$_origin_url"
            case '*github.com*'
                set _hosting "github"
            case '*gitlab.com*' '*gitlab.*'
                set _hosting "gitlab"
            case '*bitbucket.org*'
                set _hosting "bitbucket"
            case '*sr.ht*'
                set _hosting "sourcehut"
            case '*googlesource.com*'
                set _hosting "gerrit"
            end
        end
        # Write cache.  Ignore errors (read-only filesystem).
        if test -n "$_vcs"
            begin
                printf '%s %s %s\n' $_vcs (test -n "$_backend"; and echo $_backend; or echo -) (test -n "$_hosting"; and echo $_hosting; or echo -)
                printf '%s\n' $_rootdir
            end >.vcs_cache 2>/dev/null
        end
    end
    if test -z "$_vcs"; or test -z "$_rootdir"
        return 1
    end
    printf '%s\n' $_vcs
    test -n "$_vcs"
end

function cv
    find . -type f -name .vcs_cache -delete
end

function rootdir
    if not test -f .vcs_cache
        vcs >/dev/null 2>&1; or return 1
    end
    set _line1 (head -1 .vcs_cache)
    set _rootdir (sed -n 2p .vcs_cache)
    if test (count $argv) -gt 0
        for _arg in $argv
            printf '%s\n' "$_rootdir/$_arg"
        end
    else
        printf '%s\n' $_rootdir
    end
    test -n "$_rootdir"
end

function vcs_backend
    if not test -f .vcs_cache
        vcs >/dev/null 2>&1; or return 1
    end
    set _parts (string split ' ' (head -1 .vcs_cache))
    set _backend ''
    if test (count $_parts) -ge 2
        set _backend $_parts[2]
    end
    test "$_backend" = "-"; and set _backend ''
    printf '%s\n' $_backend
    test -n "$_backend"
end

function vcs_hosting
    if not test -f .vcs_cache
        vcs >/dev/null 2>&1; or return 1
    end
    set _parts (string split ' ' (head -1 .vcs_cache))
    set _hosting ''
    if test (count $_parts) -ge 3
        set _hosting $_parts[3]
    end
    test "$_hosting" = "-"; and set _hosting ''
    printf '%s\n' $_hosting
    test -n "$_hosting"
end

function subdir
    set _sub (trim_prefix (rootdir) (test -n "$argv[1]"; and echo $argv[1]; or echo $PWD))
    printf '%s\n' (string replace --regex '^/' '' $_sub)
end

# hook to define any implied prefix
function implied_prefix
    :
end

function target_relative_to
    set _target $argv[1]
    set _from ''
    if test (count $argv) -ge 2
        set _from $argv[2]
    end

    # normalize "." to empty
    test "$_from" = "."; and set _from ''
    test "$_target" = "."; and set _target ''

    # strip common leading path components
    while test -n "$_from"
        set _ff (string replace --regex '/.*' '' $_from)
        set _ft (string replace --regex '/.*' '' $_target)
        test "$_ff" != "$_ft"; and break
        switch $_from
        case '*/*'
            set _from (string replace --regex '^[^/]*/' '' $_from)
        case '*'
            set _from ''
        end
        switch $_target
        case '*/*'
            set _target (string replace --regex '^[^/]*/' '' $_target)
        case '*'
            set _target ''
        end
    end

    # prepend ../ for each remaining component in _from
    set _result ''
    while test -n "$_from"
        set _result "../$_result"
        switch $_from
        case '*/*'
            set _from (string replace --regex '^[^/]*/' '' $_from)
        case '*'
            break
        end
    end

    set _result "$_result$_target"
    set _result (string replace --regex '/$' '' $_result)
    test -z "$_result"; and set _result '.'
    printf '%s\n' $_result
end

function relative_path
    set _target $argv[1]
    set _relative_to ''
    if test (count $argv) -ge 2
        set _relative_to $argv[2]
    else
        set _relative_to (subdir)
    end
    set _target (trim_prefix (implied_prefix) $_target)
    set _relative_to (trim_prefix (implied_prefix) $_relative_to)
    target_relative_to $_target $_relative_to
end
function rp; relative_path $argv; end

function allknown
    set _unknown (unknown)
    printf '%s\n' $_unknown
    test -z "$_unknown"
end

# short aliases for VCS commands
function ab; absorb $argv; end
function ad; add $argv; end
function ak; allknown $argv; end
# am is defined in config.fish
function an; annotate $argv; end
function ann; annotate $argv; end
function bl; blame $argv; end
function change; recommit $argv; end
# ci is defined in config.fish
function cl; changelog $argv; end
function co; checkout $argv; end
# di is defined in config.fish
function dr; drop $argv; end
function ev; evolve $argv; end
function ff; fastforward $argv; end
# gr is defined in config.fish
function ig; ignore $argv; end
# lg is defined in config.fish
# ma is defined in config.fish
function re; review $argv; end
function ro; rootdir $argv; end
# sa conflicts with shpool alias, keeping shpool version in config.fish
# st is defined in config.fish
function un; undo $argv; end
function up; upload $argv; end
function upp
    upload
    presubmit
end

# create VCS dispatch functions for all commands
for command in absorb add addremove amend annotate at_tip \
    base blame branch branches \
    changed changelog changes checkout commit commitforce copy describe diffedit diffs diffstat drop \
    evolve fastforward fetchtime fix goto graft graph histedit ignore incoming lint map move next outgoing \
    mergetool pending pick precommit presubmit prev pull push \
    rebase recommit remove rename resolve restore revert review reword \
    show split squash status submit submitforce track \
    unamend uncommit undo unknown untrack upload uploadchain
    eval "function $command; vcs $command \$argv; end"
end

function cp
    set _vcs (vcs)
    if test -n "$_vcs"; and functions --query {$_vcs}_copy
        {$_vcs}_copy $argv
    else
        command cp $argv
    end
end

function mv
    set _vcs (vcs)
    if test -n "$_vcs"; and functions --query {$_vcs}_mv
        {$_vcs}_mv $argv
    else
        command mv $argv
    end
end

function rm
    set _vcs (vcs)
    if test -n "$_vcs"; and functions --query {$_vcs}_rm
        {$_vcs}_rm $argv 2>/dev/null; and return
    end
    command rm $argv
end

function clone
    switch $argv[1]
    case '*.git'
        if have_command jj
            jj git clone $argv
        else if confirm "jj is not installed. Clone using git"
            git clone $argv
        end
    case '*/hg*'
        command hg clone $argv
    end
end

function cr
    cd (rootdir)
end

function rd
    cd (rootdir)
end

function project
    basename (projectroot)
end

function projectroot
    rootdir $argv
end

function save
    allknown; and fix
end

function status_chars
    vcs status |
        awk '$1 ~ /^([[:upper:]?!]([[:upper:]?!])*)$/ { print $1 }' |
        sort | uniq | tr '\n' ' ' | sed -e 's/ *$//'
end

# Create or show a GitHub pull request.
function _github_review
    if not have_command gh
        echo "Install gh to create PRs: https://cli.github.com" >&2
        return 1
    end

    set _reviewers
    set _head ''
    while test (count $argv) -gt 0
        switch $argv[1]
        case -r -m --reviewer
            set --append _reviewers --reviewer $argv[2]
            set --erase argv[1..2]
        case '--reviewer=*'
            set --append _reviewers --reviewer (string replace --regex '^--reviewer=' '' $argv[1])
            set --erase argv[1]
        case --head
            set _head $argv[2]
            set --erase argv[1..2]
        case '--head=*'
            set _head (string replace --regex '^--head=' '' $argv[1])
            set --erase argv[1]
        case '*'
            set --erase argv[1]
        end
    end

    # For jj non-colocated repos, export GIT_DIR so gh can find the remote
    if test (vcs) = "jj"; and not test -e (rootdir)/.git
        set _git_dir (rootdir)/.jj/repo/store/git
        if test -d $_git_dir
            set --export GIT_DIR $_git_dir
        end
    end

    # Check if PR already exists
    if test -n "$_head"
        command gh pr view $_head --json url -q .url 2>/dev/null; and return
    else
        command gh pr view --json url -q .url 2>/dev/null; and return
    end

    # Determine default branch
    set _base (command gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)
    test -z "$_base"; and set _base main

    set _flags --base $_base --fill
    test -n "$_head"; and set --append _flags --head $_head
    if test (count $_reviewers) -eq 0
        set --append _flags --draft
    else
        set --append _flags $_reviewers
    end

    command gh pr create $_flags
end

# source VCS backend files
for f in (string replace '.shrc.vcs.' 'config/fish/vcs.' $HOME/.shrc.vcs.* 2>/dev/null)
    # no-op; fish VCS files are sourced explicitly below
end
for f in $HOME/.config/fish/vcs.*.fish
    if test -f $f
        source $f
    end
end
