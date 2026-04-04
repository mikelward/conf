# Shared functions for elvish shell configuration.
#
# Mikel Ward <mikel@mikelward.com>
#
# This module contains all non-interactive functions (VCS, colors, prompt
# helpers) so they can be tested without a terminal.  rc.elv sources this
# and wires up the interactive edit: namespace.

use path
use str

#######
# PATH FUNCTIONS

fn prepend-path {|dir|
  if (path:is-dir $dir) {
    set paths = [$dir (each {|p| if (not-eq $p $dir) { put $p }} $paths)]
  }
}

fn append-path {|dir|
  if (path:is-dir $dir) {
    set paths = [(each {|p| if (not-eq $p $dir) { put $p }} $paths) $dir]
  }
}

fn inpath {|dir|
  each {|p| if (eq $p $dir) { return }} $paths
  fail "not in path"
}

fn add-path {|dir &where=default|
  if (eq $where start) {
    prepend-path $dir
  } elif (eq $where end) {
    append-path $dir
  } else {
    try { inpath $dir } catch { append-path $dir }
  }
}

#################
# BASIC VARIABLES

var hostname = (hostname -s)
var uid = (id -u)

#################
# BASIC FUNCTIONS

fn have-command {|cmd|
  not-eq (search-external $cmd) ""
}

# Get an environment variable with a default if unset.
fn getenv {|name &default=""|
  if (has-env $name) {
    get-env $name
  } else {
    put $default
  }
}

#################
# COLORS

fn set-color {|@args|
  for arg $args {
    if (eq $arg normal) {
      print "\033[0m"
    } elif (eq $arg bold) {
      print "\033[1m"
    } elif (eq $arg underline) {
      print "\033[4m"
    } elif (eq $arg red) {
      print "\033[31m"
    } elif (eq $arg green) {
      print "\033[32m"
    } elif (eq $arg yellow) {
      print "\033[33m"
    } elif (eq $arg blue) {
      print "\033[34m"
    } elif (eq $arg magenta) {
      print "\033[35m"
    } elif (eq $arg cyan) {
      print "\033[36m"
    } elif (eq $arg white) {
      print "\033[37m"
    }
  }
}

fn color-print {|color text|
  set-color $color
  print $text
  set-color normal
}

fn blue {|@text| color-print blue (str:join " " $text) }
fn green {|@text| color-print green (str:join " " $text) }
fn red {|@text| color-print red (str:join " " $text) }
fn yellow {|@text| color-print yellow (str:join " " $text) }

################
# VCS DETECTION
#
# Detects git, hg, and jj repositories by walking up the directory tree.
# Caches results in .vcs_cache for performance, matching shrc behavior.

fn vcs-detect {
  # Check for .vcs_cache first
  if (path:is-regular .vcs_cache) {
    var lines = [(cat .vcs_cache)]
    if (> (count $lines) 1) {
      var fields = [(str:split " " $lines[0])]
      put $fields[0] $lines[1]
      return
    }
  }

  # Walk up to find VCS root
  var dir = $pwd
  while (not-eq $dir /) {
    if (path:is-dir $dir/.jj) {
      put jj $dir
      return
    } elif (path:is-dir $dir/.hg) {
      put hg $dir
      return
    } elif (path:is-dir $dir/.git) {
      put git $dir
      return
    }
    set dir = (path:dir $dir)
  }
  fail "no vcs"
}

# Return the VCS type for the current directory, or empty string.
fn vcs {
  try {
    var vcstype root = (vcs-detect)
    put $vcstype
  } catch {
    put ""
  }
}

# Return the VCS root directory, or empty string.
fn rootdir {
  try {
    var vcstype root = (vcs-detect)
    put $root
  } catch {
    put ""
  }
}

################
# VCS BRANCH

fn git-branch {
  try {
    var branch = (git branch 2>/dev/null | each {|line|
      if (str:has-prefix $line "* ") {
        put (str:trim-prefix $line "* ")
      }
    })
    put $branch
  } catch {
    put ""
  }
}

fn hg-branch {
  try {
    put (hg branch 2>/dev/null)
  } catch {
    put ""
  }
}

fn jj-branch {
  # jj has no current bookmark concept
  put ""
}

fn vcs-branch {
  var vcstype = (vcs)
  if (eq $vcstype git) {
    git-branch
  } elif (eq $vcstype hg) {
    hg-branch
  } elif (eq $vcstype jj) {
    jj-branch
  } else {
    put ""
  }
}

