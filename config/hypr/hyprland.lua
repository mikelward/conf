-- Hyprland configuration
-- ~/.config/hypr/hyprland.lua
--
-- A dynamic-tiling Wayland desktop for Hyprland 0.56+, which reads only this
-- Lua file (hyprland.conf is gone). Tiling comes from the tide layout
-- when it is installed and from Hyprland's master layout otherwise. The keys,
-- look and focus rules follow the tide spec (SPEC.md §6 and §14 in
-- github.com/mikelward/tide). See README.md in this directory for the
-- package list and how to start the session.

local home = os.getenv("HOME")

local terminal = "kitty"
-- Wrapper (scripts repo) that sources ~/.env (the canonical user PATH dirs,
-- including ~/scripts.local) and ~/.env.local before exec'ing, so binds that
-- run helper scripts get the login-shell PATH. A display-manager or uwsm
-- session never runs .profile/.shrc, so `browser1` alone wouldn't resolve.
local runenv = "~/scripts/runenv"
local scripts = "~/.config/hypr/scripts"
local mod = "SUPER"

-- The tide session (uwsm sets XDG_CURRENT_DESKTOP=tide:Hyprland).
-- Its units start the shell, wallpaper and idle daemon, and apps go through
-- `tide launch`; a plain Hyprland login keeps doing both itself.
local tide_session = (":" .. (os.getenv("XDG_CURRENT_DESKTOP") or "") .. ":"):find(":tide:", 1, true) ~= nil

-- The tide session locks with tide-lock (tide SPEC.md §10), and every lock
-- goes through logind: `loginctl lock-session` raises its Lock signal, and
-- hypridle's lock_cmd starts tide-lock.service. A plain Hyprland login keeps
-- hyprlock.
local lock = tide_session and "loginctl lock-session" or "hyprlock"

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
local default_monitor = { output = "", mode = "preferred", position = "auto", scale = "auto" }

local function copy_rule(r, output)
    local out = {}
    for k, v in pairs(r) do
        out[k] = v
    end
    out.output = output or r.output
    return out
end
hl.monitor(copy_rule(default_monitor))

-- tide's Displays settings (tide SPEC.md §16), which tide writes to
-- tide-outputs.lua beside this file as { ["desc:<description>"] = { scale
-- = 1.5, position = "auto-left" } }. Each is a rule for that monitor over
-- the one above, by its description, so it follows the monitor from port
-- to port. It's read as data, with nothing in scope, and an entry or a
-- setting that's wrong is reported and left out.
local TIDE_POSITIONS = { auto = true, ["auto-right"] = true, ["auto-left"] = true, ["auto-up"] = true, ["auto-down"] = true }

local function read_tide_outputs()
    local path = home .. "/.config/hypr/tide-outputs.lua"
    local text = read_optional(path, "tide-outputs.lua", 64 * 1024)
    if not text then
        return {}
    end
    local chunk, err = load(text, "@" .. path, "t", {})
    if not chunk then
        notify_error("tide-outputs.lua (none of it applied): " .. tostring(err))
        return {}
    end
    local ok, value = pcall(chunk)
    if not ok then
        notify_error("tide-outputs.lua (none of it applied): " .. tostring(value))
        return {}
    end
    if type(value) ~= "table" then
        notify_error("tide-outputs.lua (none of it applied): expected a table, not " .. type(value))
        return {}
    end
    local outputs = {}
    for output, given in pairs(value) do
        if type(output) ~= "string" or not output:match("^desc:.") then
            notify_error("tide-outputs.lua: " .. tostring(output) .. " should be desc: and a monitor's description")
        elseif type(given) ~= "table" then
            notify_error("tide-outputs.lua: " .. output .. " should be a table, not " .. type(given))
        else
            table.insert(outputs, output)
        end
    end
    -- Sorted, so the rules go in the same order each time.
    table.sort(outputs)
    local entries = {}
    for _, output in ipairs(outputs) do
        local set = {}
        for k, v in pairs(value[output]) do
            if k == "scale" then
                if type(v) == "number" and v >= 0.25 and v <= 10 then
                    -- hl.monitor takes a scale as a string.
                    set.scale = tostring(v)
                else
                    notify_error("tide-outputs.lua: " .. output .. ".scale should be a number from 0.25 to 10")
                end
            elseif k == "position" then
                if TIDE_POSITIONS[v] then
                    set.position = v
                else
                    notify_error("tide-outputs.lua: " .. output .. ".position should be auto, auto-right, auto-left, auto-up or auto-down")
                end
            else
                notify_error("tide-outputs.lua: unknown setting " .. output .. "." .. tostring(k))
            end
        end
        table.insert(entries, { output = output, set = set })
    end
    return entries
end

-- Entry `e`'s rule, `name` its output if given, else its desc:. What the
-- entry leaves out is the catch-all's, as it is when the rule is added:
-- naming a monitor means the catch-all no longer applies to it.
local function tide_rule(e, name)
    local rule = copy_rule(default_monitor, name or e.output)
    for k, v in pairs(e.set) do
        rule[k] = v
    end
    return rule
end

local tide_monitors = read_tide_outputs()
for _, e in ipairs(tide_monitors) do
    hl.monitor(tide_rule(e))
end

-- The monitor rules hyprland.local.lua makes, in order, and whether one
-- is its own catch-all (see PER-MACHINE OVERRIDES).
local local_monitors = {}
local local_catchall = false

