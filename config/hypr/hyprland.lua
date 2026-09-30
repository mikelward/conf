-- Hyprland configuration
-- ~/.config/hypr/hyprland.lua
--
-- A dynamic-tiling Wayland desktop for Hyprland 0.56+, which reads only this
-- Lua file (hyprland.conf is gone). Tiling comes from the quickspace layout
-- when it is installed and from Hyprland's master layout otherwise. The keys,
-- look and focus rules follow the quickspace spec (SPEC.md §6 and §14 in
-- github.com/mikelward/quickspace). See README.md in this directory for the
-- package list and how to start the session.

local home = os.getenv("HOME")

local terminal = "kitty"
local lock = "hyprlock"
-- Wrapper (scripts repo) that sources ~/.env (the canonical user PATH dirs,
-- including ~/scripts.local) and ~/.env.local before exec'ing, so binds that
-- run helper scripts get the login-shell PATH. A display-manager or uwsm
-- session never runs .profile/.shrc, so `browser1` alone wouldn't resolve.
local runenv = "~/scripts/runenv"
local scripts = "~/.config/hypr/scripts"
local mod = "SUPER"

-- The quickspace session (uwsm sets XDG_CURRENT_DESKTOP=quickspace:Hyprland).
-- Its units start the shell, wallpaper and idle daemon, and apps go through
-- `quickspace launch`; a plain Hyprland login keeps doing both itself.
local quickspace_session = (":" .. (os.getenv("XDG_CURRENT_DESKTOP") or "") .. ":"):find(":quickspace:", 1, true) ~= nil

-- Hyprland shows its own overlay; used for problems found while loading.
local function notify_error(text)
    hl.notification.create({ text = text, duration = 15000, icon = "error" })
end

-- Runs a Hyprland query from a key binding. A query that fails, say while a
-- monitor is going away, is reported and returns nil, so it's never mistaken
-- for the normal "nothing there" answer without a word.
local function query(what, fn)
    local ok, result = pcall(fn)
    if not ok then
        notify_error(what .. ": " .. tostring(result))
        return nil
    end
    return result
end

-- Reads one of the optional files below (the layout, the lid state, the local
-- override) whole, up to max bytes. Returns its text, or nil when it doesn't
-- exist, which is normal for all of them. Any other failure is reported and
-- also returns nil, so an unreadable file is never mistaken for an absent one.
local function read_optional(path, what, max)
    local f, err, code = io.open(path, "r")
    if not f then
        if code ~= 2 then -- ENOENT
            notify_error(what .. ": couldn't open " .. path .. ": " .. tostring(err))
        end
        return nil
    end
    local text, read_err = f:read(max + 1)
    local closed, close_err = f:close()
    if text == nil and read_err then
        notify_error(what .. ": couldn't read " .. path .. ": " .. tostring(read_err))
        return nil
    end
    if not closed then
        notify_error(what .. ": couldn't close " .. path .. ": " .. tostring(close_err))
        return nil
    end
    text = text or "" -- an empty file reads as nil with no error
    if #text > max then
        notify_error(what .. ": " .. path .. " is larger than " .. max .. " bytes; ignoring it")
        return nil
    end
    return text
end

--------------------------------------------------------------------------------
-- MONITORS
--------------------------------------------------------------------------------
-- Every output at its preferred mode, placed left to right, so no monitor
-- names are needed. Pin a specific arrangement in hyprland.local.lua.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

--------------------------------------------------------------------------------
-- AUTOSTART
--------------------------------------------------------------------------------
-- In the quickspace session this starts nothing but `uwsm finalize` (quickspace
-- SPEC.md §5.4): quickspace.service runs the bar, notifications, wallpaper,
-- polkit agent and input setup, and hypridle.service the idle daemon, each
-- once and only in that session. The list below is for a plain Hyprland login.
hl.on("hyprland.start", function()
    if quickspace_session then
        hl.exec_cmd("uwsm finalize")
        return
    end
    hl.exec_cmd("swww-daemon")
    hl.exec_cmd("sleep 1 && swww img ~/.config/hypr/wallpaper.jpg")
    hl.exec_cmd("hypridle")
    -- Mice get the right button primary; touchpads keep the default.
    hl.exec_cmd(scripts .. "/apply-input.sh")
    -- Applies the light/dark theme and launches waybar and swaync with it.
    hl.exec_cmd(scripts .. "/theme-daemon.sh")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")
end)

