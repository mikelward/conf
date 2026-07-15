# Configuration for fish shell.
#
# Mikel Ward <mikel@mikelward.com>

# Cross-shell failsafe escape hatch. Mirrors shrc's FAILSAFE=1 check
# and the equivalent in config.nu: bail out before defining functions,
# setting up the prompt, or jumping into shpool, so a misbehaving rc
# (e.g. an autoshpool loop) can be recovered from with `FAILSAFE=1 fish`.
# LC_FAILSAFE=1 is accepted as an alias so the flag survives sshd's
# env sanitization (most sshd configs AcceptEnv LC_*).
# ~/.failsafe is a persistent opt-in: `touch ~/.failsafe` to keep every
# new shell in failsafe mode without having to re-set the env var.
if test "$FAILSAFE" = 1; or test "$LC_FAILSAFE" = 1; or test -e $HOME/.failsafe
    echo failsafe mode >&2
    function fish_prompt
        echo (basename $PWD)'$ '
    end
    return
end

# standardize on bash-like variables that everyone assumes are preset
set USERNAME (id -un)
set HOSTNAME (hostname --fqdn)
set UID (id -u)
set TTY (tty)

#######
# PATH FUNCTIONS
# Functions used to modify $PATH
#
function prepend_path
    set _dir $argv[1]
    test -d $_dir; or return
    delete_path $_dir
    set --export --prepend PATH $_dir
end

function append_path
    set _dir $argv[1]
    test -d $_dir; or return
    delete_path $_dir
    set --export --append PATH $_dir
end

function delete_path
    set --path newpath ()
    for dir in $PATH
        test $dir = $argv[1]; and continue
        set --append newpath $dir
    end
    set --export --path PATH $newpath
end

function inpath
    for dir in $PATH
        test $dir = $argv[1]; and return 0
    end
    return 1
end

function add_path
    set _dir $argv[1]
    set _where $argv[2]
    set _newpath $PATH

    switch $_where
    case start end
        delete_path $_dir $_newpath
        switch $_where
        case start
            prepend_path $_dir $_newpath
        case end
            append_path $_dir $_newpath
        end
    case '*'
        inpath $_dir; or append_path $_dir
    end
end

#################
# BASIC FUNCTIONS
# Functions that are needed elsewhere in this file.

# hook for authenticating (to ssh-agent, etc.)
function a
    auth
end
# hook for authenticating (to ssh-agent, etc.)
function auth
    ssh-add
end

# hook for printing which things I need to authenticate to (ssh-agent, etc.)
# Called by prompt_line; should emit a short pre-colored warning when the
# user needs to re-auth and nothing otherwise.
function auth_info
    set problems ()
    is_ssh_valid; or set --append problems 'SSH'
    count $problems >/dev/null; and yellow $problems
end

# returns whether an SSH key is loaded
function is_ssh_valid
    ssh-add -L >/dev/null 2>&1
end

# returns whether I need to authenticate.
function need_auth
    set _info (auth_info | string collect)
    test -n "$_info"
end

# return true if this machine is my workstation
function workstation
    # cache null result too.
    if not set --query WORKSTATION
        set --global WORKSTATION (cat $HOME/.workstation 2>/dev/null)
    end
    echo $WORKSTATION
end

# return true if this machine is my workstation
function on_my_workstation
    switch $HOSTNAME
    case (workstation)
        true
    case '*laptop*'
        false
    case $USERNAME-'*'
        true
    case '*'
        false
    end
end

# return true if this session arrived over ssh
function connected_via_ssh
    test -n "$SSH_CONNECTION"
end

# return true if this session is on a remote machine
function connected_remotely
    connected_via_ssh
end

# print the connecting SSH client's hostname (best effort), or nothing and
# return non-zero if this isn't an SSH session. Tries, in order:
#   1. LC_CLIENT_HOST, smuggled through by ssh_to (servers commonly
#      AcceptEnv LC_*, so it usually survives without server-side config)
#   2. reverse DNS of the client IP from SSH_CONNECTION
#   3. the raw client IP
function ssh_client_host
    if test -n "$LC_CLIENT_HOST"
        printf '%s\n' $LC_CLIENT_HOST
        return 0
    end
    connected_via_ssh; or return 1
    set _ip (string split ' ' $SSH_CONNECTION)[1]
    set _name ""
    if have_command getent
        set _fields (getent hosts $_ip 2>/dev/null | string match --all --regex '\S+')
        if test (count $_fields) -ge 2
            set _name $_fields[2]
        end
    end
    if test -z "$_name"; and have_command dig
        set _name (dig +short -x $_ip 2>/dev/null | head -1 | string replace --regex '\.$' '')
    end
    if test -n "$_name"
        printf '%s\n' (string split '.' $_name)[1]
    else
        printf '%s\n' $_ip
    end
end

# return true if this is inside a VCS workspace/source root
function inside_project
    set _root (projectroot | string collect)
    test -n "$_root"
end

# return true if this session is attached to shpool
function in_shpool
    test -n "$SHPOOL_SESSION_NAME"
end

# return true if stdin is connected to a tty. Pulled out as a helper
# so tests can stub it without rigging up a pty.
function stdin_is_tty
    isatty stdin
end

# return true if we should auto-start shpool in this session. We require the
# autoshpool helper too, not just shpool, mirroring want_tmux's autotmux gate:
# a machine that has shpool but hasn't picked up the scripts repo yet must
# fall through to the tmux path rather than erroring on a missing autoshpool
# at every shell start.
function want_shpool
    test "$WANT_SHPOOL" = 0; and return 1
    stdin_is_tty; or return 1
    in_shpool; and return 1
    inside_tmux; and return 1
    have_command shpool; or return 1
    have_command autoshpool; or return 1
    connected_remotely; or inside_project
end

# return true if this session is inside a tmux server
function inside_tmux
    test -n "$TMUX"
end

# return true if we should auto-start tmux in this session. shpool is the
# default session manager; tmux is the fallback when shpool isn't installed
# or WANT_SHPOOL=0. The gating mirrors want_shpool. We require the autotmux
# helper too, not just tmux, so a machine that has tmux but hasn't picked up
# autotmux yet falls through to the shpool path.
function want_tmux
    test "$WANT_TMUX" = 0; and return 1
    stdin_is_tty; or return 1
    inside_tmux; and return 1
    in_shpool; and return 1
    have_command tmux; or return 1
    have_command autotmux; or return 1
    connected_remotely; or inside_project
end

# print an error message
function error
    printf '%s\n' "$argv" >&2
end

# return true if the argument exists as a command, bypassing aliases
function have_command
    command --search $argv[1] >/dev/null 2>&1
end

# return true if the argument is an alias, builtin, command, or function
function is_runnable
    type --query $argv[1]
end

# return true if the shell is interactive
function is_interactive
    status --is-interactive
end

# log the running of a command to a file
function log_history
    test -n "$HISTORY_FILE"; or return
    printf '%s %s %s\n' (date "+%Y%m%d %H%M%S %z") $TTY "$argv" >> $HISTORY_FILE
end

# run a command with output silenced
function quiet
    $argv >/dev/null 2>&1
end

# remove a prefix from a string
function trim_prefix
    string replace --regex ^(string escape --style=regex $argv[1]) '' $argv[2]
end

# print an important message that's not quite an error
function warn
    printf '%s\n' "$argv" >&2
end

###################
# GENERAL FUNCTIONS
# Useful things that could be commands if distributing them wasn't impractical.

# print the age of a file in seconds
function age
    set mtime (stat -c '%Y' $argv[1])
    math (date +%s) - $mtime