-- Whether rule `selector` names monitor `m`, as Hyprland 0.56's
-- CMonitor::matchesStaticSelector does: by its name, or desc: and the start
-- of its description.
local function names_monitor(selector, m)
    local desc = selector:match("^desc:%s*(.-)%s*$")
    if desc then
        return type(m.description) == "string" and m.description:sub(1, #desc) == desc
    end
    return selector == m.name
end

-- Whether the local file's rule `selector` names monitor `m`. Hyprland
-- also matches desc: against a monitor's full description, which
-- hl.get_monitors doesn't give (its description is the short one, as
-- hyprctl monitors shows), so where Hyprland can resolve the selector it's
-- asked.
local function local_names(selector, m)
    if names_monitor(selector, m) then
        return true
    end
    if selector == "" or type(hl.get_monitor) ~= "function" then
        return false
    end
    -- It gives an HL.Monitor userdata, or nil for one it can't resolve (a
    -- monitor not connected, or off), which is left to the match above, as
    -- is a selector it refuses.
    local ok, name = pcall(function()
        local found = hl.get_monitor(selector)
        return found ~= nil and found.name or nil
    end)
    return ok and name ~= nil and name == m.name
end

-- Hyprland 0.56.2 takes a desc: rule added at runtime but doesn't apply it
-- to a monitor already connected (hyprwm/Hyprland#15961), though a rule by
-- name it does. So when tide applies a change, each connected monitor that
-- tide sets, and the local file doesn't, gets its rule by name too. A name
-- can come to mean another monitor, so one given a rule here goes back to
-- the catch-all's settings once tide no longer sets the monitor it names,
-- as does one whose monitor tide stops setting (`reset`, its selectors).
local tide_named = {}

local function tide_name_rules(reset)
    local rules, named, seen = {}, {}, {}
    -- The monitors on: Hyprland 0.56.2's hl.get_monitors lists no others,
    -- whatever it's passed, so a closed lid's panel gets its rule when it
    -- comes back (monitor.added, below).
    for _, m in ipairs(hl.get_monitors()) do
        if type(m.name) == "string" and m.name ~= "" then
            seen[m.name] = true
            local mine = false
            for _, r in ipairs(local_monitors) do
                mine = mine or local_names(r.output, m)
            end
            local entry, was = nil, tide_named[m.name]
            for _, e in ipairs(tide_monitors) do
                if names_monitor(e.output, m) then
                    entry = e -- the last, as Hyprland takes it
                end
            end
            for _, selector in ipairs(reset or {}) do
                was = was or names_monitor(selector, m)
            end
            -- Where the local file has a rule, it wins, as it did when the
            -- config loaded.
            if entry and not mine then
                named[m.name] = true
                table.insert(rules, tide_rule(entry, m.name))
            elseif was and not mine then
                table.insert(rules, copy_rule(default_monitor, m.name))
            end
        end
    end
    -- A name not connected now keeps its mark, so whatever connects as it
    -- next is put right (monitor.added, below).
    for name in pairs(tide_named) do
        if not seen[name] then
            named[name] = true
        end
    end
    tide_named = named
    return rules
end

-- Hyprland uses the last rule added that names a monitor, and adding one
-- for an output that has a rule moves it last. So something that adds a
-- rule puts tide's back on top of it, then the local file's on top of
-- those, as the config loaded them, then turns a closed lid's panel
-- (`lid_panel`) off again. Rules that haven't changed change nothing
-- (Hyprland 0.56's CMonitorRuleManager::ensureMonitorStatus).
local function restack_monitors(reset, lid_panel)
    for _, e in ipairs(tide_monitors) do
        hl.monitor(tide_rule(e))
    end
    for _, r in ipairs(tide_name_rules(reset)) do
        hl.monitor(r)
    end
    for _, r in ipairs(local_monitors) do
        hl.monitor(copy_rule(r))
    end
    if lid_panel then
        hl.monitor({ output = lid_panel, disabled = true })
    end
end

--------------------------------------------------------------------------------
-- AUTOSTART
--------------------------------------------------------------------------------
-- In the tide session this starts nothing but `uwsm finalize` (tide
-- SPEC.md §5.4): tide.service runs the bar, notifications, wallpaper,
-- polkit agent and input setup, and hypridle.service the idle daemon, each
-- once and only in that session. The list below is for a plain Hyprland login.
hl.on("hyprland.start", function()
    if tide_session then
        hl.exec_cmd("uwsm finalize")
        return
    end
    hl.exec_cmd("swww-daemon")
    hl.exec_cmd("sleep 1 && swww img ~/.config/hypr/wallpaper.jpg")
    hl.exec_cmd("hypridle")
    -- Mice get the right button primary; touchpads keep the default. runenv
    -- brings in ~/.env.local, where HYPR_MOUSE_SCROLL_FACTOR can be set.
    hl.exec_cmd(runenv .. " " .. scripts .. "/apply-input.sh")
    -- Applies the light/dark theme and launches waybar and swaync with it.
    hl.exec_cmd(scripts .. "/theme-daemon.sh")
    hl.exec_cmd("nm-applet --indicator")
    hl.exec_cmd("blueman-applet")
end)

-- A config reload, say after pulling conf, resets every device to the
-- defaults, which would leave mice right-handed with the slow wheel, so the
-- per-device settings go back on after each one, in either session.
hl.on("config.reloaded", function()
    hl.exec_cmd(runenv .. " " .. scripts .. "/apply-input.sh")
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
-- The tide layout (tile, three-column, two columns + stack, monocle, per
-- workspace) is installed by `make install` in the tide repo. Without
-- it this falls back to Hyprland's master layout, the same shape as tile.
local qs
do
    local path = home .. "/.config/hypr/tide/layout.lua"
    -- Missing is fine: the layout just isn't installed here.
    local text = read_optional(path, "tide layout", 1024 * 1024)
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
            notify_error("tide layout failed to load, using master: " .. tostring(result))
        end
    end
end

-- The tide focus guard (SPEC.md §14): nothing steals the keyboard.
-- It's installed beside the layout, and loads in the tide session alone:
-- it opens every window unfocused until a grant says otherwise, and only
-- that session grants (`tide launch`, tide-grant), so in a plain login
-- even an app you just launched would open unfocused. Without it,
-- Hyprland's own focus rules apply (misc:focus_on_activate is off below
-- either way).
if tide_session then
    local path = home .. "/.config/hypr/tide/focus.lua"
    local text = read_optional(path, "tide focus guard", 1024 * 1024)
    if text then
        local ok, err = pcall(function()
            local m = assert(load(text, "@" .. path))()
            if type(m) ~= "table" or type(m.setup) ~= "function" then
                error("focus.lua has no setup()")
            end
            m.setup({})
        end)
        if not ok then
            notify_error("tide focus guard failed to load: " .. tostring(err))
        end
    end
end

-- Each layout action as a bind target, from tide or from master.
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
        layout = qs and "lua:tide" or "master",
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
-- The inactive dim's strength, unless tide's Appearance page sets one
-- (apply_tide_appearance below).
local DIM_STRENGTH = 0.07

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
        -- Hyprland's dim looks stronger than KDE's dim-inactive effect at
        -- the same number, so 0.07. If a dark app next to a dark app is hard
        -- to tell apart, try 0.1, on tide's Appearance page.
        dim_inactive = true,
        dim_strength = DIM_STRENGTH,
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
        -- instead (Super+Tab goes there).
        focus_on_activate = false,
        -- uwsm sets XDG_CURRENT_DESKTOP to tide:Hyprland on purpose.
        disable_xdg_env_checks = true,
        -- hyprland-guiutils (Hyprland's own dialogs) isn't in the source
        -- build, so don't warn about it at every login. See TODO.md.
        disable_hyprland_guiutils_check = true,
        -- A lock client that dies leaves the session locked; this lets a new
        -- one take the lock back, so systemd's restart of tide-lock.service
        -- (or a hyprlock run from a TTY) brings back a password prompt
        -- rather than Hyprland's dead-lock screen (tide SPEC.md §10).
        allow_session_lock_restore = true,
    },
    -- Focus never drags the pointer along with it.
    cursor = { no_warps = true },
})