--------------------------------------------------------------------------------
-- ENVIRONMENT
--------------------------------------------------------------------------------
-- For a plain `Hyprland` session. Under uwsm the same variables come from
-- config/uwsm/{env,env-hyprland}, so systemd user services see them too;
-- keep the two in sync. PATH is deliberately not set: binds that need the
-- user's PATH go through runenv.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("NIXOS_OZONE_WL", "1")
-- Classic GTK scrollbars, matching xsessionrc.
hl.env("GTK_OVERLAY_SCROLLING", "0")

--------------------------------------------------------------------------------
-- LAYOUT
--------------------------------------------------------------------------------
-- The quickspace layout (tile, three-column, two columns + stack, monocle, per
-- workspace) is installed by `make install` in the quickspace repo. Without
-- it this falls back to Hyprland's master layout, the same shape as tile.
local qs
do
    local path = home .. "/.config/hypr/quickspace/layout.lua"
    -- Missing is fine: the layout just isn't installed here.
    local text = read_optional(path, "quickspace layout", 1024 * 1024)
    if text then
        local ok, result = pcall(function()
            -- "@" names the chunk by its path, as dofile does, so the layout
            -- can still find geometry.lua beside it.
            local m = assert(load(text, "@" .. path))()
            -- Check every helper the binds below use, so an older or
            -- partial layout falls back here rather than failing a bind.
            if type(m) ~= "table" then
                error("layout.lua returned " .. type(m) .. ", not a module")
            end
            for _, name in ipairs({ "setup", "cycle_next", "cycle_prev", "toggle_monocle",
                                    "grow", "shrink", "add_master", "remove_master",
                                    "swap_with_master", "focus", "move" }) do
                if type(m[name]) ~= "function" then
                    error("layout.lua has no " .. name .. "()")
                end
            end
            m.setup({})
            return m
        end)
        if ok then
            qs = result
        else
            notify_error("quickspace layout failed to load, using master: " .. tostring(result))
        end
    end
end

-- The quickspace focus guard (SPEC.md §14): nothing steals the keyboard.
-- It's installed beside the layout; without it, Hyprland's own focus rules
-- apply (misc:focus_on_activate is off below either way).
do
    local path = home .. "/.config/hypr/quickspace/focus.lua"
    local text = read_optional(path, "quickspace focus guard", 1024 * 1024)
    if text then
        local ok, err = pcall(function()
            local m = assert(load(text, "@" .. path))()
            if type(m) ~= "table" or type(m.setup) ~= "function" then
                error("focus.lua has no setup()")
            end
            m.setup({})
        end)
        if not ok then
            notify_error("quickspace focus guard failed to load: " .. tostring(err))
        end
    end
end

-- Each layout action as a bind target, from quickspace or from master.
local act
if qs then
    act = {
        next_layout = qs.cycle_next,
        prev_layout = qs.cycle_prev,
        monocle = qs.toggle_monocle,
        grow = qs.grow,
        shrink = qs.shrink,
        add_master = qs.add_master,
        remove_master = qs.remove_master,
        swap_master = qs.swap_with_master,
        focus_next = function() qs.focus(1) end,
        focus_prev = function() qs.focus(-1) end,
        move_next = function() qs.move(1) end,
        move_prev = function() qs.move(-1) end,
    }