end

# look up a hostname in DNS, output both A and AAAA records
function addr
    dig +noall +answer +search $argv[1] a $argv[1] aaaa | get_address_records
end

function ptr
    dig +noall +answer -x $argv[1] ptr | get_ptr_records
end

# read BIND-style DNS entries, print the A and AAAA records
function get_address_records
    awk '$3 == "IN" && $4 ~ /^A/ { print $5 }'
end

# read BIND-style DNS entries, print the PTR records
function get_ptr_records
    awk '$3 == "IN" && $4 == "PTR" { print $5 }'
end

function with_address_records
    while read -r hostname
        echo $hostname (join " " (addr $hostname))
    end
end

function with_hostnames
    while read -r ip
        echo $ip (join " " (ptr $ip))
    end
end

# list this machine's IP addresses
function ips
    ip -oneline addr show up primary scope global | while read num iface afam addr rest
        switch $afam
        case inet'*'
            echo $iface $addr
        end
    end
end
function addrs
    ips
end

# list this machine's MAC addresses
# format: <iface> <MAC addr>[\n<iface> <MAC addr>]*
function macs
    ip -s l sh | sed -n '
/^[0-9][0-9]*:/{
s/^[0-9][0-9]*: \([^:]*\).*/\1/
h
}
/^    link\/ether/{
s/^    link\/ether \([^ ]*\).*/ \1/
H
x
s/\n//
p
}
'
end

function bak
    for file in $argv
        mv -i $file $file.bak
    end
end

function unbak
    for file in $argv
        switch $file
        case '*.bak'
            # strip only the suffix; basename would also strip the
            # directory and move the file into $PWD
            test -e $file; and mv -i $file (string replace -r '\.bak$' '' -- $file)
        case '*'
            test -e $file.bak; and mv -i $file.bak $file
        end
    end
end

# ring the terminal's bell
function bell
    printf '\a'
end

# ask the user whether to do something, return true if they say yes or Enter
function confirm
    read --prompt-str "$argv? [Y/n] " REPLY
    switch "$REPLY"
    case Y y ''
        true
    case '*'
        false
    end
end

# print the first line of input (the header) as-is, run a command
# on the rest the input (the body)
# e.g. ps | body grep ps
#
# accepts an option -<number>, makes the header <number> lines
# instead of 1
# e.g. netstat -tn | body -2 grep ':22\>'
function body
    set lines 1
    switch $argv[1]
    case -'*'
        set lines (string sub --start 2 -- $argv[1])
        set --erase argv[1]
    end

    while test $lines -gt 0
        read header
        printf '%s\n' $header
        set lines (math $lines - 1)
    end
    $argv
end

# print the path from buildroot to $PWD
function builddir
    # string collect keeps an empty buildroot (no project) a string
    # rather than an empty list, so the comparison and trim below
    # degrade the same way shrc and nushell do instead of erroring.
    set buildroot (buildroot | string collect)
    if test "$PWD" = "$buildroot"
        printf '%s\n' .
    else
        # strip the trailing slash too, so a subdir prints as
        # "subdir" (not "/subdir"), matching shrc and nushell
        trim_prefix "$buildroot/" $PWD
    end
end

# print the directory that builds are relative to
function buildroot
    projectroot
end

# print the name of the current project
function projectname
    if set projectroot (projectroot | string collect)
        basename "$projectroot"
    end
end

# print the root directory of the current project
function projectroot
    return 1
end

# cd to the real directory that the specified file is in, resolving symlinks
function cdfile
    cd (realdir $argv[1] | string collect)
end

function delline
    sed -i -e $argv[1]d $argv[2]
end

# print the block device associated with the given mount point (or file)
function dev
    df -Pk $argv[1] | while read fs blocks used avail cap mount
        switch $mount
        case /'*'
            echo $fs
        end
    end
end

# run a command on each line of stdin
function each
    while read line
        $argv $line
    end
end

# run a command on each null-delimited parameter from stdin
function each0
    while read --null arg
        $argv $arg
    end
end

# print the name of a source file's corresponding test file
function find_test_file
    set file (basename $argv[1])
    set dir (dirname $argv[1])
    set dots (string split '.' $file)
    if test (count $dots) -ge 2
        set base (string join '.' $dots[1..-2])
        set ext .$dots[-1]
    else
        # no extension (e.g. "Makefile", a script): the whole name is
        # the base, so "foo" maps to "foo_test", not "_test.foo"
        set base $file
        set ext ''
    end

    test -n "$dir"; and set dir $dir/
    set testfile $dir$base'_test'$ext
    test -e $testfile; and printf '%s' $testfile
end

# see what changes a command would make to a file
# e.g. trydiff mdformat <file>
function trydiff
    set _temp $argv[2].trydiff.$fish_pid
    $argv[1] $argv[2] > $_temp
    diff $argv[2] $_temp
    rm $_temp
end

# search for a file in parent directories, print the first one found
function find_up
    set start_pwd $PWD
    set file $argv[1]
    set dir $argv[2]
    test -z $dir; and set dir .
    test $dir = .; and set dir $PWD

    if test -f $dir/$file
        printf '%s/%s' $dir $file
        cd $start_pwd
        return 0
    end
    if test $dir = /
        cd $start_pwd
        return 1
    end
    find_up $file (dirname $dir)
end

# replace a file with a sorted version of itself
function isort
    sort $argv[1] >$argv[1].bak
    mv $argv[1].bak $argv[1]
end

# join the arguments list by inserting a character between each element
# the first argument is the separator, the rest are the words to join
function join
    string join $argv[1] $argv[2..-1]
end

# make a directory and cd to it
function mcd
    if test -d $argv[1]
        printf "%s already exists\n" $argv[1]
    else
        mkdir -p $argv[1]; and cd $argv[1]
    end
end

# make a temporary directory and cd to it
function mtd
    cd (mktemp -d | string collect)
end

function names
    grep '^nameserver' /etc/resolv.conf
    nmcli dev list 2>/dev/null | sed -ne '/domain_name_servers/{s/[^ ]*: *//;p}'
end

# list non-empty files, prefixed by timestamp in case sorting is needed
function nonempty
    find . -size +0 $argv -printf '%T@ %f\n'
end

# print the full path to an executable, ignoring aliases and functions
function path
    command --search $argv[1]
end

# list processes in the specified process group
# pgroup <pgid> [<pgrep args>]
function pgroup
    pgrep -g $argv
end

# grep for a pattern in the environments of processes matching the given pattern
# pegrep <environment pattern> <process pattern>
# e.g. pegrep SSH_AUTH_SOCK xfce4
function pegrep
    for pid in (pgrep -f "^$argv[2]")
        printf '%s %s\n' (ps -o pid= -o args= -p $pid | string collect) (envgrep $argv[1] $pid | string collect)
    end
end
function peg; pegrep $argv; end

# grep for a pattern in the environment of processes with the given pids
# envgrep <environment pattern> <pid>...
function envgrep
    set pattern $argv[1]
    set --erase argv[1]
    for pid in $argv
        grep -z $pattern /proc/$pid/environ
    end
end

# ps with useful default options
function psc
    # user,pid,ppid,pgid,start_time,pcpu,rss,comm are first, followed by any -o option
    # the user supplies, then args are last.
    ps -w -o user,pid,ppid,pgid,start_time,pcpu,rss,comm=EXE $argv -o args=ARGS
end

# pgrep with default ps options
# psgrep [<ps options>] <pattern>
function psgrep
    set ps_args $argv[1..-2]
    set pattern $argv[-1]

    set pids (pgrep -d , -f $pattern | string collect)
    if test -n "$pids"
        psc -p $pids $ps_args
    else
        error "No processes matching $pattern"
        return 1
    end
