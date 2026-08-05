#
# zsh-specific configuration for interactive shells.
#
# This is a real file, not a symlink to shrc like bashrc and kshrc are.
# shrc has to parse under dash, which rules out zsh's own syntax
# everywhere in it -- dash parses the `zsh)` arm of every case even
# though it never runs it, and rejects things like `foo=( ... )`. Code
# that needs to be zsh belongs here instead.
#
# What lives here: options wanted because zsh is *better* than sh.
# What stays in shrc: the sh behavior shrc's own portable code still
# depends on. That second set is the porting backlog -- when it and the
# `emulate -L sh` opt-ins are gone, the port is done.
#
# Options split by kind, because the two kinds want opposite placement.
# Resets back to a zsh default go before shrc is sourced; deviations from
# the default go after, behind the failsafe guard. See each block.
#

# This file's own path, captured while it is being read. %x names the file
# currently being sourced; $0 does not (see the source line below for why).
# Kept in a global because rerc needs it long after this file has been read,
# by which point %x names whatever is running then.
typeset -g _ZSHRC_SELF=${${(%):-%x}:A}

# Reset three options to zsh's own defaults, before shrc is sourced.
#
# They were once needed to undo shrc's `emulate sh`, which is gone, so it
# is tempting to drop them as no-ops. They aren't: an earlier startup file
# can set them, and /etc/zshenv is read before ~/.zshenv gets to turn
# GLOBAL_RCS off, so it can't be opted out of. POSIX_ALIASES is the one
# that bites -- shrc's `+` / `-` / `+-` aliases still *define* under it but
# fail to expand, so the aliases silently do nothing. That happens while
# shrc runs, which is why this block has to come first.
#
# Running before the failsafe guard is safe precisely because these are
# resets: they move the shell toward stock zsh, which is what failsafe
# wants anyway. The block below, which deviates from stock, does not get
# that exemption.
unsetopt POSIX_ALIASES  # shrc's + and - aliases won't expand otherwise
unsetopt KSH_AUTOLOAD   # zsh-style autoload, for e.g. bashcompinit
unsetopt SH_GLOB        # numeric globs, and glob grouping in parens

# The portable core: compat options, functions, prompt, session startup.
#
# %x is the file currently being read, which is the only spelling that
# works in every way this file gets loaded. $0 is NOT: when zsh reads
# ~/.zshrc as a startup file $0 is the shell name, so `${0:A:h}` would
# expand to the *current directory* and quietly source nothing. It only
# looks right under `source /path/to/zshrc`, where $0 is the file.
# `:A` then resolves the ~/.zshrc symlink back to the checkout.
. "${_ZSHRC_SELF:h}/shrc"

# Everything below is skipped in failsafe mode. shrc returns early for
# FAILSAFE / LC_FAILSAFE / ~/.failsafe, before it defines any function, so
# the absence of one is the signal -- rather than re-implementing shrc's
# tri-state flag parsing here and having the two drift. Back when zshrc was
# a symlink to shrc, failsafe reached that guard before any zsh setup at
# all; keeping these after the source restores that, so the escape hatch
# doesn't leave globbing altered by the config it exists to escape.
(( $+functions[have_command] )) || return 0

# enable ksh default features. Unlike the resets above these deviate from
# stock zsh, so they stay behind the failsafe guard and are not needed
# while shrc parses -- shrc uses no !(pattern) and no glob qualifiers.
setopt KSH_GLOB         # !(pattern) etc. like in ksh
unsetopt BARE_GLOB_QUAL # otherwise !(pattern) breaks

# Reload the whole zsh configuration, not just the portable core. shrc
# defines rerc as `. ~/.shrc`, which was the entire config while zshrc was
# a symlink to shrc -- config/mesh/rc.mesh says as much, that shrc's rerc
# re-reads one file because shrc *is* one file. That stopped being true for
# zsh here: reloading only shrc would miss this file's options (so a plugin
# that flipped one would keep it flipped) and any edit made to this file.
# fish and nushell already re-read their own active config, so this keeps
# reload in parity with startup across all of them.
#
# Defined after the source so it overrides shrc's version rather than being
# overwritten by it -- the shape every future zsh-native override takes.
rerc() { . "$_ZSHRC_SELF"; }

#  vim: set ts=4 sw=4 tw=0 et:
