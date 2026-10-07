-- Tests for hyprland.lua, run against a stub of Hyprland's `hl` API.
--
-- Usage: lua hyprland_test.lua [path/to/hyprland.lua]
--
-- Each case loads the config fresh under a fake $HOME, so the optional
-- tide layout and hyprland.local.lua can be present, missing or broken.
-- The stub records every call; bound functions are then called against
-- stubbed getters to check what they dispatch.

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local config_path = arg[1] or (here .. "/hyprland.lua")

local passes, failures = 0, 0
local current = "?"

local function test(name, fn)
    current = name
    local ok, err = pcall(fn)
    if ok then
        passes = passes + 1
    else
        failures = failures + 1
        io.stderr:write("FAIL: " .. name .. "\n  " .. tostring(err) .. "\n")
    end
end

local function fail(msg)
    error(msg, 3)
end

local function eq(want, got, what)
    if want ~= got then
        fail(string.format("%s: want %s, got %s", what or "value", tostring(want), tostring(got)))
    end
end

local function truthy(v, what)
    if not v then
        fail((what or "condition") .. " is false")
    end
end

--------------------------------------------------------------------------------
-- Fake $HOME
--------------------------------------------------------------------------------
local tmp = os.tmpname()
os.remove(tmp)
assert(os.execute("mkdir -p '" .. tmp .. "/.config/hypr/tide' '" .. tmp .. "/run/hypr/sig1' '" .. tmp .. "/run/hypr/sig2'"))

local function write(rel, text)
    local f = assert(io.open(tmp .. "/" .. rel, "w"))
    f:write(text)
    f:close()
end

local function remove(rel)
    os.remove(tmp .. "/" .. rel)
end

local LAYOUT = ".config/hypr/tide/layout.lua"
local FOCUS = ".config/hypr/tide/focus.lua"
local LOCAL = ".config/hypr/hyprland.local.lua"
local TIDE_INPUT = ".config/hypr/tide-input.lua"
local LID_FILE = "run/hypr/sig1/tide-lid"

local function exists(rel)
    local f = io.open(tmp .. "/" .. rel)
    if f then
        f:close()
    end
    return f ~= nil
end

-- A stand-in for the tide layout: every helper is a function that
-- records its own name when called.
local FAKE_LAYOUT = [[
local M = { calls = {} }
local function helper(name)
    return function(...) table.insert(M.calls, { name, ... }) end
end
for _, n in ipairs({ "cycle_next", "cycle_prev", "toggle_monocle", "grow", "shrink",
                     "add_master", "remove_master", "swap_with_master", "focus", "move" }) do
    M[n] = helper(n)
end
function M.setup(opts) M.setup_opts = opts end
_G.fake_layout = M
return M
]]

-- A stand-in for the tide focus guard, recording its setup().
local FAKE_FOCUS = [[
local M = {}
function M.setup(opts) _G.fake_focus_opts = opts end
return M
]]

--------------------------------------------------------------------------------
-- The `hl` stub
--------------------------------------------------------------------------------
local env_overrides = {}
local real_getenv = os.getenv
os.getenv = function(name)
    if name == "HOME" then
        return tmp
    end
    if env_overrides[name] ~= nil then
        return env_overrides[name] or nil
    end
    return real_getenv(name)
end

local function merge(into, from)
    for k, v in pairs(from) do
        if type(v) == "table" and type(into[k]) == "table" then
            merge(into[k], v)
        else
            into[k] = v
        end
    end
end

-- Dispatchers are recorded as { dsp = "window.close", args = {...} }.
local function dsp_namespace(prefix)
    return setmetatable({}, {
        __index = function(_, k)
            local name = prefix and (prefix .. "." .. k) or k
            if k == "window" or k == "workspace" or k == "group" or k == "cursor" then
                if not prefix then
                    return dsp_namespace(name)
                end
            end
            return function(args)
                return { dsp = name, args = args }
            end
        end,
    })
end

local S -- state of the current load

local function new_hl()
    S = {
        config = {},
        binds = {},       -- "submap|KEYS" -> { target, opts }
        bind_order = {},
        calls = {},       -- every top-level call, in order: { fn, arg }
        handlers = {},    -- event -> { fn, ... }
        execs = {},
        dispatched = {},
        notifications = {},
        monitors = {},
        rules = {}, layer_rules = {},
        -- What the getters return; set per test.
        active_workspace = nil,
        active_window = nil,
        monitor_list = {},
        workspace_list = {},
    }
    local submap = ""
    local function record(fn, a)
        table.insert(S.calls, { fn, a })
    end
    return {
        config = function(t) record("config", t); merge(S.config, t) end,
        monitor = function(t) record("monitor", t); table.insert(S.monitors, t) end,
        env = function(k, v) record("env", k); S.config.env = S.config.env or {}; S.config.env[k] = v end,
        device = function(t) record("device", t) end,
        gesture = function(t) record("gesture", t); S.gesture = t end,
        curve = function(n, t) record("curve", n) end,
        animation = function(t) record("animation", t) end,
        window_rule = function(t) record("window_rule", t); S.rules[t.name] = t end,
        layer_rule = function(t) record("layer_rule", t); S.layer_rules[t.name] = t end,
        on = function(ev, fn)
            record("on", ev)
            S.handlers[ev] = S.handlers[ev] or {}
            table.insert(S.handlers[ev], fn)
        end,
        bind = function(keys, target, opts)
            record("bind", keys)
            if target == nil then
                error("hl.bind(" .. keys .. "): no dispatcher", 2)
            end
            local id = submap .. "|" .. keys
            if S.binds[id] then
                error("hl.bind(" .. keys .. "): bound twice", 2)
            end
            S.binds[id] = { target = target, opts = opts or {} }
            table.insert(S.bind_order, id)
        end,
        unbind = function(keys) record("unbind", keys); S.binds["|" .. keys] = nil end,
        define_submap = function(name, fn)
            record("define_submap", name)
            local prev = submap
            submap = name
            fn()
            submap = prev
        end,
        exec_cmd = function(cmd) table.insert(S.execs, cmd) end,
        dispatch = function(d) table.insert(S.dispatched, d) end,
        dsp = dsp_namespace(nil),
        notification = {
            create = function(t) table.insert(S.notifications, t) end,
        },
        -- A getter set to "raise" fails, as Hyprland's can mid-transition.
        get_active_workspace = function()
            if S.active_workspace == "raise" then error("workspace gone") end
            return S.active_workspace
        end,
        get_active_window = function()
            if S.active_window == "raise" then error("window gone") end
            return S.active_window
        end,
        get_urgent_window = function()
            if S.urgent_window == "raise" then error("window gone") end
            return S.urgent_window
        end,
        -- Disabled monitors are listed only with { all = true }, as in Hyprland.
        get_monitors = function(opts)
            local out = {}
            for _, m in ipairs(S.monitor_list) do
                if (opts and opts.all) or m.enabled ~= false then
                    table.insert(out, m)
                end
            end
            return out
        end,
        get_workspaces = function() return S.workspace_list end,
    }
end

