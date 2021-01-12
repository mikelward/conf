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
function auth_info
    set problems ()
    is_ssh_valid; or set --append problems 'SSH'
    count $problems; and yellow $problems
end

# returns whether an SSH key is loaded
function is_ssh_valid
    ssh-add -L >/dev/null 2>&1
end

# returns whether I need to authenticate
function need_auth
    test -n (auth_info)
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

# print an error message
function error
    printf '%s\n' "$argv" >&2
end

# return true if the argument exists as a command, bypassing aliases
function have_command
    type --force-path --quiet $argv[1]
end

# return true if the argument is an alias, builtin, command, or function
function is_runnable
    type --path --quiet $argv[1]
end

# return true if the shell is interactive
function is_interactive
    status --is-interactive
end

## log the running of a command to a file
#function log_history
#    printf '%s\n' (date "+%Y%m%d %H%M%S %z") $TTY $argv" >> $HISTORY_FILE
#end

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
    basename (projectroot | string collect)
end

# print the root directory of the current project
function projectroot
    :
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

    test -n $dir; and set dir $dir/
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
    if test -n $pids
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

##################################
# ENVIRONMENT SETUP FOR ALL SHELLS
# Set $PATH early in case other stuff here needs it.

set --export GOPATH $HOME

add_path $HOME/android-sdk-linux/platform-tools
add_path $HOME/Android/Sdk/platform-tools
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

# set HISTORY_FILE for log_history
set HISTORY_FILE $HOME/.history

set --export LESS "-R"
if test -f $HOME/scripts/lessopen
    set --export LESSOPEN "|$HOME"'/scripts/lessopen "%s"'
end

#########################
# INTERACTIVE SHELL SETUP
# Set up the prompt, title, key bindings, etc.

if is_interactive

    #log_history "New session as $USERNAME: $0 ""$argv"

    # regain use of Ctrl+S and Ctrl+Q
    stty start undef stop undef

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
        set _ssh_machines $HOME/.ssh/machines
        test -f $_ssh_machines; or return

        while read fqdn
            set short (string match --regex '^[^.]*' $fqdn)
            printf 'alias %s="ssh %s"' $short $fqdn | source
        end <$_ssh_machines
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
    if have_command yum
        alias yum='root yum --cacheonly'
        alias update='root yum makecache'
        alias search='yum search'
        alias show='yum info'
        alias install='root yum install'
        alias installed='rpm -qa'
        alias uninstall='root yum erase'
        alias reinstall='root yum reinstall'
        alias autoremove='root yum autoremove'
        alias upgrade='root yum upgrade'
        alias versions='yum list'
        alias files='repoquery --file'
    else if have_command apt-get
        alias update='root apt-get update'
        alias search='apt-cache search --names-only'
        alias show='apt-cache show'
        alias install='root apt-get install'
        alias installed="dpkg-query --show --showformat='\${binary:Package;-36} \${Version;-32} \${Status;-10}\n'"
        alias uninstall='root apt-get remove'
        alias reinstall='root apt-get install --reinstall'
        alias autoremove='root apt-get autoremove'
        alias upgrade='root apt-get upgrade'
        alias versions='apt-cache policy'
        alias files='apt-file search'
    else
        error "No supported package manager found"
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
   # commands to execute before the prompt is displayed
   function preprompt
       #last_job_info
       set current_command
       my_set_color 'normal'
       printf '\n'
       printf '%s %s %s\n' (host_info) (dir_info) (auth_info)
       job_info
       set_title (title | string collect)
   end

   function fish_prompt
        preprompt
        ps1
        flash_terminal
    end
