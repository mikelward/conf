# Configuration for Nushell.
#
# This is a port of the zshrc (~/conf/shrc) to Nushell. It aims to provide
# the same everyday helpers, aliases, and prompt style, adapted to Nushell's
# structured-data model. Items that are intrinsically shell-specific (POSIX
# job control, DEBUG traps, bracketed-paste escapes, zle/readline keymaps)
# are handled by Nushell itself and are not ported.
#
# Mikel Ward <mikel@mikelward.com>

###############
# ENVIRONMENT

$env.USERNAME = (whoami | str trim)
$env.HOSTNAME = (try { hostname -f | str trim } catch { hostname | str trim })
$env.UID = (id -u | str trim | into int)
$env.TTY = (try { tty | str trim } catch { "" })

$env.HISTORY_FILE = ([$env.HOME ".history"] | path join)

#######
# PATH FUNCTIONS
# Functions used to modify $PATH.
# Nushell treats $env.PATH as a list, so these operate on that list.

# add $dir to the start of $env.PATH (if it exists and is not already there)
def --env prepend_path [dir: string] {
    if not ($dir | path exists) { return }
    $env.PATH = ($env.PATH | where {|it| $it != $dir } | prepend $dir)
}

# add $dir to the end of $env.PATH (if it exists and is not already there)
def --env append_path [dir: string] {
    if not ($dir | path exists) { return }
    $env.PATH = ($env.PATH | where {|it| $it != $dir } | append $dir)
}

# remove $dir from $env.PATH
def --env delete_path [dir: string] {
    $env.PATH = ($env.PATH | where {|it| $it != $dir })
}

# return true if $dir is already in $env.PATH
def inpath [dir: string] {
    $env.PATH | any {|it| $it == $dir }
}

# add $dir to $env.PATH at the given position (start, end, or default = append
# only if missing)
def --env add_path [dir: string, where?: string] {
    if not ($dir | path exists) { return }
    match $where {
        "start" => { prepend_path $dir }
        "end"   => { append_path $dir }
        _       => { if not (inpath $dir) { append_path $dir } }
    }
}

#################
# BASIC HELPERS

# print an error message to stderr
def error [...args: string] {
    print --stderr ($args | str join " ")
}

# print an important message that's not quite an error
def warn [...args: string] {
    print --stderr ($args | str join " ")
}

# print a line to stdout (mirrors shrc puts)
def puts [...args: string] {
    print ($args | str join " ")
}

# run a command with output silenced
def quiet [...args] {
    try { ^($args | first) ...($args | skip 1) out+err> /dev/null } catch { return }
}

# return true if the argument exists as an external command on $PATH,
# bypassing aliases and builtins (matches shrc have_command behaviour)
def have_command [name: string] {
    $env.PATH | any {|dir| ([$dir $name] | path join | path exists) }
}

# return true if the argument is an alias, builtin, command, or function
def is_runnable [name: string] {
    (which $name | is-not-empty) or (have_command $name)
}

# return true if we're running interactively
def is_interactive [] {
    (is-terminal --stdin) and (is-terminal --stdout)
}

# return true if connected via SSH
def connected_via_ssh [] {
    ("SSH_CONNECTION" in $env) and ($env.SSH_CONNECTION? | default "" | is-not-empty)
}

# return true if this session is on a remote machine
def connected_remotely [] {
    connected_via_ssh
}

# return true if the current shell is attached to shpool
def in_shpool [] {
    ("SHPOOL_SESSION_NAME" in $env) and ($env.SHPOOL_SESSION_NAME? | default "" | is-not-empty)
}

# return true if inside tmux
def inside_tmux [] {
    ("TMUX" in $env) and ($env.TMUX? | default "" | is-not-empty)
}

# return true if the current user is root
def i_am_root [] {
    ($env.UID? | default 1000) == 0
}

# print the contents of ~/.workstation (cached in $env.WORKSTATION)
def --env workstation [] {
    if not ("WORKSTATION" in $env) {
        let f = ([$env.HOME ".workstation"] | path join)
        $env.WORKSTATION = (if ($f | path exists) {
            open --raw $f | str trim
        } else {
            ""
        })
    }
    $env.WORKSTATION
}