-- A fresh Hyprland instance each time, unless `reload` asks for the same one
-- (whose lid state file survives).
local function load(setup)
    if not (setup and setup.keep_files) then
        assert(os.execute("rm -rf '" .. tmp .. "/" .. LAYOUT .. "' '" .. tmp .. "/" .. LOCAL .. "' '" .. tmp .. "/" .. TIDE_INPUT .. "'"))
    end
    if not (setup and setup.reload) then
        -- rm -rf, since a failed test can leave a directory in its place.
        assert(os.execute("rm -rf '" .. tmp .. "/" .. LID_FILE .. "'"))
    end
    if setup and setup.layout then
        write(LAYOUT, setup.layout)
    end
    if not (setup and setup.keep_files) then
        os.remove(tmp .. "/" .. FOCUS)
    end
    if setup and setup.focus then
        write(FOCUS, setup.focus)
    end
    _G.fake_focus_opts = nil
    if setup and setup["local"] then
        write(LOCAL, setup["local"])
    end
    if setup and setup.input then
        write(TIDE_INPUT, setup.input)
    end
    env_overrides = { XDG_RUNTIME_DIR = tmp .. "/run", HYPRLAND_INSTANCE_SIGNATURE = "sig1", XDG_CURRENT_DESKTOP = false }
    for k, v in pairs((setup and setup.env) or {}) do
        env_overrides[k] = v
    end
    _G.fake_layout = nil
    _G.hl = new_hl()
    dofile(config_path)
    return S
end

local function bind(keys, submap)
    local b = S.binds[(submap or "") .. "|" .. keys]
    if not b then
        fail("no bind for " .. keys)
    end
    return b
end

local function run(keys)
    S.dispatched, S.execs = {}, {}
    local t = bind(keys).target
    if type(t) ~= "function" then
        fail(keys .. " is bound to a dispatcher, not a function")
    end
    t()
    return S.dispatched
end

local function is_dsp(target, name)
    return type(target) == "table" and target.dsp == name
end

local function fire(event, ...)
    for _, fn in ipairs(S.handlers[event] or {}) do
        fn(...)
    end
end

--------------------------------------------------------------------------------
-- Every key is one Hyprland knows
--------------------------------------------------------------------------------
local known_keys = {}
for line in io.lines(here .. "/hyprland_keys.txt") do
    if line ~= "" and not line:match("^#") then
        known_keys[line] = true
    end
end

-- A table is a section unless its own path is a key (a gradient, say).
local function unknown_keys(t, prefix, out)
    for k, v in pairs(t) do
        local path = prefix and (prefix .. "." .. k) or k
        if not known_keys[path] then
            if type(v) == "table" then
                unknown_keys(v, path, out)
            else
                table.insert(out, path)
            end
        end
    end
    return out
end

test("every hl.config key is one Hyprland 0.56 accepts", function()
    load()
    local config = {}
    for k, v in pairs(S.config) do
        if k ~= "env" then -- the stub files hl.env() here
            config[k] = v
        end
    end
    local unknown = unknown_keys(config, nil, {})
    table.sort(unknown)
    eq("", table.concat(unknown, ", "), "unknown keys")
end)

--------------------------------------------------------------------------------
-- Spec settings (tide SPEC.md §6.2, §14)
--------------------------------------------------------------------------------
test("focus cue is the dim alone: no gaps, no borders, dim 0.07", function()
    load()
    local c = S.config
    eq(0, c.general.gaps_in, "gaps_in")
    eq(0, c.general.gaps_out, "gaps_out")
    eq(0, c.general.border_size, "border_size")
    eq(true, c.decoration.dim_inactive, "dim_inactive")
    eq(0.07, c.decoration.dim_strength, "dim_strength")
end)

test("no startup warnings for what tide does on purpose", function()
    load()
    eq(true, S.config.misc.disable_xdg_env_checks, "misc.disable_xdg_env_checks")
    eq(true, S.config.misc.disable_hyprland_guiutils_check, "misc.disable_hyprland_guiutils_check")
end)

test("a new lock client can take back a lock whose client died", function()
    load()
    eq(true, S.config.misc.allow_session_lock_restore, "misc.allow_session_lock_restore")
end)

test("nothing steals focus, and focus never warps the pointer", function()
    load()
    eq(false, S.config.misc.focus_on_activate, "misc.focus_on_activate")
    eq(true, S.config.cursor.no_warps, "cursor.no_warps")
    eq(1, S.config.input.follow_mouse, "follow_mouse")
    eq(false, S.config.input.mouse_refocus, "mouse_refocus")
    eq(1, S.config.input.focus_on_close, "focus_on_close (1 = under the cursor)")
end)

test("the pointer is adaptive at sensitivity 1", function()
    load()
    eq("adaptive", S.config.input.accel_profile, "accel_profile")
    eq(1.0, S.config.input.sensitivity, "sensitivity")
end)

test("keyboard is US Dvorak with Caps Lock as Compose and Menu as Super", function()
    load()
    eq("us", S.config.input.kb_layout)
    eq("dvorak", S.config.input.kb_variant)
    eq("compose:caps,altwin:menu_win", S.config.input.kb_options)
end)

test("touchpads: natural scroll and tap to click; 3-finger workspace swipe", function()
    load()
    eq(true, S.config.input.touchpad.natural_scroll)
    eq(true, S.config.input.touchpad.tap_to_click)
    eq(3, S.gesture.fingers)
    eq("workspace", S.gesture.action)
end)