--------------------------------------------------------------------------------
-- INPUT
--------------------------------------------------------------------------------
-- Kept as a table, since it's also what a setting tide stops making goes
-- back to (apply_tide_input).
local INPUT = {
    kb_layout = "us",
    kb_variant = "dvorak",
    -- Caps Lock is Compose, matching `setup`'s XKBOPTIONS. Menu is a
    -- second Super, as xmodmaprc made it under X11.
    kb_options = "compose:caps,altwin:menu_win",

    -- Focus follows the mouse, but only when it crosses into a window,
    -- and closing a window focuses the one under the pointer.
    follow_mouse = 1,
    mouse_refocus = false,
    focus_on_close = 1,

    -- libinput's adaptive acceleration at full speed, the KDE setup this
    -- replaces; flat, and custom curves, felt wrong on a real session.
    sensitivity = 1.0,
    accel_profile = "adaptive",
    -- Right-handed by default, which trackpads want; apply-input.sh
    -- flips mice to the right button primary.
    left_handed = false,
    natural_scroll = false,
    -- Hyprland's own, spelled out so tide's settings have a value to
    -- go back to.
    repeat_delay = 600,
    repeat_rate = 25,

    touchpad = {
        natural_scroll = true,
        tap_to_click = true,
        disable_while_typing = true,
        scroll_factor = 1.0,
    },
}
-- A copy, so nothing that keeps the table it's given can change INPUT.
local function copy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = type(v) == "table" and copy(v) or v
    end
    return out
end
hl.config({ input = copy(INPUT) })

-- tide's Mouse, Touchpad and Keyboard settings (tide SPEC.md §16), which
-- tide writes to tide-input.lua beside this file as a table in Hyprland's
-- own option names: { mouse = {...}, touchpad = {...}, keyboard = {...},
-- devices = { ["name"] = {...} } }. The keyboard's options, and the
-- touchpad's own section, apply over the ones above; mice and touchpads get
-- their speed and handedness one device at a time, through conf_input
-- below, as apply-input.sh meets each, and a device named in devices gets
-- its own settings over its kind's. With no file, the settings above
-- stand. It's read as data, with nothing in scope, and a value of the wrong
-- type, or an unknown section or setting, is reported and left out.
local TIDE_INPUT_TYPES = {
    mouse = { sensitivity = "number", scroll_factor = "number", natural_scroll = "boolean", left_handed = "boolean" },
    touchpad = {
        sensitivity = "number", scroll_factor = "number", natural_scroll = "boolean", left_handed = "boolean",
        tap_to_click = "boolean", disable_while_typing = "boolean",
    },
    keyboard = { kb_layout = "string", kb_variant = "string", repeat_delay = "number", repeat_rate = "number" },
}
-- A named device takes any mouse or touchpad option, keyed by the name
-- hyprctl devices gives it.
local TIDE_DEVICE_TYPES = TIDE_INPUT_TYPES.touchpad
-- The touchpad options that live in input.touchpad, for every touchpad;
-- the rest go to each one through conf_input.touchpad.
local TOUCHPAD_SECTION = { natural_scroll = true, tap_to_click = true, disable_while_typing = true, scroll_factor = true }
-- No settings: each kind's table is there, empty.
local function no_tide_input()
    return { mouse = {}, touchpad = {}, keyboard = {}, devices = {} }
