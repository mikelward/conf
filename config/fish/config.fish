# Configuration for fish shell.
#
# Mikel Ward <mikel@mikelward.com>

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
function auth
    :
end

# hook for printing which things I need to authenticate to (ssh-agent, etc.)
#
# TODO: reconcile this with `vcs prompt-line` (same question for shrc's
# auth_info and nushell's auth-info).
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
# TODO: see auth_info above (reconcile with `vcs prompt-line`).
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

# return true if this is inside a VCS workspace/source root
function inside_project
    set _root (projectroot | string collect)
    test -n "$_root"
end

# return true if this session is attached to shpool
function in_shpool
    test -n "$SHPOOL_SESSION_NAME"
end

# return true if we should try to run shpool
function want_shpool
    connected_remotely; or inside_project
end

# return true if this session is inside a tmux server
function inside_tmux
    test -n "$TMUX"
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
    local hostname
    while read -r hostname
        echo $hostname (join " " (addr $hostname))
    end
end

function with_hostnames
    local ip
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
        test -e $file; and mv -i $file (basename $file .bak)
        test -e $file.bak; and mv -i $file.bak $file
    end
end

# ring the terminal's bell
function bell
    printf '\a'
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
        set lines (string trim --left --chars -- - $argv[1])
        set --erase argv[1]
    end

    while test $lines -gt 0
        read header
        printf '%s\n' $header
        set lines $lines - 1
    end
    $argv
end

# print the path from buildroot to $PWD
function builddir
    set buildroot (buildroot)
    if test $PWD = $buildroot
        printf '.'
    else
        trim_prefix (buildroot) $PWD
    end
end

# print the directory that builds are relative to
function buildroot
    projectroot
end

# print the name of the current project
function projectname
    if set projectroot (projectroot | string collect)
        echo "$projectroot"
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

# see what changes a command would make to a file
# e.g. trydiff mdformat <file>
function trydiff
    set file (basename $argv[1])
    set dir (dirname $argv[1])
    set dots (string split '.' $file)
    set base (string join '.' $dots[1..-2])
    set ext $dots[-1]

    test -n "$dir"; and set dir $dir/
    set testfile $dir$base'_test'$ext
    test -e $testfile; and printf '%s' $testfile
end

# search for a file in parent directories, print the first one found
function find_up
    set start_pwd $PWD
    set file $argv[1]
    set dir $argv[2]
    test -z $dir; and set dir .
    test $dir = .; and set dir $PWD

    if test -f $dir/$file
        printf '%s/%s' $dir %file
        cd $start_pwd
        return 0
    end
    if test $dir = /
        cd $start_pwd
        return 1
    end
    find_up $file (basedir $dir)
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
    command search $argv[1]
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
function peg; pegrep; end

# grep for a pattern in the environment of processes with the given pids
# envgrep <environment pattern> <pid>...
function envgrep
    set pattern $argv[1]
    shift
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
    switch $argv[1]
    case -'*'
        set lines (string trim --left --chars -- - $argv[1])
        set --erase argv[1]
    end
    ls -t -1 $argv | head -n $lines
end

# keep trying a command until it works
# (e.g. retry ping -c 1 host)
function retry
    while true
        if $argv
            bell
            break
        else
            sleep 10
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
    set TZ $to date -d 'TZ="'$from'"'" ""$argv"
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

# Trailing-slash autocd: typing `foo/` at the prompt changes into foo
# (same lookup as `cd`, so CDPATH still applies), while bare `foo`
# remains a "command not found" error. Fish has no direct equivalent
# of bash's `shopt -s autocd` / zsh's `setopt AUTO_CD`, and we wouldn't
# use them anyway -- they auto-cd on *any* bare directory name, too
# easy to trigger by accident. Requiring a trailing `/` makes the
# intent explicit.
#
# We preserve any pre-existing fish_command_not_found (e.g. distros
# that ship one to suggest `apt install X`) by copying it to
# system_fish_command_not_found before we override. The `functions -q`
# guard on the copy target keeps re-sourcing idempotent.
if functions -q fish_command_not_found
    and not functions -q system_fish_command_not_found
    functions -c fish_command_not_found system_fish_command_not_found
