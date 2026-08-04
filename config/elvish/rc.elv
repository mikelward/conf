# Configuration for Elvish (https://elv.sh), read as ~/.config/elvish/rc.elv
# every time Elvish starts interactively.
#
# This is the Elvish port of `shrc`, kept in parity with shrc (bash/zsh),
# config/fish/config.fish, config/nushell/config.nu, and the mesh pair
# config/mesh/env.mesh + config/mesh/rc.mesh.
#
# Three things about Elvish shape this file, and each is worth knowing before
# reading it:
#
#  1. There is no environment half. Elvish reads rc.elv only when it starts
#     interactively, so `elvish script.elv` never sees any of this -- see the
#     TODO above setup-path. Everything therefore lives in one file, which is
#     also how shrc is arranged.
#
#  2. Names are resolved when a file is *compiled*, so a function must be
#     defined above every use of it. The section order below is shrc's wherever
#     that constraint allows; where it doesn't, the definition has moved up and
#     says so.
#
#  3. The line editor lives elsewhere. `$edit:` exists only when Elvish has a
#     terminal to edit on, so naming `$edit:prompt` here would make the whole
#     file fail to compile under `echo cmd | elvish`, which reads rc.elv but has
#     no editor. `use` is resolved when it runs, so the editor wiring sits in
#     lib/interactive.elv and is pulled in only once we know there is a
#     terminal. That is also what lets the test suite load this file without a
#     pty.
#
# Names are kebab-case to match Elvish's own vocabulary (`has-external`,
# `tilde-abbr`), the same rule the mesh config follows.
#
# Mikel Ward <mikel@mikelward.com>

use str
use re
use os
use path
use math

###############
# FAILSAFE
# Cross-shell escape hatch. Mirrors shrc's FAILSAFE check and the equivalents
# in config.fish, config.nu and env.mesh: bail out before touching PATH or the
# environment, so a misbehaving rc is recoverable with `FAILSAFE=1 elvish`.
# LC_FAILSAFE is accepted as an alias so the flag survives sshd's env
# sanitization (most sshd configs AcceptEnv LC_*). ~/.failsafe is the
# persistent opt-in: `touch ~/.failsafe` keeps every new shell in failsafe mode
# without re-setting the variable.
#
# TODO: this skips the *actions*, not the definitions. The other four shells
# `return` out of the file; Elvish has no top-level return (it raises an
# exception and prints it), so the definitions below always run and failsafe
# mode is gated on $failsafe-mode at the one acting block, at the bottom. A
# definition that fails to compile therefore still takes the file down -- which
# is one of the cases the other four shells' failsafe recovers from.

# read an environment variable, or a default when it isn't set
fn env-or {|name default|
    if (has-env $name) { put (get-env $name) } else { put $default }
}

# On for 1/true, off for 0/false. Anything else is a typo rather than a third
# spelling -- someone writing FAILSAFE=yes meant *on*, and silently reading it
# as off leaves them wondering why nothing happened -- so it is reported and
# read as off. Kept in step with shrc's failsafe_flag and mesh's `:bool`.
fn failsafe-flag {|name value|
    if (or (==s $value 1) (==s $value true)) { put $true; return }
    if (or (==s $value 0) (==s $value false)) { put $false; return }
    echo "rc.elv: "$name"="$value" is not 1/0/true/false, reading as false" >&2
    put $false
}

fn failsafe-wanted {
    if (failsafe-flag FAILSAFE (env-or FAILSAFE 0)) { put $true; return }
    if (failsafe-flag LC_FAILSAFE (env-or LC_FAILSAFE 0)) { put $true; return }
    put (os:exists $E:HOME/.failsafe)
}

var failsafe-mode = (failsafe-wanted)
if $failsafe-mode { echo "failsafe mode" >&2 }

#################
# BASIC HELPERS
# Small predicates the rest of this file is written in terms of. Elvish owns
# `echo`, `print` and `read-line`, so only the stderr twins need defining.

# print an important message that's not quite an error
fn warn {|@args| echo $@args >&2 }

# print an error message
fn error {|@args| echo $@args >&2 }

# Resolve a command word to something callable.
#
# Elvish runs a bare string as a command only when it contains a slash, so a
# command *name* taken from an argument list -- `retry ping ...`, `body grep
# ...` -- has to be looked up on PATH explicitly. A closure passes straight
# through, so an Elvish function can be delegated to as `retry $my-fn~`, and
# an external named the same as a function here reads as `$e:ls~`.
fn as-command {|cmd|
    if (eq (kind-of $cmd) fn) { put $cmd; return }
    put (external $cmd)
}

# return true if the argument exists as a command on PATH, ignoring functions
fn have-command {|name| has-external $name }

# print the full path to an executable, ignoring functions
fn path-of {|name| search-external $name }

# return true if the argument is runnable at all.
#
# Elvish has no reflection over its own namespaces -- `eval` runs in a fresh
# namespace inheriting only the builtins, so it cannot be asked whether a name
# this file defines is bound -- so this covers external commands, which is what
# every caller here actually asks about (vi, vim, less, tput). shrc's
# is_runnable also covers functions, builtins and aliases.
fn is-runnable {|name| has-external $name }

# run a command with its output silenced. Callers ask about the result with
# `?(quiet ...)`, since a failing external command raises rather than returning
# a status.
fn quiet {|cmd @args| (as-command $cmd) $@args >/dev/null 2>&1 }

# run a command, discarding both its output and its failure. Each call site
# says in one line why that particular failure is uninteresting.
fn try-quiet {|cmd @args| try { quiet $cmd $@args } catch _ { } }

# capture a command's stdout as one string, or "" when it failed. `dig` missing
# an answer, `getent` missing a host and `pgrep` matching nothing all report the
# miss by exiting non-zero with nothing on stdout, which is the case this
# collapses. &quiet also drops the command's stderr, for the callers where a
# miss is the ordinary outcome and its diagnostic is noise.
fn capture-or-empty {|cmd @args &quiet=$false|
    var out = ''
    try {
        if $quiet {
            set out = ((as-command $cmd) $@args 2>/dev/null | slurp)
        } else {
            set out = ((as-command $cmd) $@args | slurp)
        }
    } catch _ { }
    put $out
}

# the numeric exit status behind a caught exception, or 0 for no exception.
# Anything that isn't an external command exiting -- a signal, an Elvish error
# -- reads as 1, the way a shell would report it.
fn exit-status {|err|
    if (eq $err $nil) { put 0; return }
    var reason = $err[reason]
    if (and (has-key $reason type) (==s $reason[type] external-cmd/exited)) {
        put $reason[exit-status]
        return
    }
    put 1
}

# capture a command's stdout with surrounding whitespace removed
fn capture-word {|cmd @args &quiet=$false|
    put (str:trim-space (capture-or-empty $cmd $@args &quiet=$quiet))
}

# print a captured multi-line string as one space-separated line
fn one-line {|text|
    put (str:join ' ' [(all [(str:split "\n" $text)] | each {|part|
        if (not-eq (str:trim-space $part) '') { put (str:trim-space $part) }
    })])
}

# split a string on runs of whitespace, the way `read` and awk do. `ip -o`,
# `getent hosts` and `df` all pad their columns, so a literal single-space
# split leaves empty fields between them.
fn fields {|text| put [(all [(re:split '[ \t]+' (str:trim-space $text))] | each {|f|
    if (not-eq $f '') { put $f }
})] }

# integer division. Elvish's `/` yields an exact rational (`(/ 7 2)` is 7/2),
# which is right for arithmetic and wrong for "how many whole minutes".
fn int-div {|a b| exact-num (math:floor (/ $a $b)) }

# run a command with extra environment variables set for that call only -- the
# `VAR=value cmd` prefix bash, fish and mesh have and Elvish does not.
# `env-run [TZ UTC] date` runs `date` with TZ=UTC and puts TZ back afterwards.
fn env-run {|pairs cmd @args|
    var saved = [&]
    var names = []
    var i = 0
    while (< $i (count $pairs)) {
        var name = $pairs[$i]
        set saved[$name] = (if (has-env $name) { get-env $name } else { put $nil })
        set names = [$@names $name]
        set-env $name $pairs[(+ $i 1)]
        set i = (+ $i 2)
    }
    # `defer` rather than a plain restore after the call: the command may fail,
    # and an exception must not leave this shell's environment rewritten.
    defer {
        for name $names {
            if (eq $saved[$name] $nil) { unset-env $name } else { set-env $name $saved[$name] }
        }
    }
    (as-command $cmd) $@args
}

# run a body in another directory, returning to this one afterwards. Elvish's
# `cd` has no subshell to confine it to, so the restore is explicit.
fn tmp-cd {|dir body|
    var here = $pwd
    cd $dir
    defer { cd $here }
    $body
}

##############
# COLORS
# Elvish renders color itself through `styled`, but a captured styled value
# still carries its escapes into a pipe, so color is gated on $color the way
# shrc gates on tput. Defined here rather than down in the PROMPT section
# because auth-info, which the host predicates lead into, is already colored.

# whether to emit color escapes
var color = $true

fn init-colors {
    set color = $true
    # NO_COLOR and a dumb or unset TERM are what the other shells' tput probe
    # works out for itself.
    if (has-env NO_COLOR) { set color = $false }
    if (has-value [dumb ''] (env-or TERM '')) { set color = $false }
}

fn color-text {|code text|
    if (not $color) { put $text; return }
    put "\e["$code"m"$text"\e[0m"
}
fn blue {|@a| color-text 34 (str:join ' ' $a) }
fn green {|@a| color-text 32 (str:join ' ' $a) }
fn red {|@a| color-text 31 (str:join ' ' $a) }
fn yellow {|@a| color-text 33 (str:join ' ' $a) }

####################
# STANDARD VARIABLES
# The bash-like variables everything assumes are preset. Each is only computed
# when it isn't already in the environment, so a shell started from one of
# these pays no fork for it.

fn set-up-standard-variables {
    if (not (has-env USERNAME)) { set-env USERNAME (capture-word id -un) }
    if (not (has-env HOSTNAME)) { set-env HOSTNAME (capture-word hostname -f) }
    if (not (has-env UID)) { set-env UID (capture-word id -u) }
    # `tty` prints "not a tty" on *stdout* and exits 1 when stdin isn't a
    # terminal, so the name is only kept when the capture succeeded --
    # exporting the diagnostic would put "not a tty" into every child's TTY,
    # and into every log-history line.
    if (not (has-env TTY)) { set-env TTY (capture-word tty &quiet=$true) }
}

#######
# PATH FUNCTIONS
# Elvish keeps $PATH as the list `$paths`, so these are list operations rather
# than the string surgery shrc needs.

# remove $dir from $paths
fn delete-path {|dir|
    set paths = [(all $paths | each {|d| if (not-eq $d $dir) { put $d } })]
}

# return true if $dir is already on $paths
fn inpath {|dir| has-value $paths $dir }

# add $dir to the front of $paths, if it exists
fn prepend-path {|dir|
    if (not (os:is-dir $dir)) { return }
    delete-path $dir
    set paths = [$dir $@paths]
}

# add $dir to the end of $paths, if it exists
fn append-path {|dir|
    if (not (os:is-dir $dir)) { return }
    delete-path $dir
    set paths = [$@paths $dir]
}

# add $dir to $paths at the given position: `start`, `end`, or -- with no
# position -- append only when it isn't there already
fn add-path {|dir &where=''|
    if (==s $where start) { prepend-path $dir; return }
    if (==s $where end) { append-path $dir; return }
    if (inpath $dir) { return }
    append-path $dir
}