end
local tide_input = no_tide_input()
-- The input options hyprland.local.lua set through hl.config, keyed
-- "kb_layout" or "touchpad.scroll_factor": a reload of tide's settings
-- leaves them alone, so the local file still wins, and a setting tide
-- stops making goes back to the local file's value before INPUT's.
local local_input = {}

-- What an input option is when tide doesn't set it.
local function input_default(key)
    if local_input[key] ~= nil then
        return local_input[key]
    end
    local section, option = key:match("^(%w+)%.(.+)$")
    if section then
        return INPUT[section][option]
    end
    return INPUT[key]
end

local function read_tide_input()
    local path = home .. "/.config/hypr/tide-input.lua"
    local text = read_optional(path, "tide-input.lua", 64 * 1024)
    if not text then
        return no_tide_input()
    end
    local chunk, err = load(text, "@" .. path, "t", {})
    if not chunk then
        notify_error("tide-input.lua (none of it applied): " .. tostring(err))
        return no_tide_input()
    end
    local ok, value = pcall(chunk)
    if not ok then
        notify_error("tide-input.lua (none of it applied): " .. tostring(value))
        return no_tide_input()
    end
    if type(value) ~= "table" then
        notify_error("tide-input.lua (none of it applied): expected a table, not " .. type(value))
        return no_tide_input()
    end
    local out = no_tide_input()
    for kind in pairs(value) do
        if TIDE_INPUT_TYPES[kind] == nil and kind ~= "devices" then
            notify_error("tide-input.lua: unknown section " .. tostring(kind))
        end
    end
    for kind, types in pairs(TIDE_INPUT_TYPES) do
        local given = value[kind]
        if given ~= nil and type(given) ~= "table" then
            notify_error("tide-input.lua: " .. kind .. " should be a table, not " .. type(given))
            given = nil
        end
        for k, v in pairs(given or {}) do
            if types[k] == nil then
                notify_error("tide-input.lua: unknown setting " .. kind .. "." .. tostring(k))
            elseif type(v) ~= types[k] then
                notify_error("tide-input.lua: " .. kind .. "." .. k .. " should be a " .. types[k] .. ", not " .. type(v))
            else
                out[kind][k] = v
            end
        end
    end
    local devices = value.devices
    if devices ~= nil and type(devices) ~= "table" then
        notify_error("tide-input.lua: devices should be a table, not " .. type(devices))
        devices = nil
    end
    for name, given in pairs(devices or {}) do
        if type(name) ~= "string" or type(given) ~= "table" then
            notify_error("tide-input.lua: devices." .. tostring(name) .. " should be a table of settings, keyed by the device's name")
        else
            out.devices[name] = {}
            for k, v in pairs(given) do
                if TIDE_DEVICE_TYPES[k] == nil then
                    notify_error("tide-input.lua: unknown setting devices." .. name .. "." .. tostring(k))
                elseif type(v) ~= TIDE_DEVICE_TYPES[k] then
                    notify_error("tide-input.lua: devices." .. name .. "." .. k .. " should be a " .. TIDE_DEVICE_TYPES[k] .. ", not " .. type(v))
                else
                    out.devices[name][k] = v
                end
            end
        end
    end
    return out
end

-- Every option tide can set is applied each time, its value or the
-- default: hl.config merges, so one tide stops setting would otherwise
-- stay at its last value until a full reload.
local function apply_tide_input()
    tide_input = read_tide_input()
    local input, touchpad = {}, {}
    for k in pairs(TIDE_INPUT_TYPES.keyboard) do
        if local_input[k] == nil then
            local v = tide_input.keyboard[k]
            if v == nil then
                v = input_default(k)
            end
            input[k] = v
        end
    end
    for k in pairs(TOUCHPAD_SECTION) do
        if local_input["touchpad." .. k] == nil then
            local v = tide_input.touchpad[k]
            if v == nil then
                v = input_default("touchpad." .. k)
            end
            touchpad[k] = v
        end
    end
    if next(touchpad) then
        input.touchpad = touchpad
    end
    if next(input) then
        hl.config({ input = input })
    end
end
apply_tide_input()

-- tide's Appearance settings that reach Hyprland (tide SPEC.md §16): the
-- inactive dim's strength, which tide writes to tide-appearance.lua beside
-- this file as { dim_strength = 0.1 }. With no file, or no setting,
-- DIM_STRENGTH stands. It's read as data, as tide-input.lua is, and
-- hyprland.local.lua's own dim_strength still wins (local_dim).
-- conf_appearance.reload() is how tide applies a change.
local local_dim = nil

