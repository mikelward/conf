# zsh-specific commands for all sessions.

# Red Hat's /etc/zshrc and /etc/zprofile break things
unsetopt GLOBAL_RCS

# emulate bash
emulate sh
setopt BRACE_EXPAND
setopt BANG_HIST
setopt CSH_JUNKIE_HISTORY
setopt KSH_TYPESET
# emulate sh doesn't set this PROMPT_SUBST
# could use emulate -R, but that breaks compinit
setopt PROMPT_SUBST

# useful optional features in both bash and zsh
setopt AUTO_CD       # autocd in bash
setopt KSH_GLOB      # extglob in bash

# zsh specifics
setopt BARE_GLOB_QUAL
setopt CORRECT
setopt DVORAK
setopt PROMPT_PERCENT
setopt PUSHD_SILENT

# read .env in .zshrc for compatibility with other POSIX shells