# return true if this machine is my workstation
def --env on_my_workstation [] {
    let host = ($env.HOSTNAME? | default "")
    let ws = (workstation)
    if ($ws | is-not-empty) and ($host == $ws) { return true }
    if ($host | str contains "laptop") { return false }
    let user = ($env.USERNAME? | default "")
    if ($user | is-not-empty) and ($host | str starts-with ($user + "-")) { return true }
    false
}

# return true if this machine is my laptop
def on_my_laptop [] {
    let f = ([$env.HOME ".laptop"] | path join)
    if ($f | path exists) { return true }
    (($env.HOSTNAME? | default "") | str contains "laptop")
}

# return true if this is a non-production machine I use to get work done
def --env on_my_machine [] {
    (on_my_workstation) or (on_my_laptop)
}

# return true if this is a test host
def on_test_host [] {
    (($env.HOSTNAME? | default "") | str contains "test")
}

# return true if this is a dev host
def on_dev_host [] {
    (($env.HOSTNAME? | default "") | str contains "dev")
}

# return true if this is a production machine
def --env on_production_host [] {
    (not (on_my_machine)) and (not (on_test_host)) and (not (on_dev_host))
}

# return true if it's already obvious which host I'm on
def show_hostname_in_title [] {
    not (inside_tmux)
}

###################
# GENERAL FUNCTIONS

# print the age of a file in seconds
def age [file: path] {
    ((date now) - (ls -l $file | get 0.modified)) / 1sec
}

# look up a hostname in DNS, output A and AAAA records
def addr [host: string] {
    ^dig +noall +answer +search $host a $host aaaa | get_address_records
}

def ptr [ip: string] {
    ^dig +noall +answer -x $ip ptr | get_ptr_records
}

# read BIND-style DNS entries, print the A and AAAA records
def get_address_records [] {
    ^awk '$3 == "IN" && $4 ~ /^A/ { print $5 }'
}

# read BIND-style DNS entries, print the PTR records
def get_ptr_records [] {
    ^awk '$3 == "IN" && $4 == "PTR" { print $5 }'
}

# list this machine's IP addresses
def ips [] {
    ^ip -o a sh up primary scope global
    | lines
    | each {|line|
        let parts = ($line | split row -r '\s+')
        if ($parts | length) < 4 { return null }
        {iface: $parts.1, addr: $parts.3}
    }
    | compact
}
def addrs [] { ips }

# make a backup (file.bak) of each argument
def bak [...files: path] {
    for f in $files { ^mv -i $f ($f | into string | $"($in).bak") }
}

# restore a .bak file (or back the restore direction, matching shrc)
def unbak [...files: path] {
    for f in $files {
        let s = ($f | into string)
        if ($s | str ends-with ".bak") {
            let dest = ($s | str substring 0..(-4))
            if ($s | path exists) { ^mv -i $s $dest }
        } else {
            let src = ($s + ".bak")
            if ($src | path exists) { ^mv -i $src $s }
        }
    }
}

# ring the terminal's bell
def bell [] {
    print -n (char -u 7)
}

# print the path from buildroot to PWD
def builddir [] {
    let root = (buildroot)
    if ($env.PWD == $root) {
        "."
    } else {
        $env.PWD | str replace ($root + "/") ""
    }
}

# print the directory that builds are relative to
def buildroot [] {
    projectroot
}

# print the name of the current project
def projectname [] {
    let root = (projectroot)
    if ($root | is-empty) { "" } else { ($root | path basename) }
}

# print the root directory of the current project (hook; override locally)
def projectroot [] {
    ""
}

# cd to the real directory that the specified file is in, resolving symlinks
def --env cdfile [file: path] {
    cd (realdir $file)
}

# print the absolute path of the directory containing the specified file
def realdir [file: path] {
    ^readlink -f $file | str trim | path dirname
}

