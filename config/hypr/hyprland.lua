-- Hyprland configuration
-- ~/.config/hypr/hyprland.lua
--
-- tide's own Hyprland config (github.com/mikelward/tide, SPEC.md §6.8),
-- which `make install` there puts in ~/.config/hypr/tide, with these
-- preferences over its defaults. Its keys, rules, look and the settings
-- tide's shell writes are all tide's; hyprland.local.lua still loads last.
-- See README.md in this directory for how to start the session.

local home = os.getenv("HOME")

-- Wrapper (scripts repo) that sources ~/.env (the canonical user PATH dirs,
-- including ~/scripts.local) and ~/.env.local before exec'ing, so binds that
-- run helper scripts get the login-shell PATH. A display-manager or uwsm
-- session never runs .profile/.shrc, so `browser1` alone wouldn't resolve.
local runenv = "~/scripts/runenv"
local scripts = "~/.config/hypr/scripts"
local terminal = "kitty"

-- Where tide's is; TIDE_HYPRLAND_LUA names another, for tests.
local tide_config = os.getenv("TIDE_HYPRLAND_LUA") or (home .. "/.config/hypr/tide/hyprland.lua")

-- Classic GTK scrollbars, matching xsessionrc.
hl.env("GTK_OVERLAY_SCROLLING", "0")

local chunk, err = loadfile(tide_config)
if not chunk then
    -- Without tide there are no keys at all, so enough to get a terminal
    -- and out, and a notification saying why.
    hl.notification.create({
        text = "tide's Hyprland config didn't load (" .. tostring(err) .. "); run `make install` in tide. Super+T is a terminal, Super+Shift+E quits.",
        duration = 0,
        icon = "error",
    })
    hl.bind("SUPER + T", hl.dsp.exec_cmd(terminal))
    hl.bind("SUPER + SHIFT + E", hl.dsp.exit())
    return
end

chunk({
    terminal = terminal,
    terminal_app = terminal,
    files = terminal .. " -e yazi",
    run = runenv,
    -- Caps Lock is Compose, matching `setup`'s XKBOPTIONS. Menu is a
    -- second Super, as xmodmaprc made it under X11.
    input = { kb_variant = "dvorak", kb_options = "compose:caps,altwin:menu_win" },
    -- The right button primary, with a faster wheel; touchpads keep the
    -- default. HYPR_MOUSE_SCROLL_FACTOR in ~/.env.local, which runenv
    -- brings in, sets the wheel instead.
    mouse = { left_handed = true, scroll_factor = 3 },
    -- Outside tide's shell, fuzzel, through runenv so its app list sees the
    -- user's scripts.
    launcher = runenv .. " " .. scripts .. "/launch-fuzzel.sh",
    -- The scripts repo's: the screen, the window (--window) or a region
    -- (--region), to the clipboard, reporting its own failures.
    screenshot = runenv .. " screenshot",
    -- A plain Hyprland login, beside what tide's starts: the wallpaper, the
    -- light/dark theme (which runs waybar and swaync) and the applets.
    autostart = {
        "swww-daemon",
        "sleep 1 && swww img ~/.config/hypr/wallpaper.jpg",
        scripts .. "/theme-daemon.sh",
        "nm-applet --indicator",
        "blueman-applet",
    },
    -- The helper scripts live in the scripts repo, on the PATH runenv
    -- provides.
    apps = function(t)
        local function app(name, keys, cmd, what)
            t.bind(name, t.key(keys), t.app(runenv .. " " .. cmd), t.does(what))
        end
        app("terminal_on_workstation", "W", "terminal_on_workstation", "Terminal on the workstation")
        app("browser", "G", "browser1", "Browser")
        app("browser_third", "SHIFT + G", "browser3", "Browser, third profile")
        app("browser_second", "F", "browser2", "Browser, second profile")
        t.bind("headphones", t.key("B"), t.exec(runenv .. " bluetooth-connect"), t.does("Connect the headphones"))
        t.bind("audio_profile", t.key("SHIFT + B"), t.exec(runenv .. " pulseprofile.py"), t.does("Next audio profile"))
        app("chat", "C", "google-chat", "Google Chat")
        app("calendar", "SHIFT + C", "google-calendar", "Google Calendar")
        app("home_folder", "H", "home", "Home folder")
        app("irc", "I", "irc", "IRC")
        app("meet", "M", "google-meet", "Google Meet")
        app("notepad", "N", "notepad", "Notepad")
        app("remote_desktop", "R", "remote-desktop", "Remote desktop")
        app("music", "Y", "youtube-music", "YouTube Music")
    end,
})
