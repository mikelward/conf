# Configuration for elvish shell.
#
# Mikel Ward <mikel@mikelward.com>
#
# Aims to match the zsh/bash prompt and VCS integration from shrc.
# Non-interactive functions live in lib/shrc.elv for testability.

use shrc

########
# PATHS

shrc:prepend-path ~/bin
shrc:prepend-path ~/.local/bin

################
# PROMPT
#
# Matches the zsh/bash preprompt:
#   ――――――――――――――――――
#   hostname [session]
#   project subdir branch M ? fetch
#   base commit
#   $ _

set edit:prompt = {
  # preprompt output
  print "\n"
  shrc:bar
  print "\r"
  shrc:host-info
  print " "
  shrc:dir-info
  print "\n"
  shrc:map
  shrc:set-xterm-title (shrc:title)

  # actual prompt
  if (eq $shrc:uid 0) {
    put '# '
  } else {
    put '$ '
  }
}

set edit:rprompt = { }

################
# VI MODE

# Use vi keybindings if available
try {
  set edit:insert:binding[Escape] = $edit:command:start~
} catch { }

################
# ALIASES / SHORTCUTS

fn cr { cd (shrc:rootdir) }
fn rd { cd (shrc:rootdir) }
fn st { var v = (shrc:vcs); if (eq $v git) { git status --short --untracked-files=all } elif (eq $v hg) { hg status } elif (eq $v jj) { jj status } }
fn di { var v = (shrc:vcs); if (eq $v git) { git diff } elif (eq $v hg) { hg diff } elif (eq $v jj) { jj diff } }
fn ci {|@args| var v = (shrc:vcs); if (eq $v git) { git commit $@args } elif (eq $v hg) { hg commit $@args } elif (eq $v jj) { jj commit $@args } }
fn am {|@args| var v = (shrc:vcs); if (eq $v git) { git commit --amend --no-edit --all $@args } elif (eq $v hg) { hg amend $@args } elif (eq $v jj) { jj squash $@args } }
fn lg { var v = (shrc:vcs); if (eq $v git) { git log --oneline --graph } elif (eq $v hg) { hg log --graph } elif (eq $v jj) { jj log } }