local function read_tide_appearance()
    local path = home .. "/.config/hypr/tide-appearance.lua"
    local text = read_optional(path, "tide-appearance.lua", 64 * 1024)
    if not text then
        return {}
    end
    local chunk, err = load(text, "@" .. path, "t", {})
    if not chunk then
        notify_error("tide-appearance.lua (none of it applied): " .. tostring(err))
        return {}
    end
    local ok, value = pcall(chunk)
    if not ok then
        notify_error("tide-appearance.lua (none of it applied): " .. tostring(value))
        return {}
    end
    if type(value) ~= "table" then
        notify_error("tide-appearance.lua (none of it applied): expected a table, not " .. type(value))
        return {}
    end
    local out = {}
    for k, v in pairs(value) do
        if k ~= "dim_strength" then
            notify_error("tide-appearance.lua: unknown setting " .. tostring(k))
        elseif type(v) ~= "number" or v ~= v or v < 0 or v > 1 then
            notify_error("tide-appearance.lua: dim_strength should be a number from 0 to 1, not " .. tostring(v))
        else
            out.dim_strength = v
        end
    end
    return out
end

-- The dim is applied each time, tide's or the default, so a setting tide
-- stops making goes back to DIM_STRENGTH rather than staying put.
local function apply_tide_appearance()
    local tide = read_tide_appearance()
    if local_dim == nil then
        hl.config({ decoration = { dim_strength = tide.dim_strength or DIM_STRENGTH } })
    end
end
apply_tide_appearance()
_G.conf_appearance = { reload = apply_tide_appearance }

-- A 3-finger horizontal swipe changes workspace.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

--------------------------------------------------------------------------------
-- KEYS (tide SPEC.md §6.6)
--------------------------------------------------------------------------------
local function key(k)
    return mod .. " + " .. k
end

local function exec(cmd)
    return hl.dsp.exec_cmd(cmd)
end

-- Starts an app. In the tide session it goes through `tide
-- launch`, which waits for the shell, grants the app's first window focus
-- (the focus guard opens every other window unfocused) and runs it in
-- app-graphical.slice. id names the app for that grant; the default, "*",
-- is the first window of any app, for wrapper scripts whose window class
-- isn't known here.
local function app(cmd, id)
    if not tide_session then
        return exec(cmd)
    end
    return exec("tide launch --app '" .. (id or "*") .. "' -- " .. cmd)
end

-- A binding's options with what it does, for tide's Keys page (tide SPEC.md
-- §16), which lists `hyprctl binds -j`: a Lua binding's dispatcher there is
-- only "__lua", so its description is all that says. A copy, since some
-- options tables are shared.
local function does(description, opts)
    local o = { description = description }
    for k, v in pairs(opts or {}) do
        o[k] = v
    end
    return o
end

-- Applications. The helper scripts live in the scripts repo, on the PATH
-- runenv provides. Super+D and Super+S are left for hyprland.local.lua.
hl.bind(key("T"), app(terminal, terminal), does("Terminal"))
hl.bind(key("W"), app(runenv .. " terminal_on_workstation"), does("Terminal on the workstation"))
hl.bind(key("G"), app(runenv .. " browser1"), does("Browser"))
hl.bind(key("SHIFT + G"), app(runenv .. " browser3"), does("Browser, third profile"))
hl.bind(key("F"), app(runenv .. " browser2"), does("Browser, second profile"))
hl.bind(key("B"), exec(runenv .. " bluetooth-connect"), does("Connect the headphones"))
hl.bind(key("SHIFT + B"), exec(runenv .. " pulseprofile.py"), does("Next audio profile"))
hl.bind(key("C"), app(runenv .. " google-calendar"), does("Google Calendar"))
hl.bind(key("SHIFT + C"), app(runenv .. " google-chat"), does("Google Chat"))
hl.bind(key("H"), app(runenv .. " home"), does("Home folder"))
hl.bind(key("I"), app(runenv .. " irc"), does("IRC"))
hl.bind(key("M"), app(runenv .. " google-meet"), does("Google Meet"))
hl.bind(key("N"), app(runenv .. " notepad"), does("Notepad"))
hl.bind(key("R"), app(runenv .. " remote-desktop"), does("Remote desktop"))
hl.bind(key("Y"), app(runenv .. " youtube-music"), does("YouTube Music"))
hl.bind(key("E"), app(terminal .. " -e yazi", terminal), does("Files"))
-- tide's launcher (SPEC.md §8) while its shell runs; the call fails
-- otherwise (no shell), and fuzzel opens instead, through runenv so its app
-- list sees the user's scripts.
hl.bind(key("Space"), exec("qs -c tide ipc call launcher toggle || " .. runenv .. " " .. scripts .. "/launch-fuzzel.sh"), does("Launcher"))
-- tide's notification center (SPEC.md §9) while its shell is the
-- notification server; the call fails otherwise (no shell, or the server not
-- opted in), and swaync's panel opens instead.
hl.bind(key("SHIFT + N"), exec("qs -c tide ipc call notifications toggle || swaync-client -t -sw"), does("Notification center"))

-- Session.
hl.bind(key("BackSpace"), hl.dsp.window.close(), does("Close the window"))
hl.bind(key("L"), exec(lock), does("Lock"))
hl.bind(key("SHIFT + E"), hl.dsp.exit(), does("Quit Hyprland"))

