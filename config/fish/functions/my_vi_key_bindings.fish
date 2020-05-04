function my_vi_key_bindings --description "Mikel's vi-like key bindings for fish"
    if contains -- -h $argv
        or contains -- --help $argv
        echo "Sorry but this function doesn't support -h or --help"
        return 1
    end

    # Start with the standard Fish bindings that are similar to Vi.
    fish_vi_key_bindings

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
end