else
    act = {
        -- Master's centered orientation is the three-column shape.
        next_layout = hl.dsp.layout("orientationnext"),
        prev_layout = hl.dsp.layout("orientationprev"),
        monocle = hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }),
        grow = hl.dsp.layout("mfact +0.025"),
        shrink = hl.dsp.layout("mfact -0.025"),
        add_master = hl.dsp.layout("addmaster"),
        remove_master = hl.dsp.layout("removemaster"),
        swap_master = hl.dsp.layout("swapwithmaster master"),
        focus_next = hl.dsp.layout("cyclenext"),
        focus_prev = hl.dsp.layout("cycleprev"),
        move_next = hl.dsp.layout("swapnext"),
        move_prev = hl.dsp.layout("swapprev"),
    }
end

hl.config({
    general = {
        layout = qs and "lua:quickspace" or "master",
        -- The focus cue is the dim alone: no gaps, no borders.
        gaps_in = 0,
        gaps_out = 0,
        border_size = 0,
        resize_on_border = true,
        allow_tearing = false,
    },
    -- Master is the fallback layout. New windows join the end of the stack.
    master = {
        new_status = "slave",
        new_on_top = false,
        mfact = 0.55,
        orientation = "left",
        allow_small_split = false,
    },
})

--------------------------------------------------------------------------------
-- LOOK
--------------------------------------------------------------------------------
hl.config({
    decoration = {
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
            color = "rgba(00000044)",
        },
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        -- The same strength as the KDE setup's dim-inactive effect. If a
        -- dark app next to a dark app is hard to tell apart, try 0.25.
        dim_inactive = true,
        dim_strength = 0.15,
        dim_special = 0.2,
    },
    animations = { enabled = true },
})

hl.curve("ease", { type = "bezier", points = { { 0.25, 0.1 }, { 0.25, 1.0 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 3, bezier = "ease" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "ease", style = "popin 80%" })
hl.animation({ leaf = "border", enabled = true, speed = 6, bezier = "ease" })
hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "ease" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "ease" })

hl.config({
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        -- Nothing steals focus: an app asking for it is marked urgent
        -- instead (Super+U goes there).
        focus_on_activate = false,
        -- uwsm sets XDG_CURRENT_DESKTOP to quickspace:Hyprland on purpose.
        disable_xdg_env_checks = true,
    },
    -- Focus never drags the pointer along with it.
    cursor = { no_warps = true },
})

--------------------------------------------------------------------------------
-- INPUT
--------------------------------------------------------------------------------
hl.config({
    input = {
        kb_layout = "us",
        kb_variant = "dvorak",
        -- Caps Lock is Compose, matching `setup`'s XKBOPTIONS.
        kb_options = "compose:caps",

        -- Focus follows the mouse, but only when it crosses into a window,
        -- and closing a window focuses the one under the pointer.
        follow_mouse = 1,
        mouse_refocus = false,
        focus_on_close = 1,

        sensitivity = 0,
        accel_profile = "flat",
        -- Right-handed by default, which trackpads want; apply-input.sh
        -- flips mice to the right button primary.
        left_handed = false,

        touchpad = {
            natural_scroll = true,
            tap_to_click = true,
            disable_while_typing = true,
            scroll_factor = 1.0,
        },
    },
})

-- A 3-finger horizontal swipe changes workspace.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

--------------------------------------------------------------------------------
-- KEYS (quickspace SPEC.md §6.6)
--------------------------------------------------------------------------------
local function key(k)
    return mod .. " + " .. k
end

local function exec(cmd)
    return hl.dsp.exec_cmd(cmd)
end

-- Starts an app. In the quickspace session it goes through `quickspace
-- launch`, which waits for the shell, grants the app's first window focus
-- (the focus guard opens every other window unfocused) and runs it in
-- app-graphical.slice. id names the app for that grant; the default, "*",
-- is the first window of any app, for wrapper scripts whose window class
-- isn't known here.
local function app(cmd, id)
    if not quickspace_session then
        return exec(cmd)
    end
    return exec("quickspace launch --app '" .. (id or "*") .. "' -- " .. cmd)
end