-- Layouts.
hl.bind(key("period"), act.next_layout, does("Next layout"))
hl.bind(key("comma"), act.prev_layout, does("Previous layout"))
hl.bind(key("grave"), act.monocle, does("Monocle"))
hl.bind(key("backslash"), act.grow, does("Grow the master", { repeating = true }))
hl.bind(key("slash"), act.shrink, does("Shrink the master", { repeating = true }))
hl.bind(key("equal"), act.add_master, does("Add a master"))
hl.bind(key("minus"), act.remove_master, does("Remove a master"))
hl.bind(key("Return"), act.swap_master, does("Swap with the master"))
hl.bind(key("J"), act.focus_next, does("Focus down the stack"))
hl.bind(key("K"), act.focus_prev, does("Focus up the stack"))
hl.bind(key("SHIFT + J"), act.move_next, does("Move down the stack"))
hl.bind(key("SHIFT + K"), act.move_prev, does("Move up the stack"))

-- One window big: maximize keeps the bar, fullscreen covers it, and
-- Super+Down undoes either. Unset is a no-op for a mode that isn't on.
hl.bind(key("Up"), hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }), does("Maximize"))
hl.bind(key("SHIFT + Up"), hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), does("Fullscreen"))
hl.bind(key("Down"), function()
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "unset" }))
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset" }))
end, does("Restore"))

-- Floating.
hl.bind(key("SHIFT + F"), hl.dsp.window.float({ action = "toggle" }), does("Float or tile"))
hl.bind(key("Insert"), hl.dsp.window.float({ action = "toggle" }), does("Float or tile"))
hl.bind(key("mouse:272"), hl.dsp.window.drag(), does("Move the window", { mouse = true }))
hl.bind(key("mouse:273"), hl.dsp.window.resize(), does("Resize the window", { mouse = true }))
-- There are no title bars to double-click, so Super+middle-click toggles
-- maximize, and a second click puts the window back in its tile. It acts on
-- the focused window, which focus-follows-mouse makes the one under the
-- pointer.
hl.bind(key("mouse:274"), hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }), does("Maximize"))

-- Resize mode, for floating windows: h/j/k/l or arrows, Esc or Return to leave.
hl.bind(key("SHIFT + R"), hl.dsp.submap("resize"), does("Resize mode"))
hl.define_submap("resize", function()
    local steps = {
        H = { -40, 0 }, L = { 40, 0 }, K = { 0, -40 }, J = { 0, 40 },
        left = { -40, 0 }, right = { 40, 0 }, up = { 0, -40 }, down = { 0, 40 },
    }
    for k, d in pairs(steps) do
        local what = d[1] < 0 and "Narrower" or d[1] > 0 and "Wider" or d[2] < 0 and "Shorter" or "Taller"
        hl.bind(k, hl.dsp.window.resize({ x = d[1], y = d[2], relative = true }), does(what, { repeating = true }))
    end
    hl.bind("escape", hl.dsp.submap("reset"), does("Leave resize mode"))
    hl.bind("Return", hl.dsp.submap("reset"), does("Leave resize mode"))
end)

-- Workspaces 1-9, one shared pool across monitors.
for i = 1, 9 do
    hl.bind(key(tostring(i)), hl.dsp.focus({ workspace = i }), does("Workspace " .. i))
    hl.bind(key("SHIFT + " .. i), hl.dsp.window.move({ workspace = i, follow = false }), does("Send the window to workspace " .. i))
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
hl.bind(key("Left"), step_workspace(-1, false), does("Previous workspace"))
hl.bind(key("Right"), step_workspace(1, false), does("Next workspace"))
-- The same, where GNOME has them.
hl.bind(key("Page_Up"), step_workspace(-1, false), does("Previous workspace"))
hl.bind(key("Page_Down"), step_workspace(1, false), does("Next workspace"))
hl.bind(key("SHIFT + Left"), step_workspace(-1, true), does("Move the window to the previous workspace"))
hl.bind(key("SHIFT + Right"), step_workspace(1, true), does("Move the window to the next workspace"))

-- The way to a window that wanted focus and didn't get it (§14). Lua can't
-- mark a window urgent, so tide's focus guard keeps the ones it held
-- back; otherwise it's Hyprland's urgent window, or the last one. So with
-- one window marked, a press goes there and the next comes back.
-- Super+Tab and Super+Home both do it, on trial until one sticks.
--
-- Not `urgent_or_last`: in 0.56 its "last" reads the focus history from the
-- oldest end, so pressing it again walked through every window. `last`
-- reads it from the newest.
local function focus_attention()
    local guard = rawget(_G, "tide_focus")
    if guard and guard.focus_attention then
        local ok, went = pcall(guard.focus_attention)
        if not ok then
            notify_error("Super+Tab: the focus guard failed: " .. tostring(went))
        elseif went then
            return
        end
    end
    local urgent = query("Super+Tab: couldn't look for an urgent window", function()
        local w = hl.get_urgent_window()
        return w and w.address
    end)
    if urgent then
        hl.dispatch(hl.dsp.focus({ window = "address:" .. urgent }))
    else
        hl.dispatch(hl.dsp.focus({ last = true }))
    end
end
hl.bind(key("Tab"), focus_attention, does("The window waiting for attention"))
hl.bind(key("Home"), focus_attention, does("The window waiting for attention"))
-- Pressed again while Super is held, Super+Tab steps to the next marked
-- window, Alt+Tab style, and releasing Super clears only the one it landed
-- on. Releasing Super ends the guard's cycle, and does nothing outside one,
-- which is every other release. Non-consuming, so apps still see Super.
local function end_cycle()
    local guard = rawget(_G, "tide_focus")
    -- A guard from before cycling has no end_cycle, and nothing to end.
    if not (guard and guard.end_cycle) then
        return
    end
    local ok, err = pcall(guard.end_cycle)
    if not ok then
        notify_error("Super+Tab: the focus guard failed to finish: " .. tostring(err))
    end