# make a directory and cd to it
def --env mcd [dir: string] {
    if ($dir | path exists) {
        print $"($dir) already exists"
    } else {
        mkdir $dir
        cd $dir
    }
}

# make a temporary directory and cd to it
def --env mtd [] {
    cd (^mktemp -d | str trim)
}

# search for a file in parent directories, print the first one found
def find_up [file: string] {
    mut dir = $env.PWD
    loop {
        let candidate = ([$dir $file] | path join)
        if ($candidate | path exists) { return $candidate }
        if $dir == "/" { return "" }
        $dir = ($dir | path dirname)
    }
}

# replace a file with a sorted version of itself
def isort [file: path] {
    let tmp = (($file | into string) + ".bak")
    open --raw $file | lines | sort | str join (char newline) | save --force $tmp
    ^mv $tmp $file
}

# print the full path to an executable, ignoring aliases and functions.
# Named path_ to avoid shadowing Nushell's built-in `path` command group.
def path_ [name: string] {
    let found = (which $name | where type == "external" | get 0.path? | default "")
    if ($found | is-empty) { error $"($name) not found" } else { print $found }
}

# show the most recently changed files
def recent [count?: int, ...args: string] {
    let n = ($count | default 10)
    ^ls -t -1 ...$args | lines | first $n
}

# keep trying a command until it works
def retry [...cmd: string] {
    loop {
        let ok = (try { ^($cmd | first) ...($cmd | skip 1); true } catch { false })
        if $ok { bell; break }
        sleep 10sec
    }
}

# remove the ssh known host from the specified line number
def rmkey [line: int] {
    let known = ([$env.HOME ".ssh" "known_hosts"] | path join)
    ^sed -i -e $"($line)d" $known
}

# run a command with the first argument moved to the end
# e.g. first_arg_last grep ~/.history <args> runs grep <args> ~/.history
def first_arg_last [...args] {
    let cmd = ($args | first)
    let first = ($args | get 1)
    let rest = ($args | skip 2)
    ^$cmd ...$rest $first
}

# convert a time from one timezone to another
def tz2tz [from: string, to: string, ...spec: string] {
    with-env { TZ: $to } { ^date -d $'TZ="($from)" ($spec | str join " ")' }
}