################
# VCS STATUS

# Collect unique values from a list, preserving order.
fn unique {|@vals|
  var seen = [&]
  each {|v|
    if (not (has-key $seen $v)) {
      set seen[$v] = $true
      put $v
    }
  } $vals
}

fn git-status-chars {
  try {
    var raw = [(git status --short --untracked-files=all 2>/dev/null | each {|line|
      var fields = [(str:fields $line)]
      if (> (count $fields) 0) {
        put $fields[0]
      }
    })]
    var chars = [(unique $@raw)]
    str:join " " $chars
  } catch {
    put ""
  }
}

fn hg-status-chars {
  try {
    var raw = [(hg status 2>/dev/null | each {|line|
      var fields = [(str:fields $line)]
      if (> (count $fields) 0) {
        put $fields[0]
      }
    })]
    var chars = [(unique $@raw)]
    str:join " " $chars
  } catch {
    put ""
  }
}

fn jj-status-chars {
  try {
    # Only show status for undescribed commits (jj equivalent of uncommitted)
    var desc = (jj log --no-graph -r @ -T 'description' 2>/dev/null)
    if (not-eq $desc "") {
      put ""
      return
    }
    var raw = [(jj diff --summary 2>/dev/null | each {|line|
      var fields = [(str:fields $line)]
      if (> (count $fields) 0) {
        put $fields[0]
      }
    })]
    var chars = [(unique $@raw)]
    str:join " " $chars
  } catch {
    put ""
  }
}

fn status-chars {
  var vcstype = (vcs)
  if (eq $vcstype git) {
    git-status-chars
  } elif (eq $vcstype hg) {
    hg-status-chars
  } elif (eq $vcstype jj) {
    jj-status-chars
  } else {
    put ""
  }
}

################
# VCS FETCH INFO

fn git-fetchtime {
  try {
    var gitdir = (git rev-parse --git-dir 2>/dev/null)
    var fetch-head = $gitdir/FETCH_HEAD
    if (path:is-regular $fetch-head) {
      put (stat -c %Y $fetch-head 2>/dev/null)
    } else {
      fail "no fetch head"
    }
  } catch {
    fail "no fetchtime"
  }
}

fn hg-fetchtime {
  try {
    var root = (rootdir)
    var changelog = $root/.hg/store/00changelog.i
    if (path:is-regular $changelog) {
      put (stat -c %Y $changelog 2>/dev/null)
    } else {
      fail "no changelog"
    }
  } catch {
    fail "no fetchtime"
  }
}

fn jj-fetchtime {
  try {
    var root = (rootdir)
    var fetch-head = $root/.jj/repo/store/git/FETCH_HEAD
    if (path:is-regular $fetch-head) {
      put (stat -c %Y $fetch-head 2>/dev/null)
    } else {
      fail "no fetch head"
    }
  } catch {
    fail "no fetchtime"
  }
}

fn fetch-info {
  try {
    var vcstype = (vcs)
    var timestamp = ""
    if (eq $vcstype git) {
      set timestamp = (git-fetchtime)
    } elif (eq $vcstype hg) {
      set timestamp = (hg-fetchtime)
    } elif (eq $vcstype jj) {
      set timestamp = (jj-fetchtime)
    } else {
      return
    }
    if (eq $timestamp "") { return }
    var now = (date +%s)
    var age = (- $now $timestamp)
    if (> $age 86400) {
      yellow fetch
    }
  } catch {
    # no fetch info available
  }
}

################
# VCS MAP