end

# print the absolute path of the directory containing the specified file
function realdir
    dirname (readlink -f $argv[1] | string collect)
end

# show the most recently changed files
# defaults to the showing the last 10, override with -<number>
function recent
    set lines 10
    # numeric options only (-3): other flags pass through to ls; switch
    # can't do this because fish wildcards have no [0-9] character class
    if string match -rq -- '^-[0-9]+$' "$argv[1]"
        set lines (string sub --start 2 -- $argv[1])
        set --erase argv[1]
    end
    ls -t -1 $argv | head -n $lines
end

# keep trying a command until it works
# (e.g. retry ping -c 1 host)
# (e.g. retry --sleep 1 ping -c 1 host)
function retry
    set sleep 10
    if test "$argv[1]" = --sleep
        set sleep $argv[2]
        set --erase argv[1..2]
    else if string match -q -- '--sleep=*' "$argv[1]"
        set sleep (string replace -- '--sleep=' '' $argv[1])
        set --erase argv[1]
    end
    while true
        if $argv
            bell
            break
        else
            sleep $sleep
        end
    end
end

# remove the ssh known host from the specified line number
function rmkey
    delline $argv[1] $HOME/.ssh/known_hosts
end

# run a command with the first argument moved to the end
# e.g. first_arg_last grep ~/.history <args> runs grep <args> ~/.history
function first_arg_last
    set command $argv[1]
    set arg $argv[2]
    set --erase argv[1..2]
    $command $argv $arg
end

# Pass leading -x options of a command to a different first positional arg.
# shift_options <command> <target> [-x ...] [args...]
# Runs `<command> [-x ...] <target> [args...]`.
function shift_options
    set _command $argv[1]
    set _target $argv[2]
    set --erase argv[1..2]
    set _options
    while test (count $argv) -gt 0
        switch $argv[1]
        case '-' '--'
            break
        case '-*'
            set --append _options $argv[1]
            set --erase argv[1]
        case '*'
            break
        end
    end
    $_command $_options $_target $argv
end

# convert a time from one timezone to another
# tz2tz <from timezone> <to timezone> <date spec>
function tz2tz
    set from $argv[1]
    set to $argv[2]
    set --erase argv[1..2]
    set epoch (env TZ=$from date -d "$argv" +%s); or return 1
    env TZ=$to date -d "@$epoch"
end


# convert from UTC to local time
function utc2
    date -d 'TZ="UTC" '$argv[1]
end

# hook to run the given command under a custom ssh-agent
function with_agent
    $argv
end

# print the definition of the given command, alias, or function
function what
    type $argv[1]
end

##################################
# ENVIRONMENT SETUP FOR ALL SHELLS
# Set $PATH early in case other stuff here needs it.

set --export CDPATH . $HOME
# keep an inherited GOPATH (e.g. from ~/.env.local) instead of clobbering
# it. test -n rather than set --query so a set-but-empty GOPATH still gets
# the default, matching shrc's ${GOPATH:-$HOME}.
test -n "$GOPATH"; or set --export GOPATH $HOME

add_path /usr/local/bin
add_path $HOME/android-sdk-linux/platform-tools
add_path $HOME/android-studio/bin
add_path $HOME/Android/Sdk/platform-tools
add_path $HOME/depot_tools
add_path $HOME/google-cloud-sdk/bin
add_path $HOME/.cargo/bin
add_path $HOME/.local/bin
add_path $HOME/bin start
add_path $GOPATH/bin start
add_path $HOME/scripts start
# scripts.home, scripts.work, etc. override scripts
for dir in $HOME/scripts.*
    add_path $dir start
end
for dir in /opt/*/bin
    add_path $dir end
end
add_path /sbin end
add_path /usr/sbin end
# Load Homebrew. brew is often off-PATH (Linuxbrew lives under a prefix not on
# the default PATH), so fall back to known locations. $BREW overrides the
# search (tests). Mirrors setup_brew in shrc.
if have_command brew
    brew shellenv | source
else
    for brew_bin in $BREW /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew $HOME/.linuxbrew/bin/brew
        if test -x "$brew_bin"
            $brew_bin shellenv | source
            break
        end
    end
end

# fnm (Fast Node Manager): put its dir on PATH, then load its shell
# environment. The standalone installer lives in that dir, but a
# Homebrew/Cargo/release install puts fnm elsewhere on PATH and creates
# the data dir via `fnm env`, so don't gate the eval on the dir. The
# default install dir mirrors fnm's own installer (legacy ~/.fnm, else
# $XDG_DATA_HOME/fnm, else the macOS Application Support dir, else
# ~/.local/share/fnm); FNM_PATH overrides. Mirrors setup_fnm in shrc and
# config.nu.
set -l _fnm_path
if test -n "$FNM_PATH"
    set _fnm_path $FNM_PATH
else if test -d $HOME/.fnm
    set _fnm_path $HOME/.fnm
else if test -n "$XDG_DATA_HOME"
    set _fnm_path $XDG_DATA_HOME/fnm
else if test (uname -s) = Darwin
    set _fnm_path "$HOME/Library/Application Support/fnm"
else
    set _fnm_path $HOME/.local/share/fnm
end
test -d $_fnm_path; and add_path $_fnm_path start
if have_command fnm
    fnm env --shell fish | source
end

# set HISTORY_FILE for log_history
set --export HISTORY_FILE $HOME/.history

set --export LESS "-R"
if test -f $HOME/scripts/lessopen
    set --export LESSOPEN "|$HOME"'/scripts/lessopen "%s"'
end

test -r $HOME/.inputrc; and set --export INPUTRC $HOME/.inputrc
test -r $HOME/.editrc; and set --export EDITRC $HOME/.editrc

# default programs
# kitty wants EDITOR to be set even for non-interactive shells
is_runnable vi; and set --export EDITOR vi
is_runnable vim; and set --export EDITOR vim
is_runnable editline; and set --export EDITOR editline
is_runnable more; and set --export PAGER more
is_runnable less; and set --export PAGER less
is_runnable meld; and test -n "$DISPLAY"; and set --export DIFF meld

# program defaults
set --export BLOCKSIZE 1024
set --export CLICOLOR true
set --export GREP_COLOR 4     # BSD grep and older GNU grep - underline matches
set --export GREP_COLORS 'mt=4'  # GNU grep - underline matches

# colors for ls
switch $TERM
case linux putty vt220
    # colors for white on black
    set --export LSCOLORS 'ExFxxxxxCxxxxx'
    set --export LS_COLORS 'no=00:fi=00:di=01;34:ln=01;35:so=00;00:bd=00;00:cd=00;00:or=01;31:pi=00;00:ex=01;32'
case '*'
    # colors for black on white
    set --export LSCOLORS 'exfxxxxxcxxxxx'
    set --export LS_COLORS 'no=00:fi=00:di=00;34:ln=00;35:so=00;00:bd=00;00:cd=00;00:or=00;31:pi=00;00:ex=00;32'
end

function switchshpool
    autoshpool switch $argv[1]; and exit
end

# Name of the preferred session manager: "shpool" (the default when both are
# available), "tmux" (the fallback), or empty when neither is enabled/installed.
# $SESSION_BACKEND flips the preference: set it to "tmux" to prefer tmux with
# shpool as the fallback, or "shpool" (the default when unset) to prefer shpool
# with tmux as the fallback. The WANT_TMUX=0 / WANT_SHPOOL=0 opt-outs still
# disable each backend regardless of the preference.
function session_backend
    set -l _pref (test -n "$SESSION_BACKEND"; and echo $SESSION_BACKEND; or echo shpool)
    if test "$_pref" = tmux
        if test "$WANT_TMUX" != 0; and have_command tmux; and have_command autotmux
            echo tmux
        else if test "$WANT_SHPOOL" != 0; and have_command shpool; and have_command autoshpool
            echo shpool
        end
    else
        if test "$WANT_SHPOOL" != 0; and have_command shpool; and have_command autoshpool
            echo shpool
        else if test "$WANT_TMUX" != 0; and have_command tmux; and have_command autotmux
            echo tmux
        end
    end
end

# Attach to (or create) this project's session using the preferred backend.
function autosession
    switch (session_backend)
    case tmux
        autotmux $argv
    case shpool
        autoshpool $argv
    end
end

# Switch to a session using the preferred backend. tmux switches in place
# (autotmux switch); shpool requests a switch and exits the current shell.
function switchsession
    switch (session_backend)
    case tmux
        autotmux switch $argv[1]
    case shpool
        switchshpool $argv[1]
    end
end

# Attach to a (named) session using the preferred backend.
function sessionattach
    switch (session_backend)
    case tmux
        tmux attach $argv
    case shpool
        shpool attach $argv
    end
end

# Detaching and making named sessions live in the scripts repo as the
# detachsession/detachtmux/detachshpool and makesession/maketmux/makeshpool
# commands (dispatchers + per-backend twins, alongside autosession and
# changesession). The ds*/ms* aliases below call those scripts.