#####################
# SHELL-ENV GENERATORS
# brew and fnm publish their environment as a shell snippet meant for `eval`.
# Elvish's `eval` takes Elvish, not sh, and has no dynamically-named
# environment write, so the generic "read KEY=VALUE and apply it" helper --
# shrc's eval_tool_init, fish's `| source` -- cannot be written here. Both
# tools are handled by name instead, exactly as config/mesh/env.mesh does:
# brew's snippet is a fixed set of assignments derived from its prefix, and
# fnm's is parsed into the variables fnm is documented to set.

# Take the leading quoted run of a shell word, or the whole word when it isn't
# quoted. `fnm env` writes PATH as `"/.../bin":$PATH` -- the closing quote is in
# the middle, not at the end -- so trimming quotes off both ends would leave a
# stray one behind. Splitting on the quote character gives the quoted run as
# the second field either way.
fn unquoted-head {|value|
    if (str:has-prefix $value '"') { put [(str:split '"' $value)][1]; return }
    if (str:has-prefix $value "'") { put [(str:split "'" $value)][1]; return }
    put $value
}

# Split one `export KEY="VALUE"` line into [name value], or [] when it isn't an
# assignment. A trailing `;` is dropped and the value is unquoted.
#
# No shell expansion is performed: the callers handle the one variable that
# needs splicing -- PATH -- by name, since Elvish holds it as a list.
fn shellenv-entry {|line|
    var entry = (str:trim-space $line)
    if (==s $entry '') { put []; return }
    if (str:has-prefix $entry '#') { put []; return }
    set entry = (str:trim-prefix $entry 'export ')
    set entry = (str:trim-suffix $entry ';')
    if (not (re:match '^[A-Za-z_][A-Za-z0-9_]*=' $entry)) { put []; return }
    var name = [(str:split '=' $entry)][0]
    put [$name (unquoted-head (str:trim-prefix $entry $name'='))]
}

# brew is often off-PATH (Linuxbrew's prefix isn't on the default PATH), so
# fall back to known locations; $BREW overrides the search (tests). Rather than
# eval'ing `brew shellenv`, derive the same variables from the prefix -- which
# is all that snippet does.
fn setup-brew {
    var brew-bin = ''
    if (have-command brew) {
        set brew-bin = (path-of brew)
    } else {
        for candidate [(env-or BREW '') /opt/homebrew/bin/brew /usr/local/bin/brew ^
                       /home/linuxbrew/.linuxbrew/bin/brew $E:HOME/.linuxbrew/bin/brew] {
            if (and (not-eq $candidate '') (os:exists $candidate)) {
                set brew-bin = $candidate
                break
            }
        }
    }
    if (==s $brew-bin '') { return }
    # `<prefix>/bin/brew` is the layout every real install has, so the prefix is
    # the grandparent -- and it must *not* be resolved through symlinks, since
    # `bin/brew` points into `$prefix/Homebrew` on Linuxbrew and Intel macOS and
    # following it would name the repo as the prefix.
    #
    # That derivation is wrong only when brew was reached through a shim outside
    # its own tree (`~/bin/brew` -> the real one), where the grandparent is
    # `$HOME`. `$prefix/Cellar` is what tells the two apart -- Homebrew creates
    # it at install time -- and only then is brew asked, so the usual case pays
    # no fork where shrc's `eval "$(brew shellenv)"` pays one every time.
    var prefix = (path:dir (path:dir $brew-bin))
    if (not (os:is-dir $prefix/Cellar)) {
        var answer = (capture-word $brew-bin --prefix &quiet=$true)
        # Nothing usable to fall back to: the derived prefix is already known
        # wrong (that is what brought us here), so publishing it would export
        # bogus HOMEBREW_* and prepend bin/sbin from an unrelated tree. Say so
        # and leave brew unconfigured, which at least keeps PATH honest.
        if (==s $answer '') {
            warn "brew: cannot determine the install prefix; brew is not set up"
            return
        }
        set prefix = $answer
    }
    set-env HOMEBREW_PREFIX $prefix
    set-env HOMEBREW_CELLAR $prefix/Cellar
    # The Homebrew git repo is at $prefix/Homebrew under Linuxbrew and Intel
    # macOS, and at the prefix itself on Apple silicon; pick whichever is there,
    # as config/nushell/config.nu does.
    if (os:is-dir $prefix/Homebrew) {
        set-env HOMEBREW_REPOSITORY $prefix/Homebrew
    } else {
        set-env HOMEBREW_REPOSITORY $prefix
    }
    prepend-path $prefix/sbin
    prepend-path $prefix/bin
    # Both search paths are rebuilt idempotently, because `rerc` re-reads this
    # file: a plain prepend would put the same brew dir on the front again on
    # every reload and grow the list without bound, the way `add-path` avoids
    # for PATH by deleting first. The trailing empty component is
    # `brew shellenv`'s, and keeps the system man directories searchable:
    # MANPATH always ends in one, INFOPATH only when it was unset.
    var man-dir = $prefix/share/man
    var man-path = [(all [(str:split ':' (env-or MANPATH ''))] | each {|d|
        if (and (not-eq $d $man-dir) (not-eq $d '')) { put $d }
    })]
    set-env MANPATH (str:join ':' [$man-dir $@man-path ''])
    # An empty *interior* component of INFOPATH means "and the system defaults
    # here", so those are kept where MANPATH's are dropped.
    var info-path = [(all [(str:split ':' (env-or INFOPATH ''))] | each {|d|
        if (not-eq $d $prefix/share/info) { put $d }
    })]
    if (has-value [[] ['']] $info-path) {
        set-env INFOPATH (str:join ':' [$prefix/share/info ''])
    } else {
        set-env INFOPATH (str:join ':' [$prefix/share/info $@info-path])
    }
}

# The default fnm install dir, picked the way fnm's own installer picks it:
# legacy ~/.fnm if present, else $XDG_DATA_HOME/fnm, else the macOS Application
# Support dir, else ~/.local/share/fnm. FNM_PATH overrides all of it.
fn fnm-default-path {
    if (not-eq (env-or FNM_PATH '') '') { put $E:FNM_PATH; return }
    if (os:is-dir $E:HOME/.fnm) { put $E:HOME/.fnm; return }
    if (not-eq (env-or XDG_DATA_HOME '') '') { put $E:XDG_DATA_HOME/fnm; return }
    if (==s (capture-word uname -s) Darwin) { put $E:HOME'/Library/Application Support/fnm'; return }
    put $E:HOME/.local/share/fnm
}

# The FNM_* variables `fnm env` is documented to set. An unrecognized one is
# reported rather than dropped, so a new fnm variable shows up as a warning
# instead of a silently missing shim.
var fnm-variables = [FNM_MULTISHELL_PATH FNM_DIR FNM_LOGLEVEL FNM_NODE_DIST_MIRROR
                     FNM_COREPACK_ENABLED FNM_RESOLVE_ENGINES FNM_ARCH
                     FNM_VERSION_FILE_STRATEGY]

# fnm (Fast Node Manager): put its dir on PATH, then apply the node shims and
# FNM_* variables `fnm env` publishes. The standalone installer drops the binary
# in that dir; a Homebrew/Cargo/release install puts fnm elsewhere on PATH and
# treats this only as the data dir, which `fnm env` creates on demand -- so the
# env call isn't gated on the dir existing.
fn setup-fnm {
    var fnm-path = (fnm-default-path)
    if (os:is-dir $fnm-path) { add-path $fnm-path &where=start }
    if (not (have-command fnm)) { return }
    # `fnm env` mints a fresh multishell directory per invocation, so the shim
    # this shell is already using has to be remembered before the loop below
    # overwrites FNM_MULTISHELL_PATH: `rerc` would otherwise only ever delete
    # the *new* shim from PATH, leaving every previous one behind.
    var old-shim = (env-or FNM_MULTISHELL_PATH '')
    # Captured and checked rather than iterated inline. A failing `fnm env` --
    # an inaccessible state dir, say -- yields no assignments, and the code
    # below would then re-prepend the *previous* shim, deliberately putting a
    # stale node back at the front of PATH on every reload. Better to say so and
    # leave PATH alone.
    var output = ''
    try {
        # `fnm env` speaks bash/zsh/fish; bash's `export KEY="VALUE"` is the
        # shape shellenv-entry reads.
        set output = (fnm env --shell bash | slurp)
    } catch _ {
        warn "fnm: could not read the node environment; node shims are unchanged"
        return
    }
    for line [(str:split "\n" $output)] {
        var entry = (shellenv-entry $line)
        if (== (count $entry) 0) { continue }
        # fnm's PATH line is skipped: it writes `"<shim>":$PATH`, which would
        # need shell expansion to apply, and the shim is $FNM_MULTISHELL_PATH/bin
        # anyway. It goes on the front of Elvish's list PATH below, as
        # config/nushell/config.nu does.
        if (==s $entry[0] PATH) { continue }
        if (has-value $fnm-variables $entry[0]) {
            set-env $entry[0] $entry[1]
        } else {
            warn "fnm: "$entry[0]" is not one this shell knows how to set; node may be missing a setting"
        }
    }
    var shim = (env-or FNM_MULTISHELL_PATH '')
    if (and (not-eq $old-shim '') (not-eq $old-shim $shim)) { delete-path $old-shim/bin }
    if (==s $shim '') { return }
    # The shim dir holds the node/npm/npx symlinks for the selected version and
    # has to lead PATH. It is created by the `fnm env` call above, so prepend it
    # directly rather than through add-path, whose does-it-exist test would have
    # dropped it on the first run of a shell.
    delete-path $shim/bin
    set paths = [$shim/bin $@paths]
}

