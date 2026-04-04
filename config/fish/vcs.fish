# Version control additions to config.fish.
#
# Most VCS commands delegate to the `vcs` script (which sources shrc.vcs
# in bash).  Only functions that need to run in the current shell (cd,
# reading .vcs_cache for the prompt) are implemented natively in fish.

# Dispatch VCS commands via the vcs script.
# With no arguments, detect and print the VCS name.
# With arguments, run the named VCS subcommand.
function vcs
    if test (count $argv) -gt 0
        command vcs $argv
        return
    end

    # Read .vcs_cache if it exists (fast path for prompt).
    if test -f .vcs_cache
        read _vcs _rest <.vcs_cache
        printf '%s\n' $_vcs
        test -n "$_vcs"
        return
    end

    # No cache: call the vcs script to detect and populate it.
    have_command vcs; or return 1
    command vcs
end

function cv
    find . -type f -name .vcs_cache -delete
end

# Read fields from .vcs_cache without spawning subprocesses.
# Sets _vcs_cache_vcs, _vcs_cache_backend, _vcs_cache_hosting,
# _vcs_cache_rootdir.
function _read_vcs_cache
    if not test -f .vcs_cache
        vcs >/dev/null 2>&1; or return 1
    end
    set _lines
    while read _line
        set --append _lines $_line
    end <.vcs_cache
    set _parts (string split ' ' $_lines[1])
    set --global _vcs_cache_vcs $_parts[1]
    set --global _vcs_cache_backend ''
    set --global _vcs_cache_hosting ''
    if test (count $_parts) -ge 2; and test $_parts[2] != '-'
        set --global _vcs_cache_backend $_parts[2]
    end
    if test (count $_parts) -ge 3; and test $_parts[3] != '-'
        set --global _vcs_cache_hosting $_parts[3]
    end
    set --global _vcs_cache_rootdir $_lines[2]
end

# Read the root directory from .vcs_cache.
# This is called by the prompt, so it must be fast.
function rootdir
    _read_vcs_cache; or return 1
    if test (count $argv) -gt 0
        for _arg in $argv
            printf '%s\n' "$_vcs_cache_rootdir/$_arg"
        end
    else
        printf '%s\n' $_vcs_cache_rootdir
    end
    test -n "$_vcs_cache_rootdir"
end

function vcs_backend
    _read_vcs_cache; or return 1
    printf '%s\n' $_vcs_cache_backend
    test -n "$_vcs_cache_backend"
end

function vcs_hosting
    _read_vcs_cache; or return 1
    printf '%s\n' $_vcs_cache_hosting
    test -n "$_vcs_cache_hosting"
end

function subdir
    set _sub (trim_prefix (rootdir) (test -n "$argv[1]"; and echo $argv[1]; or echo $PWD))
    printf '%s\n' (string replace --regex '^/' '' $_sub)
end

function allknown
    set _unknown (vcs unknown)
    printf '%s\n' $_unknown
    test -z "$_unknown"
end

# Short aliases for VCS commands.
function ab; vcs absorb $argv; end
function ad; vcs add $argv; end
function ak; allknown $argv; end
# am is defined in config.fish
function an; vcs annotate $argv; end
function ann; vcs annotate $argv; end
function bl; vcs blame $argv; end
function change; vcs recommit $argv; end
# ci is defined in config.fish
function cl; vcs changelog $argv; end
function co; vcs checkout $argv; end
# di is defined in config.fish
function dr; vcs drop $argv; end
function ev; vcs evolve $argv; end
function ff; vcs fastforward $argv; end
# gr is defined in config.fish
function ig; vcs ignore $argv; end
# lg is defined in config.fish
# ma is defined in config.fish
function re; vcs review $argv; end
function ro; rootdir $argv; end
# st is defined in config.fish
function un; vcs undo $argv; end
function up; vcs upload $argv; end
function upp
    vcs upload
    vcs presubmit
end

# Create VCS dispatch functions for all commands.
# Note: "status" is excluded because it is a reserved word in fish.
# Use "st" or "vcs status" instead (defined in config.fish).
for _cmd in absorb add addremove amend annotate at_tip \
    base blame branch branches \
    changed changelog changes checkout commit commitforce copy describe diffedit diffs diffstat drop \
    evolve fastforward fetchtime fix goto graft graph histedit ignore incoming lint map move next outgoing \
    mergetool pending pick precommit presubmit prev pull push \
    rebase recommit remove rename resolve restore revert review reword \
    show split squash submit submitforce track \
    unamend uncommit undo unknown untrack upload uploadchain
    eval "function $_cmd; vcs $_cmd \$argv; end"
end

# Override cp/mv/rm to use VCS-aware versions when inside a repo.
function cp
    set _vcs (vcs 2>/dev/null)
    if test -n "$_vcs"
        command vcs copy $argv
    else
        command cp $argv
    end
end

function mv
    set _vcs (vcs 2>/dev/null)
    if test -n "$_vcs"
        command vcs move $argv
    else
        command mv $argv
    end
end

function rm
    set _vcs (vcs 2>/dev/null)
    if test -n "$_vcs"
        command vcs remove $argv 2>/dev/null; and return
    end
    command rm $argv
end

# Functions that must run in the current shell (they change directory).
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
    allknown; and vcs fix
end

# Extract unique status characters from VCS status output.
# Called on every prompt, so it calls the VCS tool directly
# to avoid bash overhead from `command vcs`.
function status_chars
    set _vcs (vcs 2>/dev/null)
    test -n "$_vcs"; or return
    switch $_vcs
    case git
        git status --short --untracked-files=all
    case hg
        command hg status
    case jj
        # Only show status for undescribed commits.
        set desc (command jj log --no-graph -r @ -T 'description' 2>/dev/null); or return
        test -z "$desc"; or return
        command jj diff --summary
    case '*'
        command vcs status
    end | awk '$1 ~ /^([[:upper:]?!]([[:upper:]?!])*)$/ { print $1 }' |
        sort | uniq | tr '\n' ' ' | sed -e 's/ *$//'
end
