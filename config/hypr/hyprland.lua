-- Hyprland configuration (Lua, Hyprland 0.55+)
-- ~/.config/hypr/hyprland.lua
--
-- A dynamic-tiling Wayland desktop with a master/stack layout, modelled on
-- the Krohnkite KWin script ("Tile" layout = master). This is the Lua port
-- of hyprland.conf: since Hyprland 0.55, hyprlang is deprecated in favour of
-- Lua, and a hyprland.lua takes precedence over hyprland.conf. The old
-- hyprland.conf is kept (frozen) for machines still on Hyprland <= 0.54,
-- which ignore this file. Keep the two in sync until every machine is on
-- 0.55+.
--
-- Wiki: https://wiki.hypr.land/Configuring/Start/

--------------------------------------------------------------------------------
-- MONITORS
--------------------------------------------------------------------------------
-- Auto-place every output at its preferred mode, left-to-right. This
-- catch-all needs no monitor names, so it works on every machine (laptop
-- panel, docked, undocked, dual-head workstation) with zero config --
-- combined with lid.sh, which disables the internal panel on lid close so a
-- clamshell setup falls back to the external automatically.
--
-- For a SPECIFIC arrangement, add per-output rules in hyprland-local.lua,
-- e.g.: hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = "1" })
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

--------------------------------------------------------------------------------
-- PROGRAMS
--------------------------------------------------------------------------------
local terminal = "kitty"
local lock     = "hyprlock"

--------------------------------------------------------------------------------
-- AUTOSTART
--------------------------------------------------------------------------------
-- Same set as hyprland.conf's exec-once lines; hl.exec_cmd spawns async, so
-- no `& disown` needed.
hl.on("hyprland.start", function()
    -- Wallpaper: swww gives a daemon you can swap wallpapers against.
    -- >>> PLACEHOLDER: point this at a real image file. <<<
    hl.exec_cmd("swww-daemon")
    hl.exec_cmd("sleep 1 && swww img ~/.config/hypr/wallpaper.jpg")

    -- Idle/lock manager.
    hl.exec_cmd("hypridle")

    -- Auto-configure pointers (mice -> right button primary; touchpads left
    -- as-is) by classifying each device at login.
    hl.exec_cmd("~/.config/hypr/scripts/apply-input.sh")

    -- Time-based light/dark theming; the daemon LAUNCHES waybar + swaync
    -- with the matching style, so they have no exec lines of their own.
    hl.exec_cmd("~/.config/hypr/scripts/theme-daemon.sh")

    -- Tray applets: NetworkManager and blueman.
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")

    -- Polkit authentication agent: uncomment the one you have installed.
    -- hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
    -- hl.exec_cmd("/usr/libexec/polkit-gnome-authentication-agent-1")
end)

--------------------------------------------------------------------------------
-- ENVIRONMENT
--------------------------------------------------------------------------------
-- These apply to a plain `exec Hyprland` session. If you launch via uwsm,
-- the same vars are also set in config/uwsm/{env,env-hyprland} (shell
-- `export` form) so systemd user services see them -- keep the two in sync.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- Prefer Wayland backends where apps support it.
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("NIXOS_OZONE_WL", "1")
-- Match your xsessionrc: disable GTK overlay (disappearing) scrollbars.
hl.env("GTK_OVERLAY_SCROLLING", "0")

--------------------------------------------------------------------------------
-- LAYOUT / LOOK
--------------------------------------------------------------------------------
hl.config({
    general = {
        layout = "master",

        -- No gaps, as requested.
        gaps_in  = 0,
        gaps_out = 0,
        border_size = 2,

        col = {
            active_border   = "rgba(88c0d0ff)",
            inactive_border = "rgba(3b4252ff)",
        },

        -- Drag-to-resize with the mouse without holding a modifier still
        -- needs the modifier below; this only affects tiled resize by
        -- dragging borders.
        resize_on_border = true,
        allow_tearing = false,
    },

    decoration = {
        -- Slightly rounded corners + subtle blur, tasteful not gaudy.
        rounding = 6,

        blur = {
            enabled = true,
            size = 4,
            passes = 2,
            new_optimizations = true,
            ignore_opacity = true,
            xray = false,
        },

        shadow = {
            enabled = true,
            range = 8,
            render_power = 2,
            color = 0x44000000, -- ARGB, was rgba(00000044)
        },

        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        -- Dim inactive windows, matching the KDE "dim inactive" effect the
        -- setup-kde config enabled (Strength 15 -> 0.15 here). Subtle, so
        -- the focused window stands out without the rest going murky.
        dim_inactive = true,
        dim_strength = 0.15,
        dim_special = 0.2,
    },

    animations = {
        enabled = true,
    },

    -- Master layout = Krohnkite "Tile". New windows join the STACK (slave),
    -- not the master, matching Krohnkite's default. mfact is the master
    -- area ratio.
    master = {
        new_status = "slave",
        new_on_top = false,
        mfact = 0.55,
        orientation = "left",
        allow_small_split = false,
    },

    dwindle = {
        pseudotile = true,
        preserve_split = true,
    },

    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        focus_on_activate = true,
        vfr = true,
    },
})