##################################
# ENVIRONMENT SETUP
# The dir list mirrors ~/.env (which POSIX shells source) and config.fish;
# Elvish cannot source a POSIX file, so the list is spelled out here the way
# fish and mesh spell it out.
#
# The ordering is shrc's, and it matters: each `start` puts its dir in front of
# the ones already there, so ~/scripts ends up ahead of ~/bin ahead of
# /usr/local/bin.
#
# TODO: Elvish reads rc.elv only when it starts interactively, so a
# non-interactive `elvish script.elv`, `elvish -c ...`, or a script with an
# `#!/usr/bin/env elvish` line gets none of this -- no PATH additions, no
# EDITOR, no PAGER. mesh solves it with env.mesh, which it reads on every
# invocation; fish with config.fish, which it also reads for non-interactive
# shells; bash/zsh by exporting ~/.env from profile/zshenv. Elvish has no
# equivalent hook, so scripts have to inherit the environment from whatever
# started them.
fn setup-path {
    add-path /usr/local/bin &where=start
    add-path ~/android-sdk-linux/platform-tools &where=start
    add-path ~/android-studio/bin &where=start
    add-path ~/Android/Sdk/platform-tools &where=start
    add-path ~/depot_tools &where=start
    add-path ~/google-cloud-sdk/bin &where=start
    add-path ~/.local/bin &where=start
    add-path ~/.cargo/bin &where=start
    add-path ~/bin &where=start
    add-path ~/scripts &where=start
    add-path /sbin &where=end
    add-path /usr/sbin &where=end
    # The globs go last, exactly as in shrc: they can't be written as a plain
    # list, and scripts.home / scripts.work override scripts.
    # The `[nomatch-ok]` modifier goes on the wildcard, not on the end of the
    # pattern: `/opt/*/bin[nomatch-ok]` would read as an index on `bin`.
    for dir [~/scripts.*[nomatch-ok]] { add-path $dir &where=start }
    for dir [/opt/*[nomatch-ok]/bin] { add-path $dir &where=end }
}

##################
# PROGRAM DEFAULTS

fn setup-program-defaults {
    # set HISTORY_FILE for log-history
    set-env HISTORY_FILE $E:HOME/.history

    set-env LESS -R
    if (os:exists $E:HOME/scripts/lessopen) {
        set-env LESSOPEN '|'$E:HOME'/scripts/lessopen "%s"'
    }

    # readline and editline configuration for the children that use them;
    # Elvish's own line editor reads neither. Elvish's command history is its
    # own SQLite-backed store rather than a $HISTFILE, so there is nothing here
    # matching shrc's zsh HISTFILE/HISTSIZE/SHARE_HISTORY block -- Elvish
    # already shares history between concurrent shells.
    if (os:exists $E:HOME/.inputrc) { set-env INPUTRC $E:HOME/.inputrc }
    if (os:exists $E:HOME/.editrc) { set-env EDITRC $E:HOME/.editrc }

    # default programs, in preference order -- the last one that exists wins.
    # kitty wants EDITOR set even for non-interactive shells.
    if (is-runnable vi) { set-env EDITOR vi }
    if (is-runnable vim) { set-env EDITOR vim }
    if (is-runnable editline) { set-env EDITOR editline }
    if (is-runnable more) { set-env PAGER more }
    if (is-runnable less) { set-env PAGER less }
    if (and (is-runnable meld) (not-eq (env-or DISPLAY '') '')) { set-env DIFF meld }

    set-env BLOCKSIZE 1024
    set-env CLICOLOR true
    set-env GREP_COLOR 4        # BSD grep and older GNU grep - underline matches
    set-env GREP_COLORS mt=4    # GNU grep - underline matches

    # `cd Downloads` from anywhere -- for children, at least.
    #
    # TODO: Elvish's `cd` ignores CDPATH and offers no equivalent, so this only
    # reaches the programs this shell starts. Ctrl-L (edit:location) covers
    # some of what it was for, over directories already visited.
    set-env CDPATH '.:'$E:HOME

    # keep an inherited GOPATH rather than clobbering it; an empty one still
    # gets the default, matching shrc's ${GOPATH:-$HOME}
    if (==s (env-or GOPATH '') '') { set-env GOPATH $E:HOME }
    # $GOPATH/bin is ~/bin already when GOPATH is the default, and prepending it
    # unconditionally would reorder ~/bin in front of ~/scripts; only add it
    # when GOPATH was moved elsewhere. shrc guards it the same way.
    if (not-eq $E:GOPATH $E:HOME) { add-path $E:GOPATH/bin &where=start }

    # colors for ls
    if (has-value [linux putty vt220] (env-or TERM '')) {
        # colors for white on black
        set-env LSCOLORS ExFxxxxxCxxxxx
        set-env LS_COLORS 'no=00:fi=00:di=01;34:ln=01;35:so=00;00:bd=00;00:cd=00;00:or=01;31:pi=00;00:ex=01;32'
    } else {
        # colors for black on white
        set-env LSCOLORS exfxxxxxcxxxxx
        set-env LS_COLORS 'no=00:fi=00:di=00;34:ln=00;35:so=00;00:bd=00;00:cd=00;00:or=00;31:pi=00;00:ex=00;32'
    }
}

##########################
# SESSION AND TTY PREDICATES

# return true if this session came in over ssh
fn connected-via-ssh { not-eq (env-or SSH_CONNECTION '') '' }

# return true if this session is on a remote machine
fn connected-remotely { connected-via-ssh }

# return true if this session is attached to shpool
fn in-shpool { not-eq (env-or SHPOOL_SESSION_NAME '') '' }

# return true if this session is inside tmux
fn inside-tmux { not-eq (env-or TMUX '') '' }

# return true if stdin is a terminal. Pulled out as a helper so tests can
# replace it without rigging up a pty, the same reason shrc has stdin_is_tty.
#
# `test -t 0` rather than something Elvish answers itself: Elvish exposes no
# isatty, and an external command inherits this shell's fd 0.
fn stdin-is-tty { if ?(test -t 0) { put $true } else { put $false } }

# return true if the current user is root. Reads the $UID
# set-up-standard-variables computed rather than forking `id -u` again: this
# runs on every prompt.
fn i-am-root { ==s (env-or UID '') 0 }

##################
# AUTHENTICATION

# return true if an ssh key is loaded
fn is-ssh-valid { if ?(quiet ssh-add -L) { put $true } else { put $false } }

# print which things need re-authenticating, pre-colored, or nothing
fn auth-info {
    if (is-ssh-valid) { put ''; return }
    put (yellow SSH)
}

# return true if anything needs authenticating
fn need-auth { not-eq (auth-info) '' }

# hook for authenticating (to ssh-agent, etc.)
fn auth { ssh-add }
fn a { auth }

##################
# HOST PREDICATES

# print this machine's name, per ~/.workstation. Cached, empty result included,
# because the file is read on every prompt otherwise.
fn workstation {
    if (==s (env-or WORKSTATION_CACHED '') '') {
        set-env WORKSTATION_CACHED 1
        set-env WORKSTATION (capture-word cat $E:HOME/.workstation &quiet=$true)
    }
    put (env-or WORKSTATION '')
}

# return true if this machine is my workstation
fn on-my-workstation {
    var host = (env-or HOSTNAME '')
    if (==s $host '') { put $false; return }
    if (==s $host (workstation)) { put $true; return }
    if (str:contains $host laptop) { put $false; return }
    var user = (env-or USERNAME '')
    if (==s $user '') { put $false; return }
    put (str:has-prefix $host $user'-')
}

# return true if this machine is my laptop
fn on-my-laptop {
    if (os:exists $E:HOME/.laptop) { put $true; return }
    put (str:contains (env-or HOSTNAME '') laptop)
}

# return true if this is a non-production machine I use to get work done
fn on-my-machine {
    if (on-my-workstation) { put $true; return }
    put (on-my-laptop)
}

fn on-test-host { str:contains (env-or HOSTNAME '') test }
fn on-dev-host { str:contains (env-or HOSTNAME '') dev }

# return true if this machine is a production machine
fn on-production-host {
    if (on-my-machine) { put $false; return }
    if (on-test-host) { put $false; return }
    if (on-dev-host) { put $false; return }
    put $true
}

# return true if it isn't already obvious which host I'm on
fn show-hostname-in-title { not (inside-tmux) }

# a short version of the hostname for the prompt, the window title, and the
# name ssh-to hands the far end. Defined here rather than down in the PROMPT
# section because ssh-to needs it and names resolve top-down.
fn short-hostname {
    var host = (env-or HOSTNAME '')
    if (==s $host '') { put ''; return }
    set host = [(str:split '.' $host)][0]
    var user = (env-or USERNAME '')
    if (==s $user '') { put $host; return }
    put (str:trim-prefix $host $user'-')
}

# print the connecting ssh client's hostname (best effort), or nothing.
# Tries, in order: LC_CLIENT_HOST (smuggled through by ssh-to, since servers
# commonly AcceptEnv LC_*), reverse DNS of the client IP, then the raw IP.
fn ssh-client-host {
    if (not-eq (env-or LC_CLIENT_HOST '') '') { put $E:LC_CLIENT_HOST; return }
    if (not (connected-via-ssh)) { put ''; return }
    var connection = (fields $E:SSH_CONNECTION)
    if (== (count $connection) 0) { put ''; return }
    var ip = $connection[0]
    var name = ''
    # A *miss* is the ordinary outcome of both -- getent exits 2 for an address
    # with no entry, dig exits 9 when the resolver doesn't answer -- and neither
    # prints anything on stdout when it misses, so the empty capture drives the
    # fallback below.
    if (have-command getent) {
        # `getent hosts` pads its columns, so the hostname is the second
        # whitespace-separated field rather than the second literal-space one.
        var entry = (fields (capture-or-empty getent hosts $ip &quiet=$true))
        if (> (count $entry) 1) { set name = $entry[1] }
    }
    if (and (==s $name '') (have-command dig)) {
        var answer = (capture-word dig +short -x $ip &quiet=$true)
        if (not-eq $answer '') {
            set name = (str:trim-suffix [(str:split "\n" $answer)][0] '.')
        }
    }
    if (==s $name '') { put $ip; return }
    put [(str:split '.' $name)][0]
}

##################
# LOGGING AND TRACING

# Set once an unwritable history file has been reported, so the warning below is
# said one time rather than once per command.
var history-logging-warned = $false

# log the running of a command to a file
fn log-history {|@args|
    var file = (env-or HISTORY_FILE '')
    if (==s $file '') { return }
    var stamp = (capture-word date "+%Y%m%d %H%M%S %z")
    try {
        echo $stamp" "(env-or TTY '')" "(str:join ' ' $args) >> $file
    } catch _ {
        # This runs from the prompt hook on every command, so an unwritable
        # history file must not become a message per command -- but going
        # silent loses the log with nothing to show for it. Said once, then
        # quiet. The append is still attempted every time, so a filesystem that
        # frees up or a permission that gets fixed resumes logging without
        # needing a new shell.
        if (not $history-logging-warned) {
            set history-logging-warned = $true
            warn "history: cannot append to "$file"; commands are not being logged"
        }
    }
}

# run a command, or just print what would be run when SIMULATE is true
fn run {|cmd @args|
    if (==s (env-or SIMULATE false) true) {
        echo "Would run "$cmd" "(str:join ' ' $args)
        return
    }
    # not every host runs a syslog daemon
    try-quiet logger -p user.info "Running "$cmd" "(str:join ' ' $args)
    (as-command $cmd) $@args
}

# hook to run the given command under a custom ssh-agent
fn with-agent {|cmd @args| (as-command $cmd) $@args }

# print the definition of the given command or function.
#
# TODO: an Elvish function's body cannot be printed -- there is no reflection
# for it -- so this reports what it can and says the rest is in this file.
fn what {|name|
    if (have-command $name) { path-of $name; return }
    echo $name": an Elvish function or builtin (see ~/.config/elvish/rc.elv)"
}

# run a command under a trace of what it does. Elvish has no `set -x`, so this
# is the nearest equivalent: announce the command, then run it.
fn setx {|cmd @args|
    echo "+ "$cmd" "(str:join ' ' $args) >&2
    (as-command $cmd) $@args
}

# ask the user whether to do something; true on yes or a bare Enter.
#
# The prompt goes to stderr: it is UI rather than output, so `confirm x > log`
# still asks, and a caller reading stdout gets only what it asked for. bash's
# own `read -p` prompts on stderr for the same reason.
fn confirm {|@question|
    print (str:join ' ' $question)"? [Y/n] " >&2
    var reply = ''
    try { set reply = (read-line) } catch _ { put $false; return }
    put (has-value [Y y ''] (str:trim-space $reply))
}

###################
# GENERAL FUNCTIONS
# Useful things that could be commands if distributing them wasn't impractical.

# print the age of a file in seconds, or nothing when it can't be read. `stat`
# has already said why; without the guard its diagnostic would be followed by a
# second one for the arithmetic.
fn age {|file|
    var stamp = (capture-word stat -c %Y $file)
    if (==s $stamp '') { return }
    put (- (num (capture-word date +%s)) (num $stamp))
}

# read BIND-style DNS entries, print the A and AAAA records
fn get-address-records { awk '$3 == "IN" && $4 ~ /^A/ { print $5 }' }

# read BIND-style DNS entries, print the PTR records
fn get-ptr-records { awk '$3 == "IN" && $4 == "PTR" { print $5 }' }

# look up a hostname in DNS, printing both A and AAAA records
fn addr {|host| dig +noall +answer +search $host a $host aaaa | get-address-records }
fn ptr {|ip| dig +noall +answer -x $ip ptr | get-ptr-records }

# read hostnames on stdin, printing each one with its addresses on one line
fn with-address-records {
    each {|hostname| echo $hostname" "(one-line (capture-or-empty $addr~ $hostname)) }
}

# read IP addresses on stdin, printing each one with its names
fn with-hostnames {
    each {|ip| echo $ip" "(one-line (capture-or-empty $ptr~ $ip)) }
}

# list this machine's IP addresses, as "<iface> <address>" lines
fn ips {
    ip -o a sh up primary scope global | each {|line|
        var parts = (fields $line)
        if (< (count $parts) 4) { continue }
        if (str:has-prefix $parts[2] inet) { echo $parts[1]" "$parts[3] }
    }
}
fn addrs { ips }

# list this machine's MAC addresses, as "<iface> <MAC>" lines. Same sed program
# as shrc:624 and config.fish:360 -- it holds the interface name from the `N:`
# line until the matching `link/ether` line arrives -- split across -e
# expressions because an Elvish string is single-line.
fn macs {
    ip -s l sh | sed -n ^
        -e '/^[0-9][0-9]*:/{s/^[0-9][0-9]*: \([^:]*\).*/\1/;h;}' ^
        -e '/^    link\/ether/{s/^    link\/ether \([^ ]*\).*/ \1/;H;x;s/\n//;p;}'
}

# get this machine's public IP address as seen by Google
fn myip { dig +short o-o.myaddr.l.google.com txt @ns1.google.com | tr -d '"' }

# print the list of nameservers
fn names {
    sed -ne '/^nameserver/{s/^nameserver[[:space:]]*//;p}' /etc/resolv.conf
    # not every machine runs NetworkManager
    if (have-command nmcli) {
        capture-or-empty nmcli dev show &quiet=$true | ^
            sed -ne '/^IP..DNS/{s/[^ ]*: *//;p}'
    }
}

# rename each file to <file>.bak
fn bak {|@files| for file $files { mv -i $file $file.bak } }

# undo bak
fn unbak {|@files|
    for file $files {
        if (str:has-suffix $file .bak) {
            if (os:exists $file) { mv -i $file (str:trim-suffix $file .bak) }
        } elif (os:exists $file.bak) {
            mv -i $file.bak $file
        }
    }
}

# ring the terminal's bell
fn bell { print "\a" }

# get the user's attention when a command finishes, but only where the bell is
# an attention signal rather than a noise: shrc gates on xterm and its variants,
# since that is what forwards it to the window manager as an urgency hint.
# Anything else -- a linux console, a dumb TERM under a pipe -- would just beep.
fn flash-terminal {
    var term = (env-or TERM '')
    if (or (==s $term xterm) (str:has-prefix $term xterm-)) { bell }
}

# print the first line(s) of input as-is and run a command on the rest,
# e.g. `ps | body grep ps`. The count is read off the front as `-<number>`,
# `--count`/`--lines <number>` or `--lines=<number>`, matching shrc's
# `netstat -tn | body -2 grep ...`.
fn body {|@args|
    var lines = 1
    var rest = $args
    if (> (count $rest) 0) {
        if (str:has-prefix $rest[0] --lines=) {
            set lines = (num (str:trim-prefix $rest[0] --lines=))
            set rest = $rest[1..]
        } elif (and (> (count $rest) 1) (==s $rest[0] --lines)) {
            set lines = (num $rest[1])
            set rest = $rest[2..]
        } elif (re:match '^-[0-9]+$' $rest[0]) {
            # Narrowed to digits: shrc matches any `-*` and would read `-x` as
            # a count.
            set lines = (num (str:trim-prefix $rest[0] -))
            set rest = $rest[1..]
        }
    }
    var left = $lines
    while (> $left 0) {
        echo (read-line)
        set left = (- $left 1)
    }
    if (== (count $rest) 0) { return }
    (as-command $rest[0]) (all $rest[1..])
}

# make a directory and cd to it
fn mcd {|dir|
    if (os:is-dir $dir) {
        echo $dir" already exists"
        return
    }
    # A failed mkdir (read-only parent, full filesystem) raises, so the cd below
    # never runs and reports a second, more confusing error for the same cause.
    mkdir -p $dir
    cd $dir
}

# make a temporary directory and cd to it
fn mtd { cd (capture-word mktemp -d) }

# cd to the real directory the given file is in, resolving symlinks
fn realdir {|file| path:dir (capture-word readlink -f $file) }
fn cdfile {|file| cd (realdir $file) }

# search for a file in parent directories, returning the first one found, or ""
# when there is none. A value rather than shrc's exit status, since Elvish has
# no `find_up x && ...` to carry a status to; ask with an explicit comparison.
# Same shape as config.nu and rc.mesh.
fn find-up {|name|
    var dir = $pwd
    while $true {
        if (os:is-regular $dir/$name) { put $dir/$name; return }
        if (==s $dir /) { put ''; return }
        set dir = (path:dir $dir)
    }
}

# print the name of a source file's corresponding test file
fn find-test-file {|file|
    var base = (path:base $file)
    var ext = (path:ext $base)
    var candidate = (path:dir $file)/(str:trim-suffix $base $ext)'_test'$ext
    if (os:exists $candidate) { put $candidate; return }
    put ''
}

# join the arguments, placing the first between each of the rest
fn join {|sep @words| echo (str:join $sep $words) }

# replace a file with a sorted version of itself. Staged beside the file and
# moved into place only once `sort` succeeded -- the same reason applydiff
# stages: a sort that dies partway (read error, no space) would otherwise have
# its truncated output moved over the original.
fn isort {|file|
    var staged = $file.bak
    try {
        sort $file > $staged
    } catch e {
        try-quiet rm -f $staged
        error "isort: sort failed; "$file" is unchanged"
        fail $e
    }
    mv $staged $file
}

# delete the given line number from a file
fn delline {|line file| sed -i -e $line'd' $file }

# remove the ssh known host on the given line
fn rmkey {|line| delline $line $E:HOME/.ssh/known_hosts }

# print the block device the given mount point (or file) lives on
fn dev {|file|
    df -P -k $file | each {|line|
        var parts = (fields $line)
        if (== (count $parts) 0) { continue }
        if (str:has-prefix $parts[-1] /) { echo $parts[0] }
    }
}

# run a command on each line of stdin, e.g. `ls | each-line wc -l`.
#
# Named each-line rather than `each`, which is one of Elvish's own builtins and
# already does very nearly this (`ls | each {|f| wc -l $f }`); shadowing it
# would cost every other use of it in this file.
fn each-line {|cmd @args| each {|line| (as-command $cmd) $@args $line } }

# run a command on each null-delimited item from stdin, e.g.
# `find . -print0 | each0 wc -l`.
#
# Delegated to xargs rather than written as the loop each-line is: Elvish's
# `each` splits byte input on newlines and nothing else. The cost is that this
# one runs programs only -- xargs cannot call an Elvish function.
#
# `-r` matters: GNU xargs runs the command once even on empty input, where the
# shrc and fish loops run it zero times. BSD and macOS xargs already behave that
# way and accept -r as a no-op for GNU compatibility, so it is portable.
fn each0 {|cmd @args| xargs -0 -r -n 1 $cmd $@args }

# see what changes a command would make to a file, e.g. `trydiff mdformat f`.
# A failing command leaves partial output behind, and showing that as a proposed
# change is worse than showing nothing: the diff looks like a real suggestion.
# So the preview is gated on the command succeeding.
fn trydiff {|cmd file|
    var temp = $file'.trydiff.'$pid
    try {
        (as-command $cmd) $file > $temp
    } catch e {
        try-quiet rm -f $temp
        error "trydiff: "$cmd" failed; nothing to compare"
        fail $e
    }
    # `diff` exits 1 when the files differ, which is the whole point of a
    # preview -- raising that would break `trydiff x f; applydiff x f` and make
    # every useful run look failed. 2-and-up is a real failure (an unreadable
    # file, and so on), so it is kept and re-raised after the cleanup: a caller
    # has to be able to tell a broken preview from a useful one. diff has
    # already said what went wrong on stderr.
    var failure = $nil
    try { diff $file $temp } catch e { if (> (exit-status $e) 1) { set failure = $e } }
    try-quiet rm -f $temp
    if (not (eq $failure $nil)) { fail $failure }
}

# apply the changes trydiff would have made. The output is staged beside the
# file and only moved into place once the command succeeded -- a formatter that
# rejects its input exits nonzero after writing nothing, and moving that over
# the original would lose the file.
fn applydiff {|cmd file|
    var staged = $file.new
    try {
        (as-command $cmd) $file > $staged
    } catch e {
        try-quiet rm -f $staged
        error "applydiff: "$cmd" failed; "$file" is unchanged"
        fail $e
    }
    mv $staged $file
}

# show the most recently changed files; the count defaults to 10, overridden
# with a leading -<number>, --count <number> or --count=<number>
fn recent {|@args|
    var lines = 10
    var rest = $args
    if (> (count $rest) 0) {
        if (str:has-prefix $rest[0] --count=) {
            set lines = (num (str:trim-prefix $rest[0] --count=))
            set rest = $rest[1..]
        } elif (and (> (count $rest) 1) (==s $rest[0] --count)) {
            set lines = (num $rest[1])
            set rest = $rest[2..]
        } elif (re:match '^-[0-9]+$' $rest[0]) {
            set lines = (num (str:trim-prefix $rest[0] -))
            set rest = $rest[1..]
        }
    }
    ls -t -1 $@rest | head -n (to-string $lines)
}
fn latest {|@args| recent --count=1 $@args }

# list non-empty files, prefixed by timestamp in case sorting is needed
fn nonempty {|@args| find . -size +0 $@args -printf '%T@ %f\n' }

# keep trying a command until it works, e.g. `retry --sleep=1 ping -c 1 host`.
#
# `--sleep` is read off the front by hand rather than declared as an option,
# because a declared option would be matched anywhere in the argument list and
# `retry curl --fail URL` would lose curl's own `--fail`. shrc reads it as a
# leading option only and forwards the rest verbatim.
fn retry {|@args|
    var seconds = 10
    var rest = $args
    if (and (> (count $rest) 1) (==s $rest[0] --sleep)) {
        set seconds = $rest[1]
        set rest = $rest[2..]
    } elif (and (> (count $rest) 0) (str:has-prefix $rest[0] --sleep=)) {
        set seconds = (str:trim-prefix $rest[0] --sleep=)
        set rest = $rest[1..]
    }
    if (== (count $rest) 0) { return }
    var cmd = (as-command $rest[0])
    var cmd-args = $rest[1..]
    while $true {
        if ?($cmd $@cmd-args) {
            bell
            break
        }
        sleep $seconds
    }
}

# run a command with the first argument moved to the end, e.g.
# `first-arg-last grep ~/.history -a foo` runs `grep -a foo ~/.history`
fn first-arg-last {|cmd arg @rest| (as-command $cmd) $@rest $arg }