-- Applications. The helper scripts live in the scripts repo, on the PATH
-- runenv provides. Super+D and Super+S are left for hyprland.local.lua.
hl.bind(key("T"), app(terminal, terminal))
hl.bind(key("W"), app(runenv .. " terminal_on_workstation"))
hl.bind(key("G"), app(runenv .. " browser1"))
hl.bind(key("SHIFT + G"), app(runenv .. " browser3"))
hl.bind(key("F"), app(runenv .. " browser2"))
hl.bind(key("B"), exec(runenv .. " bluetooth-connect"))
hl.bind(key("SHIFT + B"), exec(runenv .. " pulseprofile.py"))
hl.bind(key("C"), app(runenv .. " google-calendar"))
hl.bind(key("SHIFT + C"), app(runenv .. " google-chat"))
hl.bind(key("H"), app(runenv .. " home"))
hl.bind(key("I"), app(runenv .. " irc"))
hl.bind(key("M"), app(runenv .. " google-meet"))
hl.bind(key("N"), app(runenv .. " notepad"))
hl.bind(key("R"), app(runenv .. " remote-desktop"))
hl.bind(key("Y"), app(runenv .. " youtube-music"))
hl.bind(key("E"), app(terminal .. " -e yazi", terminal))
-- Through runenv so the launcher's app list sees the user's scripts.
hl.bind(key("Space"), exec(runenv .. " " .. scripts .. "/launch-fuzzel.sh"))
hl.bind(key("SHIFT + N"), exec("swaync-client -t -sw"))

-- Session.
hl.bind(key("BackSpace"), hl.dsp.window.close())
hl.bind(key("L"), exec(lock))
hl.bind(key("SHIFT + E"), hl.dsp.exit())

-- Layouts.
hl.bind(key("period"), act.next_layout)
hl.bind(key("comma"), act.prev_layout)
hl.bind(key("grave"), act.monocle)
hl.bind(key("backslash"), act.grow, { repeating = true })
hl.bind(key("slash"), act.shrink, { repeating = true })
hl.bind(key("equal"), act.add_master)
hl.bind(key("minus"), act.remove_master)
hl.bind(key("Return"), act.swap_master)
hl.bind(key("J"), act.focus_next)
hl.bind(key("K"), act.focus_prev)
hl.bind(key("SHIFT + J"), act.move_next)
hl.bind(key("SHIFT + K"), act.move_prev)

-- One window big: maximize keeps the bar, fullscreen covers it, and
-- Super+Down undoes either. Unset is a no-op for a mode that isn't on.
hl.bind(key("Up"), hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(key("SHIFT + Up"), hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(key("Down"), function()
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "unset" }))
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset" }))
end)

-- Floating.
hl.bind(key("SHIFT + F"), hl.dsp.window.float({ action = "toggle" }))
hl.bind(key("Insert"), hl.dsp.window.float({ action = "toggle" }))
hl.bind(key("mouse:272"), hl.dsp.window.drag(), { mouse = true })
hl.bind(key("mouse:273"), hl.dsp.window.resize(), { mouse = true })
-- There are no title bars to double-click, so Super+middle-click toggles
-- maximize, and a second click puts the window back in its tile. It acts on
-- the focused window, which focus-follows-mouse makes the one under the
-- pointer.
hl.bind(key("mouse:274"), hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))

-- Resize mode, for floating windows: h/j/k/l or arrows, Esc or Return to leave.
hl.bind(key("SHIFT + R"), hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    local steps = {
        H = { -40, 0 }, L = { 40, 0 }, K = { 0, -40 }, J = { 0, 40 },
        left = { -40, 0 }, right = { 40, 0 }, up = { 0, -40 }, down = { 0, 40 },
    }
    for k, d in pairs(steps) do
        hl.bind(k, hl.dsp.window.resize({ x = d[1], y = d[2], relative = true }), { repeating = true })
    end
    hl.bind("escape", hl.dsp.submap("reset"))
    hl.bind("Return", hl.dsp.submap("reset"))
end)

-- Workspaces 1-9, one shared pool across monitors.
for i = 1, 9 do
    hl.bind(key(tostring(i)), hl.dsp.focus({ workspace = i }))
    hl.bind(key("SHIFT + " .. i), hl.dsp.window.move({ workspace = i, follow = false }))