# List sessions using the preferred backend (tmuxlist / shpoollist).
function sessionlist
    switch (session_backend)
    case tmux
        tmuxlist $argv
    case shpool
        shpoollist $argv
    end
end

function maybe_start_session_and_exit
    switch (session_backend)
    case shpool
        want_shpool; and autoshpool; and exit
    case tmux
        want_tmux; and autotmux; and exit
    end
end

# ssh to a host from ~/.ssh/config, telling the remote who is connecting
# via LC_CLIENT_HOST (read back with ssh_client_host). set -lx keeps the
# override function-local and exported: it reaches ssh/rw and their
# children, is restored when ssh_to returns (so a LC_CLIENT_HOST inherited
# from an inbound SSH session survives chained hops), and never leaks into
# the interactive shell -- matching the subshell-confined bash/zsh path.
# Set before the branch so both paths carry it; SendEnv is additive, so
# the usual LANG/LC_* forwarding is left intact.
function ssh_to
    set -lx LC_CLIENT_HOST (short_hostname | string collect)
    if have_command rw; and test (count $argv) -eq 1
        rw -r $argv
    else
        # ssh flags the user typed after the host alias must be moved
        # in front of the host, or ssh runs them as the remote command
        # (e.g. `somehost -v uptime` remotely ran `-v uptime`). Unlike
        # shift_options, honor ssh flags whose value is a separate word
        # (-p 2222, -i file, -o opt, ...): the value must travel with
        # its flag, not stop the scan (`somehost -p 2222 uptime` must
        # not pass `-p somehost`). The flag list is OpenSSH's usage
        # line's value-taking options.
        set -l _host $argv[1]
        set --erase argv[1]
        # Count the leading option words (flags plus their values);
        # everything after them is the remote command.
        set -l _nopts 0
        set -l _expect_value 0
        for _arg in $argv
            if test $_expect_value -eq 1
                set _expect_value 0
                set _nopts (math $_nopts + 1)
                continue
            end
            switch $_arg
            case '--'
                # end of options: rotate it along with the options so
                # it lands before the host (ssh accepts
                # `ssh [options] -- destination [command]`), and
                # everything after it is the remote command even if it
                # starts with a dash.
                set _nopts (math $_nopts + 1)
                break
            case '-'
                break
            case '-B' '-b' '-c' '-D' '-E' '-e' '-F' '-I' '-i' '-J' '-L' '-l' '-m' '-O' '-o' '-P' '-p' '-Q' '-R' '-S' '-W' '-w'
                set _expect_value 1
                set _nopts (math $_nopts + 1)
            case '-*'
                set _nopts (math $_nopts + 1)
            case '*'
                break
            end
        end
        # Slice rather than rotate: fish reverses a range whose start
        # exceeds its end, so guard the empty slices explicitly.
        set -l _opts
        set -l _cmd
        if test $_nopts -gt 0
            set _opts $argv[1..$_nopts]
        end
        if test $_nopts -lt (count $argv)
            set _cmd $argv[(math $_nopts + 1)..-1]
        end
        ssh -t -oSendEnv=LC_CLIENT_HOST $_opts $_host $_cmd
    end
end

function set_up_ssh_aliases
    set _ssh_config $HOME/.ssh/config
    test -f $_ssh_config; or return 0

    while read _line
        set _match (string match --regex '^[[:space:]]*[Hh]ost[[:space:]]+(.*)$' -- $_line)
        test -n "$_match"; or continue
        set _hosts (string replace --all --regex '[[:space:]]+' ' ' -- $_match[2] | string trim | string split --no-empty ' ')
        for _alias in $_hosts
            switch $_alias
            case '*\**' '*\?*' '*-*'
                continue
            end
            eval "function $_alias; ssh_to $_alias \$argv; end"
        end
    end <$_ssh_config
end

#########################
# INTERACTIVE SHELL SETUP
# Set up the prompt, title, key bindings, etc.