# convert `command target [options] arg...` to `command [options] target arg...`,
# so a function can imply the command and take the subcommand or object first.
# Options must start with `-` and carry their value attached (-ffile,
# --file=file); `--file file` is not supported, matching shrc.
fn shift-options {|cmd target @args|
    var options = []
    var rest = []
    var scanning = $true
    for arg $args {
        if (and $scanning (not-eq $arg -) (not-eq $arg --) (str:has-prefix $arg -)) {
            set options = [$@options $arg]
        } else {
            set scanning = $false
            set rest = [$@rest $arg]
        }
    }
    (as-command $cmd) $@options $target $@rest
}

# convert a time from one timezone to another, each leg under its own $TZ
fn tz2tz {|from to @spec|
    # An unparsable spec or timezone has already been reported by `date`;
    # running the second leg on an empty epoch would bury that under a second
    # diagnostic for the same cause.
    var epoch = (capture-word $env-run~ [TZ $from] date -d (str:join ' ' $spec) +%s)
    if (==s $epoch '') { return }
    env-run [TZ $to] date -d '@'$epoch
}

# convert a Unix timestamp in microseconds to a human-readable datetime
fn udate {|ts @args| date -d '@'(to-string (int-div (num $ts) 1000000)) $@args }

# convert from UTC to local time
fn utc2 {|spec| date -d 'TZ="UTC" '$spec }

# list processes in the given process group
fn pgroup {|@args| pgrep -g $@args }

# ps with useful default options
fn psc {|@args|
    ps -w -o user,pid,ppid,pgid,start_time,pcpu,rss,comm=EXE $@args -o args=ARGS
}

# pgrep with default ps options: psgrep [<ps options>] <pattern>
fn psgrep {|@args|
    if (== (count $args) 0) { return }
    var pattern = $args[-1]
    var ps-args = $args[..-1]
    # `pgrep` exits 1 and prints nothing when nothing matched, which is exactly
    # the case the branch below is written for.
    var pids = (capture-word pgrep -d , -f $pattern &quiet=$true)
    if (==s $pids '') {
        error "No processes matching "$pattern
        fail 'no processes matching '$pattern
    }
    psc -p $pids $@ps-args
}

# grep for a pattern in the environment of the processes with the given pids
# `pid` is one of Elvish's read-only builtin variables, so the loop
# variable is spelled out rather than shadowing it.
fn envgrep {|pattern @pids| for each-pid $pids { grep -z $pattern /proc/$each-pid/environ } }

# grep for a pattern in the environments of processes matching a pattern,
# e.g. `pegrep SSH_AUTH_SOCK xfce4`
fn pegrep {|env-pattern proc-pattern|
    for each-pid [(str:split "\n" (capture-word pgrep -f '^'$proc-pattern &quiet=$true))] {
        if (==s $each-pid '') { continue }
        echo (capture-word ps -o pid= -o args= -p $each-pid)" "^
             (capture-word $envgrep~ $env-pattern $each-pid)
    }
}
fn peg {|env-pattern proc-pattern| pegrep $env-pattern $proc-pattern }

#####################
# PROJECT AND VCS
# The per-VCS work lives in the `vcs` binary; these are the thin wrappers the
# prompt and the everyday shortcuts need.

# print the root directory of the current project, or nothing
fn rootdir {
    if (not (have-command vcs)) { put ''; return }
    put (capture-word $e:vcs~ rootdir &quiet=$true)
}
fn projectroot { rootdir }
fn pr { echo (projectroot) }

# print the name of the current project
fn projectname {
    var root = (projectroot)
    if (==s $root '') { put ''; return }
    put (path:base $root)
}
fn project { echo (projectname) }

# return true if we are inside a VCS workspace
fn inside-project { not-eq (projectroot) '' }

# print the directory that builds are relative to
fn buildroot { projectroot }

# print the path from buildroot to the working directory
fn builddir {
    var root = (buildroot)
    if (or (==s $pwd $root) (==s $root '')) { put .; return }
    put (str:trim-prefix $pwd $root/)
}

# cd to the root of the current project
fn rd {
    var root = (rootdir)
    if (==s $root '') { return }
    cd $root
}

fn vcs-backend { e:vcs backend }
fn vcs-hosting { e:vcs hosting }
fn prompt-info {|@a| e:vcs prompt-info $@a }
fn unmerged { e:vcs unmerged }
fn cv { e:vcs clearcache }

# The `vcs` subcommands that earn a name of their own, kept in step with
# config/nushell/config.nu and config/mesh/rc.mesh -- neither of which can do
# what shrc.vcs does and generate one function per name from
# `vcs --list-commands`.
#
# TODO, carried over from config.nu and rc.mesh: this list is hand-maintained
# and drifts from the binary, which currently ships 74 subcommands
# (vcs/commands.go). The canonical list should be the binary itself --
# generated into a file each shell reads at startup rather than restated in
# every shell's config. In Elvish that file would have to be a module under
# ~/.config/elvish/lib whose names are re-published with `edit:add-vars`, since
# a module's names are namespaced.
#
# Note `diffs`, not `diff`: the binary's command is the plural one, alongside
# `diffedit` and `diffstat`. There is no `diff`.
fn add {|@a| e:vcs add $@a }
fn amend {|@a| e:vcs amend $@a }
fn annotate {|@a| e:vcs annotate $@a }
fn base {|@a| e:vcs base $@a }
fn branch {|@a| e:vcs branch $@a }
fn branches {|@a| e:vcs branches $@a }
fn changed {|@a| e:vcs changed $@a }
fn changelog {|@a| e:vcs changelog $@a }
fn changes {|@a| e:vcs changes $@a }
fn checkout {|@a| e:vcs checkout $@a }
fn commit {|@a| e:vcs commit $@a }
fn commitforce {|@a| e:vcs commitforce $@a }
fn diffs {|@a| e:vcs diffs $@a }
fn fix {|@a| e:vcs fix $@a }
fn graph {|@a| e:vcs graph $@a }
fn incoming {|@a| e:vcs incoming $@a }
fn lint {|@a| e:vcs lint $@a }
fn map {|@a| e:vcs map $@a }
fn outgoing {|@a| e:vcs outgoing $@a }
fn pending {|@a| e:vcs pending $@a }
fn precommit {|@a| e:vcs precommit $@a }
fn presubmit {|@a| e:vcs presubmit $@a }
fn pull {|@a| e:vcs pull $@a }
fn push {|@a| e:vcs push $@a }
fn recommit {|@a| e:vcs recommit $@a }
fn revert {|@a| e:vcs revert $@a }
fn review {|@a| e:vcs review $@a }
fn reword {|@a| e:vcs reword $@a }
fn status {|@a| e:vcs status $@a }
fn submit {|@a| e:vcs submit $@a }
fn submitforce {|@a| e:vcs submitforce $@a }
fn unknown {|@a| e:vcs unknown $@a }
fn upload {|@a| e:vcs upload $@a }
fn uploadchain {|@a| e:vcs uploadchain $@a }

# short aliases -- hand-picked, not generated, matching config.nu and rc.mesh
fn am {|@a| e:vcs amend $@a }
fn ci {|@a| e:vcs commit $@a }
fn di {|@a| e:vcs diffs $@a }
fn gr {|@a| e:vcs graph $@a }
fn lg {|@a| e:vcs graph $@a }
fn ma {|@a| e:vcs review $@a }
fn st {|@a| e:vcs status $@a }

# clone a repo with whichever VCS its URL implies: jj for a git URL (falling
# back to git itself, but only if the user says so), hg for an hg one.
#
# The URL comes first: `clone URL --depth 1`, not `clone --depth 1 URL`. The URL
# is what picks the VCS, so a leading flag would leave neither branch matching.
fn clone {|url @args|
    if (str:has-suffix $url .git) {
        if (have-command jj) {
            jj git clone $url $@args
        } elif (confirm "jj is not installed. Clone using git") {
            git clone $url $@args
        }
    } elif (str:contains $url /hg) {
        hg clone $url $@args
    }
}

# update config files
fn pc {
    for dir [~/conf ~/conf.*[nomatch-ok] ~/scripts ~/scripts.*[nomatch-ok]] {
        if (not (os:is-dir $dir)) { continue }
        echo "== "(path:base $dir)
        # A failed pull stops the sweep rather than carrying on into the next
        # checkout, matching shrc's `pull || exit 1` inside its `|| break` loop.
        tmp-cd $dir {
            pull
            if (os:exists .gitmodules) {
                git submodule init
                git submodule update
            }
            if (os:is-dir vcs/.git) { git -C vcs pull }
        }
    }
}

###############
# SSH
# Connect to a host telling it who is connecting, and give every ~/.ssh/config
# Host entry a command of its own.

# does this ssh short-option word take the *next* word as its value?
#
# A value-taking option at the end of a short-option cluster still does:
# `-vp 2222` is `-v -p 2222`. Anything after that letter in the same word is an
# attached value instead (`-p2222`, `-lBob`), so the letters before it must all
# be flags -- the first value-taking letter ends the cluster and everything
# after it belongs to that option. Both letter sets are ssh(1)'s own: the
# boolean cluster from its SYNOPSIS, then the options the SYNOPSIS gives an
# argument.
fn ssh-option-takes-value {|word|
    re:match '^-[46AaCfGgKkMNnqsTtVvXxYy]*[BbcDEeFIiJLlmOoPpQRSWw]$' $word
}

# ssh to a host, smuggling this machine's name across as LC_CLIENT_HOST --
# servers commonly AcceptEnv LC_*, which is why it rides in that namespace, and
# ssh-client-host reads it at the far end. SendEnv is additive, so the usual
# LANG/LC_* forwarding is left intact.
fn ssh-to {|host @args|
    var client = (short-hostname)
    if (and (have-command rw) (== (count $args) 0)) {
        env-run [LC_CLIENT_HOST $client] rw -r $host
        return
    }
    # ssh flags typed *after* the host alias have to be moved in front of it, or
    # ssh runs them as the remote command -- `host1 -v uptime` remotely ran
    # `-v uptime`. Unlike shift-options, a flag whose value is a separate word
    # (-p 2222, -i file, -o opt) must keep its value with it rather than having
    # the scan stop there.
    var nopts = 0
    var expect-value = $false
    for arg $args {
        if $expect-value {
            set expect-value = $false
            set nopts = (+ $nopts 1)
            continue
        }
        if (==s $arg --) {
            # End of options: rotated along with them so it lands before the
            # host, which ssh accepts; everything after it is the remote command
            # even if it starts with a dash.
            set nopts = (+ $nopts 1)
            break
        }
        if (==s $arg -) { break }
        if (ssh-option-takes-value $arg) {
            set expect-value = $true
            set nopts = (+ $nopts 1)
            continue
        }
        if (str:has-prefix $arg -) {
            set nopts = (+ $nopts 1)
            continue
        }
        break
    }
    var opts = $args[..$nopts]
    var remote = $args[$nopts..]
    env-run [LC_CLIENT_HOST $client] ssh -t -oSendEnv=LC_CLIENT_HOST $@opts $host $@remote
}

# print every usable `Host` alias in ~/.ssh/config, one per line.
#
# Patterns and negations aren't hosts to connect to, and a name that isn't a
# plain identifier can't be an Elvish variable name, so both are dropped -- the
# same filter mesh applies, and stricter than shrc's and fish's.
fn ssh-config-hosts {
    var config = $E:HOME/.ssh/config
    if (not (os:is-regular $config)) { return }
    # Read separately from the parse, and reported. The file passed the
    # is-regular test above, so a failure here is permissions or I/O -- and
    # collapsing that into an empty result would drop every alias while looking
    # exactly like a config that never had a Host entry. `cat`'s own diagnostic
    # is silenced so there is one message rather than two for the same cause.
    var contents = ''
    try {
        set contents = (cat $config 2>/dev/null | slurp)
    } catch _ {
        warn "ssh aliases: cannot read the ssh config; host aliases are not defined"
        return
    }
    for line [(str:split "\n" $contents)] {
        var parts = (fields $line)
        if (< (count $parts) 2) { continue }
        if (not (has-value [Host host] $parts[0])) { continue }
        for name $parts[1..] {
            if (re:match '[*?-]' $name) { continue }
            if (not (re:match '^[A-Za-z_][A-Za-z0-9_]*$' $name)) { continue }
            put $name
        }
    }
}