end

-- Previous / next workspace, as in KDE and on the Mac, stopping at 1 and 9.
local function step_workspace(delta, carry_window)
    return function()
        local ws = query("couldn't read the active workspace", hl.get_active_workspace)
        local id = ws and ws.id
        -- Special workspaces have negative ids; there's no "next" from one.
        if type(id) ~= "number" or id < 1 then
            return
        end
        local target = math.max(1, math.min(9, id + delta))
        if target == id then
            return
        end
        if carry_window then
            hl.dispatch(hl.dsp.window.move({ workspace = target, follow = true }))
        else
            hl.dispatch(hl.dsp.focus({ workspace = target }))
        end
    end
end
hl.bind(key("Left"), step_workspace(-1, false))
hl.bind(key("Right"), step_workspace(1, false))
hl.bind(key("SHIFT + Left"), step_workspace(-1, true))
hl.bind(key("SHIFT + Right"), step_workspace(1, true))

-- The way to a window that wanted focus and didn't get it (§14). Lua can't
-- mark a window urgent, so quickspace's focus guard keeps the ones it held
-- back; otherwise it's Hyprland's urgent window, or the last one.
hl.bind(key("U"), function()
    local guard = rawget(_G, "quickspace_focus")
    if guard and guard.focus_attention then
        local ok, went = pcall(guard.focus_attention)
        if not ok then
            notify_error("Super+U: the focus guard failed: " .. tostring(went))
        elseif went then
            return
        end
    end
    hl.dispatch(hl.dsp.focus({ urgent_or_last = true }))
end)

-- Screenshots to the clipboard, with an explicit PNG type so paste works
-- everywhere. Alt+Print takes the focused window.
local copy_png = " - | wl-copy --type image/png"
hl.bind("Print", exec("grim" .. copy_png))
hl.bind("SHIFT + Print", exec("grim -g \"$(slurp)\"" .. copy_png))
hl.bind(key("Print"), exec("grim -g \"$(slurp)\"" .. copy_png))
hl.bind("ALT + Print", function()
    local geometry = query("couldn't read the focused window", function()
        local w = hl.get_active_window()
        return w and string.format("%d,%d %dx%d", w.at.x, w.at.y, w.size.x, w.size.y)
    end)
    if not geometry then
        return
    end
    hl.exec_cmd("grim -g '" .. geometry .. "'" .. copy_png)
end)

-- Volume, microphone, brightness and playback keys. These work on the lock
-- screen too; the calculator doesn't, since it opens a window.
local locked = { locked = true }
local locked_repeating = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume", exec("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), locked_repeating)
hl.bind("XF86AudioLowerVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), locked_repeating)
hl.bind("XF86AudioMute", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), locked)
hl.bind("XF86AudioMicMute", exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), locked)
hl.bind(key("SHIFT + M"), exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), locked)
hl.bind("XF86MonBrightnessUp", exec("brightnessctl set 5%+"), locked_repeating)
hl.bind("XF86MonBrightnessDown", exec("brightnessctl set 5%-"), locked_repeating)
hl.bind("XF86AudioPlay", exec("playerctl play-pause"), locked)
hl.bind("XF86AudioPause", exec("playerctl play-pause"), locked)
hl.bind("XF86AudioNext", exec("playerctl next"), locked)
hl.bind("XF86AudioPrev", exec("playerctl previous"), locked)
hl.bind("XF86Calculator", app("gnome-calculator", "org.gnome.Calculator"))

--------------------------------------------------------------------------------
-- LAPTOP LID
--------------------------------------------------------------------------------
-- logind owns suspend (HandleLidSwitch=suspend, HandleLidSwitchDocked=ignore),
-- so this only handles the docked case: closing the lid with an external
-- display turns the panel off, and Hyprland moves its workspaces over.
-- Opening it turns the panel back on and returns those workspaces.
local lid = { panel = nil, workspaces = {} }