if is_interactive
    # Transitional fallback: the updated scripts-repo helpers open the session in
    # the right directory via `shpool attach -d`, leaving SHPOOL_INITIAL_PWD
    # unset (this block a no-op). Until that ships everywhere
    # (mikelward/scripts#107), the older helpers still stamp SHPOOL_INITIAL_PWD
    # (forwarded via the shpool config's forward_env), so cd there on entry.
    # Remove this block and the forward_env entry once the scripts update is
    # deployed.
    if in_shpool; and test -n "$SHPOOL_INITIAL_PWD"
        cd $SHPOOL_INITIAL_PWD
        set --erase SHPOOL_INITIAL_PWD
    end
    maybe_start_session_and_exit

    # Past this point we're the shell we're keeping (the handoff exits if it
    # started a session). Build the ssh-config host aliases here -- an
    # interactive convenience a launcher/handoff skips.
    set_up_ssh_aliases

    log_history "New session as $USERNAME: $0 $argv"

    # use custom vi-like key bindings (emacs bindings layered on vi mode)
    set -g fish_key_bindings my_vi_key_bindings

    # regain use of Ctrl+S and Ctrl+Q. Guard with `isatty stdin` so
    # config.fish doesn't SIGTTOU-hang when sourced in an interactive-
    # but-non-tty context (parallel test runs under `make -j`, fish -i
    # under nohup, etc.): stty calls tcsetattr on the controlling tty,
    # which fires SIGTTOU when the caller's process group isn't the
    # foreground. 2>/dev/null alone doesn't help -- SIGTTOU is a signal,
    # not stderr.
    if isatty stdin
        stty start undef stop undef 2>/dev/null
    end

    # mirror zsh's `zle_highlight=(default:bold)` so user input stands out.
    set -g fish_color_command --bold

    # determine the graphics mode escape sequences
    set --global color false
    if is_runnable tput
        if quiet tput longname
            set bold (tput bold | string collect)
            set underline (tput smul | string collect)
            set standout (tput smso | string collect)
            set normal (tput sgr0 | string collect)
            set black (tput setaf 0 | string collect)
            set red (tput setaf 1 | string collect)
            set green (tput setaf 2 | string collect)
            set yellow (tput setaf 3 | string collect)
            set blue (tput setaf 4 | string collect)
            set magenta (tput setaf 5 | string collect)
            set cyan (tput setaf 6 | string collect)
            set white (tput setaf 7 | string collect)
            set --global color true

            set khome (tput khome | string collect)
            set kend (tput kend | string collect)
            set kdch1 (tput kdch1 | string collect)
        end
    end

    # determine the window title escape sequences
    switch $TERM
    case aixterm dtterm putty rxvt xterm'*'
        set titlestart (printf '\e]0;')
        set titlefinish (printf '\a')
    case cygwin
        set titlestart (printf '\e];')
        set titlefinish (printf '\a')
    case konsole
        set titlestart (printf '\e]30;')
        set titlefinish (printf '\a')
    case screen'*'
        # window title
        # screen/tmux are responsible for setting the terminal title
        set titlestart (printf '\ek')
        set titlefinish (printf '\e\\')
    case '*'
        if is_runnable tput
            if quiet tput longname
                set titlestart (tput tsl | string collect)
                set titlefinish (tput fsl | string collect)
            end
        else
            set titlestart ''
            set titlefinish ''
        end
    end

    # prevent running "exit" if the user is still running jobs in the background
    # the user is expected to close the jobs or disown them
    function _exit
        if jobs -q
            jobs
        else
            exit 0
        end
    end

    function path_or_empty
        type --force-path $argv[1]
        or printf ''
    end

    #alias '?'='path_or_empty'
    alias @='path_or_empty'
    # Session-manager verbs, named {verb}{backend}: verb is a(uto), c(hange),
    # d(etach), or m(ake); backend is s (session: pick tmux/shpool via
    # session_backend), sp (shpool), or tm (tmux). The *s spellings follow the
    # active backend; *sp/*tm force one. auto* attach-or-create at startup,
    # change* are the fzf switchers, detach*/make* detach or create named
    # sessions. change*/detach*/make* and the autoshpool/autotmux binaries live
    # in the scripts repo; autosession/switch* stay shell wrappers.
    #
    # cs/ds/ms are functions, not aliases, so they can pass session_backend
    # (which honours WANT_SHPOOL/WANT_TMUX and the $SESSION_BACKEND preference)
    # as SESSION_BACKEND: the *s scripts dispatch on
    # $TMUX/$SHPOOL_SESSION_NAME/$SESSION_BACKEND then fall back to whichever
    # backend is installed (shpool first), so an opted-in tmux user
    # (WANT_SHPOOL=0) outside a session would otherwise get the scripts'
    # default -- the scripts can't see the WANT_* opt-outs. When
    # session_backend is empty and we aren't in a session they no-op
    # rather than trigger that fallback. cs additionally exits after a shpool
    # switch (the script
    # detaches us and the outer autoshpool loop attaches the target, like
    # switchshpool's `and exit`). changesession dispatches on $TMUX before
    # $SHPOOL_SESSION_NAME, so a tmux session nested in shpool switches in place
    # and must stay: only exit when shpool was picked (in shpool, not in tmux).
    # A cancelled picker returns non-zero so we stay. csp forces shpool. Capture
    # the picker's status and run the exit guard separately (same as ms/msp): a
    # successful switch that doesn't exit -- an in-place tmux switch, or an
    # attach/detach from outside any session -- must still return the picker's
    # own status (0), not the failed guard's 1.
    alias as='autosession'
    alias asp='autoshpool'
    alias atm='autotmux'
    function cs; set -lx SESSION_BACKEND (session_backend); test -n "$TMUX$SHPOOL_SESSION_NAME$SESSION_BACKEND"; or return; changesession $argv; set -l rc $status; test $rc -eq 0; and test (count $argv) -eq 0; and test -z "$TMUX"; and test -n "$SHPOOL_SESSION_NAME"; and exit; return $rc; end
    function csp; changeshpool $argv; set -l rc $status; test $rc -eq 0; and test (count $argv) -eq 0; and test -n "$SHPOOL_SESSION_NAME"; and exit; return $rc; end
    alias ctm='changetmux'
    function ds; set -lx SESSION_BACKEND (session_backend); test -n "$TMUX$SHPOOL_SESSION_NAME$SESSION_BACKEND"; and detachsession $argv; end
    alias dsp='detachshpool'
    alias dtm='detachtmux'
    # make* mirror change*'s exit handling: inside a shpool session makeshpool
    # hands the new session to autoshpool's loop via request_switch (detaching
    # us), so the parked shell must exit. make always targets a named session
    # (no no-arg picker path), so there's no count==0 gate; exit when shpool was
    # the backend that ran (in shpool, not tmux). msp forces shpool. Capture the
    # make's status and run the exit guard separately so a make that succeeds but
    # doesn't exit still returns its own status, not the failed guard's 1.
    function ms; set -lx SESSION_BACKEND (session_backend); test -n "$TMUX$SHPOOL_SESSION_NAME$SESSION_BACKEND"; or return; makesession $argv; set -l rc $status; test $rc -eq 0; and test -z "$TMUX"; and test -n "$SHPOOL_SESSION_NAME"; and exit; return $rc; end
    function msp; makeshpool $argv; set -l rc $status; test $rc -eq 0; and test -n "$SHPOOL_SESSION_NAME"; and exit; return $rc; end
    alias mtm='maketmux'
    alias bindkeys='daemon xbindkeys'
    set code_patterns "*.c" "*.h" "*.cc" "*.cpp" "*.hh" "*.coffee" "*.go" "*.hs" "*.java" "*.js" "*.pl" "*.py" "*.sh" "*.rb" "*.swig" "*.ts"
    alias c='less -FX'
    alias cdf='cdfile'
    function rd; cd (projectroot); end
    # one --glob per pattern, expanded as a list (the old quoted
    # "$code_includes" collapsed to a single argument, and --include is a
    # GNU grep option that ripgrep rejects)
    function cg
        rg "--glob="$code_patterns $argv
    end
    alias ct='ctags -R'
    alias cx='chmod +x'
    alias cc='codeconfig'
    function codeconfig
        makemakefile
        maketasks
        makesettings
        makeensime
        makelocal
    end
    function codelocal
        code --new-window .
    end
    alias d='codeconfig; codelocal'
    function daemon
        pkill $argv[1]
        # background and disown so the daemon detaches from this shell
        # (shrc runs it as `(setsid "$1"&)`)
        setsid $argv[1] &
        disown
    end
    alias diga='dig +noall +answer +search'
    alias digs='dig +short +search'
    function download; cd $HOME/Downloads; wget $argv; end
    # not an alias: '$EDITOR' unset would execute the file argument itself
    function e
        set -l editor $EDITOR
        test -n "$editor"; or set editor vim
        $editor $argv
    end
    alias eg='g -E'
    alias emacs='emacs -nw'
    alias f='command fg'
    alias g='grep -In'
    alias gdb='gdb -q '
    # Note that grep options must go after ~/.history.
    alias gh='first_arg_last grep ~/.history -a'
    alias gitdir='git rev-parse --git-dir'
    alias gl='cd /var/log'
    alias h='head'
    alias headers='curl -L -i -sS -o/dev/null -D-'
    alias hms='date +"%H:%M:%S"'
    alias hmsns='date +"%H:%M:%S.%N"'
    alias hosts='getent hosts'
    alias ipy='ipython'
    alias ipy3='ipython3'
    alias killcode='pkill -f /usr/share/code/code'
    alias kssh='ssh -o PreferredAuthentications=publickey'
    if have_command l
        alias l='l -Kv -e -x'
        alias ll='l -pTBV -h --time-style=relative'
        alias lt='l -Tt'
    else if quiet ls --color=auto -v -d /
        alias l='ls --color=auto -v -b -x'
        alias ll='l -l'
        alias lt='ll -t'
    else
        alias l='ls -v -b -x'
        alias ll='l -l'
        alias lt='ll -t'
    end
    alias l1='l -1'
    alias la='l -a'
    alias latest='recent -1'
    alias lc='l -C'
    function lssock
        lsof -a -n -P -i $argv
    end
    alias lss='lssock'
    alias j='jobs'
    # Clone/cd into a repo, then start a session (shpool by default, tmux
    # when WANT_SHPOOL=0 or shpool is missing) matching the new vcs rootdir.
    # autosession only runs
    # if the underlying command succeeds, so a failed clone/cd doesn't spawn
    # a stray session. Functions rather than aliases so `and autosession`
    # runs after the command instead of having $argv appended to it.
    function jd; jjd $argv; and autosession; end
    function hd; hgd $argv; and autosession; end
    function gd; gitd $argv; and autosession; end
    function mjd; jjd -f $argv; and autosession; end
    function mhd; hgd -f $argv; and autosession; end
    function mgd; gitd -f $argv; and autosession; end
    alias m='make -f .Makefile'
    alias ml='m lint'
    # shadows magtape command, but who uses that?
    alias mt='m test'
    alias now='date +"%Y-%m-%dT%H:%M:%S"'
    alias nowns='date +"%Y-%m-%dT%H:%M:%S.%N"'
    alias nv='nvim'
    function p
        set -l pager $PAGER
        test -n "$pager"; or set pager more
        $pager $argv
    end
    alias pgrep,='pgrep -d , -f'
    alias pg,='pgrep'
    alias phup='pkill -HUP'
    alias popd='popd >/dev/null'
    alias psg='psgrep'
    alias psu='ps -o user,pid,start,time,pcpu,stat,cmd'
    alias pushd='pushd >/dev/null'
    alias pd='pushd'
    alias po='popd'
    alias pssh='ssh -o PreferredAuthentications=keyboard-interactive,password'
    alias pr='projectroot'
    alias py='python'
    alias py2='python2'
    alias py3='python3'
    alias rerc='source $HOME/.config/fish/config.fish'
    alias rg='command rg --follow --line-number'
    function rh
        gh $argv | tail -n 20
    end
    alias q='xa'
    alias s='subl'
    alias spell='aspell -a'
    alias sr='ssh -l root'
    alias symlink='ln -sr'
    alias t='tail'
    alias tf='t -f'
    alias tl='t -f /var/log/syslog'
    alias today='date +"%Y-%m-%d"'
    alias ts='t -f /var/log/syslog'
    alias userctl='systemctl --user'
    alias userjournal='journalctl --user'
    alias userjnl='userjournal'
    alias v='view'
    alias view='vim -R -c ":set mouse="'
    alias vl='view /var/log/syslog'
    alias wcp='with_agent scp'
    alias wsh='with_agent ssh'
    alias x='xa'
    function xa
        while builtin fg 2>/dev/null
            :
        end
        _exit
    end
    alias xevkey='xev -event keyboard'
    alias xr='DISPLAY=:0.0 xrandr'

    # in case root isn't available, fall back to sudo
    if not have_command root
        alias sudo='root'
    end

    # enable colors in commands that support it
    # (ls is done above)
    quiet grep -q --color=auto "" /etc/hosts; and alias grep='grep --color=auto'
    set --export CLICOLOR true

    # TODO
    #alias ginfo='(path info)'
    # aliases to abstract away differences between package managers
    # delegates to the `package` script, which dispatches to dnf, yum,
    # or apt-get depending on what's available
    alias update='package update'
    alias search='package search'
    alias install='package install'
    alias installed='package installed'
    alias uninstall='package uninstall'
    alias reinstall='package reinstall'
    alias autoremove='package autoremove'
    alias upgrade='package upgrade'
    alias versions='package versions'
    alias info='package info'
    alias files='package files'
    alias listfiles='package listfiles'
    alias depends='package depends'
    alias rdepends='package rdepends'

    # make %<num> resume jobs
    # this matches the first column in the prompt output
    alias %='fg'
    for i in (seq 0 9)
        alias %$i='fg %$i'
    end

    function fish_greeting
    end

#    # set a basic prompt that doesn't rely on precommand and preprompt hooks
#    function basic_prompt
#        set PS1 '$ '
#        set PS2 '_ '
#        set PS3 '#? '
#        set_title (title | string collect)
#    end
#
    function preexec --on-event fish_preexec
        log_history "$argv"
        set --global last_job_status 0
        set --global current_command $argv
        #set_title (title | string collect)
        my_set_color 'normal'
        #set SECONDS 0
    end

    function postexec --on-event fish_postexec
        set --global last_job_status $status
        last_job_info
        set current_command
    end

    # Spawn a detached background fetch via the vcs binary, which knows
    # the right fetch command per VCS (git/hg/jj), the per-VCS marker
    # file to mtime-gate against, and how to detach the spawned process.
    # Called from fish_prompt; this function only owns:
    #   - PWD-change gate: most prompts don't follow a cd, so early-return.
    #   - auth gate: skip when auth_info reports problems so the prompt's
    #     {behind} indicator still nags.
    function maybe_background_fetch
        if set -q _LAST_BG_FETCH_PWD; and test "$PWD" = "$_LAST_BG_FETCH_PWD"
            return
        end
        set --global _LAST_BG_FETCH_PWD $PWD
        have_command vcs; or return
        set _auth (auth_info | string collect)
        test -z "$_auth"; or return
        # `command` skips any `vcs` function wrapper so the call goes
        # straight to the binary on PATH.
        command vcs auto-fetch >/dev/null 2>&1
    end

    function fish_prompt
        my_set_color 'normal'
        maybe_background_fetch
        # Warm the session name once so host_info and title reuse it instead
        # of each forking `tmux display-message`. Erased at the end so the
        # cache is scoped to this render and direct callers stay fresh.
        set -g _session_name (session_name | string collect)
        printf '\n'
        bar $COLUMNS
        printf '\r%s \n' (prompt_line | string collect)
        vcs unmerged 2>/dev/null
        job_info
        publish_jobs
        set_title (title | string collect)
        ps1
        flash_terminal
        set -e _session_name
    end

    # wrapper around `vcs prompt-info` so dir_info (and anything else that
    # wants VCS prompt data) can stub it out cheaply in tests.
    function prompt_info
        command vcs prompt-info $argv
    end

    # print the hostname and session tag for the preprompt line.
    # Hostname is red on production hosts. The session tag is a green
    # session name when attached to a shpool or tmux session, or a yellow
    # warning naming the backend that would start when not: $SESSION_BACKEND
    # if set, else the session_backend the gating would pick (shpool by
    # default), falling back to shpool.
    function host_info
        set _host (short_hostname | string collect)
        if on_production_host
            set _host (red $_host | string collect)
        end
        set _root_info ""
        if i_am_root
            set _root_info "["(red 'root' | string collect)"] "
        end
        set _tag
        set _session (prompt_session_name | string trim)
        if test -n "$_session"
            set _tag " "(green $_session | string collect)
        else
            set _backend $SESSION_BACKEND
            test -z "$_backend"; and set _backend (session_backend | string collect)
            test -z "$_backend"; and set _backend shpool
            set _tag " "(yellow $_backend | string collect)
        end
        printf '%s%s%s' $_root_info $_host $_tag
    end

    # replace a leading $HOME in $PWD with "~"
    function tilde_pwd
        set _cwd $PWD
        if test "$_cwd" = "$HOME"
            echo '~'
        else if string match --quiet "$HOME/*" $_cwd
            echo '~'(string sub --start=(math --scale=0 (string length $HOME) + 1) $_cwd)
        else
            echo $_cwd
        end
    end

    # print the directory info for the preprompt line. Try `vcs prompt-info`
    # (one fork); outside a repo the binary prints nothing and exits
    # non-zero, so we fall back to a tilde-expanded $PWD. The whole thing
    # is wrapped in blue.
    function dir_info
        set _color_flag --color=never
        if $color
            set _color_flag --color=always
        end
        set _info (prompt_info $_color_flag 2>/dev/null | string collect)
        if test -z "$_info"
            set _info (tilde_pwd | string collect)
        end
        blue $_info
    end

    # print the first line of the preprompt: host + dir + auth.
    # Composed in-shell from host_info, dir_info, and auth_info. The VCS
    # part is delegated to `vcs prompt-info`; the rest is pure fish.
    # auth_info is captured once so ssh-add -L runs a single time per
    # prompt (need_auth would double that).
    function prompt_line
        set _auth (auth_info | string collect)
        set _out (host_info | string collect)" "(dir_info | string collect)
        if test -n "$_auth"
            set _out "$_out $_auth"
        end
        echo $_out
    end

    function last_job_info
        # Must be the very first thing.
        set last_error (fish_last_error)

        test -z $current_command; and return

        my_set_color 'normal'
        set printed false
        if test -n "$last_error"
            red $last_error
            set printed true
        end
        set duration (format_duration $CMD_DURATION)
        if test -n "$duration"
            if $printed
                printf ' '
            end
            yellow "took $duration"
            set printed true
        end
        if $printed
            printf '\n'
        end
    end

    function format_duration
        set millis $argv
        set seconds (math --scale=0 $millis/1000)
        set hours (math --scale=0 $seconds/3600)
        set seconds (math --scale=0 $seconds-$hours\*3600)
        set minutes (math --scale=0 $seconds/60)
        set seconds (math --scale=0 $seconds-$minutes\*60)
        if test $hours -gt 0
            echo "$hours hours $minutes minutes $seconds seconds"
        else if test $minutes -gt 0
            echo "$minutes minutes $seconds seconds"
        else if test $seconds -gt 1
            echo "$seconds seconds"
        end
    end

    function fish_last_error
        # Mirror bash_last_error / nushell last-job-info: 0 is silent,
        # 130 (SIGINT / Ctrl-C) renders as "interrupted", 148 (SIGTSTP /
        # suspended) is silent, anything else renders as "status N".
        switch $last_job_status
            case 0 148
            case 130
                echo "interrupted"
            case '*'
                echo "status $last_job_status"
        end
    end

    # get the user's attention
    function flash_terminal
        switch $TERM
        case xterm xterm-'*'
            bell
        end
    end

    # return true if the current user is root
    function i_am_root
        test $UID -eq 0
    end

    # return true if this machine is my laptop
    function _on_my_laptop
        if test -f $HOME/.laptop
            true
        else
            switch $HOSTNAME
            case '*laptop*'; true
            case '*'; false
            end
        end
    end

    # return true if this machine is my laptop
    function on_my_laptop
        if test -z $laptop
            if _on_my_laptop
                set --global laptop true
            else
                set --global laptop false
            end
        end
        $laptop
    end

    # return true if this is a non-production machine I use to get work done
    function on_my_machine
        on_my_workstation; or on_my_laptop
    end

    # return true if it's already obvious which host I'm on
    function show_hostname_in_title
        not inside_tmux
    end

    # return true if this machine is a production machine
    function on_production_host
        not on_my_machine; and not on_test_host; and not on_dev_host
    end

    # return true if this machine is a test (i.e. non production) machine
    function on_test_host
        switch $HOSTNAME
        case '*test*'; true
        case '*'; false
        end
    end

    function on_dev_host
        switch $HOSTNAME
        case '*dev*'; true
        case '*'; false
        end
    end

    # print a leading space before $argv if $argv is non-empty
    function maybe_space
        test -n "$argv"; and printf ' %s' "$argv"
    end

    # print $argv[1] "―" characters (used as a separator in the prompt)
    function bar
        set _width $argv[1]
        set _i 0
        while test $_i -lt $_width
            printf '―'
            set _i (math $_i + 1)
        end
    end

    # print the current session name (shpool or tmux), with a trailing space.
    # Callers that want a bare name (e.g. for a bracketed tag) trim the space.
    function session_name
        if in_shpool
            printf '%s ' $SHPOOL_SESSION_NAME
        else if inside_tmux
            printf '%s ' (tmux display-message -p '#S' | string collect)
        end
    end

    # Resolve the session name for the current prompt. fish_prompt warms
    # $_session_name once per render so host_info and title reuse it instead
    # of each forking `tmux display-message`. The variable being set (even
    # empty) means warmed; fish_prompt erases it after the render, so direct
    # callers (e.g. tests) fall back to session_name.
    function prompt_session_name
        if set -q _session_name
            printf '%s' $_session_name
        else
            session_name
        end
    end

    # print information about all shell jobs on a single line,
    # intended to be used in the preprompt.
    #
    # fish's `jobs` builtin emits a tab-separated table where the
    # first column is the job id and the last column is the full
    # command line. CPU is an optional middle column on systems
    # that support it (per the fish docs), so we deliberately don't
    # index by position past the first field -- splitting on tab and
    # taking $fields[1] / $fields[-1] survives the missing-CPU case.
    # The old bash-style "[N]+ Running cmd" sed pipeline never
    # matched fish's output and passed the raw table through. Now we
    # produce the same "%N command args & %M command args &" single-
    # line shape shrc emits, so callers (preprompt, publish_jobs)
    # get the same data model in either shell.
    function job_info
        set -l _entries
        for _line in (jobs)
            set -l _fields (string split \t -- $_line)
            # Skip the header row (its first field is "Job", not numeric).
            string match --quiet --regex '^[0-9]+$' -- $_fields[1]; or continue
            # Skip the preprompt's own vcs plumbing. maybe_background_fetch
            # and the vcs wrapper shell out via `command vcs ...`; those can
            # surface as transient job entries and would otherwise leak into
            # the job list the preprompt prints. A user's deliberate `vcs foo
            # &` shows as `vcs foo`, not `command vcs`, so it survives. Parity
            # with shrc's job_info `command vcs` filter.
            string match --quiet --regex '^command vcs( |$)' -- $_fields[-1]; and continue
            set --append _entries "%$_fields[1] $_fields[-1]"
        end
        if test (count $_entries) -gt 0
            string join ' ' $_entries
        end
    end

    # Resolve the per-shell file publish_jobs writes a short summary
    # of the current shell's job table to so a status-bar consumer
    # (tmux, screen, ...) can display it without querying a foreign
    # shell's job table. Keyed by $TTY rather than a multiplexer-
    # specific pane id so the same scheme works in any multiplexer,
    # and outside of one. Empty (and publishing is silently disabled)
    # when $TTY isn't a /dev/... path or when $XDG_RUNTIME_DIR isn't
    # set -- a /tmp fallback would be a predictable, per-uid path
    # that a local attacker could pre-create as a symlink for the
    # prompt to truncate. $XDG_RUNTIME_DIR is per-user mode 0700 on
    # modern Linux. Cached in _publish_jobs_file.
    function publish_jobs_file
        if not set --query _publish_jobs_file
            set --global _publish_jobs_file ""
            if test -n "$XDG_RUNTIME_DIR"; and string match --quiet --regex '^/dev/.+' -- $TTY
                set --global _publish_jobs_file "$XDG_RUNTIME_DIR/shell-jobs$TTY"
            end
        end
        echo $_publish_jobs_file
    end

    # Write a single-line "%N command %M command ..." summary of the
    # current shell's job table to publish_jobs_file (e.g. "%1 vi %2
    # tail"). Called from fish_prompt so the value refreshes on every
    # prompt redraw. job_info emits "%N command args & %M command
    # args &" (one line, all jobs joined) in the same shape shrc
    # uses; we walk the fields, grab the word after each "%N" token,
    # and drop the trailing args. An empty file means "no jobs", so
    # the consumer can just `cat` the file without further parsing.
    # No-op when the publish file can't be resolved (no tty).
    function publish_jobs
        set _file (publish_jobs_file | string collect)
        test -n "$_file"; or return
        mkdir -p (dirname $_file) 2>/dev/null; or return
        job_info | awk '
            { for (i = 1; i <= NF; i++)
                if ($i ~ /^%[0-9]+$/ && (i+1) <= NF)
                    printf "%s %s ", $i, $(i+1) }
        ' > $_file
    end

    # Remove this shell's publish file. Installed as a fish_exit event
    # handler below so the file doesn't linger after the shell exits
    # and confuse the next shell on the same pty.
    function unpublish_jobs
        set _file (publish_jobs_file | string collect)
        test -n "$_file"; or return
        rm -f $_file
    end

    function _publish_jobs_exit --on-event fish_exit
        unpublish_jobs
    end

    function short_pwd
        set projectname (projectname)
        if test -n "$projectname"
            printf '%s' $projectname
        else
            printf '%s' (basename $PWD)
        end
    end

    function project_or_command_or_pwd
        set projectname (projectname)
        if test -n "$projectname"
            printf '%s' $projectname
        else if test -n "$current_command"
            set command (string split ' ' $current_command)
            printf '%s' $command[1]
        else
            printf '%s' (basename $PWD)
        end
    end

    function project_or_pwd
        set projectname (projectname)
        if test -n "$projectname"
            printf '%s' $projectname
        else
            printf '%s' (basename $PWD)
        end
    end

    # print the name of the current branch
    function branch
        :
    end

    # print the name of all branches
    function branches
        :
    end

    function blue
        if $color
            printf '%s%s%s' $blue "$argv" $normal
        else
            printf '%s' "$argv"
        end
    end
    function green
        if $color
            printf '%s%s%s' $green "$argv" $normal
        else
            printf '%s' "$argv"
        end
    end
    # shadows /bin/red, but I don't use it here
    function red
        if $color
            printf '%s%s%s' $red "$argv" $normal
        else
            printf '%s' "$argv"
        end
    end
    function yellow
        if $color
            printf '%s%s%s' $yellow "$argv" $normal
        else
            printf '%s' "$argv"
        end
    end

    # print what remote commits would get pulled
    function incoming
        :
    end

    # print what local commits would get pushed
    function outgoing
        :
    end

    # clone a version control system repo (parity with shrc.vcs: prefer jj
    # for git URLs, and only hg-clone URLs that look like hg)
    function clone
        switch $argv[1]
        case '*.git'
            if have_command jj
                jj git clone $argv
            else if confirm "jj is not installed. Clone using git"
                git clone $argv
            end
        case '*/hg*'
            hg clone $argv
        end
    end

    alias am='amend'
    alias ci='commit'
    alias di='diffs'
    alias gr='graph'
    alias lg='graph'
    # ma=mail
    alias ma='review'
    # fish reserves the word "status"
    alias st='vcs status'
    for command in \
        add amend annotate base branch branches \
        changed changelog changes checkout commit commitforce diffs \
        fix graph incoming lint map outgoing pending precommit presubmit pull \
        push recommit revert review reword submit submitforce \
        unknown upload uploadchain
        alias $command="vcs $command"
    end

    # get a short version of the hostname for use in the prompt or window title
    function short_hostname
        string replace --regex '^'$USERNAME'-' '' (string match --regex '^[^.]*' $HOSTNAME)
    end

    # print the string that should be used as the xterm title.
    # Format: "<hostname> <session> <project-or-pwd>", matching the session
    # tag used in host_info. Each leading part is omitted when empty.
    function title
        if show_hostname_in_title
            printf '%s ' (short_hostname | string collect)
        end
        set _session (prompt_session_name | string trim)
        if test -n "$_session"
            printf '%s ' $_session
        end
        project_or_pwd
    end

    # set all the prompt strings
    # done this way so that \[ (bash) and \{ (zsh) are handled consistently
    function set_prompt
        set PS1 (ps1 | string collect)
    end

    # output the string that should be used as the prompt
    function ps1
        ps1_character
        printf ' '
    end

    # Print a character that should be the last part of the prompt.
    # Deliberately different from bash/zsh's `$`: seeing `>` at the
    # prompt is a hint that this is fish, i.e. which syntax is live.
    # Each shell uses its own native glyph so the prompt doubles as
    # a which-shell-am-I-in cue. When root, the glyph is the same
    # (`>`) but coloured red; host_info also prepends a red [root]
    # tag so the "you are root" cue is visible even without colour.
    function ps1_character
        if i_am_root
            red '>'
        else
            printf '>'
        end
    end

    # print the current vi-like editing mode (e.g. INSERT, NORMAL).
    # Overrides fish's default fish_mode_prompt. Fish prepends this to the
    # last line of fish_prompt so the mode appears right before the cursor.
    function fish_mode_prompt
        test -z "$fish_bind_mode"; and return
        switch $fish_bind_mode
        case default
            printf 'NORMAL '
        case insert
            printf 'INSERT '
        case visual
            printf 'VISUAL '
        case replace_one replace
            printf 'REPLACE '
        case '*'
            printf '%s ' $fish_bind_mode
        end
    end

    # set the xterm title to the supplied string
    function set_title
        if test -n "$titlestart"
            printf "%s%s%s" $titlestart "$argv" $titlefinish
        end
    end

    # TODO: expand_job

    # set the terminal color to the specified color or terminal attribute
    # accepts multiple arguments, e.g. my_set_color bold blue underline
    function my_set_color
        for arg in $argv
            eval "printf \"%s\" \"\$$arg\""
        end
    end

    function terminal_supports_bracketed_paste
        switch $TERM
        case rxvt-unicode xterm; true
        case '*'; false
        end
    end

    function enable_bracketed_paste
        if terminal_supports_bracketed_paste
            printf '\e[?2004h'
        end
    end

    function disable_bracketed_paste
        if terminal_supports_bracketed_paste
            printf '\e[?2004l'
        end
    end

    # set a simple prompt for non-bash non-zsh
    # (will be overridden immediately by bash and zsh)
    # TODO: configure prompt
    #basic_prompt
end

# source local overrides file (work vs home, etc.)
test -f $HOME/.config/fish/local.fish; and source $HOME/.config/fish/local.fish

# authenticate on startup if needed, mirroring shrc's startup check.
# Skipped when attached to a shpool session (credentials come from the
# parent), and when stdin isn't a tty (ssh-add can't prompt there, and
# the fish test harness runs `fish -i` with stdin detached).
if is_interactive; and stdin_is_tty; and not in_shpool
    if need_auth
        auth
    end
end

# finish with a zero exit status so the first prompt is '$' rather than '?'
true