#
#    function last_job_info
#        # Must be the very first thing.
#        set last_error (${shell}_last_error | string collect)
#
#        test -z $current_command; and return
#
#        my_set_color 'normal'
#        set printed false
#        if test -n $last_error
#            red $last_error
#            set printed true
#        end
#        set duration
#        if test $SECONDS -gt 0
#            local hours minutes seconds
#            set seconds $SECONDS
#            set hours (math $seconds/3600)
#            set seconds (math $seconds-$hours*3600)
#            set minutes (math $seconds/60)
#            set seconds (math $seconds-$minutes*60)
#            if test $hours -gt 0
#                set duration "$hours hours $minutes minutes $seconds seconds"
#            else if test $minutes -gt 0
#                set duration "$minutes minutes $seconds seconds"
#            else if test $seconds -gt 1
#                set duration "$seconds seconds"
#            end
#        end
#        if test -n $duration
#            if $printed
#                printf ' '
#            end
#            yellow "Took $duration"
#            set printed true
#        end
#        if $printed
#            printf '\n'
#        end
#    end

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

    function connected_via_ssh
        test -n $SSH_CONNECTION
    end

    function inside_tmux
        test -n $TMUX
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

    # print information about this machine
    function host_info
        if on_production_host
            my_set_color 'red'
        end
        printf '%s' (short_hostname | string collect)
        my_set_color 'normal'
        printf '\n'
    end

    # print information about all shell jobs
    # intended to be used in the preprompt
    function job_info
            jobs |
                sed -e 's/^\[\([0-9][0-9]*\)\][-+ ]*[^ ]* */%\1 /' |
                grep -v '(pwd now:'
    end

    function status_chars
        :
    end

    # print directory stack listing in "+<number> <directory>" format
    # intended to be used in the preprompt
    function dir_info
            blue (_dir_info $PWD)
    end
    function _dir_info
        # if the directory is under version control, print
        # <project name> <subdir under project root> <branch>,
        # otherwise just the directory with $HOME turned into ~
        cd $argv[1]
        set projectroot (projectroot)
        if test -n "$projectroot"
            green (basename $projectroot)
            local projectsubdir
            set projectsubdir (trim_prefix (projectroot) $PWD)
            if test -n $projectsubdir
                printf ' '
                blue $projectsubdir
            end
            set statuschars (status_chars)
            if test -n $statuschars
                printf ' '
                yellow $statuschars
            end
            # local branch
            # set branch (branch)
            # if test -n $branch
            #     printf ' '
            #     green $branch
            # end
        else
            tilde_directory
        end
    end

    function short_pwd
        set projectname (projectname)
        if test -n $projectname
            printf '%s' $projectname
        else
            printf '%s' (basename $PWD)
        end
    end

    function project_or_command_or_pwd
        set projectname (projectname)
        if test -n $projectname
            printf '%s' $projectname
        else if test -n $current_command
            set command (string split ' ' $current_command)
            printf '%s' $command[1]
        else
            printf '%s' (basename $PWD)
        end
    end

    function project_or_pwd
        set projectname (projectname)
        if test -n $projectname
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
        add amend annotate branch branches \
        changed changelog changes checkout commit commitforce diffs \
        fix graph incoming lint outgoing pending precommit presubmit pull \
        push recommit revert review reword submit submitforce \
        unknown upload uploadchain
        alias $command="vcs $command"
    end

    # TODO: fish_last_error

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

    # print the current directory with $HOME changed to ~
    function tilde_directory
        printf '%s' $PWD | sed -e 's#^'$HOME'#~#'
    end

    # print the string that should be used as the xterm title
    function title
        if show_hostname_in_title
            short_hostname
            printf ' '
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

    # print a character that should be the last part of the prompt
    function ps1_character
        printf '>'
    end

#    # function to run just before running a command from the command line
#    # see also preexec (zsh) and DEBUG (bash)
#    # the first argument is the command line being run
#    function precommand
#        log_history "$argv"
#        set current_command (expand_job "$argv")
#        set_title (title | string collect)
#        my_set_color 'normal'
#        set SECONDS 0
#    end

    # set the xterm title to the supplied string
    function set_title
        if test -n $titlestart
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

    # TODO: move out of interactive block?
    # program defaults
    set --export BLOCKSIZE 1024
    set --export GREP_COLOR 4

    # default programs
    is_runnable vi; and set --export EDITOR vi
    is_runnable vim; and set --export EDITOR vim
    is_runnable editline; and set --export EDITOR editline
    is_runnable more; and set --export PAGER more
    is_runnable less; and set --export PAGER less
    is_runnable meld; and test -n $DISPLAY; and set --export DIFF meld

    # colors for ls
    switch $TERM
    case linux putty vt220
        # colors for white on black
        set --export LSCOLORS 'ExFxxxxxCxxxxx'
        set --export LS_COLORS 'no=00:fi=00:di=01;34:ln=01;35:so=00;00:bd=00;00:cd=00;00:or=01;31:pi=00;00:ex 01;32'
    case '*'
        # colors for black on white
        set --export LSCOLORS 'exfxxxxxcxxxxx'
        set --export LS_COLORS 'no=00:fi=00:di=00;34:ln=00;35:so=00;00:bd=00;00:cd=00;00:or=00;31:pi=00;00:ex 00;32'
    end

    # command line editing
    test -r $HOME/.inputrc; and set --export INPUTRC $HOME/.inputrc
end

# source local overrides file (work vs home, etc.)
test -f $HOME/.config/fish/local.fish; and source $HOME/.config/fish/local.fish

# finish with a zero exit status so the first prompt is '$' rather than '?'
true