end
for _, super in ipairs({ "Super_L", "Super_R" }) do
    hl.bind(mod .. " + " .. super, end_cycle, does("End Super+Tab's cycle", { release = true, non_consuming = true }))
end

-- Screenshots to the clipboard as PNG, with a notification, through the
-- scripts repo's screenshot: the screen, the focused window (Alt), or a
-- region (Shift or Super). It reports its own failures, since a key binding
-- has no terminal, and Esc on a region cancels quietly.
local screenshot = runenv .. " screenshot"
hl.bind("Print", exec(screenshot), does("Screenshot"))
hl.bind("ALT + Print", exec(screenshot .. " --window"), does("Screenshot of the window"))
hl.bind("SHIFT + Print", exec(screenshot .. " --region"), does("Screenshot of a region"))
hl.bind(key("Print"), exec(screenshot .. " --region"), does("Screenshot of a region"))

-- Volume, microphone, brightness and playback keys. These work on the lock
-- screen too; the calculator doesn't, since it opens a window.
local locked = { locked = true }
local locked_repeating = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume", exec("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), does("Volume up", locked_repeating))
hl.bind("XF86AudioLowerVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), does("Volume down", locked_repeating))
hl.bind("XF86AudioMute", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), does("Mute", locked))
hl.bind("XF86AudioMicMute", exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), does("Mute the microphone", locked))
hl.bind(key("SHIFT + M"), exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), does("Mute the microphone", locked))
-- tide's command shows the new level on the shell's OSD. Only a
-- tide from before it (a usage error, 2) or none (127) falls back to
-- brightnessctl alone: any other failure may have changed the level already,
-- so it's passed on as the binding's status instead.
local function brightness(step)
    return exec("tide brightness " .. step .. "; s=$?; "
        .. "if test $s -eq 2 || test $s -eq 127; then brightnessctl set " .. step .. "; else exit $s; fi")