-- A config reload starts a fresh Lua state and clears every monitor rule, so
-- a closed lid is also kept in a file in this Hyprland instance's runtime
-- directory: a reload finds it, a new session doesn't.
local lid_file
do
    local dir = os.getenv("XDG_RUNTIME_DIR")
    local sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
    if dir and dir ~= "" and sig and sig ~= "" then
        lid_file = dir .. "/hypr/" .. sig .. "/quickspace-lid"
    end
end

local function save_lid()
    if not lid_file then
        return
    end
    local lines = { lid.panel }
    for _, id in ipairs(lid.workspaces) do
        table.insert(lines, tostring(id))
    end
    -- Written beside the real file and renamed over it, so a reload only ever
    -- reads a complete state: a failed write leaves the temporary file, which
    -- nothing reads, never a truncated quickspace-lid.
    local tmp = lid_file .. ".tmp"
    local f, err = io.open(tmp, "w")
    local ok = f ~= nil
    if f then
        ok, err = f:write(table.concat(lines, "\n"), "\n")
        -- close() flushes, so a full disk often shows up only here.
        local closed, close_err = f:close()
        if ok and not closed then
            ok, err = false, close_err
        end
    end
    if ok then
        ok, err = os.rename(tmp, lid_file)
    end
    if not ok then
        -- Best effort: the temporary file is never read, so leaving it
        -- behind costs nothing but the space.
        os.remove(tmp)
        -- Not fatal: only a reload before the lid opens loses the state.
        notify_error("lid: couldn't save the closed-lid state: " .. tostring(err))
    end
end

local function forget_lid()
    lid.panel = nil
    lid.workspaces = {}
    if lid_file then
        local ok, err, code = os.remove(lid_file)
        -- ENOENT is the usual case: the lid wasn't closed while docked.
        if not ok and code ~= 2 then
            -- A stale file would turn the panel off again on the next reload.
            notify_error("lid: couldn't clear the closed-lid state, so a config reload will turn the panel off; delete "
                .. lid_file .. ": " .. tostring(err))
        end
    end
end

-- The internal panel: $HYPR_INTERNAL_OUTPUT, or the first eDP/LVDS/DSI output.
local function internal_panel(monitors)
    local override = os.getenv("HYPR_INTERNAL_OUTPUT")
    if override and override ~= "" then
        return override
    end
    for _, m in ipairs(monitors) do
        local name = m.name or ""
        if name:match("^eDP") or name:match("^LVDS") or name:match("^DSI") then
            return name
        end
    end
    return nil
end

local function lid_close()
    local monitors = hl.get_monitors()
    local panel = internal_panel(monitors)
    if not panel then
        return
    end
    local external = false
    for _, m in ipairs(monitors) do
        if m.name ~= panel then
            external = true
        end
    end
    -- Undocked: leave the panel alone; logind suspends and hypridle locks.
    if not external then
        return
    end
    lid.panel = panel
    lid.workspaces = {}
    for _, ws in ipairs(hl.get_workspaces()) do
        local m = ws.monitor
        if m and m.name == panel and type(ws.id) == "number" and ws.id > 0 then
            table.insert(lid.workspaces, ws.id)
        end
    end
    save_lid()
    hl.monitor({ output = panel, disabled = true })
end

