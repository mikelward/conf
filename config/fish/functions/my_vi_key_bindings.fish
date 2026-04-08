function my_vi_key_bindings --description "Mikel's vi-like key bindings for fish"
    if contains -- -h $argv
        or contains -- --help $argv
        echo "Sorry but this function doesn't support -h or --help"
        return 1
    end

    # Start with the standard Fish bindings that are similar to Vi.
    fish_vi_key_bindings

    # Try to differentiate between Esc and Alt+<key> by shortening the wait.
    # Mirrors KEYTIMEOUT=1 in zsh (shrc).
    set -g fish_escape_delay_ms 10

    # Don't move backwards when switching from insert to normal (command) mode.
    # If we are paging, stay in insert mode.
    bind -s -M insert \e "if commandline -P; commandline -f cancel; else; set fish_bind_mode default; commandline -f force-repaint; end"

    # Undo weird Vi EOL behavior.
    bind -s -M default x delete-char
    bind -s -M default X backward-delete-char
    bind -s -M insert -k dc delete-char
    bind -s -M default -k dc delete-char

    # Backspace deletes a char in normal/default mode too.
    bind -s -M default -k backspace backward-delete-char
    bind -s -M default \ch backward-delete-char
    bind -s -M default \x7f backward-delete-char

    # Add Emacs bindings to both insert and normal mode.
    # Mirrors _bind_vi in shrc for the zsh config.
    for mode in insert default
        # Motion.
        bind -s -M $mode \ca beginning-of-line
        bind -s -M $mode \ce end-of-line
        # History.
        bind -s -M $mode \cn down-or-search
        bind -s -M $mode \cp up-or-search
        bind -s -M $mode \cr history-pager
        bind -s -M $mode \cs forward-char
        # Kill/yank.
        bind -s -M $mode \ck kill-line
        bind -s -M $mode \cu kill-whole-line
        bind -s -M $mode \cw backward-kill-word
        bind -s -M $mode \cy yank
        # Esc prefix bindings.
        bind -s -M $mode \eb backward-word
        bind -s -M $mode \ef forward-word
        bind -s -M $mode \ey yank-pop
        bind -s -M $mode \e_ history-token-search-backward
        bind -s -M $mode \e\x7f backward-kill-word
    end

    # Home, End, and Delete keys via terminfo-style names.
    for mode in insert default
        bind -s -M $mode -k home beginning-of-line
        bind -s -M $mode -k end end-of-line
        # Prevent Page Up and Page Down from inserting a bogus ~.
        bind -s -M $mode -k ppage ''
        bind -s -M $mode -k npage ''
        # Shift+Tab does a menu-complete backwards.
        bind -s -M $mode -k btab complete-and-search
    end
end