end
hl.bind("XF86MonBrightnessUp", brightness("5%+"), does("Brightness up", locked_repeating))
hl.bind("XF86MonBrightnessDown", brightness("5%-"), does("Brightness down", locked_repeating))
hl.bind("XF86AudioPlay", exec("playerctl play-pause"), does("Play or pause", locked))
hl.bind("XF86AudioPause", exec("playerctl play-pause"), does("Play or pause", locked))
hl.bind("XF86AudioNext", exec("playerctl next"), does("Next track", locked))
hl.bind("XF86AudioPrev", exec("playerctl previous"), does("Previous track", locked))
hl.bind("XF86Calculator", app("gnome-calculator", "org.gnome.Calculator"), does("Calculator"))

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
        lid_file = dir .. "/hypr/" .. sig .. "/tide-lid"
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
    -- nothing reads, never a truncated tide-lid.
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
    -- once the panel shows up as a monitor again (monitor.added below). A
    -- rule for an output that has one starts from that one's fields
    -- (Hyprland 0.56's hlMonitor), so it has to undo lid_close's disabled.
    -- It takes the catch-all's settings, the local file's if it has one,
    -- since naming the panel means the catch-all no longer applies to it.
    local rule = copy_rule(default_monitor, panel)
    rule.disabled = false
    hl.monitor(rule)
    -- And it would win over tide's and the local file's rules for the panel.
    restack_monitors(nil, nil)
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

hl.bind("switch:on:Lid Switch", lid_close, does("Lid closed", locked))
hl.bind("switch:off:Lid Switch", lid_open, does("Lid opened", locked))

--------------------------------------------------------------------------------
-- WINDOW RULES (tide SPEC.md §6.2 and §6.4)
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

-- tide's notification popups (SPEC.md §9) show black in a screen
-- share, so one that appears while sharing doesn't show its text.
hl.layer_rule({
    name = "no-share-notifications",
    match = { namespace = "^tide-notifications$" },
    no_screen_share = true,
})

--------------------------------------------------------------------------------
-- PER-MACHINE OVERRIDES
--------------------------------------------------------------------------------
-- ~/.config/hypr/hyprland.local.lua, the same name plus .local like
-- .shrc.local, is loaded last so its settings win. It is machine-local and
-- never committed; hyprland.local.lua.template shows what belongs there.
-- Binds add rather than replace, so rebinding a key needs hl.unbind first.
--
-- apply-input.sh runs after this, at login and after every reload, and sets
-- each mouse through conf_input.mouse() and each touchpad through
-- conf_input.touchpad(). A mouse is left-handed with the script's wheel
-- speed, unless tide's mouse settings say otherwise; a touchpad takes tide's
-- touchpad speed and handedness. The fields the local file gave a device in
-- hl.device() are recorded, and these leave those alone, so a machine can
-- make one mouse right-handed or slow its wheel here. hl.device() merges
-- field by field, so the rest still applies. conf_input.reload() is how tide
-- applies a change to its settings: it reads tide-input.lua again and runs
-- apply-input.sh.
local local_devices = {}

-- What input.touchpad's option is, as apply_tide_input set it: the local
-- file's, else tide's, else the config's.
local function touchpad_option(k)
    local v = local_input["touchpad." .. k]
    if v == nil then
        v = tide_input.touchpad[k]
    end
    if v == nil then
        v = INPUT.touchpad[k]
    end
    return v
end

local function device(name, want)
    local set = local_devices[(name:gsub(" ", "-"))] or {}
    local t = { name = name }
    for k, v in pairs(want) do
        if set[k] == nil then
            t[k] = v
        end
    end
    hl.device(t)
end

-- Each device gets every field tide can set, its value or the default,
-- for the same reason as apply_tide_input: hl.device merges too. A device
-- tide's settings name gets its own over its kind's.
_G.conf_input = {
    mouse = function(name, scroll_factor)
        local want = {
            left_handed = true,
            scroll_factor = scroll_factor,
            sensitivity = input_default("sensitivity"),
            natural_scroll = input_default("natural_scroll"),
        }
        for k, v in pairs(tide_input.mouse) do
            want[k] = v
        end
        for k, v in pairs(tide_input.devices[name] or {}) do
            -- A touchpad's tap_to_click means nothing to a mouse, and once
            -- set it would stay set, since nothing here resets it.
            if TIDE_INPUT_TYPES.mouse[k] ~= nil then
                want[k] = v
            end
        end
        device(name, want)
    end,
    touchpad = function(name)
        local want = {
            sensitivity = input_default("sensitivity"),
            left_handed = input_default("left_handed"),
        }
        for k, v in pairs(tide_input.touchpad) do
            if not TOUCHPAD_SECTION[k] then
                want[k] = v
            end
        end
        -- Its own settings may include the touchpad section's, which
        -- hl.device takes for one touchpad (Hyprland 0.56's DEVICE_FIELDS).
        -- So each touchpad gets those too, as input.touchpad has them, so
        -- that one its own settings stop making goes back.
        for k in pairs(TOUCHPAD_SECTION) do
            want[k] = touchpad_option(k)
        end
        for k, v in pairs(tide_input.devices[name] or {}) do
            want[k] = v
        end
        device(name, want)
    end,
    reload = function()
        apply_tide_input()
        hl.exec_cmd(runenv .. " " .. scripts .. "/apply-input.sh")
    end,
}
-- conf_outputs.reload() is how tide applies a change to its display
-- settings: it reads tide-outputs.lua again and restacks the rules, so the
-- local file's still win, then turns a closed lid's panel off again. A
-- monitor tide no longer sets goes back to the catch-all's settings, since
-- Hyprland can't drop a rule.
_G.conf_outputs = {
    reload = function()
        local gone = {}
        for _, e in ipairs(tide_monitors) do
            gone[e.output] = true
        end
        tide_monitors = read_tide_outputs()
        for _, e in ipairs(tide_monitors) do
            gone[e.output] = nil
        end
        local outputs = {}
        for output in pairs(gone) do
            table.insert(outputs, output)
        end
        table.sort(outputs)
        for _, output in ipairs(outputs) do
            hl.monitor(copy_rule(default_monitor, output))
        end
        restack_monitors(outputs, lid.panel)
    end,
}

-- A monitor that connects, or comes back on, takes tide's rule by name,
-- which a desc: rule added since the config loaded wouldn't give it; and
-- one that connects as a name this gave a rule to may not be the monitor
-- the rule was for.
hl.on("monitor.added", function()
    if next(tide_named) ~= nil or #tide_monitors > 0 then
        restack_monitors(nil, lid.panel)
    end
end)
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
            -- Hyprland names a device with its spaces as dashes.
            local real_device, real_config, real_monitor = hl.device, hl.config, hl.monitor
            hl.monitor = function(t)
                if type(t) == "table" and type(t.output) == "string" then
                    table.insert(local_monitors, copy_rule(t))
                    -- What tide's rules leave out, and a monitor tide stops
                    -- setting goes back to.
                    if t.output == "" then
                        for k, v in pairs(t) do
                            default_monitor[k] = v
                        end
                        local_catchall = true
                    end
                end
                return real_monitor(t)
            end
            hl.device = function(t)
                if type(t) == "table" and type(t.name) == "string" then
                    local key = t.name:gsub(" ", "-")
                    local set = local_devices[key] or {}
                    for k, v in pairs(t) do
                        set[k] = v
                    end
                    local_devices[key] = set
                end
                return real_device(t)
            end
            hl.config = function(t)
                local decoration = type(t) == "table" and t.decoration
                if type(decoration) == "table" and decoration.dim_strength ~= nil then
                    local_dim = decoration.dim_strength
                end
                local input = type(t) == "table" and t.input
                if type(input) == "table" then
                    for k, v in pairs(input) do
                        if k == "touchpad" and type(v) == "table" then
                            for tk, tv in pairs(v) do
                                local_input["touchpad." .. tk] = tv
                            end
                        else
                            local_input[k] = v
                        end
                    end
                end
                return real_config(t)
            end
            local ok, run_err = pcall(chunk)
            hl.device, hl.config, hl.monitor = real_device, real_config, real_monitor
            if not ok then
                notify_error("hyprland.local.lua stopped (the calls before this applied): " .. tostring(run_err))
            end
            -- tide's rules were added before the local catch-all was known,
            -- so they're added again with it, under the local file's and a
            -- closed lid's, as a reload of tide's settings would add them.
            if local_catchall then
                restack_monitors(nil, lid.panel)
            end
        end
    end
end