local function lid_open()
    local panel = lid.panel
    if not panel then
        -- No record of a close (it predates this config, or the state file
        -- couldn't be written): turn on an internal panel that is off.
        local all = hl.get_monitors({ all = true })
        local candidate = internal_panel(all)
        for _, m in ipairs(all) do
            if m.name == candidate and m.enabled == false then
                panel = candidate
                lid.panel = panel
            end
        end
        if not panel then
            return
        end
    end
    -- The rule applies on Hyprland's next refresh; the workspaces go back
    -- once the panel shows up as a monitor again (monitor.added below).
    hl.monitor({ output = panel, mode = "preferred", position = "auto", scale = "auto" })
end

-- After a reload with the lid still closed, keep the panel off. The file is
-- one output name, then one workspace id per line; anything else is dropped.
if lid_file then
    local text = read_optional(lid_file, "lid", 4096)
    if text then
        local lines = {}
        for line in text:gmatch("[^\n]+") do
            table.insert(lines, line)
        end
        local panel = lines[1]
        local valid = panel ~= nil and panel:match("^[%w%-_.]+$") ~= nil
        local workspaces = {}
        for i = 2, #lines do
            local id = lines[i]:match("^%d+$") and tonumber(lines[i])
            if not id then
                valid = false
            end
            table.insert(workspaces, id)
        end
        if valid then
            lid.panel = panel
            lid.workspaces = workspaces
            hl.monitor({ output = panel, disabled = true })
        else
            notify_error("lid: ignoring a malformed closed-lid state in " .. lid_file)
            forget_lid()
        end
    end
end

hl.on("monitor.added", function(m)
    if not lid.panel or m.name ~= lid.panel then
        return
    end
    for _, id in ipairs(lid.workspaces) do
        hl.dispatch(hl.dsp.workspace.move({ workspace = id, monitor = lid.panel }))
    end
    forget_lid()
end)

hl.bind("switch:on:Lid Switch", lid_close, locked)
hl.bind("switch:off:Lid Switch", lid_open, locked)

--------------------------------------------------------------------------------
-- WINDOW RULES (quickspace SPEC.md §6.2 and §6.4)
--------------------------------------------------------------------------------
-- Dialogs float, centered. Hyprland floats most on its own (parented, fixed
-- size); these catch the rest.
local dialogs = {
    { name = "float-modal", match = { modal = true } },
    { name = "float-pavucontrol", match = { class = "^(org\\.pulseaudio\\.)?pavucontrol$" } },
    { name = "float-nm-connection-editor", match = { class = "^nm-connection-editor$" } },
    { name = "float-blueman-manager", match = { class = "^blueman-manager$" } },
    { name = "float-portal-file-chooser", match = { class = "^xdg-desktop-portal-(gtk|gnome|kde)$" } },
    { name = "float-file-dialog-title", match = { title = "^(Open File|Open Files|Save File|Save As)(…|\\.\\.\\.)?$" } },
}
for _, rule in ipairs(dialogs) do
    rule.float = true
    rule.center = true
    hl.window_rule(rule)
end

-- Picture-in-picture floats, pinned on every workspace, bottom right.
hl.window_rule({
    name = "pip",
    match = { title = "^Picture[- ]in[- ][Pp]icture$" },
    float = true,
    pin = true,
    size = "monitor_w*0.25 monitor_h*0.25",
    move = "monitor_w-window_w-16 monitor_h-window_h-16",
    no_dim = true,
})

-- No dim where there's nothing to tell apart (a lone window), or where a
-- dimmed window would look broken (video, a call on the other monitor).
hl.window_rule({ name = "no-dim-lone-window", match = { workspace = "w[tv1]" }, no_dim = true })
hl.window_rule({ name = "no-dim-video", match = { content = "video" }, no_dim = true })

--------------------------------------------------------------------------------
-- PER-MACHINE OVERRIDES
--------------------------------------------------------------------------------
-- ~/.config/hypr/hyprland.local.lua, the same name plus .local like
-- .shrc.local, is loaded last so its settings win. It is machine-local and
-- never committed; hyprland.local.lua.template shows what belongs there.
-- Binds add rather than replace, so rebinding a key needs hl.unbind first.
do
    local path = home .. "/.config/hypr/hyprland.local.lua"
    local text = read_optional(path, "hyprland.local.lua", 1024 * 1024)
    if text then
        -- Like Hyprland's own config, it applies as it runs: a syntax error
        -- applies none of it, and a runtime error stops it after the calls
        -- before it have applied. The notification says which.
        local chunk, err = load(text, "@" .. path)
        if not chunk then
            notify_error("hyprland.local.lua (none of it applied): " .. tostring(err))
        else
            local ok, run_err = pcall(chunk)
            if not ok then
                notify_error("hyprland.local.lua stopped (the calls before this applied): " .. tostring(run_err))
            end
        end
    end
end