# convert from Unix timestamp in micros to a human-readable datetime
def udate [ts: int, ...fmt: string] {
    let secs = ($ts // 1000000)
    ^date -d $"@($secs)" ...$fmt
}

# convert from UTC to local time
def utc2 [spec: string] {
    ^date -d $'TZ="UTC" ($spec)'
}

# hook to run the given command under a custom ssh-agent
def with_agent [...cmd] {
    ^($cmd | first) ...($cmd | skip 1)
}

# print the definition of the given command, alias, or function
def what [name: string] {
    which $name
}

# get a short version of the hostname for use in the prompt or window title
def short_hostname [] {
    let h = (($env.HOSTNAME? | default "") | split row "." | first)
    let user = ($env.USERNAME? | default "")
    if ($user | is-not-empty) {
        $h | str replace --regex $"^($user)-" ""
    } else {
        $h
    }
}

# print a short version of $PWD for the title: project name or basename
def short_pwd [] {
    let p = (projectname)
    if ($p | is-not-empty) { $p } else { $env.PWD | path basename }
}

# print project name, else basename of PWD
def project_or_pwd [] {
    let p = (projectname)
    if ($p | is-not-empty) { $p } else { $env.PWD | path basename }
}

# print the current session name (shpool or tmux), with trailing space
def session_name [] {
    if (in_shpool) {
        $"($env.SHPOOL_SESSION_NAME) "
    } else if (inside_tmux) {
        let s = (^tmux display-message -p '#S' | str trim)
        $"($s) "
    } else {
        ""
    }
}

##################################
# ENVIRONMENT SETUP
# Set $PATH and other variables, parallel to the shrc section.

$env.CDPATH = [
    "."
    $env.HOME
    ([$env.HOME "conf"] | path join)
    ([$env.HOME "conf" "config"] | path join)
]
$env.GOPATH = $env.HOME

add_path "/usr/local/bin"
add_path ([$env.HOME "android-sdk-linux" "platform-tools"] | path join)
add_path ([$env.HOME "android-studio" "bin"] | path join)
add_path ([$env.HOME "Android" "Sdk" "platform-tools"] | path join)
add_path ([$env.HOME "depot_tools"] | path join)
add_path ([$env.HOME "google-cloud-sdk" "bin"] | path join)
add_path ([$env.HOME ".cargo" "bin"] | path join)
add_path ([$env.HOME ".local" "bin"] | path join)
add_path ([$env.HOME "bin"] | path join) "start"
add_path ([$env.GOPATH "bin"] | path join) "start"
add_path ([$env.HOME "scripts"] | path join) "start"

# scripts.home, scripts.work, etc. override scripts
let _scripts_dirs = (try { glob ($env.HOME + "/scripts.*") } catch { [] })
for dir in $_scripts_dirs {
    add_path ($dir | into string) "start"
}
let _opt_bins = (try { glob "/opt/*/bin" } catch { [] })
for dir in $_opt_bins {
    add_path ($dir | into string) "end"
}
add_path "/sbin" "end"
add_path "/usr/sbin" "end"

$env.LESS = "-R"
let _lessopen_script = ([$env.HOME "scripts" "lessopen"] | path join)
if ($_lessopen_script | path exists) {
    $env.LESSOPEN = $"|($_lessopen_script) %s"
}

let _inputrc = ([$env.HOME ".inputrc"] | path join)
if ($_inputrc | path exists) { $env.INPUTRC = $_inputrc }
let _editrc = ([$env.HOME ".editrc"] | path join)
if ($_editrc | path exists) { $env.EDITRC = $_editrc }

# default programs
if (is_runnable "vi")       { $env.EDITOR = "vi" }
if (is_runnable "vim")      { $env.EDITOR = "vim" }
if (is_runnable "editline") { $env.EDITOR = "editline" }
if (is_runnable "more")     { $env.PAGER  = "more" }
if (is_runnable "less")     { $env.PAGER  = "less" }
if (is_runnable "meld") and (("DISPLAY" in $env) and ($env.DISPLAY? | default "" | is-not-empty)) {
    $env.DIFF = "meld"
}

# program defaults
$env.BLOCKSIZE = "1024"
$env.CLICOLOR = "true"
$env.GREP_COLOR = "4"
$env.GREP_COLORS = "mt=4"

# colors for ls — match shrc
let _term = ($env.TERM? | default "")
if ($_term in ["linux" "putty" "vt220"]) {
    # colors for white on black
    $env.LSCOLORS = "ExFxxxxxCxxxxx"
    $env.LS_COLORS = "no=00:fi=00:di=01;34:ln=01;35:so=00;00:bd=00;00:cd=00;00:or=01;31:pi=00;00:ex=01;32"
} else {
    # colors for black on white
    $env.LSCOLORS = "exfxxxxxcxxxxx"
    $env.LS_COLORS = "no=00:fi=00:di=00;34:ln=00;35:so=00;00:bd=00;00:cd=00;00:or=00;31:pi=00;00:ex=00;32"
}

##############################
# PROMPT / TERMINAL FUNCTIONS
# The prompt mirrors shrc: a first line showing host/dir/auth, a separator
# bar, and a simple prompt character. VCS info is delegated to `vcs
# prompt-line` when the helper binary is available.

# Print the argument wrapped in ANSI color escapes. Nushell prints the ANSI
# sequences unconditionally; callers that don't want color should set
# $env.NO_COLOR and strip them. Mirrors the shrc helpers; `red` shadows the
# /bin/red binary just as the shrc function does.
def blue   [...args: string] { $"(ansi blue)($args | str join ' ')(ansi reset)" }
def green  [...args: string] { $"(ansi green)($args | str join ' ')(ansi reset)" }
def red    [...args: string] { $"(ansi red)($args | str join ' ')(ansi reset)" }
def yellow [...args: string] { $"(ansi yellow)($args | str join ' ')(ansi reset)" }

# print a bar of length $n
def bar [n: int] {
    if $n <= 0 { "" } else {
        1..$n | each {|_| "―" } | str join
    }
}

# print a leading space before $args if $args is non-empty
def maybe_space [...args: string] {
    let s = ($args | str join " ")
    if ($s | is-not-empty) { $" ($s)" } else { "" }
}

# format a duration (given as nanoseconds or a duration) as h/m/s
def format_duration [d: duration] {
    let total = ($d / 1sec | into int)
    let hours = ($total // 3600)
    let minutes = (($total - ($hours * 3600)) // 60)
    let seconds = ($total - ($hours * 3600) - ($minutes * 60))
    if $hours > 0 {
        $"($hours) hours ($minutes) minutes ($seconds) seconds"
    } else if $minutes > 0 {
        $"($minutes) minutes ($seconds) seconds"
    } else if $seconds > 1 {
        $"($seconds) seconds"
    } else {
        ""
    }
}

# print the first line of the preprompt: host + dir + auth.
# Delegates to `vcs prompt-line` so the whole line renders in one process.
def --env prompt_line [] {
    let color_flag = if (($env.NO_COLOR? | default "") | is-empty) { "--color=always" } else { "--color=never" }
    let production = if (on_production_host) { ["--production"] } else { [] }
    let host = (short_hostname)
    try {
        ^vcs prompt-line $"--hostname=($host)" $color_flag ...$production | str trim
    } catch {
        # fallback if vcs binary is unavailable
        $"($host) ((session_name))((project_or_pwd))"
    }
}

# print the string that should be used as the xterm title
def title [] {
    let parts = if (show_hostname_in_title) {
        [(short_hostname) " " (session_name) (project_or_pwd)]
    } else {
        [(session_name) (project_or_pwd)]
    }
    $parts | str join
}

# print a character that should be the last part of the prompt
def ps1_character [] {
    if (i_am_root) { "#" } else { "$" }
}

# get the user's attention (terminal bell in xterm)
def flash_terminal [] {
    let t = ($env.TERM? | default "")
    if ($t == "xterm") or ($t | str starts-with "xterm-") { bell }
}

# the main Nushell PROMPT_COMMAND callback.
# Mirrors shrc preprompt output: newline + separator bar + CR + prompt_line.
# The CR overwrites the start of the bar, leaving the trailing bar chars
# visible after the prompt line.
def --env render_prompt [] {
    let cols = (try { term size | get columns } catch { 80 })
    let sep = (bar $cols)
    let line = (prompt_line)
    let nl = (char newline)
    let cr = (char cr)
    $"($nl)($sep)($cr)($line) ($nl)((ps1_character)) "
}

def render_right_prompt [] { "" }

# used by Nushell's transient prompt (shown for previous prompts) so the
# separator bar and VCS line aren't repeated in scrollback.
def render_transient_prompt [] {
    $"((ps1_character)) "
}

#########################
# INTERACTIVE: ALIASES AND COMMANDS
# Short command wrappers for everyday use. These mirror the zshrc aliases.
# Defined with `def` (rather than `alias`) so they can accept arguments
# consistently and still work when shadowing Nushell builtins.

def c  [...args] { ^less --quit-if-one-screen --no-init ...$args }
def --env cdf [file: path] { cdfile $file }
def ct [...args]  { ^ctags -R ...$args }
def cx [...args]  { ^chmod +x ...$args }
def diga [...args] { ^dig +noall +answer +search ...$args }
def digs [...args] { ^dig +short +search ...$args }
def download [...args] {
    cd ([$env.HOME "Downloads"] | path join)
    ^wget ...$args
}
def e [...args] { ^($env.EDITOR? | default "vim") ...$args }
def eg [...args] { ^grep --binary-files=without-match --line-number -E ...$args }
def f [id?: int] {
    if $id == null { job unfreeze } else { job unfreeze $id }
}
def g [...args] { ^grep --binary-files=without-match --line-number ...$args }

def gh_search [...args] {
    # Note that grep options must go after ~/.history.
    ^grep -a ...$args ([$env.HOME ".history"] | path join)
}
def gitdir [...args] { ^git rev-parse --git-dir ...$args }
def github [...args] { ^gh ...$args }
def gl [] { cd "/var/log" }
def h [...args] { ^head ...$args }
def headers [...args] { ^curl --location --include --silent --show-error --output /dev/null --dump-header - ...$args }
def hms [...args] { ^date '+%H:%M:%S' ...$args }
def hmsns [...args] { ^date '+%H:%M:%S.%N' ...$args }
def hosts [...args] { ^getent hosts ...$args }
def ipy  [...args] { ^ipython ...$args }
def ipy3 [...args] { ^ipython3 ...$args }
def killcode [...args] { ^pkill -f /usr/share/code/code ...$args }
def kssh [...args] { ^ssh -o PreferredAuthentications=publickey ...$args }

# ls wrappers: prefer the `l` tool if installed, else GNU coreutils `ls`.
# Defined as custom commands (not alias) so they always take a path arg.
def l [...args: string] {
    if (have_command "l") {
        ^l -K -v -e -x ...$args
    } else {
        ^ls --color=auto -v -b -x ...$args
    }
}
def ll [...args: string] {
    if (have_command "l") {
        ^l -K -v -e -x -p -T -B -V -h --time-style=relative ...$args
    } else {
        ^ls --color=auto -v -b -x -l ...$args
    }
}
def lt [...args: string] {
    if (have_command "l") {
        ^l -K -v -e -x -T -t ...$args
    } else {
        ^ls --color=auto -v -b -x -l -t ...$args
    }
}
def l1 [...args: string] { l "-1" ...$args }
def la [...args: string] { l "-a" ...$args }
def lc [...args: string] { l "-C" ...$args }
def latest [...args: string] { recent 1 ...$args }

def lssock [...args] { ^lsof -a -n -P -i ...$args }
def lss [...args] { lssock ...$args }

def j [] { job list }

def m [...args] { ^make -f .Makefile ...$args }
def ml [] { m lint }
def mt [] { m test }

def n [] { ^date '+%Y%m%d%H%M%S' }
def now [] { ^date '+%Y-%m-%dT%H:%M:%S' }
def nowns [] { ^date '+%Y-%m-%dT%H:%M:%S.%N' }
def nv [...args] { ^nvim ...$args }

def p [...args] { ^($env.PAGER? | default "less") ...$args }
def phup [...args] { ^pkill -HUP ...$args }
def psg [...args] { psgrep ...$args }
def psu [...args] { ^ps -o user,pid,start,time,pcpu,stat,cmd ...$args }
def pr [] { projectroot }
def py  [...args] { ^python ...$args }
def py2 [...args] { ^python2 ...$args }
def py3 [...args] { ^python3 ...$args }
def rg [...args] { g "--recursive" "--exclude-dir=.*" ...$args }
def rh [...args] { gh_search ...$args | last 20 }
def s [...args] { ^subl ...$args }
def spell [...args] { ^aspell -a ...$args }
def sr [...args] { ^ssh -l root ...$args }
def symlink [...args] { ^ln --symbolic --relative ...$args }
def t  [...args] { ^tail ...$args }
def tf [...args] { t "-f" ...$args }
def tl [] { t "-f" "/var/log/syslog" }
def today [] { ^date '+%Y-%m-%d' }
def userctl [...args] { ^systemctl --user ...$args }
def userjournal [...args] { ^journalctl --user ...$args }
def userjnl [...args] { userjournal ...$args }
def view [...args] { ^vim -R -c ':set mouse=' ...$args }
def v    [...args] { view ...$args }
def vl [] { view /var/log/syslog }
def wcp [...args] { with_agent "scp" ...$args }
def wsh [...args] { with_agent "ssh" ...$args }
def xevkey [...args] { ^xev -event keyboard ...$args }
def xr [...args] { with-env { DISPLAY: ":0.0" } { ^xrandr ...$args } }

# ps with useful default options
def psc [...args] {
    ^ps -w -o user,pid,ppid,pgid,start_time,pcpu,rss,comm=EXE ...$args -o args=ARGS
}

# pgrep with default ps options
# psgrep [<ps options>] <pattern>
def psgrep [...args: string] {
    let pattern = ($args | last)
    let ps_args = ($args | drop 1)
    let pids = (^pgrep -d , -f $pattern | str trim)
    if ($pids | is-empty) {
        error $"No processes matching ($pattern)"
    } else {
        psc "-p" $pids ...$ps_args
    }
}

# list processes in the specified process group
def pgroup [...args] { ^pgrep -g ...$args }

# grep for a pattern in environments of matching processes
def pegrep [env_pattern: string, proc_pattern: string] {
    let pids = (^pgrep -f $"^($proc_pattern)" | lines)
    for pid in $pids {
        let head = (^ps -o pid= -o args= -p $pid | str trim)
        let envgrep = (envgrep $env_pattern $pid | str trim)
        print $"($head) ($envgrep)"
    }
}
def peg [env_pattern: string, proc_pattern: string] { pegrep $env_pattern $proc_pattern }

# grep for a pattern in the env of the given pids
def envgrep [pattern: string, ...pids: string] {
    for pid in $pids {
        ^grep -z $pattern $"/proc/($pid)/environ"
    }
}

# jc/sc/uc: journalctl/systemctl wrappers
def jc [...args] { ^journalctl --no-hostname ...$args }
def sc [...args] { ^systemctl ...$args }
def uc [...args] { ^systemctl --user ...$args }

# reload this config (exec a new shell — Nushell's `source` requires a
# constant path, so a genuine in-place reload is not supported)
def rerc [] {
    exec nu
}

###############################
# PACKAGE MANAGER ABSTRACTIONS
# Install/update/search/etc. map to apt-get or yum depending on what's
# available, mirroring the shrc.

def root [...args] {
    if (have_command "root") {
        ^root --nohome ...$args
    } else {
        ^sudo ...$args
    }
}

if (have_command "yum") {
    def update  [...args] { root "yum" "makecache" ...$args }
    def search  [...args] { ^yum search ...$args }
    def install [...args] { root "yum" "install" ...$args }
    def installed [...args] { ^rpm -qa ...$args }
    def uninstall [...args] { root "yum" "erase" ...$args }
    def reinstall [...args] { root "yum" "reinstall" ...$args }
    def autoremove [...args] { root "yum" "autoremove" ...$args }
    def upgrade [...args] { root "yum" "upgrade" ...$args }
    def versions [...args] { ^yum list ...$args }
    def files [...args] { ^repoquery --file ...$args }
} else if (have_command "apt-get") {
    def update  [...args] { root "apt-get" "update" ...$args }
    def search  [...args] { ^apt-cache search --names-only ...$args }
    def install [...args] { root "apt-get" "install" ...$args }
    def installed [...args] { ^dpkg-query --show --showformat '${binary:Package;-36} ${Version;-32} ${Status;-10}\n' ...$args }
    def uninstall [...args] { root "apt-get" "remove" ...$args }
    def reinstall [...args] { root "apt-get" "install" "--reinstall" ...$args }
    def autoremove [...args] { root "apt-get" "autoremove" ...$args }
    def upgrade [...args] { root "apt-get" "upgrade" ...$args }
    def versions [...args] { ^apt-cache policy ...$args }
    def files [...args] { ^apt-file search ...$args }
} else {
    # No supported package manager; define stubs so calling them is harmless.
    def update  [] { error "No supported package manager found" }
    def install [...args] { error "No supported package manager found" }
}

#######################
# VCS ALIASES
# Mirror the shrc: short commands delegate to the `vcs` helper when
# available. These are defined regardless of whether `vcs` is on PATH
# — the stub below fires a helpful error otherwise.

def vcs [...args: string] {
    if (have_command "vcs") {
        ^vcs ...$args
    }
}

def add        [...args] { vcs "add" ...$args }
def amend      [...args] { vcs "amend" ...$args }
def annotate   [...args] { vcs "annotate" ...$args }
def base       [...args] { vcs "base" ...$args }
def branch     [...args] { vcs "branch" ...$args }
def branches   [...args] { vcs "branches" ...$args }
def changed    [...args] { vcs "changed" ...$args }
def changelog  [...args] { vcs "changelog" ...$args }
def changes    [...args] { vcs "changes" ...$args }
def checkout   [...args] { vcs "checkout" ...$args }
def commit     [...args] { vcs "commit" ...$args }
def commitforce [...args] { vcs "commitforce" ...$args }
def diffs      [...args] { vcs "diffs" ...$args }
def fix        [...args] { vcs "fix" ...$args }
def graph      [...args] { vcs "graph" ...$args }
def incoming   [...args] { vcs "incoming" ...$args }
def lint       [...args] { vcs "lint" ...$args }
def map_       [...args] { vcs "map" ...$args }
def outgoing   [...args] { vcs "outgoing" ...$args }
def pending    [...args] { vcs "pending" ...$args }
def precommit  [...args] { vcs "precommit" ...$args }
def presubmit  [...args] { vcs "presubmit" ...$args }
def pull       [...args] { vcs "pull" ...$args }
def push       [...args] { vcs "push" ...$args }
def recommit   [...args] { vcs "recommit" ...$args }
def revert     [...args] { vcs "revert" ...$args }
def review     [...args] { vcs "review" ...$args }
def reword     [...args] { vcs "reword" ...$args }
def submit     [...args] { vcs "submit" ...$args }
def submitforce [...args] { vcs "submitforce" ...$args }
def unknown    [...args] { vcs "unknown" ...$args }
def upload     [...args] { vcs "upload" ...$args }
def uploadchain [...args] { vcs "uploadchain" ...$args }

# short aliases mirroring the fish config
def am [...args] { amend ...$args }
def ci [...args] { commit ...$args }
def di [...args] { diffs ...$args }
def gr [...args] { graph ...$args }
def lg [...args] { graph ...$args }
def ma [...args] { review ...$args }
def st [...args] { vcs "status" ...$args }

# clone a version control system repo based on the URL
def clone [url: string, ...args: string] {
    if ($url | str ends-with ".git") {
        ^git clone $url ...$args
    } else {
        ^hg clone $url ...$args
    }
}

######################
# INTERACTIVE: PROMPT / HOOKS
# Install the prompt closures on the first interactive run. Nushell reads
# config.nu for interactive sessions by default, so this section always
# runs in the interactive case.

$env.PROMPT_COMMAND = {|| render_prompt }
$env.PROMPT_COMMAND_RIGHT = {|| render_right_prompt }
$env.PROMPT_INDICATOR = ""
$env.PROMPT_INDICATOR_VI_INSERT = ""
$env.PROMPT_INDICATOR_VI_NORMAL = ""
$env.PROMPT_MULTILINE_INDICATOR = "_ "
$env.TRANSIENT_PROMPT_COMMAND = {|| render_transient_prompt }
$env.TRANSIENT_PROMPT_INDICATOR = ""
$env.TRANSIENT_PROMPT_INDICATOR_VI_INSERT = ""
$env.TRANSIENT_PROMPT_INDICATOR_VI_NORMAL = ""
$env.TRANSIENT_PROMPT_MULTILINE_INDICATOR = ""

# Nushell config tweaks: edit mode, history, etc.
$env.config = ($env.config | upsert edit_mode "emacs")
$env.config = ($env.config | upsert show_banner false)
$env.config = ($env.config | upsert history.file_format "plaintext")
$env.config = ($env.config | upsert history.max_size 5000)

# source local overrides file (work vs home, etc.)
# Nushell's `source` is a parse-time operation, so the file must exist at
# parse time. Create an empty ~/.config/nushell/local.nu to enable per-host
# overrides, then uncomment the line below.
# source ~/.config/nushell/local.nu
