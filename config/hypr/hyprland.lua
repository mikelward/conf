-- Hyprland configuration
-- ~/.config/hypr/hyprland.lua
--
-- tide's Hyprland config (github.com/mikelward/tide), with my changes:
-- tide's `make install` puts its config in ~/.config/hypr/tide/, and this
-- loads it, changes what I prefer, and sets it up. tide has the session,
-- its layout, keys, look, lid and window rules (its SPEC.md §6 and §14,
-- and README.md in its hypr/tide). What's here is mine: the app keys, the
-- keyboard and mice, the fallbacks for a session without tide's shell, and
-- a plain Hyprland login's autostart. See README.md in this directory for
-- the package list and how to start the session.

local home = os.getenv("HOME")

local terminal = "kitty"
-- Wrapper (scripts repo) that sources ~/.env (the canonical user PATH dirs,
-- including ~/scripts.local) and ~/.env.local before exec'ing, so binds that
-- run helper scripts get the login-shell PATH. A display-manager or uwsm
-- session never runs .profile/.shrc, so `browser1` alone wouldn't resolve.
local runenv = "~/scripts/runenv"
local scripts = "~/.config/hypr/scripts"

local tide_path = home .. "/.config/hypr/tide/config.lua"
do
    local f = io.open(tide_path)
    if not f then
        error("tide's Hyprland config isn't installed (no " .. tide_path .. "): run make install in tide", 0)
    end
    f:close()
end
local tide = dofile(tide_path)
local key, exec, app, does = tide.key, tide.exec, tide.app, tide.does

--------------------------------------------------------------------------------
-- AUTOSTART
--------------------------------------------------------------------------------
-- tide starts the tide session's own (uwsm finalize). This list is for a
-- plain Hyprland login.
hl.on("hyprland.start", function()
    if tide.session then
        return
    end
    hl.exec_cmd("swww-daemon")
    hl.exec_cmd("sleep 1 && swww img ~/.config/hypr/wallpaper.jpg")
    hl.exec_cmd("hypridle")
    -- Mice get the right button primary; touchpads keep the default. runenv
    -- brings in ~/.env.local, where HYPR_MOUSE_SCROLL_FACTOR can be set.
    hl.exec_cmd(runenv .. " " .. scripts .. "/apply-input.sh")
    -- And again for a device plugged in later, such as through a KVM switch.
    hl.exec_cmd(runenv .. " " .. scripts .. "/watch-input.sh")
    -- Applies the light/dark theme and launches waybar and swaync with it.
    hl.exec_cmd(scripts .. "/theme-daemon.sh")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")
end)

-- tide runs this after each config load and each change to its input
-- settings; runenv brings in ~/.env.local's HYPR_MOUSE_SCROLL_FACTOR.
tide.input_setup = runenv .. " " .. scripts .. "/apply-input.sh"

--------------------------------------------------------------------------------
-- ENVIRONMENT
--------------------------------------------------------------------------------
-- For a plain `Hyprland` session, beside tide's. Under uwsm the same
-- variables come from config/uwsm/{env,env-hyprland}, so systemd user
-- services see them too; keep the two in sync. PATH is deliberately not
-- set: binds that need the user's PATH go through runenv.
-- Classic GTK scrollbars, matching xsessionrc.
hl.env("GTK_OVERLAY_SCROLLING", "0")

--------------------------------------------------------------------------------
-- INPUT
--------------------------------------------------------------------------------
-- US Dvorak. Caps Lock is Compose, matching `setup`'s XKBOPTIONS. Menu is a
-- second Super, as xmodmaprc made it under X11. tide's Keyboard settings
-- still apply over these.
tide.input.kb_variant = "dvorak"
tide.input.kb_options = "compose:caps,altwin:menu_win"
-- Mice have the right button primary (apply-input.sh), unless tide's
-- Mouse settings say otherwise.
tide.mouse.left_handed = true

--------------------------------------------------------------------------------
-- KEYS
--------------------------------------------------------------------------------
-- Applications. The helper scripts live in the scripts repo, on the PATH
-- runenv provides. Super+D is left for hyprland.local.lua. Named, so
-- tide's Keyboard shortcuts list them and can give them other keys.
tide.bind("terminal_on_workstation", key("W"), app(runenv .. " terminal_on_workstation"), does("Terminal on the workstation"))
tide.bind("browser", key("G"), app(runenv .. " browser1"), does("Browser"))
tide.bind("browser_third", key("SHIFT + G"), app(runenv .. " browser3"), does("Browser, third profile"))
tide.bind("browser_second", key("F"), app(runenv .. " browser2"), does("Browser, second profile"))
tide.bind("headphones", key("B"), exec(runenv .. " bluetooth-connect"), does("Connect the headphones"))
tide.bind("audio_profile", key("SHIFT + B"), exec(runenv .. " pulseprofile.py"), does("Next audio profile"))
tide.bind("chat", key("C"), app(runenv .. " google-chat"), does("Google Chat"))
tide.bind("calendar", key("SHIFT + C"), app(runenv .. " google-calendar"), does("Google Calendar"))
tide.bind("home_folder", key("H"), app(runenv .. " home"), does("Home folder"))
tide.bind("irc", key("I"), app(runenv .. " irc"), does("IRC"))
tide.bind("meet", key("M"), app(runenv .. " google-meet"), does("Google Meet"))
tide.bind("notepad", key("N"), app(runenv .. " notepad"), does("Notepad"))
tide.bind("remote_desktop", key("R"), app(runenv .. " remote-desktop"), does("Remote desktop"))
tide.bind("music", key("Y"), app(runenv .. " youtube-music"), does("YouTube Music"))
tide.bind("files", key("E"), app(terminal .. " -e yazi", terminal), does("Files"))

-- tide's own keys, with my fallbacks where tide's shell isn't running.
-- The launcher: fuzzel, through runenv so its app list sees my scripts.
tide.bind("launcher", key("Space"), exec("qs -c tide ipc call launcher toggle || " .. runenv .. " " .. scripts .. "/launch-fuzzel.sh"), does("Launcher"))
-- The notification center: swaync's panel, while the shell isn't the
-- notification server.
tide.bind("notifications", key("SHIFT + N"), exec("qs -c tide ipc call notifications toggle || swaync-client -t -sw"), does("Notification center"))
-- Screenshots through the scripts repo's screenshot, on runenv's PATH.
local screenshot = runenv .. " screenshot"
tide.bind("screenshot", "Print", exec(screenshot), does("Screenshot"))
tide.bind("screenshot_window", "ALT + Print", exec(screenshot .. " --window"), does("Screenshot of the window"))
tide.bind("screenshot_region", { "SHIFT + Print", key("Print") }, exec(screenshot .. " --region"), does("Screenshot of a region"))

tide.setup()

--------------------------------------------------------------------------------
-- PER-MACHINE OVERRIDES
--------------------------------------------------------------------------------
-- ~/.config/hypr/hyprland.local.lua, the same name plus .local like
-- .shrc.local, is loaded last so its settings win, over tide's settings
-- too. It is machine-local and never committed;
-- hyprland.local.lua.template shows what belongs there. Binds add rather
-- than replace, so rebinding a key needs hl.unbind first.
tide.override(home .. "/.config/hypr/hyprland.local.lua")
