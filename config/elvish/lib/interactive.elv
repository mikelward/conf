# The line-editor half of the Elvish config, imported by rc.elv as
# ~/.config/elvish/lib/interactive.elv.
#
# It lives in a module rather than in rc.elv because `$edit:` exists only when
# Elvish has a terminal to edit on, and Elvish resolves variable references when
# a file is *compiled*: naming `$edit:prompt` in rc.elv would make the whole of
# it fail to compile under `echo cmd | elvish`, which reads rc.elv but has no
# editor. `use` is resolved when it runs, so rc.elv reaches this file only once
# it knows there is a terminal, and the test suite can load rc.elv without a pty.
#
# A module cannot see rc.elv's definitions, so everything this file needs is
# handed to `install` as options.
#
# Mikel Ward <mikel@mikelward.com>

use str

# Publish a map of names to values into the interactive namespace, so `rc.elv`
# can bind names it computes -- the ssh-config host aliases. `edit:add-vars` is
# the only way to bind a computed name in Elvish; there is no `eval` route,
# since eval's namespace is thrown away.
fn publish-vars {|to-publish|
    # `keys` outputs one value per key rather than a list, so it is collected
    # before being counted.
    if (== (count [(keys $to-publish)]) 0) { return }
    edit:add-vars $to-publish
}

# The prompt glyph.
#
# Deliberately `$`, matching shrc and mesh rather than fish's and nushell's `>`:
# each shell uses its own native glyph so the prompt doubles as a
# which-shell-am-I-in cue. Elvish's own default is `~> `, so `$ ` also says
# "this prompt is configured". When root the glyph is the same but red;
# rc.elv's host-info also prepends a red [root] tag, so the cue survives
# without color.
fn -prompt-glyph {|root color|
    if (and ($root) $color) {
        put (styled '$' red)
    } else {
        put '$'
    }
    put ' '
}

# atuin's Ctrl-R search.
#
# TODO: hand-rolled, because `atuin init` has no elvish target -- the other
# shells get this widget from atuin itself. `atuin search -i` draws its TUI on
# the terminal and writes the chosen command to stdout, which is the same
# contract the shipped integrations rely on. A cancelled search prints nothing
# and exits non-zero, which is the `catch` below.
#
# The pane's size and style come from config/atuin/config.toml, which atuin
# reads whoever launched it, so the inline nine-row search the other shells get
# is what appears here too -- nothing to keep in parity by hand.
fn -atuin-search {
    var chosen = ''
    try {
        set chosen = (atuin search -i -- $edit:current-command | slurp)
    } catch _ {
        return
    }
    set chosen = (str:trim-space $chosen)
    if (==s $chosen '') { return }
    set edit:current-command = $chosen
}

# Wire the editor up to the callbacks rc.elv computed.
#
# &before-readline runs before each prompt is drawn (shrc's preprompt),
# &after-readline once a line is accepted (shrc's precommand / zsh's preexec),
# and &after-command once it has run, with a map of &src, &duration and &error
# (what shrc's last_job_info reconstructs from $? and $SECONDS).
fn install {|&before-readline=$nop~ &after-readline=$nop~ &after-command=$nop~ ^
             &root={ put $false } &color=$true &atuin=$false|
    set edit:prompt = { -prompt-glyph $root $color }
    # Elvish's default right prompt is a reverse-video user@host. rc.elv already
    # puts the hostname on the context line above the prompt, and shrc has no
    # right prompt at all, so this is blanked rather than left doubled up.
    set edit:rprompt = { }
    set @edit:before-readline = $before-readline
    set @edit:after-readline = $after-readline
    set @edit:after-command = $after-command

    # Regain the use of Ctrl-S and Ctrl-Q, as shrc does. Guarded because
    # tcsetattr raises SIGTTOU when this shell isn't the terminal's foreground
    # process group, and a terminal that has no such flow control at all
    # (a serial console, a bare pty) makes stty exit non-zero.
    try { stty start undef stop undef 2>/dev/null } catch _ { }

    if $atuin {
        set edit:insert:binding[Ctrl-R] = { -atuin-search }
    }
}

# TODO: no key-binding parity with shrc. Elvish's editor has one keymap rather
# than readline's and zle's emacs/vi pair, and no `bindkey -M`; its own defaults
# already cover most of what shrc rebinds (Ctrl-A/E/K/U/W/Y, Alt-B/F, word
# motion), so nothing is rebound here beyond Ctrl-R above. shrc's vi-mode
# additions, its Page Up / Page Down suppression and its terminfo-driven
# Home/End/Delete bindings have no Elvish equivalent -- Elvish reads those keys
# itself.
#
# TODO: no vi-mode indicator either, since there is no vi mode: shrc's
# keymap_character (NORMAL / INSERT before the glyph) and fish's
# fish_mode_prompt have nothing to report here.
#
# TODO: no bold-input attribute. shrc leaves bold on at the end of the prompt
# and clears it from PS0, and zsh does it through zle_highlight; Elvish
# highlights the line it is editing itself -- commands green, unknown ones red
# -- and offers no way to add an attribute over the whole input.