end

function fish_command_not_found
    if string match -q -- '*/' $argv[1]
        if test -d $argv[1]
            cd -- $argv[1]
            return
        end
    end
    if functions -q system_fish_command_not_found
        system_fish_command_not_found $argv
    else if functions -q __fish_default_command_not_found_handler
        __fish_default_command_not_found_handler $argv
    else
        echo "fish: Unknown command: $argv[1]" >&2
        return 127
    end
end

##################################
# ENVIRONMENT SETUP FOR ALL SHELLS
# Set $PATH early in case other stuff here needs it.

set --export CDPATH . $HOME
set --export GOPATH $HOME

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
if have_command brew
    brew shellenv | source
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

function maybe_start_shpool_and_exit
    if not in_shpool; and want_shpool; and have_command shpool
        autoshpool; and exit
    end
end

#########################
# INTERACTIVE SHELL SETUP
# Set up the prompt, title, key bindings, etc.

if is_interactive
    if in_shpool
        # Prevent shpool from clearing the screen during startup.
        # This ensures we can see any motd, errors, etc.
        function clear
            functions --erase clear
        end
        if test -n "$SHPOOL_INITIAL_PWD"
            cd $SHPOOL_INITIAL_PWD
            set --erase SHPOOL_INITIAL_PWD
        end
    else
        # This will be overridden by autoshpool.
        set --export SHPOOL_INITIAL_PWD $PWD
    end
    maybe_start_shpool_and_exit

    log_history "New session as $USERNAME: $0 $argv"

    # use custom vi-like key bindings (emacs bindings layered on vi mode)
    set -g fish_key_bindings my_vi_key_bindings

    # regain use of Ctrl+S and Ctrl+Q
    stty start undef stop undef 2>/dev/null

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
    alias asp='autoshpool'
    alias attach='shpool attach'
    alias detach='shpool detach'
    alias bindkeys='daemon xbindkeys'
    set code_patterns "*.c" "*.h" "*.cc" "*.cpp" "*.hh" "*.coffee" "*.go" "*.hs" "*.java" "*.js" "*.pl" "*.py" "*.sh" "*.rb" "*.swig" "*.ts"
    set code_includes "--include="$code_patterns
    alias c='less -FX'
    alias cdf='cdfile'
    alias cg='rg "$code_includes"'
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
        setsid $argv[1]
    end
    alias diga='dig +noall +answer +search'
    alias digs='dig +short +search'
    function download; cd $HOME/Downloads; wget $argv; end
    alias e='$EDITOR'
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
    else if quiet ls set --color auto -v -d /
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
    alias jd='jjd'
    alias mjd='jjd -f'
    alias m='make -f .Makefile'
    alias ml='m lint'
    # shadows magtape command, but who uses that?
    alias mt='m test'
    alias now='date +"%Y-%m-%dT%H:%M:%S"'
    alias nowns='date +"%Y-%m-%dT%H:%M:%S.%N"'
    alias nv='nvim'
    alias p='$PAGER'
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
    alias rg='g -IR --exclude-dir=".*"'
    function rh
        gh $argv | tail -n 20
    end
    alias q='xa'
    alias s='subl'
    alias sa='shpool attach'
    alias sd='shpool detach'
    alias shpoolswitch='switchshpool'
    alias shsw='switchshpool'
    alias spa='shpool attach'
    alias spd='shpool detach'
    alias spell='aspell -a'
    alias sps='switchshpool'
    alias sr='ssh -l root'
    alias ssp='switchshpool'
    alias sw='switchshpool'
    alias swsh='switchshpool'
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
    alias view='vim -R'
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

    function set_up_ssh_aliases
        set _ssh_config $HOME/.ssh/config
        test -f $_ssh_config; or return

        while read _line
            set _match (string match --regex '^[[:space:]]*[Hh]ost[[:space:]]+(.*)$' -- $_line)
            test -n "$_match"; or continue
            set _hosts (string replace --all --regex '[[:space:]]+' ' ' -- $_match[2] | string trim | string split --no-empty ' ')
            for _alias in $_hosts
                switch $_alias
                case '*\**' '*\?*' '*-*'
                    continue
                end
                eval "function $_alias; shift_options ssh -t $_alias \$argv; end"
            end
        end <$_ssh_config
    end
    set_up_ssh_aliases

    # in case root isn't available, fall back to sudo
    if not have_command root
        alias sudo='root'
    end

    # enable colors in commands that support it
    # (ls is done above)
    quiet grep -q set --color auto "" /etc/hosts; and alias grep='grep --color=auto'
    set --export CLICOLOR true

    # TODO
    #alias ginfo='(path info)'
    # aliases to abstract away differences between package managers
    # delegates to the `package` script, which dispatches to dnf, yum,
    # or apt-get depending on what's available
    if have_command package
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
    end

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

    function fish_prompt
        my_set_color 'normal'
        printf '\n'
        bar $COLUMNS
        printf '\r%s \n' (prompt_line | string collect)
        vcs map 2>/dev/null
        job_info
        set_title (title | string collect)
        ps1
        flash_terminal
    end

    # print the first line of the preprompt: host + dir + auth.
    # Delegates to `vcs prompt-line` so the whole line renders in one
    # process. Policy (short hostname, production-host coloring) stays in
    # fish and is passed via flags.
    function prompt_line
        set _color_flag --color=never
        if $color
            set _color_flag --color=always
        end
        set _flags --hostname=(short_hostname | string collect) $_color_flag
        if on_production_host
            set _flags --production $_flags
        end
        vcs prompt-line $_flags
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
            yellow "Took $duration"
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
        else if test $seconds -gt 0
            echo "$seconds seconds"
        end
    end

    function fish_last_error
        if test $last_job_status -ne 0
            echo "Exit status $last_job_status"
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

    # print the current session name, if any, with a trailing space
    function session_name
        if test -n "$SHPOOL_SESSION_NAME"
            printf '%s ' $SHPOOL_SESSION_NAME
        else if test -n "$TMUX"
            printf '%s ' (tmux display-message -p '#S' | string collect)
        end
    end

    # print information about all shell jobs
    # intended to be used in the preprompt
    function job_info
            jobs |
                sed -e 's/^\[\([0-9][0-9]*\)\][-+ ]*[^ ]* */%\1 /' |
                grep -v '(pwd now:'
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

    # clone a version control system repo
    function clone
        switch $argv[1]
        case '*.git'
            git clone $argv
        case '*'
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

    # ssh to remote host using current shell's config
    function mssh
        switch $SHELL
        case '*bash'; bssh $ssh_opts $argv
        case '*zsh';  zssh $ssh_opts $argv
        case '*';     ssh  $ssh_opts $argv
        end
    end

    # ssh to remote host using this host's bashrc
    function bssh
        # pass options to ssh/scp
        for arg in $argv
            string match --regex '^-' $arg; or break
            string match --regex '^--$'; and break
            set --append ssh_opts $arg
            set --erase argv[1]
        end
        set -q BASHRC; or set BASHRC .bashrc
        ssh $ssh_opts -t $argv '
export BASHRC "$(mktemp /tmp/bash.XXXXXXXX)";
scp $ssh_opts "'$HOSTNAME:$BASHRC'" "$BASHRC";
exec bash --rcfile "$BASHRC" -i'
    end

    # ssh to remote host using this host's zshrc
    function zssh
        # pass options to ssh/scp
        for arg in $argv
            string match --regex '^-' $arg; or break
            string match --regex '^--$'; and break
            set --append ssh_opts $arg
            set --erase argv[1]
        end
        set -q ZDOTDIR; or set ZDOTDIR $HOME
        ssh $ssh_opts -t $argv '
export ZDOTDIR "$(mktemp -d /tmp/zsh.XXXXXXXX)";
scp $ssh_opts "'$HOSTNAME:$ZDOTDIR/.zshrc'" "$ZDOTDIR";
exec zsh -i'
    end

    # print the string that should be used as the xterm title
    function title
        if show_hostname_in_title
            short_hostname
            printf ' '
        end
        session_name
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

    # print a character that should be the last part of the prompt
    function ps1_character
        printf '>'
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

# finish with a zero exit status so the first prompt is '$' rather than '?'
true