# the ssh host aliases as a map of `<name>~` to the closure that connects,
# ready for `edit:add-vars`
#
# TODO: a `Host` entry sharing a name with one of the shortcuts above takes it
# over. shrc and fish avoid that by defining their shortcuts afterwards and mesh
# by asking `is-function`; Elvish offers neither -- `edit:add-vars` is the only
# way to bind a computed name, it runs after every `fn` above, and there is no
# way to ask whether a name is already bound.
fn ssh-alias-vars {
    var host-vars = [&]
    for name [(ssh-config-hosts)] {
        set host-vars[$name'~'] = {|@args| ssh-to $name $@args }
    }
    put $host-vars
}

#####################
# SESSION MANAGEMENT
# shpool is the default; tmux is the fallback when shpool is missing or
# WANT_SHPOOL=0. SESSION_BACKEND=tmux flips the preference. Kept in parity with
# shrc, config.fish, config.nu and rc.mesh.

fn shpool-available {
    if (==s (env-or WANT_SHPOOL 1) 0) { put $false; return }
    if (not (have-command shpool)) { put $false; return }
    put (have-command autoshpool)
}

fn tmux-available {
    if (==s (env-or WANT_TMUX 1) 0) { put $false; return }
    if (not (have-command tmux)) { put $false; return }
    put (have-command autotmux)
}

# name of the preferred session manager: "shpool" (the default when both are
# available), "tmux" (the fallback), or "" when neither is enabled
fn session-backend {
    if (==s (env-or SESSION_BACKEND shpool) tmux) {
        if (tmux-available) { put tmux; return }
        if (shpool-available) { put shpool; return }
        put ''
        return
    }
    if (shpool-available) { put shpool; return }
    if (tmux-available) { put tmux; return }
    put ''
}

# return true if we should auto-start shpool in this session. The autoshpool
# helper is required as well as shpool: a machine with shpool that hasn't picked
# up the scripts repo must fall through to tmux rather than failing on a missing
# autoshpool at every shell start.
fn want-shpool {
    if (==s (env-or WANT_SHPOOL 1) 0) { put $false; return }
    if (not (stdin-is-tty)) { put $false; return }
    if (in-shpool) { put $false; return }
    if (inside-tmux) { put $false; return }
    if (not (have-command shpool)) { put $false; return }
    if (not (have-command autoshpool)) { put $false; return }
    if (connected-remotely) { put $true; return }
    put (inside-project)
}

# return true if we should auto-start tmux in this session
fn want-tmux {
    if (==s (env-or WANT_TMUX 1) 0) { put $false; return }
    if (not (stdin-is-tty)) { put $false; return }
    if (inside-tmux) { put $false; return }
    if (in-shpool) { put $false; return }
    if (not (have-command tmux)) { put $false; return }
    if (not (have-command autotmux)) { put $false; return }
    if (connected-remotely) { put $true; return }
    put (inside-project)
}

# attach to (or create) this project's session using the preferred backend
fn autosession {|@args|
    var backend = (session-backend)
    if (==s $backend tmux) { autotmux $@args; return }
    if (==s $backend shpool) { autoshpool $@args }
}

# switch to a session. tmux switches in place; shpool requests a switch and the
# now-parked shell exits, which is what hands control to autoshpool's outer
# loop. A failed switch raises, so the exit below is never reached.
fn switchshpool {|name| autoshpool switch $name; exit }

fn switchsession {|name|
    var backend = (session-backend)
    if (==s $backend tmux) { autotmux switch $name; return }
    if (==s $backend shpool) { switchshpool $name }
}

# attach to a (named) session using the preferred backend
fn sessionattach {|@args|
    var backend = (session-backend)
    if (==s $backend tmux) { tmux attach $@args; return }
    if (==s $backend shpool) { shpool attach $@args }
}

# list sessions using the preferred backend (the vcs-aware tmuxlist /
# shpoollist helpers)
fn sessionlist {|@args|
    var backend = (session-backend)
    if (==s $backend tmux) { tmuxlist $@args; return }
    if (==s $backend shpool) { shpoollist $@args }
}

# Transitional fallback: the updated scripts-repo helpers open the session in
# the right directory via `shpool attach -d`, leaving SHPOOL_INITIAL_PWD unset
# and this a no-op. Until that ships everywhere (mikelward/scripts#107), the
# older helpers still stamp SHPOOL_INITIAL_PWD (forwarded via the shpool
# config's forward_env), so cd there on entry. Remove this and the forward_env
# entry once the scripts update is deployed.
#
# The variable is cleared only once the cd worked: it is the only record of
# where the handoff meant to land, so a directory deleted since the launcher
# stamped it should leave the value in place to diagnose with.
fn apply-shpool-initial-pwd {
    if (not (in-shpool)) { return }
    var initial = (env-or SHPOOL_INITIAL_PWD '')
    if (==s $initial '') { return }
    try {
        cd $initial
    } catch _ {
        error "shpool: cannot enter "$initial"; staying in "$pwd
        return
    }
    set-env SHPOOL_INITIAL_PWD ''
}

# The shell the user explicitly started, for autoshpool to run in the sessions
# it creates (shpool attach --cmd). An inherited value wins (so SESSION_SHELL=...
# overrides); otherwise empty -- and the daemon's default shell applies --
# unless SHLVL shows a parent shell: Elvish increments SHLVL before rc.elv runs,
# so 1 is the terminal's or login's own first shell, the default rather than an
# explicit choice. The full path, because the shpool daemon's PATH may not
# include where Elvish is installed; -l so the session's shell starts as a login
# shell, matching the shpool daemon's default spawn.
fn session-shell {
    var existing = (env-or SESSION_SHELL '')
    if (not-eq $existing '') { put $existing; return }
    var level = (env-or SHLVL 0)
    if (not (re:match '^[0-9]+$' $level)) { put ''; return }
    if (< (num $level) 2) { put ''; return }
    if (not (have-command elvish)) { put ''; return }
    put (path-of elvish)" -l"
}

# The launcher only replaces this shell when it actually started a session, so a
# launcher that fails -- no daemon, bad config -- leaves a working shell behind
# instead of closing a remote login. Same guard shrc, config.fish, config.nu and
# rc.mesh use.
#
# SESSION_SHELL is set for the launcher alone and put back when it fails, so a
# failed handoff does not leave this shell's identity for later nested shells to
# inherit.
fn maybe-start-session-and-exit {
    var backend = (session-backend)
    var launcher = ''
    if (and (==s $backend shpool) (want-shpool)) { set launcher = autoshpool }
    if (and (==s $backend tmux) (want-tmux)) { set launcher = autotmux }
    if (==s $launcher '') { return }
    if ?(env-run [SESSION_SHELL (session-shell)] $launcher) { exit }
}

##############################
# PROMPT
# The layout is shrc's: a rule, then a context line of host, directory, and
# anything needing authentication, then a bare `$` to type at. The `$` glyph
# itself is the line editor's, so it lives in lib/interactive.elv.

# replace a leading $HOME in the working directory with "~"
fn tilde-pwd { tilde-abbr $pwd }

# print the current session name (shpool or tmux), or nothing
fn session-name {
    if (in-shpool) { put $E:SHPOOL_SESSION_NAME; return }
    if (inside-tmux) { put (capture-word tmux display-message -p '#S' &quiet=$true); return }
    put ''
}

# the hostname and session tag for the context line. The hostname is red on a
# production host; the session tag is a green session name when attached, or a
# yellow warning naming the backend that would start when not.
fn host-info {
    var host = (short-hostname)
    if (on-production-host) { set host = (red $host) }
    var out = ''
    if (i-am-root) { set out = '['(red root)'] ' }
    set out = $out$host' '
    var session = (session-name)
    if (not-eq $session '') { put $out(green $session); return }
    var backend = (env-or SESSION_BACKEND '')
    if (==s $backend '') { set backend = (session-backend) }
    if (==s $backend '') { set backend = shpool }
    put $out(yellow $backend)
}

# the directory part of the context line: `vcs prompt-info` renders it (one
# fork), and outside a repo the binary prints nothing, so we fall back to a
# tilde-shortened $pwd. Deliberately *not* gated on inside-project, which would
# spend a whole `vcs rootdir` fork per prompt to learn what the empty output
# already says -- the same reason config.fish, config.nu and rc.mesh call
# prompt-info unconditionally. have-command is a PATH lookup, not a fork.
fn dir-info {
    var info = ''
    if (have-command vcs) {
        var flag = --color=never
        if $color { set flag = --color=always }
        set info = (capture-word $e:vcs~ prompt-info $flag &quiet=$true)
    }
    if (==s $info '') { set info = (tilde-pwd) }
    put (blue $info)
}

# the context line: host, directory, and anything needing authentication.
# `auth` is a parameter so preprompt can compute auth-info once and hand the
# same answer to maybe-background-fetch: `ssh-add -L` (via is-ssh-valid) is a
# fork, and asking twice per prompt would double it.
fn prompt-line {|&auth=$nil|
    if (eq $auth $nil) { set auth = (auth-info) }
    var out = (host-info)' '(dir-info)
    if (not-eq $auth '') { set out = $out' '$auth }
    put $out
}

# the width of the terminal, for the rule above the context line.
#
# TODO: Elvish exposes no terminal width, so this forks `tput cols` on every
# prompt -- bash and zsh read $COLUMNS for free, fish has $COLUMNS, and mesh
# reads $sh.width. Falls back to 80 when tput can't answer (no terminal, dumb
# TERM), which is not a width but is a usable rule.
fn terminal-width {
    var cols = (capture-word tput cols &quiet=$true)
    if (not (re:match '^[1-9][0-9]*$' $cols)) { put 80; return }
    put (num $cols)
}

fn bar {|width| echo (str:join '' [(repeat $width '―')]) }

# print the window title: "<hostname> <session> <project-or-pwd>", each leading
# part omitted when empty
fn title {
    var parts = []
    if (show-hostname-in-title) { set parts = [$@parts (short-hostname)] }
    var session = (session-name)
    if (not-eq $session '') { set parts = [$@parts $session] }
    var name = (projectname)
    if (==s $name '') { set name = (path:base $pwd) }
    put (str:join ' ' [$@parts $name])
}

# the escape that sets the terminal title, per $TERM. Elvish writes no title of
# its own, so this is the whole of it.
fn set-title {|text|
    var term = (env-or TERM '')
    if (or (str:has-prefix $term xterm) (str:has-prefix $term rxvt) ^
           (has-value [aixterm dtterm putty] $term)) {
        print "\e]0;"$text"\a"
    } elif (==s $term konsole) {
        print "\e]30;"$text"\a"
    } elif (str:has-prefix $term screen) {
        # screen and tmux own the terminal title; this sets the window name.
        print "\ek"$text"\e\\"
    }
}