fn git-base {
  try {
    var head = (git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if (eq $head HEAD) {
      print "(detached) "
    }
    git --no-pager log -1 --oneline 2>/dev/null
  } catch { }
}

fn git-graph {
  try {
    git --no-pager log --oneline '@{upstream}..HEAD' 2>/dev/null
  } catch { }
}

fn git-at-tip {
  try {
    var head = (git rev-parse --abbrev-ref HEAD 2>/dev/null)
    not-eq $head HEAD
  } catch {
    put $true
  }
}

fn hg-base {
  try {
    hg --pager never log -r . --template '{onelinesummary}\n' 2>/dev/null
  } catch { }
}

fn hg-graph {
  try {
    hg --pager never log --template '{onelinesummary}\n' -r '::. and not ::last(heads(branch(.)))' 2>/dev/null
  } catch { }
}

fn hg-at-tip {
  try {
    var result = (hg --pager never log -r '. and last(heads(branch(.)))' --template x 2>/dev/null)
    not-eq $result ""
  } catch {
    put $true
  }
}

fn jj-base {
  try {
    jj --no-pager log --no-graph -r '@|@-' --template 'if(self.contained_in("@"), if(description.first_line(), "@ " ++ change_id.shortest() ++ " " ++ description.first_line() ++ "\n"), "* " ++ change_id.shortest() ++ " " ++ description.first_line() ++ "\n")' 2>/dev/null
  } catch { }
}

fn jj-at-tip {
  try {
    var result = (jj --no-pager log --no-graph -r 'children(@) | (children(@-) ~ @)' --template '"x"' 2>/dev/null)
    eq $result ""
  } catch {
    put $true
  }
}

fn map {
  var vcstype = (vcs)
  if (eq $vcstype git) {
    if (git-at-tip) { git-base } else { git-graph }
  } elif (eq $vcstype hg) {
    if (hg-at-tip) { hg-base } else { hg-graph }
  } elif (eq $vcstype jj) {
    if (jj-at-tip) { jj-base } else { jj-base }
  }
}

################
# HOST INFO

fn on-my-laptop {
  if (path:is-regular ~/.laptop) {
    put $true
  } else {
    str:contains $hostname laptop
  }
}

fn on-production-host {
  if (on-my-laptop) {
    put $false
  } elif (str:contains $hostname test) {
    put $false
  } elif (str:contains $hostname dev) {
    put $false
  } else {
    put $true
  }
}

fn short-hostname {
  put $hostname
}

fn host-info {
  if (on-production-host) {
    set-color red
  }
  print (short-hostname)
  set-color normal
  if (not-eq (getenv SHPOOL_SESSION_NAME) "") {
    print " ["
    green (getenv SHPOOL_SESSION_NAME)
    print "]"
  }
}

################
# DIR INFO

fn trim-prefix {|prefix str|
  if (str:has-prefix $str $prefix) {
    put (str:trim-prefix $str $prefix)
  } else {
    put $str
  }
}

fn tilde-directory {
  str:replace (getenv HOME) "~" $pwd
}

fn dir-info {
  var root = (rootdir)
  if (not-eq $root "") {
    green (path:base $root)
    var subdir = (trim-prefix $root $pwd)
    if (not-eq $subdir "") {
      print " "
      blue (str:trim-left $subdir "/")
    }
    var branch = (vcs-branch)
    if (not-eq $branch "") {
      print " "$branch
    }
    var sc = (status-chars)
    if (not-eq $sc "") {
      print " "
      yellow $sc
    }
    fetch-info
  } else {
    blue (tilde-directory)
  }
}

################
# TITLE

fn set-xterm-title {|@args|
  var title = (str:join " " $args)
  print "\033]0;"$title"\007"
}

fn title {
  var parts = []
  set parts = [$@parts (short-hostname)]
  if (not-eq (getenv SHPOOL_SESSION_NAME) "") {
    set parts = [$@parts (getenv SHPOOL_SESSION_NAME)]
  }
  var root = (rootdir)
  if (not-eq $root "") {
    set parts = [$@parts (path:base $root)]
  } else {
    set parts = [$@parts (path:base $pwd)]
  }
  str:join " " $parts
}

################
# BAR

fn bar {
  var width = 80
  try {
    set width = (tput cols)
  } catch { }
  print (str:join "" [(repeat $width "―")])
}

################
# ALIASES / SHORTCUTS

fn cr { cd (rootdir) }
fn rd { cd (rootdir) }
fn st { var v = (vcs); if (eq $v git) { git status --short --untracked-files=all } elif (eq $v hg) { hg status } elif (eq $v jj) { jj status } }
fn di { var v = (vcs); if (eq $v git) { git diff } elif (eq $v hg) { hg diff } elif (eq $v jj) { jj diff } }
fn ci {|@args| var v = (vcs); if (eq $v git) { git commit $@args } elif (eq $v hg) { hg commit $@args } elif (eq $v jj) { jj commit $@args } }
fn am {|@args| var v = (vcs); if (eq $v git) { git commit --amend --no-edit --all $@args } elif (eq $v hg) { hg amend $@args } elif (eq $v jj) { jj squash $@args } }
fn lg { var v = (vcs); if (eq $v git) { git log --oneline --graph } elif (eq $v hg) { hg log --graph } elif (eq $v jj) { jj log } }