-- Animation curve + speeds carried over from hyprland.conf (speed unit is
-- unchanged; `windowsOut` keeps its popin style).
hl.curve("ease", { type = "bezier", points = { {0.25, 0.1}, {0.25, 1.0} } })
hl.animation({ leaf = "windows",    enabled = true, speed = 3, bezier = "ease" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "ease", style = "popin 80%" })
hl.animation({ leaf = "border",     enabled = true, speed = 6, bezier = "ease" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3, bezier = "ease" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "ease" })

--------------------------------------------------------------------------------
-- INPUT
--------------------------------------------------------------------------------
hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "dvorak",
        -- Caps Lock is the Compose key, matching `setup`'s
        -- configure_keyboard (XKBOPTIONS="compose:caps"). (Your espanso
        -- config also uses lv3:menu_switch; add it here as
        -- "compose:caps,lv3:menu_switch" if you want the Menu key as AltGr
        -- too.)
        kb_options = "compose:caps",

        -- Focus follows the mouse; no click needed to focus a window.
        follow_mouse = 1,
        -- Don't change the tiled split when the mouse merely passes over
        -- windows.
        mouse_refocus = false,

        sensitivity = 0,
        accel_profile = "flat",

        -- Global default handedness = right-handed (LEFT button primary):
        -- what trackpads should use, so trackpads need no per-device block.
        -- apply-input.sh flips MICE to left_handed = true (RIGHT button
        -- primary) per device at login; no device names are hardcoded.
        left_handed = false,

        touchpad = {
            natural_scroll = true,
            tap_to_click = true,
            disable_while_typing = true,
            -- Trackpad scroll speed (applies to every touchpad).
            scroll_factor = 1.0,
        },
    },
})

-- Touchpad gestures: a 3-finger horizontal swipe cycles workspaces.
hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

--------------------------------------------------------------------------------
-- KEYBINDS
--------------------------------------------------------------------------------
local mainMod = "SUPER"

-- Register every bind's handle in a global table keyed by its key string,
-- so hyprland-local.lua can REBIND a key by disabling the shared bind first:
--     hyprbinds["SUPER + E"]:set_enabled(false)
--     hl.bind("SUPER + E", hl.dsp.exec_cmd("nautilus"))
-- (Binds accumulate -- every bind on a key fires in order -- so this is the
-- Lua replacement for hyprland.conf.local's `unbind` dance.)
hyprbinds = {}
local function bind(keys, action, flags)
    hyprbinds[keys] = hl.bind(keys, action, flags)
    return hyprbinds[keys]
end

-- --- Applications / session ---
-- SUPER+<letter> launchers mirror your xbindkeysrc (Mod4). The helper
-- scripts (browser1, home, irc, google-calendar, notepad, ...) live in the
-- scripts repo on $PATH. Two intentional differences from xbindkeysrc: E is
-- the file manager (not editor), and lock uses hyprlock directly
-- (Wayland-native).
bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))                     -- terminal
bind(mainMod .. " + W", hl.dsp.exec_cmd("terminal_on_workstation"))    -- terminal on workstation
bind(mainMod .. " + G", hl.dsp.exec_cmd("browser1"))
bind(mainMod .. " + SHIFT + G", hl.dsp.exec_cmd("browser3"))
bind(mainMod .. " + F", hl.dsp.exec_cmd("browser2"))
bind(mainMod .. " + B", hl.dsp.exec_cmd("bluetooth-connect"))
bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd("pulseprofile.py"))
bind(mainMod .. " + C", hl.dsp.exec_cmd("google-calendar"))
bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("google-chat"))
bind(mainMod .. " + H", hl.dsp.exec_cmd("home"))
bind(mainMod .. " + I", hl.dsp.exec_cmd("irc"))
bind(mainMod .. " + M", hl.dsp.exec_cmd("google-meet"))
bind(mainMod .. " + N", hl.dsp.exec_cmd("notepad"))
bind(mainMod .. " + R", hl.dsp.exec_cmd("remote-desktop"))
bind(mainMod .. " + Y", hl.dsp.exec_cmd("youtube-music"))
-- NOTE: SUPER+D (code) and SUPER+S (secureshell) are intentionally left
-- unbound -- those helper scripts aren't in this repo. Add them in
-- ~/.config/hypr/hyprland-local.lua (required at the end of this file).
bind(mainMod .. " + E", hl.dsp.exec_cmd(terminal .. " -e yazi"))       -- file manager (yazi)
bind(mainMod .. " + Space", hl.dsp.exec_cmd("~/.config/hypr/scripts/launch-fuzzel.sh")) -- launcher
bind(mainMod .. " + BackSpace", hl.dsp.window.close())                 -- close / kill window
bind(mainMod .. " + L", hl.dsp.exec_cmd(lock))                         -- lock screen (hyprlock)
bind(mainMod .. " + SHIFT + E", hl.dsp.exit())                         -- exit Hyprland (log out)