# spawn a detached background fetch through the `vcs` binary, which knows the
# right fetch command per VCS, the marker file to mtime-gate against, and how to
# detach. The shell owns only two gates: skip unless the directory changed (most
# prompts don't follow a cd), and skip while something needs authenticating so
# the prompt's {behind} indicator still nags.
#
# The directory is recorded only once a fetch is actually spawned: recording it
# before the auth gate means a directory first seen without an ssh identity
# never fetches, however long the session stays there after authenticating.
var last-fetch-dir = ''

fn maybe-background-fetch {|&auth=$nil|
    if (eq $auth $nil) { set auth = (auth-info) }
    if (==s $pwd $last-fetch-dir) { return }
    if (not (have-command vcs)) { return }
    if (not-eq $auth '') { return }
    # `vcs auto-fetch` is mtime-gated inside the binary, so a successful call is
    # cheap to repeat; a failed one (couldn't fork, couldn't reach the marker
    # file) is worth retrying on the next prompt rather than disabling the fetch
    # for this directory until the next cd.
    if ?(quiet $e:vcs~ auto-fetch) { set last-fetch-dir = $pwd }
}

# what the prompt draws before each command line
fn preprompt {
    # Asked once and handed to both callers below: is-ssh-valid forks
    # `ssh-add -L`, and this is the prompt's hot path.
    var auth = (auth-info)
    maybe-background-fetch &auth=$auth
    echo ''
    bar (terminal-width)
    echo (prompt-line &auth=$auth)
    # `unmerged` prints its warning on *stdout*, so only its diagnostics are
    # silenced -- try-quiet would redirect both and drop the warning this call
    # exists to show. Not gated on inside-project for the same reason dir-info
    # isn't. shrc, config.fish and rc.mesh all redirect stderr only.
    if (have-command vcs) { try { e:vcs unmerged 2>/dev/null } catch _ { } }
    set-title (title)
    # TODO: no job list. Elvish has no job control -- no `jobs`, no `bg`, and
    # only an undocumented `fg` -- so shrc's job_info line, its publish_jobs
    # status file for tmux, and the `_exit`/xa guard against leaving with jobs
    # still running have no equivalent here.
    #
    # Last, as in shrc and rc.mesh: the bell announces a prompt that is already
    # drawn.
    flash-terminal
}

# format an elapsed time the way shrc's last_job_info does, or "" under two
# seconds
fn format-duration {|seconds|
    var whole = (exact-num (math:floor $seconds))
    if (< $whole 2) { put ''; return }
    var hours = (int-div $whole 3600)
    set whole = (- $whole (* $hours 3600))
    var minutes = (int-div $whole 60)
    set whole = (- $whole (* $minutes 60))
    if (> $hours 0) {
        put $hours" hours "$minutes" minutes "$whole" seconds"
        return
    }
    if (> $minutes 0) {
        put $minutes" minutes "$whole" seconds"
        return
    }
    put $whole" seconds"
}

# describe a command's failure the way shrc's *_last_error functions do, or ""
# when it succeeded or was merely suspended
fn describe-error {|err|
    if (eq $err $nil) { put ''; return }
    var reason = $err[reason]
    if (not (has-key $reason type)) { put (to-string $reason); return }
    if (==s $reason[type] external-cmd/signaled) {
        # Elvish names signals the way Go's Signal.String() does -- "interrupt",
        # "stopped" -- rather than SIGINT/SIGTSTP.
        if (==s $reason[signal-name] interrupt) { put interrupted; return }
        # A suspended command isn't an error to report; shrc skips status 148
        # for the same reason.
        if (has-value [stopped 'stopped (signal)' 'terminal stop'] $reason[signal-name]) {
            put ''
            return
        }
        put "killed by "$reason[signal-name]
        return
    }
    if (==s $reason[type] external-cmd/exited) {
        put "status "$reason[exit-status]
        return
    }
    put (to-string $reason)
}

# report a command that failed or took a noticeable while. Elvish's
# after-command hook hands us the status and the elapsed seconds rather than
# making us recover them, which is what shrc's SECONDS bookkeeping is for.
fn command-finished {|m|
    var reported = (describe-error $m[error])
    if (not-eq $reported '') { set reported = (red $reported) }
    var duration = (format-duration $m[duration])
    if (not-eq $duration '') {
        if (not-eq $reported '') { set reported = $reported' ' }
        set reported = $reported(yellow "took "$duration)
    }
    if (not-eq $reported '') { echo $reported }
}

# log every interactive command, the way shrc's precommand does
fn command-started {|line|
    log-history $line
    set-title (title)
}

##########################
# COMMAND SHORTCUTS
# shrc spells most of these as functions and a few as aliases; Elvish has no
# aliases, so they are all functions. `e:name` reaches past a function of the
# same name to the external command, which is what makes the shortcuts that
# share a name with what they wrap safe -- it is shrc's `command` prefix.

fn c {|@a| e:less --quit-if-one-screen --no-init $@a }
fn cdf {|file| cdfile $file }
fn cg {|@a| e:rg --glob='{*.c,*.h,*.cc,*.cpp,*.hh,*.coffee,*.go,*.hs,*.java,*.js,*.pl,*.py,*.sh,*.rb,*.swig,*.ts}' $@a }
fn ct {|@a| e:ctags -R $@a }
fn cx {|@a| e:chmod +x $@a }
# restart a background daemon; setsid gives it a session of its own so it
# outlives this shell
fn daemon {|name @args|
    # pkill exits 1 when nothing was running, which is the normal first start
    try-quiet pkill $name
    setsid $name $@args &
}
fn bindkeys {|@a| daemon xbindkeys $@a }
fn diga {|@a| e:dig +noall +answer +search $@a }
fn digs {|@a| e:dig +short +search $@a }
# A failed `cd` raises, so wget never runs and can't save into whatever
# directory the caller happened to be in; `cd` prints its own diagnostic.
fn download {|@a| cd $E:HOME/Downloads; e:wget $@a }
fn e {|@a| (external (env-or EDITOR vim)) $@a }
# terminal mode, so `emacs file` stays in the shell it was typed in rather than
# opening a window when a display happens to be available
fn emacs {|@a| e:emacs --no-window-system $@a }
fn g {|@a| e:grep --binary-files=without-match --line-number $@a }
fn eg {|@a| g -E $@a }
fn gdb {|@a| e:gdb -q $@a }
# note that grep options must go after ~/.history
fn gh {|@a| first-arg-last grep $E:HOME/.history -a $@a }
fn github {|@a| e:gh $@a }
fn gitdir {|@a| e:git rev-parse --git-dir $@a }
fn gl { cd /var/log }
fn h {|@a| e:head $@a }
fn headers {|@a| e:curl --location --include --silent --show-error --output /dev/null --dump-header - $@a }
fn hms {|@a| e:date +%H:%M:%S $@a }
fn hmsns {|@a| e:date +%H:%M:%S.%N $@a }
fn hosts {|@a| e:getent hosts $@a }
fn ipy {|@a| e:ipython $@a }
fn ipy3 {|@a| e:ipython3 $@a }
fn killcode {|@a| e:pkill -f /usr/share/code/code $@a }
fn kssh {|@a| e:ssh -o PreferredAuthentications=publickey $@a }
fn lssock {|@a| e:lsof -a -n -P -i $@a }
fn lss {|@a| lssock $@a }
fn m {|@a| e:make -f .Makefile $@a }
fn ml { m lint }
fn mt { m test }
fn n {|@a| e:date +%Y%m%d%H%M%S $@a }
fn now {|@a| e:date +%Y-%m-%dT%H:%M:%S $@a }
fn nowns {|@a| e:date +%Y-%m-%dT%H:%M:%S.%N $@a }
fn nv {|@a| e:nvim $@a }
fn p {|@a| (external (env-or PAGER more)) $@a }
fn phup {|@a| e:pkill -HUP $@a }
fn psg {|@a| psgrep $@a }
fn psu {|@a| e:ps -o user,pid,start,time,pcpu,stat,cmd $@a }
fn pssh {|@a| e:ssh -o PreferredAuthentications=keyboard-interactive,password $@a }
fn py {|@a| e:python $@a }
fn py2 {|@a| e:python2 $@a }
fn py3 {|@a| e:python3 $@a }
fn rg {|@a| e:rg --follow --line-number $@a }
fn rh {|@a| gh $@a | tail -n 20 }
fn s {|@a| e:subl $@a }
fn spell {|@a| e:aspell -a $@a }
fn sr {|@a| e:ssh -l root $@a }
fn symlink {|@a| e:ln --symbolic --relative $@a }
fn t {|@a| e:tail $@a }
fn tf {|@a| t -f $@a }
fn tl {|@a| t -f /var/log/syslog $@a }
fn today {|@a| e:date +%Y-%m-%d $@a }
fn userctl {|@a| e:systemctl --user $@a }
fn userjournal {|@a| e:journalctl --user $@a }
fn userjnl {|@a| userjournal $@a }
fn view {|@a| e:vim -R -c ':set mouse=' $@a }
fn v {|@a| view $@a }
fn vl {|@a| view /var/log/syslog $@a }
fn wcp {|@a| with-agent scp $@a }
fn wsh {|@a| with-agent ssh $@a }
fn xevkey {|@a| e:xev -event keyboard $@a }
fn xr {|@a| env-run [DISPLAY :0.0] xrandr $@a }
fn jc {|@a| e:journalctl --no-hostname $@a }
fn sc {|@a| e:systemctl $@a }
fn uc {|@a| e:systemctl --user $@a }

# Three listers, picked the way shrc picks them: the separate `l` program when
# this host has one, else GNU-style `ls` if it takes those flags, else a plain
# `ls`. The middle arm has to be probed rather than assumed -- BSD and macOS
# `ls` reject `--color=auto` outright, which would break `l` and every shortcut
# built on it. One fork at startup, as in shrc; the answer is remembered here
# because Elvish has no `if` at definition time that could pick the body.
var ls-flavor = plain

fn pick-ls-flavor {
    if (have-command l) {
        set ls-flavor = l
    } elif ?(quiet $e:ls~ --color=auto -v -d /) {
        set ls-flavor = gnu
    } else {
        set ls-flavor = plain
    }
}
fn l {|@a|
    if (==s $ls-flavor l) { e:l -K -v -e -x $@a; return }
    if (==s $ls-flavor gnu) { e:ls --color=auto -v -b -x $@a; return }
    e:ls -v -b -x $@a
}
fn ll {|@a|
    if (==s $ls-flavor l) { l -p -T -B -V -h --time-style=relative $@a; return }
    l -l $@a
}
fn lt {|@a|
    if (==s $ls-flavor l) { l -T -t $@a; return }
    ll -t $@a
}
fn l1 {|@a| l -1 $@a }
fn la {|@a| l -a $@a }
fn lc {|@a| l -C $@a }

# package management, delegated to the `package` script, which dispatches to
# dnf, yum, or apt-get depending on what's available
fn update {|@a| package update $@a }
fn search {|@a| package search $@a }
fn install {|@a| package install $@a }
fn installed {|@a| package installed $@a }
fn uninstall {|@a| package uninstall $@a }
fn reinstall {|@a| package reinstall $@a }
fn autoremove {|@a| package autoremove $@a }
fn upgrade {|@a| package upgrade $@a }
fn versions {|@a| package versions $@a }
# `info` and `files` shadow the programs of those names, deliberately and in
# step with shrc, fish and nushell; `e:info` still reaches the reader. mesh
# cannot do this for `files`, which is one of its reserved words.
fn info {|@a| package info $@a }
fn files {|@a| package files $@a }
fn listfiles {|@a| package listfiles $@a }
fn depends {|@a| package depends $@a }
fn rdepends {|@a| package rdepends $@a }

