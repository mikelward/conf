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
def --env prepend-path [dir: string] {
    if not ($dir | path exists) { return }
    $env.PATH = ($env.PATH | where {|it| $it != $dir } | prepend $dir)
}

# add $dir to the end of $env.PATH (if it exists and is not already there)
def --env append-path [dir: string] {
    if not ($dir | path exists) { return }
    $env.PATH = ($env.PATH | where {|it| $it != $dir } | append $dir)
}

# remove $dir from $env.PATH
def --env delete-path [dir: string] {
    $env.PATH = ($env.PATH | where {|it| $it != $dir })
}

# return true if $dir is already in $env.PATH
def inpath [dir: string] {
    $env.PATH | any {|it| $it == $dir }
}

# add $dir to $env.PATH at the given position (start, end, or default = append
# only if missing)
def --env add-path [dir: string, where?: string] {
    if not ($dir | path exists) { return }
    match $where {
        "start" => { prepend-path $dir }
        "end"   => { append-path $dir }
        _       => { if not (inpath $dir) { append-path $dir } }
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

# print a line to stdout
def puts [...args: string] {
    print ($args | str join " ")
}

# run a command with output silenced
def quiet [...args] {
    try { ^($args | first) ...($args | skip 1) out+err> /dev/null } catch { return }
}

# log the running of a command to $env.HISTORY_FILE, no-op if unset
def log-history [...args: string] {
    let file = ($env.HISTORY_FILE? | default "")
    if ($file | is-empty) { return }
    let ts = (^date "+%Y%m%d %H%M%S %z" | str trim)
    let tty = ($env.TTY? | default "")
    let msg = ($args | str join " ")
    $"($ts) ($tty) ($msg)(char newline)" | save --append $file
}

# return true if the named env var is set to a non-empty value
def is-env-set [name: string] {
    ($name in $env) and (($env | get $name | into string) | is-not-empty)
}

# prompt the user for a yes/no answer; default yes on empty reply
def confirm [prompt: string] {
    print -n $"($prompt)? [Y/n] "
    let reply = (^head -n 1 | str downcase | str trim)
    ($reply == "") or ($reply | str starts-with "y")
}

# hook for authenticating (e.g. to ssh-agent). Overridable: set
# $env.auth = {|| ... } in an autoload file for site-specific flows.
# Other config.nu callers (the startup `if (need-auth) { auth }` block,
# the `a` alias) dispatch through $env so the override takes effect.
# See the comment at the bottom of this file for why a plain `def` in an
# autoload file cannot override commands defined here.
$env.auth = {|| ^ssh-add }
def auth [] { do $env.auth }

# short alias for auth
def a [] { auth }

# return true if an SSH key is loaded into the agent
def is-ssh-valid [] {
    let r = (try { ^ssh-add -L | complete } catch { {exit_code: 1} })
    $r.exit_code == 0
}

# print a space-separated, yellow-colored list of auth problems, or ""
# if everything is fine. Mirrors shrc's auth_info. Overridable: set
# $env.auth-info = {|| ... } in an autoload file to report additional
# auth problems (Kerberos, AWS SSO, ...); need-auth dispatches through
# $env so the override propagates.
#
# TODO: reconcile this with `vcs prompt-line` (same question for shrc's
# auth_info and fish's auth_info).
$env.auth-info = {||
    let problems = (if (is-ssh-valid) { [] } else { ["SSH"] })
    if ($problems | is-empty) { "" } else { yellow ($problems | str join " ") }
}
def auth-info [] { do $env.auth-info }

# return true if auth-info reports any problems.
# TODO: see auth-info above (reconcile with `vcs prompt-line`).
def need-auth [] {
    (auth-info | is-not-empty)
}

# return true if the argument exists as an external command on $PATH,
# bypassing aliases and builtins. A plain `path exists` check isn't
# enough: a non-executable file in a PATH directory with the same name
# would pass it, but shrc's `have_command` (built on `test -x`) would
# correctly reject it. We shell out to /usr/bin/test here because nu
# has no builtin access() check; the absolute path avoids depending on
# the caller's $PATH (tests often scrub it). `any` short-circuits so
# cost is bounded to the first match (or PATH length for true negatives).
def have-command [name: string] {
    $env.PATH | any {|dir|
        let p = ([$dir $name] | path join)
        if not ($p | path exists) { return false }
        (try { ^/usr/bin/test -x $p | complete } catch { {exit_code: 1} }).exit_code == 0
    }
}

# return true if the argument is an alias, builtin, command, or function
def is-runnable [name: string] {
    (which $name | is-not-empty) or (have-command $name)
}

# return true if we're running interactively
def is-interactive [] {
    (is-terminal --stdin) and (is-terminal --stdout)
}

# return true if connected via SSH
def connected-via-ssh [] {
    is-env-set "SSH_CONNECTION"
}

# return true if this session is on a remote machine
def connected-remotely [] {
    connected-via-ssh
}

# return true if the current shell is attached to shpool
def in-shpool [] {
    is-env-set "SHPOOL_SESSION_NAME"
}

# return true if this is inside a VCS workspace/source root
def inside-project [] {
    ((projectroot) | is-not-empty)
}

# return true if we should try to run shpool
def want-shpool [] {
    (connected-remotely) or (inside-project)
}

# start shpool if this session warrants it, then exit the current shell.
# Mirrors shrc's maybe_start_shpool_and_exit.
def maybe-start-shpool-and-exit [] {
    if (not (in-shpool)) and (want-shpool) and (have-command "shpool") {
        let r = (^autoshpool | complete)
        if $r.exit_code == 0 { exit }
    }
}

# return true if inside tmux
def inside-tmux [] {
    is-env-set "TMUX"
}

# return true if the current user is root
def i-am-root [] {
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
def --env on-my-workstation [] {
    let host = ($env.HOSTNAME? | default "")
    let ws = (workstation)
    if ($ws | is-not-empty) and ($host == $ws) { return true }
    if ($host | str contains "laptop") { return false }
    let user = ($env.USERNAME? | default "")
    if ($user | is-not-empty) and ($host | str starts-with ($user + "-")) { return true }
    false
}

# return true if this machine is my laptop
def on-my-laptop [] {
    let f = ([$env.HOME ".laptop"] | path join)
    if ($f | path exists) { return true }
    (($env.HOSTNAME? | default "") | str contains "laptop")
}

# return true if this is a non-production machine I use to get work done
def --env on-my-machine [] {
    (on-my-workstation) or (on-my-laptop)
}

# return true if this is a test host
def on-test-host [] {
    (($env.HOSTNAME? | default "") | str contains "test")
}

# return true if this is a dev host
def on-dev-host [] {
    (($env.HOSTNAME? | default "") | str contains "dev")
}

# return true if this is a production machine. Overridable: set
# $env.on-production-host = {|| ... } in an autoload file if the default
# (not-my-machine and not-test and not-dev) doesn't match your fleet. This
# feeds the --production flag to `vcs prompt-line`, so overriding is the
# only way to change that flag's behaviour from user config.
$env.on-production-host = {||
    (not (on-my-machine)) and (not (on-test-host)) and (not (on-dev-host))
}
def --env on-production-host [] { do --env $env.on-production-host }

# return true if it's already obvious which host I'm on
def show-hostname-in-title [] {
    not (inside-tmux)
}

###################
# GENERAL FUNCTIONS

# print the age of a file in seconds
def age [file: path] {
    ((date now) - (ls -l $file | get 0.modified)) / 1sec
}

# look up a hostname in DNS, output A and AAAA records
def addr [host: string] {
    ^dig +noall +answer +search $host a $host aaaa | get-address-records
}

def ptr [ip: string] {
    ^dig +noall +answer -x $ip ptr | get-ptr-records
}

# read BIND-style DNS entries, print the A and AAAA records
def get-address-records [] {
    ^awk '$3 == "IN" && $4 ~ /^A/ { print $5 }'
}

# read BIND-style DNS entries, print the PTR records
def get-ptr-records [] {
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
    for f in $files {
        let s = ($f | into string)
        ^mv -i $s ($s + ".bak")
    }
}

# restore a .bak file (or back the restore direction)
def unbak [...files: path] {
    for f in $files {
        let s = ($f | into string)
        if ($s | str ends-with ".bak") {
            let dest = ($s | str substring 0..<(-4))
            if ($s | path exists) { ^mv -i $s $dest }
        } else {
            let src = ($s + ".bak")
            if ($src | path exists) { ^mv -i $src $s }
        }
    }
}

# ring the terminal's bell
def bell [] {
    print -n (char bel)
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

# Walk parent directories from $env.PWD looking for any of the given
# marker names; return the absolute path of the first directory that
# contains one, or "" if nothing is found before reaching "/". Used by
# the projectroot fallback, and factored out so the closure body stays
# a plain expression (no reliance on `return` inside a closure).
def find-project-root [markers: list<string>] {
    mut d = $env.PWD
    loop {
        for m in $markers {
            if (([$d $m] | path join) | path exists) { return $d }
        }
        if $d == "/" { return "" }
        $d = ($d | path dirname)
    }
}

# print the root directory of the current project. The default dispatches
# to `^vcs rootdir` when the helper binary is on PATH, since it knows
# about all the backends (jj, git, hg, citc, p4) and keeps its own
# cache. When the binary is missing, fall back to walking parents for
# the common VCS markers, mirroring shrc.vcs's shell-only fallback.
# The .vcs_cache half of that fallback is intentionally not ported:
# the parent walk is fast enough in nu and sidesteps cache-invalidation
# bugs.
#
# Overridable: set $env.projectroot = {|| ... } in an autoload file to
# plug in custom detection (workspace markers, monorepo layouts, ...).
# Other config.nu callers (inside-project, buildroot, projectname,
# want-shpool, maybe-start-shpool-and-exit, ...) dispatch through $env
# so the override propagates through the whole chain.
$env.projectroot = {||
    # Try `vcs rootdir` directly: it's the common case (vcs ships with
    # this repo and users normally have it installed) and skipping a
    # have-command pre-check halves the cost — one fork+exec instead
    # of two. When vcs isn't on PATH `^vcs` raises command-not-found
    # which the try catches; `null` is used as the sentinel because
    # `complete` always returns a record on success.
    let r = (try { ^vcs rootdir | complete } catch { null })
    if $r == null {
        find-project-root [".jj" ".hg" ".git" ".citc" ".p4config"]
    } else if $r.exit_code == 0 {
        $r.stdout | str trim
    } else {
        ""
    }
}
def projectroot [] { do $env.projectroot }

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
def find-up [file: string] {
    mut dir = $env.PWD
    loop {
        let candidate = ([$dir $file] | path join)
        if ($candidate | path exists) { return $candidate }
        if $dir == "/" { return "" }
        $dir = ($dir | path dirname)
    }
}

# forward the first --lines lines of stdin unchanged, then run the given
# command on the remaining body. e.g. `ps | body grep ps` or
# `netstat -tn | body --lines 2 grep ':22\>'`. The default header count is
# 1. Nushell's parser reserves bare `-N` flags for commands that declare
# them, so shrc/fish's `body -2 grep ssh` shorthand is spelled
# `body --lines=2 grep ssh` here.
def body [--lines (-l): int = 1, ...args: string] {
    let all = ($in | lines)
    let headers = ($all | first $lines)
    let body_lines = ($all | skip $lines)
    for h in $headers { print $h }
    $body_lines | str join (char newline) | ^($args | first) ...($args | skip 1)
}

# delete a specific line number from a file in place
def delline [line: int, file: path] {
    ^sed -i -e $"($line)d" $file
}

# see what changes a command would make to a file
# e.g. `trydiff mdformat README.md`
def trydiff [cmd: string, file: path] {
    let temp = ($"($file).trydiff.($nu.pid)")
    ^$cmd $file | save --force $temp
    # diff exits 1 when files differ, which is the common case here; don't
    # let nushell surface that as a command error.
    try { ^diff $file $temp }
    ^rm $temp
}

# replace a file with a sorted version of itself
def isort [file: path] {
    let tmp = (($file | into string) + ".bak")
    open --raw $file | lines | sort | str join (char newline) | save --force $tmp
    ^mv $tmp $file
}

# print the full path to an executable, ignoring aliases and functions.
# The explicit is-empty check avoids `get 0.path?` crashing on an empty
# list; `?` only makes the column optional, not the row index.
def which-path [name: string] {
    let matches = (which $name | where type == "external")
    if ($matches | is-empty) {
        error $"($name) not found"
    } else {
        print ($matches | first | get path)
    }
}

# show the most recently changed files
def recent [count?: int, ...args: string] {
    let n = ($count | default 10)
    ^ls -t -1 ...$args | lines | first $n
}

# keep trying a command until it works
def retry [--sleep (-s): duration = 10sec, ...cmd: string] {
    loop {
        let ok = (try { ^($cmd | first) ...($cmd | skip 1); true } catch { false })
        if $ok { bell; break }
        sleep $sleep
    }
}

# remove the ssh known host from the specified line number
def rmkey [line: int] {
    let known = ([$env.HOME ".ssh" "known_hosts"] | path join)
    ^sed -i -e $"($line)d" $known
}

# run a command with the first argument moved to the end
# e.g. first-arg-last grep ~/.history <args> runs grep <args> ~/.history
# With 1 arg it runs the command as-is (nothing to rearrange). 0 args
# is a usage error and surfaces as such rather than silently doing
# nothing, which would hide bugs in callers. Nushell's `get 1` errors
# on short lists, so the length guard avoids a confusing
# `access_beyond_end` crash.
def first-arg-last [...args: string] {
    match ($args | length) {
        0 => {
            error make {msg: "first-arg-last: usage: first-arg-last <command> [arg] [...]"}
        }
        1 => { ^($args | first) }
        _ => {
            let cmd = ($args | first)
            let first = ($args | get 1)
            let rest = ($args | skip 2)
            ^$cmd ...$rest $first
        }
    }
}

# pass leading -x options of a command to a different first positional arg.
# shift-options <command> <target> [-x ...] [args...]
# runs `<command> [-x ...] <target> [args...]`. Stops collecting options at
# the first non-option, at `-`, or at `--`.
def shift-options [command: string, target: string, ...args: string] {
    mut options = []
    mut rest = $args
    while ($rest | is-not-empty) {
        let head = ($rest | first)
        if ($head == "-") or ($head == "--") { break }
        if ($head | str starts-with "-") {
            $options = ($options | append $head)
            $rest = ($rest | skip 1)
        } else {
            break
        }
    }
    ^$command ...$options $target ...$rest
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

# run a command under a custom ssh-agent. Overridable: set
# $env.with-agent = {|...cmd| ... } in an autoload file to wrap calls in
# `ssh-agent sh -c`, source a pinned $SSH_AUTH_SOCK, or whatever your
# flow needs. Callers (wcp, wsh) dispatch through $env so the override
# takes effect.
$env.with-agent = {|...cmd|
    ^($cmd | first) ...($cmd | skip 1)
}
def with-agent [...cmd] { do $env.with-agent ...$cmd }

# print the definition of the given command, alias, or function.
# Mirrors shrc's `what` (`whence -f` / `typeset -f`) and fish's `type`:
# for custom defs and aliases, print the source; for externals, print
# the absolute path; for nu built-ins and keywords, print the `which`
# row so the caller still gets something useful. The explicit `print`
# around `view source` is load-bearing: a bare `view source` at the
# end of a function returns a string, and intermediate return values
# get discarded when `what` is called from a longer pipeline/script.
def what [name: string] {
    let matches = (which $name)
    if ($matches | is-empty) {
        error $"($name) not found"
        return
    }
    let info = ($matches | first)
    match $info.type {
        "custom" | "alias" => { print (view source $name) }
        "external" => { print $info.path }
        _ => { print $info }
    }
}

# get a short version of the hostname for use in the prompt or window title
def short-hostname [] {
    let h = (($env.HOSTNAME? | default "") | split row "." | first)
    let user = ($env.USERNAME? | default "")
    if ($user | is-not-empty) {
        $h | str replace --regex $"^($user)-" ""
    } else {
        $h
    }
}

# print a short version of $PWD for the title: project name or basename
def short-pwd [] {
    let p = (projectname)
    if ($p | is-not-empty) { $p } else { $env.PWD | path basename }
}

# print project name, else basename of PWD
def project-or-pwd [] {
    let p = (projectname)
    if ($p | is-not-empty) { $p } else { $env.PWD | path basename }
}

# print the current session name (shpool or tmux), with trailing space
def session-name [] {
    if (in-shpool) {
        $"($env.SHPOOL_SESSION_NAME) "
    } else if (inside-tmux) {
        let s = (^tmux display-message -p '#S' | str trim)
        $"($s) "
    } else {
        ""
    }
}

##################################
# ENVIRONMENT SETUP
# Set $PATH and other variables.

$env.CDPATH = [
    "."
    $env.HOME
]
$env.GOPATH = $env.HOME

add-path "/usr/local/bin"
add-path ([$env.HOME "android-sdk-linux" "platform-tools"] | path join)
add-path ([$env.HOME "android-studio" "bin"] | path join)
add-path ([$env.HOME "Android" "Sdk" "platform-tools"] | path join)
add-path ([$env.HOME "depot_tools"] | path join)
add-path ([$env.HOME "google-cloud-sdk" "bin"] | path join)
add-path ([$env.HOME ".cargo" "bin"] | path join)
add-path ([$env.HOME ".local" "bin"] | path join)
add-path ([$env.HOME "bin"] | path join) "start"
add-path ([$env.GOPATH "bin"] | path join) "start"
add-path ([$env.HOME "scripts"] | path join) "start"

# scripts.home, scripts.work, etc. override scripts
let _scripts_dirs = (try { glob ($env.HOME + "/scripts.*") } catch { [] })
for dir in $_scripts_dirs {
    add-path ($dir | into string) "start"
}
let _opt_bins = (try { glob "/opt/*/bin" } catch { [] })
for dir in $_opt_bins {
    add-path ($dir | into string) "end"
}
add-path "/sbin" "end"
add-path "/usr/sbin" "end"

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
if (is-runnable "vi")       { $env.EDITOR = "vi" }
if (is-runnable "vim")      { $env.EDITOR = "vim" }
if (is-runnable "editline") { $env.EDITOR = "editline" }
if (is-runnable "more")     { $env.PAGER  = "more" }
if (is-runnable "less")     { $env.PAGER  = "less" }
if (is-runnable "meld") and (is-env-set "DISPLAY") {
    $env.DIFF = "meld"
}

# program defaults
$env.BLOCKSIZE = "1024"
$env.CLICOLOR = "true"
$env.GREP_COLOR = "4"
$env.GREP_COLORS = "mt=4"

# colors for ls
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
# A first line showing host/dir/auth, a separator bar, and a simple prompt
# character. VCS info is delegated to `vcs prompt-line` when the helper
# binary is available.

# Print the argument wrapped in ANSI color escapes. Nushell prints the ANSI
# sequences unconditionally; callers that don't want color should set
# $env.NO_COLOR and strip them. `red` shadows the /bin/red binary.
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
def maybe-space [...args: string] {
    let s = ($args | str join " ")
    if ($s | is-not-empty) { $" ($s)" } else { "" }
}

# format a duration (given as nanoseconds or a duration) as h/m/s
def format-duration [d: duration] {
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

# print "took <duration>\n" for the previous command when $env.CMD_DURATION
# is set by the pre_prompt hook; returns "" if no command just finished or
# the duration is below format-duration's display threshold. Mirrors the
# duration half of shrc's last_job_info.
def last-job-info [] {
    let dur = ($env.CMD_DURATION? | default 0sec)
    let s = (format-duration $dur)
    if ($s | is-empty) { "" } else {
        (yellow $"took ($s)") + (char newline)
    }
}

# print the first line of the preprompt: host + dir + auth.
# Delegates to `vcs prompt-line` so the whole line renders in one process.
def --env prompt-line [] {
    let color_flag = if (($env.NO_COLOR? | default "") | is-empty) { "--color=always" } else { "--color=never" }
    let production = if (on-production-host) { ["--production"] } else { [] }
    let host = (short-hostname)
    try {
        ^vcs prompt-line $"--hostname=($host)" $color_flag ...$production | str trim
    } catch {
        # fallback if vcs binary is unavailable
        $"($host) ((session-name))((project-or-pwd))"
    }
}

# print the string that should be used as the xterm title
def title [] {
    let parts = if (show-hostname-in-title) {
        [(short-hostname) " " (session-name) (project-or-pwd)]
    } else {
        [(session-name) (project-or-pwd)]
    }
    $parts | str join
}

# return the OSC escape sequence to set the terminal window title, or
# "" for terminals that don't understand xterm-style titles. Mirrors
# the common cases from shrc's init_title_sequences.
def title-escape [t: string] {
    let term = ($env.TERM? | default "")
    let supported = (
        ($term == "xterm") or ($term | str starts-with "xterm-") or
        ($term == "rxvt")  or ($term | str starts-with "rxvt-")  or
        ($term == "aixterm") or ($term == "dtterm") or
        ($term == "putty")   or ($term | str starts-with "putty-") or
        ($term == "kitty")
    )
    if $supported {
        $"(char -u "1b")]0;($t)(char bel)"
    } else {
        ""
    }
}

# print a character that should be the last part of the prompt
def ps1-character [] {
    if (i-am-root) { "#" } else { ">" }
}

# return the bell character for xterm-family terminals so the caller
# can inline it into the prompt; returns "" otherwise. Silent in other
# terminals since the BEL byte would print literally.
def flash-terminal [] {
    let t = ($env.TERM? | default "")
    if ($t == "xterm") or ($t | str starts-with "xterm-") {
        (char bel)
    } else {
        ""
    }
}

# the main Nushell PROMPT_COMMAND callback.
# Outputs (optional) last-job-info line, sets the xterm title, optionally
# rings the bell, then prints newline + separator bar + CR + prompt-line.
# The CR overwrites the start of the bar, leaving the trailing bar chars
# visible after the prompt line.
def --env render-prompt [] {
    let info = (last-job-info)
    let cols = (try { term size | get columns } catch { 80 })
    let sep = (bar $cols)
    let line = (prompt-line)
    let nl = (char newline)
    let cr = (char cr)
    let title_seq = (title-escape (title))
    let bell = (flash-terminal)
    $"($bell)($info)($title_seq)($nl)($sep)($cr)($line) ($nl)((ps1-character)) "
}

def render-right-prompt [] { "" }

# used by Nushell's transient prompt (shown for previous prompts) so the
# separator bar and VCS line aren't repeated in scrollback.
def render-transient-prompt [] {
    $"((ps1-character)) "
}

#########################
# INTERACTIVE: ALIASES AND COMMANDS
# Short command wrappers for everyday use. Defined with `def` (rather than
# `alias`) so they can accept arguments consistently and still work when
# shadowing Nushell builtins.

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

def gh-search [...args] {
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
    if (have-command "l") {
        ^l -K -v -e -x ...$args
    } else {
        ^ls --color=auto -v -b -x ...$args
    }
}
def ll [...args: string] {
    if (have-command "l") {
        ^l -K -v -e -x -p -T -B -V -h --time-style=relative ...$args
    } else {
        ^ls --color=auto -v -b -x -l ...$args
    }
}
def lt [...args: string] {
    if (have-command "l") {
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
def rh [...args] { gh-search ...$args | last 20 }
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
def wcp [...args] { with-agent "scp" ...$args }
def wsh [...args] { with-agent "ssh" ...$args }
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
# available.

def root [...args] {
    if (have-command "root") {
        ^root --nohome ...$args
    } else {
        ^sudo ...$args
    }
}

if (have-command "yum") {
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
} else if (have-command "apt-get") {
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
# Thin aliases over the `vcs` helper binary. These are aliases rather
# than `def` wrappers for two reasons:
#
#   1. `alias X = ^vcs X` is a parse-time substitution, so flags pass
#      through to ^vcs without nushell's flag parser catching them on
#      the wrapper. With `def X [...args] { ^vcs X ...$args }` typing
#      `ci -m "msg"` errors with `unknown flag -m` because the custom
#      command's signature doesn't declare it. `def --wrapped` works
#      too, but alias is shorter and expresses the intent better.
#
#   2. If `vcs` isn't on PATH, calling one of these surfaces a clear
#      "command not found" error instead of silently doing nothing as
#      the previous `if (have-command "vcs") { ... }` dispatcher did.
#
# TODO: this list is hand-maintained and drifts from shrc.vcs / the
# `vcs` binary's actual command set. The `vcs` binary supports
# `--list-commands` which prints every subcommand; we should generate
# this file from that output. Options under consideration:
#   (a) A nu generator script invoked from vcs/Makefile's install
#       target, writing $nu.default-config-dir/vcs-aliases.nu, which
#       config.nu then `source`s with a const path.
#   (b) Run the generator from profile/xsession on login so machines
#       that never `make install` still get the aliases in sync.
# Whatever shape this takes, the canonical list should be the binary
# itself, not a file in this repo. The list below is missing roughly
# half of what the binary ships (blame, drop, evolve, rebase, resolve,
# restore, squash, status, track, uncommit, undo, etc.).

alias add         = ^vcs add
alias amend       = ^vcs amend
alias annotate    = ^vcs annotate
alias base        = ^vcs base
alias branch      = ^vcs branch
alias branches    = ^vcs branches
alias changed     = ^vcs changed
alias changelog   = ^vcs changelog
alias changes     = ^vcs changes
alias checkout    = ^vcs checkout
alias commit      = ^vcs commit
alias commitforce = ^vcs commitforce
alias diffs       = ^vcs diffs
alias fix         = ^vcs fix
alias graph       = ^vcs graph
alias incoming    = ^vcs incoming
alias lint        = ^vcs lint
alias map         = ^vcs map
alias outgoing    = ^vcs outgoing
alias pending     = ^vcs pending
alias precommit   = ^vcs precommit
alias presubmit   = ^vcs presubmit
alias pull        = ^vcs pull
alias push        = ^vcs push
alias recommit    = ^vcs recommit
alias revert      = ^vcs revert
alias review      = ^vcs review
alias reword      = ^vcs reword
alias submit      = ^vcs submit
alias submitforce = ^vcs submitforce
alias unknown     = ^vcs unknown
alias upload      = ^vcs upload
alias uploadchain = ^vcs uploadchain

# short aliases — hand-picked, not generated
alias am = ^vcs amend
alias ci = ^vcs commit
alias di = ^vcs diffs
alias gr = ^vcs graph
alias lg = ^vcs graph
alias ma = ^vcs review
alias st = ^vcs status

# clone a version control system repo based on the URL
def clone [url: string, ...args: string] {
    if ($url | str ends-with ".git") {
        if (have-command "jj") {
            ^jj git clone $url ...$args
        } else if (confirm "jj is not installed. Clone using git") {
            ^git clone $url ...$args
        }
    } else if ($url | str contains "/hg") {
        ^hg clone $url ...$args
    }
}

######################
# INTERACTIVE: PROMPT / HOOKS
# Install the prompt closures on the first interactive run. Nushell reads
# config.nu for interactive sessions by default, so this section always
# runs in the interactive case.

$env.PROMPT_COMMAND = {|| render-prompt }
$env.PROMPT_COMMAND_RIGHT = {|| render-right-prompt }
$env.PROMPT_INDICATOR = ""
$env.PROMPT_INDICATOR_VI_INSERT = ""
$env.PROMPT_INDICATOR_VI_NORMAL = ""
$env.PROMPT_MULTILINE_INDICATOR = "_ "
$env.TRANSIENT_PROMPT_COMMAND = {|| render-transient-prompt }
$env.TRANSIENT_PROMPT_INDICATOR = ""
$env.TRANSIENT_PROMPT_INDICATOR_VI_INSERT = ""
$env.TRANSIENT_PROMPT_INDICATOR_VI_NORMAL = ""
$env.TRANSIENT_PROMPT_MULTILINE_INDICATOR = ""

# Nushell config tweaks: edit mode, history, etc.
$env.config = ($env.config | upsert edit_mode "emacs")
$env.config = ($env.config | upsert show_banner false)
$env.config = ($env.config | upsert history.file_format "plaintext")
$env.config = ($env.config | upsert history.max_size 100000)

# Capture command timing so render-prompt can show the previous command's
# duration via last-job-info. pre_execution fires just before the user's
# command runs; pre_prompt fires just before the next prompt is drawn.
$env.config = ($env.config | upsert hooks.pre_execution [{||
    $env.CMD_START_TIME = (date now)
}])
$env.config = ($env.config | upsert hooks.pre_prompt [{||
    let start = ($env.CMD_START_TIME? | default null)
    if $start != null {
        $env.CMD_DURATION = ((date now) - $start)
    } else {
        $env.CMD_DURATION = 0sec
    }
    $env.CMD_START_TIME = null
}])

# Trailing-slash autocd: no hook needed. Nushell's REPL already cds
# when a path to an existing directory is entered bare, including
# `foo/`, `./foo/`, `/abs/path/`, and `../`. Bare names without a path
# separator (`foo`) still go through command lookup and error if not
# found, which matches shrc's maybe_autocd_trailing_slash. This is a
# REPL-only behavior -- `nu -c './foo/'` errors -- so the nushell test
# suite only asserts that no overriding hook is installed and that an
# explicit `cd ./foo/` still works.

# Maybe attach to shpool instead of running a bare nu interactively.
# Skipped in non-interactive mode so the test suite stays quiet. Mirrors
# shrc's `maybe_start_shpool_and_exit` call on startup.
if (is-interactive) {
    maybe-start-shpool-and-exit
}

# Log session start to $env.HISTORY_FILE, matching shrc/fish.
if (is-interactive) {
    log-history $"New session as ($env.USERNAME? | default ''): nu"
}

# authenticate on startup if needed, mirroring shrc's startup check.
# Skipped when attached to a shpool session (credentials come from the
# parent) and when non-interactive (so the nushell test suite is quiet).
if (is-interactive) and (not (in-shpool)) {
    if (need-auth) { auth }
}

# Local overrides (work vs home, per-host tweaks, etc.) go in the user
# autoload directory: ~/.config/nushell/autoload/*.nu. Nushell auto-sources
# every *.nu file there at startup and silently skips the directory if it
# doesn't exist, so no conditional `source` line is needed here. (Requires
# nushell 0.101+.)
#
# Two kinds of override are possible in an autoload file:
#
#   1. Add a brand-new command, or `def` a command that you'll call from
#      the REPL. These work because the REPL is parsed after the autoload
#      file, so the new definition is what the parser sees.
#
#   2. Change what an existing config.nu hook returns: set one of the
#      $env.* closures below. The helpers in this file dispatch through
#      those closures with `do`, which is looked up at runtime, so the
#      override propagates into every caller.
#
# You CANNOT redefine an arbitrary config.nu command (e.g. `short-pwd`,
# `l`, `psgrep`) with a plain `def` in an autoload file and expect other
# config.nu helpers to see the change. Nushell resolves `def`-to-`def`
# calls at parse time, and config.nu is fully parsed before the autoload
# file runs, so the internal callers stay frozen to the original
# definitions. Direct REPL calls to the redefined name will pick up the
# override, but code inside this file will not.
#
# The intentional hook points, which all use the $env.* pattern, are:
#
#   $env.projectroot         {|| ... } -> string
#   $env.auth                {|| ... }
#   $env.with-agent          {|...cmd| ... }
#   $env.on-production-host  {|| ... } -> bool
#
# Example autoload file — override $env.projectroot to recognise a
# custom workspace marker in addition to the default .git/.jj/.hg walk:
#
#   # ~/.config/nushell/autoload/local.nu
#   $env.projectroot = {||
#       mut d = $env.PWD
#       loop {
#           if (([$d "WORKSPACE"] | path join) | path exists) { return $d }
#           if $d == "/" { return "" }
#           $d = ($d | path dirname)
#       }
#   }