-- --- Krohnkite-equivalent master/stack controls ---
-- On symbol keys, so the letters above stay free for launchers.
-- Master ratio (mfact): Meta+\ grows the master area, Meta+/ shrinks it.
bind(mainMod .. " + backslash", hl.dsp.layout("mfact +0.025"), { repeating = true })
bind(mainMod .. " + slash",     hl.dsp.layout("mfact -0.025"), { repeating = true })

-- Set the focused window as master.
bind(mainMod .. " + Return", hl.dsp.layout("swapwithmaster master"))

-- Add / remove windows from the master area.
bind(mainMod .. " + equal", hl.dsp.layout("addmaster"))
bind(mainMod .. " + minus", hl.dsp.layout("removemaster"))

-- Cycle the master orientation (left/top/right/bottom/center).
bind(mainMod .. " + O", hl.dsp.layout("orientationnext"))
bind(mainMod .. " + SHIFT + O", hl.dsp.layout("orientationprev"))

-- Cycle layouts (tile -> threecolumn -> columns); monocle has its own key
-- below.
bind(mainMod .. " + period", hl.dsp.exec_cmd("~/.config/hypr/scripts/layout-cycle.sh next"))
bind(mainMod .. " + comma",  hl.dsp.exec_cmd("~/.config/hypr/scripts/layout-cycle.sh prev"))

-- Monocle: maximize keeps gaps and the bar visible (old `fullscreen, 1`).
bind(mainMod .. " + grave", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))

-- Move focus through the stack.
bind(mainMod .. " + J", hl.dsp.layout("cyclenext"))
bind(mainMod .. " + K", hl.dsp.layout("cycleprev"))
-- Move the focused window within the stack.
bind(mainMod .. " + SHIFT + J", hl.dsp.layout("swapnext"))
bind(mainMod .. " + SHIFT + K", hl.dsp.layout("swapprev"))

-- Directional focus / move (arrow keys, in addition to the vim stack keys).
bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))
bind(mainMod .. " + SHIFT + left",  hl.dsp.window.move({ direction = "left" }))
bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
bind(mainMod .. " + SHIFT + up",    hl.dsp.window.move({ direction = "up" }))
bind(mainMod .. " + SHIFT + down",  hl.dsp.window.move({ direction = "down" }))