# session-manager verbs, named {verb}{backend}: verb is a(uto), c(hange),
# d(etach), or m(ake); backend is s (follow the active backend), sp (shpool), or
# tm (tmux). The change*/detach*/make* scripts live in the scripts repo and
# dispatch on $TMUX/$SHPOOL_SESSION_NAME/$SESSION_BACKEND, so the backend
# session-backend picked (which honors the WANT_* opt-outs the scripts can't
# see) is handed to them explicitly.
fn as {|@a| autosession $@a }
fn asp {|@a| autoshpool $@a }
fn atm {|@a| autotmux $@a }
fn ctm {|@a| changetmux $@a }
fn dsp {|@a| detachshpool $@a }
fn dtm {|@a| detachtmux $@a }
fn mtm {|@a| maketmux $@a }

fn session-script-wanted {
    if (inside-tmux) { put $true; return }
    if (in-shpool) { put $true; return }
    not-eq (session-backend) ''
}

# shpool cannot switch a live client itself: changeshpool hands the switch to
# autoshpool's outer loop by detaching us, so the parked shell has to exit. Only
# on the no-arg picker path -- --list/--help also succeed but only print -- and
# only when shpool is the backend that ran, since a tmux session nested in
# shpool switches in place and must stay.
fn cs {|@a|
    if (not (session-script-wanted)) { return }
    if (not ?(env-run [SESSION_BACKEND (session-backend)] changesession $@a)) { return }
    if (> (count $a) 0) { return }
    if (inside-tmux) { return }
    if (in-shpool) { exit }
}
fn csp {|@a|
    if (not ?(changeshpool $@a)) { return }
    if (> (count $a) 0) { return }
    if (in-shpool) { exit }
}
fn ds {|@a|
    if (not (session-script-wanted)) { return }
    env-run [SESSION_BACKEND (session-backend)] detachsession $@a
}
fn ms {|@a|
    if (not (session-script-wanted)) { return }
    if (not ?(env-run [SESSION_BACKEND (session-backend)] makesession $@a)) { return }
    if (inside-tmux) { return }
    if (in-shpool) { exit }
}
fn msp {|@a|
    if (not ?(makeshpool $@a)) { return }
    if (in-shpool) { exit }
}

# clone or cd into a repo, then start a session matching the new root. A failed
# clone or cd raises, so autosession never runs and no stray session is spawned.
fn jd {|@a| jjd $@a; autosession }
fn hd {|@a| hgd $@a; autosession }
fn gd {|@a| gitd $@a; autosession }
fn mjd {|@a| jjd -f $@a; autosession }
fn mhd {|@a| hgd -f $@a; autosession }
fn mgd {|@a| gitd -f $@a; autosession }

# re-read this configuration.
#
# TODO: Elvish has no `source`, and `eval` runs in a temporary namespace whose
# definitions are discarded, so the only way to pick up an edited rc.elv is to
# replace this shell with a fresh one. shrc's `rerc` is a plain `. ~/.shrc`;
# rc.mesh's re-sources both of its files.
fn rerc { exec elvish }

# TODO: no equivalents for shrc's job-control and directory-stack shortcuts.
# Elvish has neither job control nor a directory stack, and its function names
# must be identifiers, so `f`/`fg`, `j`, `x`/`xa`/`q`, `+`, `-`, `+-`,
# `+0`..`+9`, `%1`.., `pd`/`po`/`pushd`/`popd`, `@` and `$` are all absent.
# Ctrl-L (edit:location) covers some of what the directory stack was for.

##############################
# INTERACTIVE TOOL INTEGRATIONS
# Optional third-party tools wired into the interactive shell: zoxide
# (frecency-ranked directory jumps), carapace (multi-shell completions) and
# atuin (SQLite-backed history search). Each is skipped when the tool isn't
# installed, so a host without them behaves exactly as before. A tool that IS
# installed but whose init fails warns rather than being silently dropped.
#
# Keep in parity with shrc, config/fish/config.fish and config/nushell/config.nu.
#
# TODO: no fzf. fzf ships key bindings for bash, zsh, fish and nushell but has
# no `fzf --elvish` and no key-bindings.elv, and the community modules that fill
# the gap aren't vendored here. Elvish's own Ctrl-R (histlist), Ctrl-N
# (navigation) and Ctrl-L (location) cover much of what fzf was bound for.

# Run a tool's init generator and evaluate what it prints.
#
# Elvish's `eval` runs the code in a temporary namespace, so a tool's snippet
# only reaches this shell if it publishes its own names with `edit:add-var` --
# which is exactly what `zoxide init elvish` and `carapace _carapace elvish` are
# written to do, and why their documented setup is a bare `eval (... | slurp)`.
# A generator that instead expects a `source` has no Elvish spelling and is
# reported rather than half-applied.
fn eval-tool-init {|tool cmd @args|
    var code = ''
    try {
        set code = ((as-command $cmd) $@args | slurp)
    } catch _ {
        warn $tool": shell integration skipped, '"$cmd" "(str:join ' ' $args)"' failed"
        return
    }
    # Loading is a second failure point: the generator can exit 0 and still emit
    # something this shell won't take. Nothing can be undone by then, so report
    # it rather than reporting success.
    try {
        eval $code
    } catch _ {
        warn $tool": shell integration may be incomplete, its init failed while loading"
    }
}

# zoxide's `z`/`zi` directory jumps. `cd` is deliberately left alone: the
# builtin stays predictable, and z is the opt-in fuzzy version.
fn init-zoxide {
    if (not (have-command zoxide)) { return }
    eval-tool-init zoxide zoxide init elvish
}

# carapace's completions, which cover far more commands than Elvish works out
# for itself. CARAPACE_BRIDGES is the fallback for commands carapace has no spec
# of its own for: it delegates to bash-completion (which scrapes `cmd --help`),
# fish's man-page-derived completions, and the CLI frameworks' own completers.
fn init-carapace {
    if (not (have-command carapace)) { return }
    if (==s (env-or CARAPACE_BRIDGES '') '') {
        set-env CARAPACE_BRIDGES bash,fish,inshellisense
    }
    eval-tool-init carapace carapace _carapace elvish
}

# atuin's history recording.
#
# TODO: `atuin init` has no elvish target, so this drives atuin's documented
# history CLI directly -- the same route shrc takes under bash, where
# bash-preexec would otherwise fight shrc for the DEBUG trap. `atuin history
# start` opens an entry when a line is accepted and `atuin history end` closes
# it with the command's exit status. The Ctrl-R search widget the other shells
# get from `atuin init` is in lib/interactive.elv, hand-rolled around
# `atuin search -i`.
var atuin-history-id = ''

fn atuin-wanted {
    if (not (have-command atuin)) { put $false; return }
    put (not-eq (env-or ATUIN_SESSION '') '')
}

# Record the command about to run. A half-written id is worse than none:
# atuin-command-finished would close out an entry that doesn't exist, and
# keeping it would leave the next command closing this one. Drop it and say so
# -- the command goes unrecorded either way, but silently is how you find out
# weeks later.
fn atuin-command-started {|line|
    if (not (atuin-wanted)) { return }
    var id = ''
    try {
        set id = (str:trim-space (atuin history start -- $line | slurp))
    } catch _ {
        set id = ''
    }
    # An empty id counts as a failure even when the call succeeded: there would
    # be nothing for atuin-command-finished to close out, and keeping it would
    # leave the next command closing this one. shrc:2394 tests both the status
    # and the id for the same reason.
    if (==s $id '') {
        set atuin-history-id = ''
        warn "atuin: history start failed; this command won't be recorded"
        return
    }
    set atuin-history-id = $id
}

# Close out the entry, with the exit status of the command that just finished.
# Runs detached: `history end` can block on the sync daemon, and a prompt must
# not wait for it. Only stdout is discarded -- a failure here means the entry is
# stranded unfinished, so atuin's own diagnostic is left on stderr.
fn atuin-command-finished {|m|
    if (==s $atuin-history-id '') { return }
    if (not (have-command atuin)) { set atuin-history-id = ''; return }
    var id = $atuin-history-id
    set atuin-history-id = ''
    atuin history end --exit (to-string (exit-status $m[error])) -- $id >/dev/null &
}

# Open an atuin session. The other shells get $ATUIN_SESSION from
# `atuin init`, which has no elvish target, so it is minted here -- the recorded
# history is grouped by it, and `atuin history start` needs it set.
fn init-atuin {
    if (not (have-command atuin)) { return }
    if (not-eq (env-or ATUIN_SESSION '') '') { return }
    var id = (capture-word atuin uuid)
    if (==s $id '') {
        warn "atuin: could not start a session; history won't be recorded"
        return
    }
    set-env ATUIN_SESSION $id
}

fn init-shell-tools {
    init-zoxide
    init-carapace
    init-atuin
}

#########################
# INTERACTIVE SETUP
# Everything above is definitions, so loading this file from a test is
# side-effect free. Everything below acts.

if (not $failsafe-mode) {
    set-up-standard-variables
    setup-path
    setup-brew
    setup-fnm
    setup-program-defaults
    init-colors
    pick-ls-flavor

    apply-shpool-initial-pwd

    # Hand off to shpool or tmux before anything else interactive is set up: a
    # shell that is about to be replaced should not pay for a prompt it will
    # throw away.
    maybe-start-session-and-exit

    log-history "New session as" (env-or USERNAME '') "in elvish"

    if (stdin-is-tty) {
        # `use` is resolved when it runs, not when this file is compiled, so
        # everything that names `$edit:` is reached only from here -- see note 3
        # at the top of the file.
        use interactive

        # Before the editor is wired up, so `install` can see whether atuin
        # has a session to search and so its Ctrl-R binding is installed last
        # -- the same ordering shrc uses to let atuin win that key.
        init-shell-tools

        interactive:install ^
            &before-readline=$preprompt~ ^
            &after-readline={|line| command-started $line; atuin-command-started $line } ^
            &after-command={|m| command-finished $m; atuin-command-finished $m } ^
            &root=$i-am-root~ ^
            &color=$color ^
            &atuin=(atuin-wanted)

        # Past this point we're the shell we're keeping -- the handoff above
        # exits if it started a session -- so build the ssh-config host aliases
        # here, as shrc and config.fish do at the same point.
        interactive:publish-vars (ssh-alias-vars)

        # Interactive local overrides (work vs home, etc.), matching shrc's
        # ~/.shrc.local and config.fish's local.fish.
        #
        # TODO: Elvish cannot source a file into this namespace, so the local
        # overrides have to be a module: ~/.config/elvish/lib/local.elv. It can
        # set environment variables and $paths directly, but a function it
        # defines lands in its own namespace and reaches the prompt only if the
        # file publishes it with `edit:add-var` -- where ~/.shrc.local and
        # local.fish just define one. Anything the session handoff above reads
        # -- WANT_SHPOOL, WANT_TMUX, SESSION_BACKEND -- is too late here and has
        # to come from the environment this shell inherited.
        try {
            use local
        } catch e {
            # A missing local.elv is the normal case, not a failure; anything
            # else is worth reporting, and is not fatal for the same reason
            # shrc's `. ~/.shrc.local` isn't: a broken per-machine override
            # shouldn't cost the shell everything already set up before it.
            if (not (str:contains (to-string $e) 'no such module')) {
                warn "local.elv failed; the rest of the interactive setup still ran"
            }
        }

        # Gated on a real terminal as well as interactivity: `ssh-add` prompts,
        # and a session with stdin redirected cannot answer it.
        if (and (not (in-shpool)) (need-auth)) { auth }
    }
}