test("one catch-all monitor rule places every output", function()
    load()
    eq(1, #S.monitors, "monitor rules")
    eq("", S.monitors[1].output)
    eq("auto", S.monitors[1].scale)
end)

test("PATH is never set by the config (runenv owns it)", function()
    load()
    eq(nil, S.config.env.PATH, "env PATH")
end)

--------------------------------------------------------------------------------
-- Layout: tide when installed, master otherwise
--------------------------------------------------------------------------------
test("without the tide layout: master, with no error shown", function()
    load()
    eq("master", S.config.general.layout)
    eq(0, #S.notifications, "notifications")
    eq("slave", S.config.master.new_status, "new windows join the stack")
    truthy(is_dsp(bind("SUPER + period").target, "layout"), "Super+. is a layoutmsg")
    eq("mfact +0.025", bind("SUPER + backslash").target.args)
    eq("cyclenext", bind("SUPER + J").target.args)
    eq("swapwithmaster master", bind("SUPER + Return").target.args)
end)

test("with the tide layout: lua:tide and its helpers", function()
    load({ layout = FAKE_LAYOUT })
    eq("lua:tide", S.config.general.layout)
    eq(0, #S.notifications, "notifications")
    truthy(_G.fake_layout.setup_opts, "setup() was called")
    local qs = _G.fake_layout
    eq(qs.cycle_next, bind("SUPER + period").target, "Super+.")
    eq(qs.cycle_prev, bind("SUPER + comma").target, "Super+,")
    eq(qs.toggle_monocle, bind("SUPER + grave").target, "Super+`")
    eq(qs.grow, bind("SUPER + backslash").target, "Super+\\")
    eq(qs.shrink, bind("SUPER + slash").target, "Super+/")
    eq(qs.swap_with_master, bind("SUPER + Return").target, "Super+Return")
    run("SUPER + J")
    run("SUPER + SHIFT + K")
    eq("focus", qs.calls[1][1])
    eq(1, qs.calls[1][2])
    eq("move", qs.calls[2][1])
    eq(-1, qs.calls[2][2])
end)

test("a broken tide layout falls back to master and says so", function()
    load({ layout = "error('boom')" })
    eq("master", S.config.general.layout)
    eq(1, #S.notifications, "notifications")
    truthy(S.notifications[1].text:find("boom", 1, true), "the error is in the notification")
end)

test("a tide layout missing a helper the keys use falls back too", function()
    load({ layout = FAKE_LAYOUT:gsub("\"cycle_prev\", ", "") })
    eq("master", S.config.general.layout)
    eq(1, #S.notifications, "notifications")
    truthy(S.notifications[1].text:find("cycle_prev", 1, true), S.notifications[1].text)
    eq(nil, _G.fake_layout.setup_opts, "setup() isn't called on a module that's rejected")
    load({ layout = "return 42" })
    eq("master", S.config.general.layout)
    eq(1, #S.notifications, "a non-table module")
end)

test("an unreadable tide layout is reported, not taken as absent", function()
    load()
    -- A directory opens but fails to read, like an I/O error.
    assert(os.execute("mkdir -p '" .. tmp .. "/" .. LAYOUT .. "'"))
    load({ keep_files = true })
    assert(os.execute("rm -rf '" .. tmp .. "/" .. LAYOUT .. "'"))
    eq("master", S.config.general.layout)
    eq(1, #S.notifications, "notifications")
    truthy(S.notifications[1].text:find("couldn't read", 1, true), S.notifications[1].text)
end)

local TIDE = { XDG_CURRENT_DESKTOP = "tide:Hyprland" }

test("the focus guard is set up when installed", function()
    load({ focus = FAKE_FOCUS, env = TIDE })
    truthy(_G.fake_focus_opts, "setup() was called")
    eq(0, #S.notifications, "notifications")
end)

test("a plain Hyprland login leaves the focus guard out", function()
    -- Nothing there grants focus, so the guard would keep every new window
    -- unfocused, even an app launched from a key on an empty workspace.
    load({ focus = FAKE_FOCUS })
    eq(nil, _G.fake_focus_opts, "setup() wasn't called")
    eq(0, #S.notifications, "notifications")
end)

test("no focus guard installed is quiet", function()
    load({ env = TIDE })
    eq(nil, _G.fake_focus_opts)
    eq(0, #S.notifications, "notifications")
end)

test("a broken focus guard is reported, and the rest of the config loads", function()
    load({ focus = "error('boom')", env = TIDE })
    eq(1, #S.notifications, "notifications")
    truthy(S.notifications[1].text:find("focus guard failed to load", 1, true), S.notifications[1].text)
    truthy(S.rules.pip, "later sections still ran")
    load({ focus = "return {}", env = TIDE })
    eq(1, #S.notifications, "a module with no setup() is reported too")
end)

test("a tide layout whose setup() rejects options falls back too", function()
    load({ layout = "return { setup = function() error('bad option') end }" })
    eq("master", S.config.general.layout)
    eq(1, #S.notifications, "notifications")
end)

--------------------------------------------------------------------------------
-- Keys (SPEC.md §6.6)
--------------------------------------------------------------------------------
test("every key in the spec is bound", function()
    load({ layout = FAKE_LAYOUT })
    local keys = {
        "SUPER + Space", "SUPER + T", "SUPER + W", "SUPER + G", "SUPER + F",
        "SUPER + SHIFT + G", "SUPER + E", "SUPER + B", "SUPER + C", "SUPER + SHIFT + C",
        "SUPER + H", "SUPER + I", "SUPER + M", "SUPER + N", "SUPER + R", "SUPER + Y",
        "SUPER + BackSpace", "SUPER + L",
        "SUPER + Left", "SUPER + Right", "SUPER + SHIFT + Left", "SUPER + SHIFT + Right",
        "SUPER + Page_Up", "SUPER + Page_Down",
        "SUPER + J", "SUPER + K", "SUPER + SHIFT + J", "SUPER + SHIFT + K",
        "SUPER + Return", "SUPER + backslash", "SUPER + slash", "SUPER + equal", "SUPER + minus",
        "SUPER + period", "SUPER + comma", "SUPER + grave",
        "SUPER + Up", "SUPER + SHIFT + Up", "SUPER + Down",
        "SUPER + SHIFT + F", "SUPER + Insert", "SUPER + SHIFT + R",
        "SUPER + Tab", "SUPER + Home", "SUPER + SHIFT + N",
        "Print", "ALT + Print", "SHIFT + Print", "SUPER + Print",
        "XF86AudioMicMute", "SUPER + SHIFT + M",
        "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute",
        "XF86MonBrightnessUp", "XF86MonBrightnessDown",
        "XF86AudioPlay", "XF86AudioPause", "XF86AudioNext", "XF86AudioPrev",
    }
    for i = 1, 9 do
        table.insert(keys, "SUPER + " .. i)
        table.insert(keys, "SUPER + SHIFT + " .. i)
    end
    for _, k in ipairs(keys) do
        bind(k)
    end
end)

test("the dropped keys stay unbound", function()
    load()
    -- BSP toggle, pseudo-tile, rotate master, and a tenth workspace.
    for _, k in ipairs({ "SUPER + SHIFT + backslash", "SUPER + P", "SUPER + O",
                         "SUPER + SHIFT + O", "SUPER + 0", "SUPER + SHIFT + 0" }) do
        eq(nil, S.binds["|" .. k], k)
    end
end)

test("launchers run the scripts repo's helpers through runenv", function()
    load()
    eq("~/scripts/runenv browser1", bind("SUPER + G").target.args)
    eq("~/scripts/runenv google-meet", bind("SUPER + M").target.args)
    eq("kitty", bind("SUPER + T").target.args)
    truthy(bind("SUPER + Space").target.args:find("runenv", 1, true), "launcher through runenv")
end)

test("Super+1..9 go to a workspace; Shift sends the window without following", function()
    load()
    for i = 1, 9 do
        local go = bind("SUPER + " .. i).target
        truthy(is_dsp(go, "focus"), "Super+" .. i)
        eq(i, go.args.workspace)
        local send = bind("SUPER + SHIFT + " .. i).target
        truthy(is_dsp(send, "window.move"), "Super+Shift+" .. i)
        eq(i, send.args.workspace)
        eq(false, send.args.follow)
    end
end)

test("Super+Left/Right step through workspaces 1-9 and stop at the ends", function()
    load()
    S.active_workspace = { id = 3 }
    local d = run("SUPER + Right")
    eq(1, #d)
    truthy(is_dsp(d[1], "focus"))
    eq(4, d[1].args.workspace)
    d = run("SUPER + Left")
    eq(2, d[1].args.workspace)
    d = run("SUPER + Page_Down")
    eq(4, d[1].args.workspace, "PgDn is next")
    d = run("SUPER + Page_Up")
    eq(2, d[1].args.workspace, "PgUp is previous")
    S.active_workspace = { id = 9 }
    eq(0, #run("SUPER + Right"), "past 9")
    S.active_workspace = { id = 1 }
    eq(0, #run("SUPER + Left"), "before 1")
    S.active_workspace = { id = -98 }
    eq(0, #run("SUPER + Right"), "from a special workspace")
    S.active_workspace = nil
    eq(0, #run("SUPER + Right"), "with no workspace")
end)

test("a failed workspace lookup is reported, not silently ignored", function()
    load()
    S.active_workspace = "raise"
    eq(0, #run("SUPER + Right"), "nothing dispatched")
    eq(1, #S.notifications, "notifications")
    truthy(S.notifications[1].text:find("active workspace", 1, true), S.notifications[1].text)
    S.active_workspace = nil
    run("SUPER + Right")
    eq(1, #S.notifications, "no workspace at all is quiet")
end)

test("Super+Shift+Left/Right carry the window and follow it", function()
    load()
    S.active_workspace = { id = 5 }
    local d = run("SUPER + SHIFT + Left")
    truthy(is_dsp(d[1], "window.move"))
    eq(4, d[1].args.workspace)
    eq(true, d[1].args.follow)
    S.active_workspace = { id = 9 }
    eq(0, #run("SUPER + SHIFT + Right"), "past 9")
end)

test("maximize, fullscreen and restore", function()
    load()
    local up = bind("SUPER + Up").target
    eq("maximized", up.args.mode)
    eq("toggle", up.args.action)
    local sup = bind("SUPER + SHIFT + Up").target
    eq("fullscreen", sup.args.mode)
    local d = run("SUPER + Down")
    eq(2, #d, "Super+Down undoes both modes")
    local modes = {}
    for _, x in ipairs(d) do
        eq("unset", x.args.action)
        modes[x.args.mode] = true
    end
    truthy(modes.maximized and modes.fullscreen, "both modes unset")
end)

test("float toggles on Super+Shift+F and Super+Insert", function()
    load()
    truthy(is_dsp(bind("SUPER + SHIFT + F").target, "window.float"))
    truthy(is_dsp(bind("SUPER + Insert").target, "window.float"))
    truthy(bind("SUPER + mouse:272").opts.mouse, "drag is a mouse bind")
end)

test("Super+middle-click toggles maximize, so a second click restores the tile", function()
    load()
    local b = bind("SUPER + mouse:274")
    truthy(is_dsp(b.target, "window.fullscreen"))
    eq("maximized", b.target.args.mode)
    eq("toggle", b.target.args.action)
    eq(nil, b.opts.mouse, "a click, not a drag")
end)

test("the resize submap resizes and has a way out", function()
    load()
    eq("resize", bind("SUPER + SHIFT + R").target.args)
    local h = bind("H", "resize")
    truthy(is_dsp(h.target, "window.resize"))
    eq(-40, h.target.args.x)
    eq(true, h.target.args.relative)
    eq(true, h.opts.repeating)
    eq("reset", bind("escape", "resize").target.args)
    eq("reset", bind("Return", "resize").target.args)
end)

-- tide's Keys page lists `hyprctl binds -j`, where a Lua binding's
-- dispatcher is only "__lua": its description is all that says what it does.
test("every binding says what it does, for tide's Keys page", function()
    load()
    truthy(#S.bind_order > 0, "some bindings")
    for _, id in ipairs(S.bind_order) do
        local d = S.binds[id].opts.description
        truthy(type(d) == "string" and d ~= "", id .. " has a description")
    end
    eq("Terminal", bind("SUPER + T").opts.description)
    eq("Taller", bind("J", "resize").opts.description)
    eq("Send the window to workspace 3", bind("SUPER + SHIFT + 3").opts.description)
    -- Bindings that share an options table each keep their own description,
    -- and the table's options.
    eq("Mute", bind("XF86AudioMute").opts.description)
    eq("Play or pause", bind("XF86AudioPlay").opts.description)
    eq(true, bind("XF86AudioMute").opts.locked)
end)

test("Super+Tab focuses the urgent or last window without the guard", function()
    load()
    _G.tide_focus = nil
    for _, keys in ipairs({ "SUPER + Tab", "SUPER + Home" }) do
        local d = run(keys)
        eq(1, #d, keys)
        -- Not urgent_or_last, whose "last" walks every window in 0.56.
        eq(true, d[1].args.last, keys .. ": none urgent goes back")
        S.urgent_window = { address = "0xabc" }
        d = run(keys)
        eq(1, #d, keys)
        eq("address:0xabc", d[1].args.window, keys .. ": the urgent window")
        S.urgent_window = nil
    end
end)

test("Super+Tab goes back when it can't look for an urgent window", function()
    load()
    _G.tide_focus = nil
    S.urgent_window = "raise"
    local d = run("SUPER + Tab")
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("urgent window", 1, true))
    eq(true, d[1].args.last)
end)

test("Super+Tab and Super+Home go to the guard's waiting window first", function()
    load()
    local waiting = 1
    _G.tide_focus = {
        focus_attention = function()
            if waiting == 0 then
                return false
            end
            waiting = waiting - 1
            hl.dispatch({ name = "guard-focus" })
            return true
        end,
    }
    local d = run("SUPER + Tab")
    eq(1, #d)
    eq("guard-focus", d[1].name)
    d = run("SUPER + Home")
    eq(true, d[1].args.last, "none waiting: goes back")
    _G.tide_focus = { focus_attention = function() error("boom") end }
    d = run("SUPER + Tab")
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("boom", 1, true))
    eq(true, d[1].args.last, "a failed guard falls back")
    _G.tide_focus = nil
end)

test("releasing Super ends the guard's Super+Tab cycle, without consuming Super", function()
    load()
    local ended = 0
    _G.tide_focus = { end_cycle = function() ended = ended + 1 return true end }
    for _, keys in ipairs({ "SUPER + Super_L", "SUPER + Super_R" }) do
        eq(true, bind(keys).opts.release, keys .. " on release")
        eq(true, bind(keys).opts.non_consuming, keys .. " passes Super on")
        run(keys)
    end
    eq(2, ended)
    -- A guard from before cycling, or none, is left alone.
    _G.tide_focus = { focus_attention = function() return false end }
    run("SUPER + Super_L")
    _G.tide_focus = nil
    run("SUPER + Super_L")
    eq(0, #S.notifications)
    _G.tide_focus = { end_cycle = function() error("boom") end }
    run("SUPER + Super_L")
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("boom", 1, true))
    _G.tide_focus = nil
end)

test("tide's notification popups are blacked out of screen shares", function()
    load()
    local r = S.layer_rules["no-share-notifications"]
    truthy(r, "the rule")
    eq("^tide-notifications$", r.match.namespace)
    eq(true, r.no_screen_share)
end)

test("the brightness keys show the OSD through tide, else plain brightnessctl", function()
    load()
    for keys, step in pairs({ XF86MonBrightnessUp = "5%+", XF86MonBrightnessDown = "5%-" }) do
        local cmd = bind(keys).target.args
        truthy(cmd:find("tide brightness " .. step, 1, true), keys)
        -- Run the binding's shell with fakes: brightnessctl runs again only
        -- when tide lacks the command (2) or is missing (127).
        -- Any other status is the binding's own.
        for status, want in pairs({ [0] = { false, 0 }, [1] = { false, 1 }, [2] = { true, 0 }, [127] = { true, 0 } }) do
            local script = "tide() { return " .. status .. "; }; brightnessctl() { echo fallback; }; " .. cmd
            local p = io.popen("sh -c '" .. script:gsub("'", "'\\''") .. "'")
            local out = p:read("a")
            local _, _, code = p:close()
            eq(want[1], out:find("fallback", 1, true) ~= nil, keys .. " fallback after exit " .. status)
            eq(want[2], code, keys .. " status after exit " .. status)
        end
    end
    eq(true, bind("XF86MonBrightnessUp").opts.locked)
    eq(true, bind("XF86MonBrightnessUp").opts.repeating)
end)

test("Print takes the screen, Alt the window, Shift or Super a region", function()
    load()
    for keys, args in pairs({
        ["Print"] = "", ["ALT + Print"] = " --window",
        ["SHIFT + Print"] = " --region", ["SUPER + Print"] = " --region",
    }) do
        eq("~/scripts/runenv screenshot" .. args, bind(keys).target.args, keys)
    end
end)

test("mic mute is system-wide and works on the lock screen", function()
    load()
    for _, k in ipairs({ "XF86AudioMicMute", "SUPER + SHIFT + M" }) do
        local b = bind(k)
        truthy(b.target.args:find("@DEFAULT_AUDIO_SOURCE@ toggle", 1, true), k)
        eq(true, b.opts.locked, k .. " locked")
    end
end)

test("the calculator doesn't open over the lock screen", function()
    load()
    eq(nil, bind("XF86Calculator").opts.locked)
end)

--------------------------------------------------------------------------------
-- Laptop lid (SPEC.md §5.2, §6.5)
--------------------------------------------------------------------------------
local function docked()
    S.monitor_list = { { name = "eDP-1" }, { name = "DP-1" } }
    local edp, dp = S.monitor_list[1], S.monitor_list[2]
    S.workspace_list = {
        { id = 1, monitor = edp }, { id = 2, monitor = edp },
        { id = 3, monitor = dp }, { id = -98, monitor = edp },
    }
end

local function lid(which)
    S.monitors, S.dispatched = {}, {}
    bind("switch:" .. which .. ":Lid Switch").target()
end

test("lid binds work on the lock screen", function()
    load()
    eq(true, bind("switch:on:Lid Switch").opts.locked)
    eq(true, bind("switch:off:Lid Switch").opts.locked)
end)

test("docked lid close disables the panel; open restores it and its workspaces", function()
    load()
    docked()
    lid("on")
    eq(1, #S.monitors)
    eq("eDP-1", S.monitors[1].output)
    eq(true, S.monitors[1].disabled)
    lid("off")
    eq(1, #S.monitors)
    eq("eDP-1", S.monitors[1].output)
    eq("preferred", S.monitors[1].mode)
    eq("auto", S.monitors[1].scale, "auto scale, not 1x on a HiDPI panel")
    eq(0, #S.dispatched, "workspaces wait for the panel to come back")
    fire("monitor.added", { name = "DP-2" })
    eq(0, #S.dispatched, "another monitor isn't the panel")
    fire("monitor.added", { name = "eDP-1" })
    eq(2, #S.dispatched, "the panel's two regular workspaces go back")
    eq(1, S.dispatched[1].args.workspace)
    eq(2, S.dispatched[2].args.workspace)
    eq("eDP-1", S.dispatched[1].args.monitor)
    S.dispatched = {}
    fire("monitor.added", { name = "eDP-1" })
    eq(0, #S.dispatched, "only once")
    eq(false, exists(LID_FILE), "the saved state is gone once restored")
end)

test("a reload with the lid closed keeps the panel off, and opening restores it", function()
    load()
    docked()
    lid("on")
    truthy(exists(LID_FILE), "the closed lid is saved")
    -- A reload: a new Lua state, the same Hyprland instance.
    load({ reload = true })
    eq(2, #S.monitors, "the catch-all plus the panel's disabled rule")
    eq("eDP-1", S.monitors[2].output)
    eq(true, S.monitors[2].disabled)
    docked()
    S.monitor_list[1].enabled = false
    lid("off")
    eq("eDP-1", S.monitors[1].output)
    eq("preferred", S.monitors[1].mode)
    fire("monitor.added", { name = "eDP-1" })
    eq(2, #S.dispatched, "the workspaces saved before the reload go back")
    eq(false, exists(LID_FILE))
end)

test("a lid state that can't be written is reported and not left behind", function()
    -- /dev/full accepts the open and fails the flush, like a full disk.
    local devfull = io.open("/dev/full", "w")
    if not devfull then
        return -- not every OS has /dev/full
    end
    devfull:close()
    load({ env = { HYPRLAND_INSTANCE_SIGNATURE = "sigfull" } })
    -- The state is written to a temporary file and renamed into place.
    assert(os.execute("mkdir -p '" .. tmp .. "/run/hypr/sigfull' && ln -sf /dev/full '" .. tmp .. "/run/hypr/sigfull/tide-lid.tmp'"))
    docked()
    lid("on")
    eq(1, #S.notifications, "notifications")
    truthy(S.notifications[1].text:find("closed-lid state", 1, true), S.notifications[1].text)
    eq(false, exists("run/hypr/sigfull/tide-lid"), "no state file appears")
    eq(false, exists("run/hypr/sigfull/tide-lid.tmp"), "the temporary file is cleaned up")
    eq(true, S.monitors[1].disabled, "the panel still turns off")
end)

test("a failed lid-state write never truncates the saved state", function()
    load()
    docked()
    lid("on")
    local f = assert(io.open(tmp .. "/" .. LID_FILE))
    local before = f:read("a")
    f:close()
    -- A second close, with different workspaces, whose write fails must
    -- leave the first state whole.
    table.remove(S.workspace_list, 1)
    assert(os.execute("ln -sf /dev/full '" .. tmp .. "/" .. LID_FILE .. ".tmp'"))
    lid("on")
    f = assert(io.open(tmp .. "/" .. LID_FILE))
    eq(before, f:read("a"), "the saved state is unchanged")
    f:close()
    assert(os.execute("rm -f '" .. tmp .. "/" .. LID_FILE .. ".tmp'"))
end)

test("a lid state that can't be cleared is reported", function()
    load()
    docked()
    lid("on")
    lid("off")
    -- A non-empty directory in its place makes the removal fail.
    remove(LID_FILE)
    assert(os.execute("mkdir -p '" .. tmp .. "/" .. LID_FILE .. "/x'"))
    fire("monitor.added", { name = "eDP-1" })
    eq(1, #S.notifications, "notifications")
    truthy(S.notifications[1].text:find("couldn't clear the closed-lid state", 1, true), S.notifications[1].text)
    assert(os.execute("rm -rf '" .. tmp .. "/" .. LID_FILE .. "'"))
end)

test("an unreadable lid state is reported, and the rest of the config still loads", function()
    load()
    assert(os.execute("mkdir -p '" .. tmp .. "/" .. LID_FILE .. "'"))
    load({ reload = true })
    eq(1, #S.notifications, "notifications")
    truthy(S.notifications[1].text:find("couldn't read", 1, true), S.notifications[1].text)
    eq(1, #S.monitors, "no disabled rule from it")
    truthy(S.rules.pip, "later sections still ran")
    bind("switch:off:Lid Switch")
    assert(os.execute("rm -rf '" .. tmp .. "/" .. LID_FILE .. "'"))
end)

test("a malformed lid state is reported and discarded", function()
    load()
    write(LID_FILE, "eDP-1\nnot-a-workspace\n")
    load({ reload = true })
    eq(1, #S.notifications, "notifications")
    truthy(S.notifications[1].text:find("malformed", 1, true), S.notifications[1].text)
    eq(1, #S.monitors, "no disabled rule from it")
    eq(false, exists(LID_FILE), "discarded")
    write(LID_FILE, "")
    load({ reload = true })
    eq(1, #S.notifications, "an empty file is malformed too")
end)

test("a new session ignores another instance's saved lid", function()
    load()
    docked()
    lid("on")
    load({ reload = true, env = { HYPRLAND_INSTANCE_SIGNATURE = "sig2" } })
    eq(1, #S.monitors, "only the catch-all rule")
end)

test("with no saved state, opening the lid turns on an internal panel that is off", function()
    load({ env = { XDG_RUNTIME_DIR = "" } })
    S.monitor_list = { { name = "eDP-1", enabled = false }, { name = "DP-1" } }
    lid("off")
    eq(1, #S.monitors)
    eq("eDP-1", S.monitors[1].output)
    eq("preferred", S.monitors[1].mode)
    fire("monitor.added", { name = "eDP-1" })
    S.monitor_list = { { name = "eDP-1" }, { name = "DP-1" } }
    lid("off")
    eq(0, #S.monitors, "an enabled panel is left alone")
end)

test("undocked lid close leaves suspend to logind", function()
    load()
    S.monitor_list = { { name = "eDP-1" } }
    lid("on")
    eq(0, #S.monitors, "no monitor rule")
    eq(0, #S.execs, "no suspend from the config")
    lid("off")
    eq(0, #S.monitors, "nothing to restore")
end)

test("HYPR_INTERNAL_OUTPUT names the panel", function()
    load({ env = { HYPR_INTERNAL_OUTPUT = "DP-9" } })
    S.monitor_list = { { name = "DP-9" }, { name = "HDMI-A-1" } }
    lid("on")
    eq("DP-9", S.monitors[1].output)
end)

test("a desktop with no internal panel ignores the lid", function()
    load()
    S.monitor_list = { { name = "DP-1" }, { name = "DP-2" } }
    lid("on")
    eq(0, #S.monitors)
end)

--------------------------------------------------------------------------------
-- Window rules (SPEC.md §6.2, §6.4)
--------------------------------------------------------------------------------
test("dialogs float centered", function()
    load()
    for _, name in ipairs({ "float-modal", "float-pavucontrol", "float-nm-connection-editor",
                            "float-blueman-manager", "float-portal-file-chooser",
                            "float-file-dialog-title" }) do
        local r = S.rules[name]
        truthy(r, name)
        eq(true, r.float, name .. " float")
        eq(true, r.center, name .. " center")
    end
    eq(true, S.rules["float-modal"].match.modal)
    local title = S.rules["float-file-dialog-title"].match.title
    for _, t in ipairs({ "Open File", "Save File", "Save As" }) do
        truthy(title:find(t, 1, true), t)
    end
end)

test("picture-in-picture floats, pinned, undimmed", function()
    load()
    local r = S.rules.pip
    eq(true, r.float)
    eq(true, r.pin)
    eq(true, r.no_dim)
end)

test("a lone window and video never dim", function()
    load()
    eq("w[tv1]", S.rules["no-dim-lone-window"].match.workspace)
    eq(true, S.rules["no-dim-lone-window"].no_dim)
    eq("video", S.rules["no-dim-video"].match.content)
end)

--------------------------------------------------------------------------------
-- Autostart
--------------------------------------------------------------------------------
test("Super+L locks through logind in the tide session, with hyprlock outside it", function()
    load({ env = { XDG_CURRENT_DESKTOP = "tide:Hyprland" } })
    eq("loginctl lock-session", bind("SUPER + L").target.args)
    load()
    eq("hyprlock", bind("SUPER + L").target.args)
end)

test("the tide session's autostart is uwsm finalize alone", function()
    load({ env = { XDG_CURRENT_DESKTOP = "tide:Hyprland" } })
    fire("hyprland.start")
    eq(1, #S.execs, "one command")
    eq("uwsm finalize", S.execs[1])
end)

test("in the tide session, app keys go through tide launch", function()
    load({ env = { XDG_CURRENT_DESKTOP = "tide:Hyprland" } })
    eq("tide launch --app 'kitty' -- kitty", bind("SUPER + T").target.args)
    eq("tide launch --app '*' -- ~/scripts/runenv browser1", bind("SUPER + G").target.args)
    eq("tide launch --app 'org.gnome.Calculator' -- gnome-calculator", bind("XF86Calculator").target.args)
    -- Not apps: these stay plain commands.
    eq("qs -c tide ipc call notifications toggle || swaync-client -t -sw", bind("SUPER + SHIFT + N").target.args)
end)

test("Super+Shift+N opens tide's notification center, else swaync's", function()
    load()
    local cmd = bind("SUPER + SHIFT + N").target.args
    -- Run the binding's shell with fakes: swaync's panel opens only when
    -- the call to the shell fails.
    for status, fallback in pairs({ [0] = false, [1] = true, [255] = true, [127] = true }) do
        -- swaync-client isn't a name dash takes for a function, so it's a
        -- script on PATH.
        local script = "d=$(mktemp -d) || exit 1; printf '#!/bin/sh\\necho fallback\\n' >\"$d/swaync-client\"; "
            .. "chmod +x \"$d/swaync-client\"; PATH=\"$d:$PATH\"; "
            .. "qs() { echo \"$*\"; return " .. status .. "; }; " .. cmd .. "; rm -rf \"$d\""
        local p = io.popen("sh -c '" .. script:gsub("'", "'\\''") .. "'")
        local out = p:read("a")
        p:close()
        truthy(out:find("-c tide ipc call notifications toggle", 1, true), "qs called")
        eq(fallback, out:find("fallback", 1, true) ~= nil, "fallback after exit " .. status)
    end
end)

test("Super+Space opens tide's launcher, else fuzzel", function()
    load()
    local cmd = bind("SUPER + Space").target.args
    -- Run the binding's shell with fakes: fuzzel's script runs only when the
    -- call to the shell fails. HOME points ~/scripts/runenv at a fake.
    for status, fallback in pairs({ [0] = false, [1] = true, [255] = true, [127] = true }) do
        local script = "d=$(mktemp -d) || exit 1; mkdir \"$d/scripts\"; "
            .. "printf '#!/bin/sh\\necho fallback \"$@\"\\n' >\"$d/scripts/runenv\"; "
            .. "chmod +x \"$d/scripts/runenv\"; HOME=\"$d\"; "
            .. "qs() { echo \"$*\"; return " .. status .. "; }; " .. cmd .. "; rm -rf \"$d\""
        local p = io.popen("sh -c '" .. script:gsub("'", "'\\''") .. "'")
        local out = p:read("a")
        p:close()
        truthy(out:find("-c tide ipc call launcher toggle", 1, true), "qs called")
        eq(fallback, out:find("fallback", 1, true) ~= nil, "fallback after exit " .. status)
        if fallback then
            truthy(out:find("launch-fuzzel.sh", 1, true), "fallback is fuzzel")
        end
    end
end)

test("outside the tide session, app keys run the command itself", function()
    load({ env = { XDG_CURRENT_DESKTOP = "Hyprland" } })
    eq("kitty", bind("SUPER + T").target.args)
    eq("~/scripts/runenv browser1", bind("SUPER + G").target.args)
end)

test("autostart runs on hyprland.start, not at load", function()
    load()
    eq(0, #S.execs, "nothing runs while the config loads")
    fire("hyprland.start")
    local all = table.concat(S.execs, "\n")
    for _, cmd in ipairs({ "hypridle", "swww-daemon", "runenv ~/.config/hypr/scripts/apply-input.sh",
        "theme-daemon.sh", "nm-applet" }) do
        truthy(all:find(cmd, 1, true), cmd)
    end
end)

test("a config reload puts the mouse settings back, in either session", function()
    for _, desktop in ipairs({ "tide:Hyprland", "Hyprland" }) do
        load({ env = { XDG_CURRENT_DESKTOP = desktop } })
        fire("config.reloaded")
        eq(1, #S.execs, desktop .. ": one command")
        truthy(S.execs[1]:find("runenv ~/.config/hypr/scripts/apply-input.sh", 1, true),
            desktop .. ", with ~/.env.local: " .. S.execs[1])
    end
end)

--------------------------------------------------------------------------------
-- Per-machine overrides
--------------------------------------------------------------------------------
test("hyprland.local.lua loads last, so its settings win", function()
    load({ ["local"] = "hl.config({ decoration = { dim_strength = 0.25 } })\nhl.unbind('SUPER + E')\nhl.bind('SUPER + E', hl.dsp.exec_cmd('nautilus'))" })
    eq(0.25, S.config.decoration.dim_strength)
    eq("nautilus", bind("SUPER + E").target.args)
    -- Nothing from the shared config comes after the local file's calls.
    local last = S.calls[#S.calls]
    eq("bind", last[1])
    eq("SUPER + E", last[2])
end)

test("a broken hyprland.local.lua is reported, and the shared config stands", function()
    load({ ["local"] = "this is not lua" })
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("hyprland.local.lua (none of it applied)", 1, true))
    eq(0.07, S.config.decoration.dim_strength)
end)

test("a hyprland.local.lua that fails partway says what applied", function()
    load({ ["local"] = 'hl.config({ decoration = { dim_strength = 0.3 } })\nerror("late")' })
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("the calls before this applied", 1, true), S.notifications[1].text)
    truthy(S.notifications[1].text:find("late", 1, true))
end)

-- The hl.device() calls since the last mark, as their tables.
local function devices()
    local out = {}
    for _, c in ipairs(S.calls) do
        if c[1] == "device" then
            table.insert(out, c[2])
        end
    end
    return out
end

test("apply-input's conf_input.mouse makes a mouse left-handed with its wheel speed", function()
    load()
    S.calls = {}
    conf_input.mouse("logitech-usb-receiver", 3)
    local d = devices()
    eq(1, #d)
    eq("logitech-usb-receiver", d[1].name)
    eq(true, d[1].left_handed)
    eq(3, d[1].scroll_factor)
end)

test("conf_input.mouse leaves alone what hyprland.local.lua set for that mouse", function()
    load({ ["local"] = 'hl.device({ name = "logitech usb receiver", left_handed = false })\n'
        .. 'hl.device({ name = "trackball", left_handed = false, scroll_factor = 0.5 })' })
    eq(2, #devices(), "the local file's own calls still reach Hyprland")
    S.calls = {}
    conf_input.mouse("logitech-usb-receiver", 3)
    conf_input.mouse("trackball", 3)
    conf_input.mouse("other-mouse", 3)
    local d = devices()
    eq(nil, d[1].left_handed, "its handedness is the local file's (spaces as dashes)")
    eq(3, d[1].scroll_factor, "but the wheel speed still applies")
    eq(nil, d[2].left_handed, "both set locally")
    eq(nil, d[2].scroll_factor, "both set locally")
    eq(true, d[3].left_handed, "a mouse the local file didn't name")
end)

test("only hyprland.local.lua's own hl.device calls are recorded", function()
    load({ ["local"] = 'hl.device({ name = "trackball", left_handed = false })\nerror("late")' })
    eq(1, #S.notifications, "the error is reported")
    hl.device({ name = "mouse", left_handed = false })
    S.calls = {}
    conf_input.mouse("trackball", 3)
    conf_input.mouse("mouse", 3)
    local d = devices()
    eq(nil, d[1].left_handed, "a call before the error counts")
    eq(true, d[2].left_handed, "a call after loading doesn't")
end)

-- tide's settings (tide SPEC.md §16), as tide writes them.
local TIDE_SETTINGS = [[
return {
    mouse = { sensitivity = -0.5, scroll_factor = 2, natural_scroll = false, left_handed = false },
    touchpad = {
        sensitivity = 0.25, scroll_factor = 0.75, natural_scroll = false, left_handed = true,
        tap_to_click = false, disable_while_typing = false,
    },
    keyboard = { kb_layout = "us,de", kb_variant = "dvorak,", repeat_delay = 300, repeat_rate = 40 },
}
]]

test("without tide's input settings, the config's own stand", function()
    load()
    eq("us", S.config.input.kb_layout)
    eq("dvorak", S.config.input.kb_variant)
    eq(true, S.config.input.touchpad.tap_to_click)
    eq(0, #S.notifications)
    S.calls = {}
    conf_input.touchpad("synps/2-synaptics-touchpad")
    local d = devices()
    eq(1, #d)
    eq(1.0, d[1].sensitivity, "a touchpad takes the global settings")
    eq(false, d[1].left_handed)
end)

test("tide's keyboard and touchpad settings apply over the config's", function()
    load({ input = TIDE_SETTINGS })
    eq(0, #S.notifications)
    eq("us,de", S.config.input.kb_layout)
    eq("dvorak,", S.config.input.kb_variant)
    eq(300, S.config.input.repeat_delay)
    eq(40, S.config.input.repeat_rate)
    eq(false, S.config.input.touchpad.tap_to_click)
    eq(false, S.config.input.touchpad.disable_while_typing)
    eq(false, S.config.input.touchpad.natural_scroll)
    eq(0.75, S.config.input.touchpad.scroll_factor)
    eq(nil, S.config.input.touchpad.sensitivity, "speed and handedness are per touchpad")
    eq("compose:caps,altwin:menu_win", S.config.input.kb_options, "what tide doesn't set stays")
end)

test("each mouse takes tide's mouse settings, and each touchpad its own", function()
    load({ input = TIDE_SETTINGS })
    S.calls = {}
    conf_input.mouse("logitech-usb-receiver", 3)
    conf_input.touchpad("synps/2-synaptics-touchpad")
    local d = devices()
    eq(2, #d)
    eq(false, d[1].left_handed, "tide's handedness over the default")
    eq(2, d[1].scroll_factor, "tide's wheel speed over the script's")
    eq(-0.5, d[1].sensitivity)
    eq(false, d[1].natural_scroll)
    eq(true, d[2].left_handed)
    eq(0.25, d[2].sensitivity)
    eq(false, d[2].tap_to_click, "the touchpad section's options, as input.touchpad has them")
end)

local TIDE_DEVICES = [[
return {
    mouse = { sensitivity = -0.5, left_handed = false },
    touchpad = { tap_to_click = false },
    devices = {
        ["logitech-usb-receiver"] = { sensitivity = 0.75, left_handed = true },
        ["synps/2-synaptics-touchpad"] = { tap_to_click = true, sensitivity = -0.25 },
    },
}
]]

test("a device tide's settings name gets its own over its kind's", function()
    load({ input = TIDE_DEVICES })
    eq(0, #S.notifications)
    S.calls = {}
    conf_input.mouse("logitech-usb-receiver", 3)
    conf_input.mouse("other-mouse", 3)
    conf_input.touchpad("synps/2-synaptics-touchpad")
    local d = devices()
    eq(3, #d)
    eq(0.75, d[1].sensitivity, "its own speed")
    eq(true, d[1].left_handed, "its own handedness")
    eq(3, d[1].scroll_factor, "the rest as every mouse's")
    eq(-0.5, d[2].sensitivity, "another mouse keeps every mouse's")
    eq(false, d[2].left_handed)
    eq(-0.25, d[3].sensitivity)
    eq(true, d[3].tap_to_click, "a touchpad section option, for this touchpad alone")
    eq(false, S.config.input.touchpad.tap_to_click, "every other touchpad keeps tide's")
end)

test("a mouse takes only a mouse's settings of its own, so none stays set once gone", function()
    load({ input = 'return { devices = { trackball = { tap_to_click = false, disable_while_typing = false, sensitivity = 0.5 } } }' })
    eq(0, #S.notifications)
    S.calls = {}
    conf_input.mouse("trackball", 3)
    local d = devices()
    eq(0.5, d[1].sensitivity)
    eq(nil, d[1].tap_to_click)
    eq(nil, d[1].disable_while_typing)
end)

test("a device's own setting that tide stops making goes back to its kind's on reload", function()
    load({ input = TIDE_DEVICES })
    write(TIDE_INPUT, 'return { mouse = { sensitivity = -0.5, left_handed = false }, touchpad = { tap_to_click = false } }')
    conf_input.reload()
    S.calls = {}
    conf_input.mouse("logitech-usb-receiver", 3)
    conf_input.touchpad("synps/2-synaptics-touchpad")
    local d = devices()
    eq(-0.5, d[1].sensitivity)
    eq(false, d[1].left_handed)
    eq(1.0, d[2].sensitivity)
    eq(false, d[2].tap_to_click, "tide's touchpad setting again")
end)

test("hyprland.local.lua still wins over a device's own tide settings", function()
    load({
        input = TIDE_DEVICES,
        ["local"] = 'hl.device({ name = "synps/2-synaptics-touchpad", tap_to_click = false })\n'
            .. 'hl.config({ input = { touchpad = { disable_while_typing = false } } })',
    })
    S.calls = {}
    conf_input.touchpad("synps/2-synaptics-touchpad")
    local d = devices()
    eq(nil, d[1].tap_to_click, "the local file's field for that touchpad")
    eq(-0.25, d[1].sensitivity, "its own tide setting for the rest")
    eq(false, d[1].disable_while_typing, "the local file's touchpad option, as input.touchpad has it")
end)

test("a devices table that isn't one, or a bad device setting, is reported and left out", function()
    load({ input = 'return { devices = 5, mouse = { sensitivity = 0.5 } }' })
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("devices should be a table", 1, true), S.notifications[1].text)
    load({ input = 'return { devices = { trackball = { speed = 1, left_handed = "yes", sensitivity = 0.5 }, [1] = {} } }' })
    eq(3, #S.notifications)
    local texts = {}
    for _, n in ipairs(S.notifications) do
        texts[#texts + 1] = n.text
    end
    local all = table.concat(texts, "\n")
    truthy(all:find("unknown setting devices.trackball.speed", 1, true), all)
    truthy(all:find("devices.trackball.left_handed should be a boolean", 1, true), all)
    truthy(all:find("devices.1 should be a table of settings", 1, true), all)
    S.calls = {}
    conf_input.mouse("trackball", 3)
    eq(0.5, devices()[1].sensitivity, "its good setting still applies")
end)

test("hyprland.local.lua still wins over tide's settings, per device and in input", function()
    load({
        input = TIDE_SETTINGS,
        ["local"] = 'hl.device({ name = "logitech usb receiver", sensitivity = 0.9 })\n'
            .. 'hl.config({ input = { kb_layout = "fr", touchpad = { tap_to_click = true } } })',
    })
    eq("fr", S.config.input.kb_layout)
    eq(true, S.config.input.touchpad.tap_to_click)
    S.calls = {}
    conf_input.mouse("logitech-usb-receiver", 3)
    eq(nil, devices()[1].sensitivity, "the local file's speed for that mouse")
    eq(false, devices()[1].left_handed, "tide's for the rest")
    -- A change to tide's settings reapplies them, but not over the local file.
    S.calls, S.execs = {}, {}
    conf_input.reload()
    eq("fr", S.config.input.kb_layout)
    eq(true, S.config.input.touchpad.tap_to_click)
    eq("us,de", (function()
        for _, c in ipairs(S.calls) do
            if c[1] == "config" and c[2].input and c[2].input.kb_variant then
                return "us,de"
            end
        end
    end)(), "the rest of tide's settings reapply")
end)

test("a setting tide stops making goes back to the config's on reload", function()
    load({ input = TIDE_SETTINGS })
    write(TIDE_INPUT, "return {}")
    conf_input.reload()
    eq("us", S.config.input.kb_layout)
    eq("dvorak", S.config.input.kb_variant)
    eq(600, S.config.input.repeat_delay)
    eq(true, S.config.input.touchpad.tap_to_click)
    eq(1.0, S.config.input.touchpad.scroll_factor)
    S.calls = {}
    conf_input.mouse("logitech-usb-receiver", 3)
    conf_input.touchpad("synps/2-synaptics-touchpad")
    local d = devices()
    eq(true, d[1].left_handed, "a mouse is left-handed again")
    eq(3, d[1].scroll_factor, "with the script's wheel speed")
    eq(1.0, d[1].sensitivity, "and the global speed")
    eq(false, d[1].natural_scroll)
    eq(false, d[2].left_handed, "a touchpad is right-handed again")
    eq(1.0, d[2].sensitivity)
    -- And the same with no file at all.
    os.remove(tmp .. "/" .. TIDE_INPUT)
    conf_input.reload()
    eq("us", S.config.input.kb_layout)
end)

test("a device's default follows a global the local file changed", function()
    load({ ["local"] = 'hl.config({ input = { sensitivity = 0.5, left_handed = true } })' })
    S.calls = {}
    conf_input.touchpad("synps/2-synaptics-touchpad")
    conf_input.mouse("logitech-usb-receiver", 3)
    local d = devices()
    eq(0.5, d[1].sensitivity)
    eq(true, d[1].left_handed)
    eq(0.5, d[2].sensitivity)
    -- tide's settings for a kind of device are more specific than a global,
    -- as the mouse's own left-handed default is, so they apply over it.
    load({ input = TIDE_SETTINGS, ["local"] = 'hl.config({ input = { sensitivity = 0.5, left_handed = true } })' })
    eq(0.5, S.config.input.sensitivity, "the global stays the local file's")
    S.calls = {}
    conf_input.touchpad("synps/2-synaptics-touchpad")
    conf_input.mouse("logitech-usb-receiver", 3)
    d = devices()
    eq(0.25, d[1].sensitivity, "tide's touchpad speed")
    eq(-0.5, d[2].sensitivity, "tide's mouse speed")
    eq(false, d[2].left_handed, "tide's mouse handedness")
end)

test("conf_input.reload reads tide's settings again and reapplies every device", function()
    load()
    write(TIDE_INPUT, TIDE_SETTINGS)
    S.execs = {}
    conf_input.reload()
    eq("us,de", S.config.input.kb_layout)
    eq(1, #S.execs)
    truthy(S.execs[1]:find("apply-input.sh", 1, true), "apply-input.sh runs again: " .. tostring(S.execs[1]))
    S.calls = {}
    conf_input.touchpad("synps/2-synaptics-touchpad")
    eq(0.25, devices()[1].sensitivity)
end)

test("a broken tide-input.lua is reported and applies nothing", function()
    load({ input = "return {" })
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("tide-input.lua (none of it applied)", 1, true), S.notifications[1].text)
    eq("us", S.config.input.kb_layout)
    load({ input = "return 5" })
    truthy(S.notifications[1].text:find("expected a table", 1, true), S.notifications[1].text)
end)

test("tide-input.lua is data: it can't reach anything", function()
    load({ input = 'os.execute("true") return {}' })
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("none of it applied", 1, true), S.notifications[1].text)
end)

test("a setting of the wrong type or name is reported and left out", function()
    load({ input = 'return { keyboard = { kb_layout = 5, repeat_rate = 30 }, mouse = { speed = 1 } }' })
    eq(2, #S.notifications)
    eq("us", S.config.input.kb_layout, "the bad one is left out")
    eq(30, S.config.input.repeat_rate, "the good one applies")
    load({ input = 'return { keybord = { kb_layout = "de" }, keyboard = { repeat_rate = 30 } }' })
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("unknown section keybord", 1, true), S.notifications[1].text)
    eq(30, S.config.input.repeat_rate, "the known section still applies")
end)

test("an unreadable hyprland.local.lua is reported, not taken as absent", function()
    load()
    assert(os.execute("mkdir -p '" .. tmp .. "/" .. LOCAL .. "'"))
    load({ keep_files = true })
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("hyprland.local.lua: couldn't read", 1, true), S.notifications[1].text)
    eq(0.07, S.config.decoration.dim_strength)
end)

test("an optional file whose close fails is reported and not used", function()
    load({ ["local"] = 'hl.config({ decoration = { dim_strength = 0.3 } })' })
    local real_open = io.open
    io.open = function(path, mode)
        local f, err, code = real_open(path, mode)
        if f and path:sub(-#LOCAL) == LOCAL then
            return {
                read = function(_, ...) return f:read(...) end,
                close = function() f:close(); return nil, "Input/output error", 5 end,
            }
        end
        return f, err, code
    end
    local ok, err = pcall(load, { keep_files = true })
    io.open = real_open
    assert(ok, err)
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("hyprland.local.lua: couldn't close", 1, true), S.notifications[1].text)
    eq(0.07, S.config.decoration.dim_strength)
end)

test("the template is all comments, and loads cleanly as a local file", function()
    local f = assert(io.open(here .. "/hyprland.local.lua.template"))
    local body = f:read("a")
    f:close()
    for line in body:gmatch("[^\n]+") do
        truthy(line:match("^%s*%-%-") or line:match("^%s*$"), "active line: " .. line)
    end
    load({ ["local"] = body })
    eq(0, #S.notifications)
end)

os.execute("rm -rf '" .. tmp .. "'")
io.write(string.format("hyprland_test.lua: %d passed, %d failed\n", passes, failures))
os.exit(failures == 0 and 0 or 1)