-- --- Layout / window state ---
-- Quick toggle between master and dwindle layouts.
bind(mainMod .. " + SHIFT + backslash", hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-layout.sh"))
-- Toggle floating for the focused window (two keys for the same action).
bind(mainMod .. " + SHIFT + F", hl.dsp.window.float({ action = "toggle" }))
bind(mainMod .. " + Insert",    hl.dsp.window.float({ action = "toggle" }))
-- Pseudo-tile (useful with dwindle).
bind(mainMod .. " + P", hl.dsp.window.pseudo())

-- --- Resize submap (modal resize mode) ---
-- Enter with SUPER+Shift+R, then use h/j/k/l or arrows to resize; Esc/Enter
-- exits.
bind(mainMod .. " + SHIFT + R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    hl.bind("H", hl.dsp.window.resize({ x = -40, y = 0,   relative = true }), { repeating = true })
    hl.bind("L", hl.dsp.window.resize({ x = 40,  y = 0,   relative = true }), { repeating = true })
    hl.bind("K", hl.dsp.window.resize({ x = 0,   y = -40, relative = true }), { repeating = true })
    hl.bind("J", hl.dsp.window.resize({ x = 0,   y = 40,  relative = true }), { repeating = true })
    hl.bind("left",  hl.dsp.window.resize({ x = -40, y = 0,   relative = true }), { repeating = true })
    hl.bind("right", hl.dsp.window.resize({ x = 40,  y = 0,   relative = true }), { repeating = true })
    hl.bind("up",    hl.dsp.window.resize({ x = 0,   y = -40, relative = true }), { repeating = true })
    hl.bind("down",  hl.dsp.window.resize({ x = 0,   y = 40,  relative = true }), { repeating = true })
    hl.bind("escape", hl.dsp.submap("reset"))
    hl.bind("Return", hl.dsp.submap("reset"))
end)

-- --- Workspaces (virtual desktops 1-10) ---
-- SUPER+N switches; SUPER+Shift+N moves the focused window WITHOUT
-- following it (old movetoworkspacesilent), so follow = false.
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    bind(mainMod .. " + " .. key,              hl.dsp.focus({ workspace = i }))
    bind(mainMod .. " + SHIFT + " .. key,      hl.dsp.window.move({ workspace = i, follow = false }))
end

-- --- Mouse: drag to move / resize ---
-- SUPER + left mouse drags to move, SUPER + right mouse drags to resize.
bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- --- Media / brightness keys (laptop friendly) ---
-- locked = work behind the lock screen (old bindl/bindel).
bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl set 5%+"), { locked = true, repeating = true })
bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true, repeating = true })
-- Playback keys (your xbindkeysrc binds XF86AudioPlay). playerctl talks to
-- any MPRIS player (browsers, music apps).
bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"), { locked = true })
bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"), { locked = true })
-- Calculator key: NOT locked, so it doesn't launch a GUI app behind the
-- lock screen.
bind("XF86Calculator", hl.dsp.exec_cmd("gnome-calculator"))

-- --- Screenshots (your xbindkeysrc binds Print) ---
-- Print = whole screen to the clipboard; SUPER+Print / Shift+Print = select
-- a region to the clipboard. Uses grim + slurp + wl-copy.
bind("Print", hl.dsp.exec_cmd('grim - | wl-copy --type image/png'))
bind(mainMod .. " + Print", hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy --type image/png'))
bind("SHIFT + Print",       hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy --type image/png'))

-- --- Laptop lid ---
-- On close: disable the internal panel; the helper suspends ONLY when no
-- external display is connected (so a docked laptop with the lid shut keeps
-- running on the external screen). On open: re-enable the internal panel.
-- For this to be the sole lid handler, setup-hypr installs a logind drop-in
-- setting HandleLidSwitch=ignore (see the scripts repo / README).
bind("switch:on:Lid Switch",  hl.dsp.exec_cmd("~/.config/hypr/scripts/lid.sh close"), { locked = true })
bind("switch:off:Lid Switch", hl.dsp.exec_cmd("~/.config/hypr/scripts/lid.sh open"),  { locked = true })

--------------------------------------------------------------------------------
-- WINDOW RULES
--------------------------------------------------------------------------------
-- Float common transient dialogs so they don't disrupt the tiling.
hl.window_rule({ name = "float-pavucontrol", match = { class = "^(pavucontrol)$" },          float = true })
hl.window_rule({ name = "float-nm-editor",   match = { class = "^(nm-connection-editor)$" }, float = true })
hl.window_rule({ name = "float-open-file",   match = { title = "^(Open File)$" },            float = true })
hl.window_rule({ name = "float-save-file",   match = { title = "^(Save File)$" },            float = true })

--------------------------------------------------------------------------------
-- PER-MACHINE OVERRIDES
--------------------------------------------------------------------------------
-- ~/.config/hypr/hyprland-local.lua -- the Lua counterpart of
-- hyprland.conf.local (same idea as .shrc.local and sway's config.local).
-- Required LAST so its settings (hl.config values, monitor rules) override
-- the shared defaults above; the file itself is machine-local and never
-- committed. setup-hypr seeds it from hyprland-local.lua.template (see that
-- file for what belongs here: pinned monitor rules, the unbound SUPER+D/S
-- launchers, device tweaks, and how to rebind a shared key via hyprbinds).
-- pcall makes the file optional: unlike hyprlang's `source`, a missing
-- require() would otherwise abort this whole file.
pcall(require, "hyprland-local")
