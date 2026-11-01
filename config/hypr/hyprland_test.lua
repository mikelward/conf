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
local SPAN = ".config/hypr/tide/span.lua"
local LOCAL = ".config/hypr/hyprland.local.lua"
local TIDE_INPUT = ".config/hypr/tide-input.lua"
local TIDE_OUTPUTS = ".config/hypr/tide-outputs.lua"
local TIDE_APPEARANCE = ".config/hypr/tide-appearance.lua"
local TIDE_POWER = ".config/hypr/tide-power.lua"
local TIDE_WORKSPACES = ".config/hypr/tide-workspaces.lua"
local TIDE_FLOATING = ".config/hypr/tide-floating.lua"
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
                     "add_master", "remove_master", "swap_with_master", "focus", "move",
                     "focus_side", "move_side", "drag_press", "drag_release" }) do
    M[n] = helper(n)
end
function M.setup(opts) M.setup_opts = opts end
_G.fake_layout = M
return M
]]

-- A stand-in for tide's span.lua (tide SPEC.md §6.5, Monitors), to its
-- contract: NAME on the main monitor, NAME@OUT on the others, and a switch
-- showing the focused monitor's part last.
local FAKE_SPAN = [[
local M = {}
function M.part(name, output, main)
    return output == main and name or name .. "@" .. output
end
function M.split(n)
    if n == "" or n:find("^special:") then return nil end
    local name, output = n:match("^(.+)@([^@]+)$")
    if name then return name, output end
    return n, nil
end
function M.rules(name, outputs, main)
    local out = {}
    for _, o in ipairs(outputs) do
        table.insert(out, { workspace = "name:" .. M.part(name, o, main), monitor = o })
    end
    return out
end
function M.switch(name, outputs, main, focused)
    local out = {}
    for _, o in ipairs(outputs) do
        if o ~= focused then table.insert(out, { output = o, workspace = "name:" .. M.part(name, o, main) }) end
    end
    table.insert(out, { output = focused, workspace = "name:" .. M.part(name, focused, main) })
    return out
end
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
        -- The monitor rules as Hyprland keeps them, which monitors above
        -- doesn't (tests clear it); see rule_for.
        monitor_rules = {},
        rules = {}, layer_rules = {}, workspace_rules = {},
        -- What the getters return; set per test.
        active_workspace = nil,
        active_window = nil,
        -- hl.get_monitor("l") and ("r"): { l = monitor, r = monitor }.
        monitor_that_way = nil,
        monitor_list = {},
        workspace_list = {},
    }
    local submap = ""
    local function record(fn, a)
        table.insert(S.calls, { fn, a })
    end
    return {
        config = function(t) record("config", t); merge(S.config, t) end,
        monitor = function(t)
            record("monitor", t)
            table.insert(S.monitors, t)
            -- As Hyprland 0.56 keeps them: a rule for an output that already
            -- has one starts from that one's fields, and goes last.
            local rule = {}
            for i, r in ipairs(S.monitor_rules) do
                if r.output == t.output then
                    rule = table.remove(S.monitor_rules, i)
                    break
                end
            end
            for k, v in pairs(t) do
                rule[k] = v
            end
            table.insert(S.monitor_rules, rule)
        end,
        env = function(k, v) record("env", k); S.config.env = S.config.env or {}; S.config.env[k] = v end,
        device = function(t) record("device", t) end,
        gesture = function(t) record("gesture", t); S.gesture = t end,
        curve = function(n, t) record("curve", n) end,
        animation = function(t) record("animation", t) end,
        -- As Hyprland 0.56.2 keeps them (hlWindowRule): a rule given a name
        -- it has merges into that one. Each match given replaces the old
        -- one, a match not given stays, `enabled` is set (true unless
        -- given false), and each effect is added again, which `added`
        -- counts.
        window_rule = function(t)
            record("window_rule", t)
            local rule = S.rules[t.name]
            if not rule then
                rule = { match = {}, added = {} }
                S.rules[t.name] = rule
            end
            rule.name = t.name
            rule.enabled = t.enabled ~= false
            for k, v in pairs(t.match or {}) do
                rule.match[k] = v
            end
            for k, v in pairs(t) do
                if k ~= "name" and k ~= "enabled" and k ~= "match" then
                    rule[k] = v
                    rule.added[k] = (rule.added[k] or 0) + 1
                end
            end
        end,
        -- As Hyprland 0.56.2 keeps them (WorkspaceRuleManager's
        -- replaceOrAdd): a rule for a workspace that has an enabled one is
        -- merged into it, its fields over the old ones', except `enabled`,
        -- which the merge doesn't copy. Each call returns the rule's
        -- handle, whose set_enabled turns it on or off.
        workspace_rule = function(t)
            record("workspace_rule", t)
            local rule = S.workspace_rules[t.workspace]
            if not rule or rule.enabled == false then
                rule = { enabled = t.enabled ~= false }
                S.workspace_rules[t.workspace] = rule
            end
            for k, v in pairs(t) do
                if k ~= "enabled" then
                    rule[k] = v
                end
            end
            return { set_enabled = function(_, on) rule.enabled = on end }
        end,
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
            -- Hyprland keeps a key's press and release binds apart, so the
            -- stub files a release bind under "release:KEYS".
            local id = submap .. "|" .. ((opts or {}).release and "release:" or "") .. keys
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
        get_active_monitor = function() return S.active_monitor end,
        get_active_window = function()
            if S.active_window == "raise" then error("window gone") end
            return S.active_window
        end,
        get_urgent_window = function()
            if S.urgent_window == "raise" then error("window gone") end
            return S.urgent_window
        end,
        -- Disabled monitors are listed only with { all = true }. Hyprland
        -- 0.56.2 lists them never, whatever it's passed (its hlGetMonitors);
        -- `on_only` has the stub do the same. The lid's fallback test
        -- predates finding that out (TODO.md, "Find a docked panel that's
        -- off").
        get_monitors = function(opts)
            local out = {}
            for _, m in ipairs(S.monitor_list) do
                if (opts and opts.all and not S.on_only) or m.enabled ~= false then
                    table.insert(out, m)
                end
            end
            return out
        end,
        get_workspaces = function() return S.workspace_list end,
        -- By name, or desc: and the start of the short description or the
        -- full one (`full_description`, which hl.get_monitors doesn't give),
        -- as Hyprland resolves a selector; enabled monitors only. Hyprland
        -- gives an HL.Monitor userdata: a file handle given its own
        -- metatable stands in for one, so a check for a table fails here too.
        get_monitor = function(selector)
            local function userdata(m)
                local u = io.tmpfile()
                debug.setmetatable(u, { __index = function(_, k) return m[k] end })
                return u
            end
            -- A direction, from the focused monitor: S.monitor_that_way.
            if selector == "l" or selector == "r" then
                if S.monitor_that_way == "raise" then error("monitors gone") end
                local m = (S.monitor_that_way or {})[selector]
                return m and userdata(m)
            end
            local desc = selector:match("^desc:%s*(.-)%s*$")
            for _, m in ipairs(S.monitor_list) do
                if m.enabled ~= false then
                    if desc then
                        for _, d in ipairs({ m.description or "", m.full_description or "" }) do
                            if d:sub(1, #desc) == desc then
                                return userdata(m)
                            end
                        end
                    elseif m.name == selector then
                        return userdata(m)
                    end
                end
            end
            return nil
        end,
    }
end

-- A fresh Hyprland instance each time, unless `reload` asks for the same one
-- (whose lid state file survives).
local function load(setup)
    if not (setup and setup.keep_files) then
        assert(os.execute("rm -rf '" .. tmp .. "/" .. LAYOUT .. "' '" .. tmp .. "/" .. LOCAL .. "' '" .. tmp .. "/" .. TIDE_INPUT .. "' '" .. tmp .. "/" .. TIDE_OUTPUTS .. "' '" .. tmp .. "/" .. TIDE_APPEARANCE .. "' '" .. tmp .. "/" .. TIDE_WORKSPACES .. "' '" .. tmp .. "/" .. TIDE_POWER .. "' '" .. tmp .. "/" .. TIDE_FLOATING .. "'"))
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
        os.remove(tmp .. "/" .. SPAN)
    end
    if setup and setup.span then
        write(SPAN, setup.span)
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
    if setup and setup.outputs then
        write(TIDE_OUTPUTS, setup.outputs)
    end
    if setup and setup.appearance then
        write(TIDE_APPEARANCE, setup.appearance)
    end
    if setup and setup.workspaces then
        write(TIDE_WORKSPACES, setup.workspaces)
    end
    if setup and setup.power then
        write(TIDE_POWER, setup.power)
    end
    if setup and setup.floating then
        write(TIDE_FLOATING, setup.floating)
    end
    env_overrides = { XDG_RUNTIME_DIR = tmp .. "/run", HYPRLAND_INSTANCE_SIGNATURE = "sig1", XDG_CURRENT_DESKTOP = false }
    for k, v in pairs((setup and setup.env) or {}) do
        env_overrides[k] = v
    end
    _G.fake_layout = nil
    _G.hl = new_hl()
    -- Monitors already connected as the config loads, as on a reload.
    if setup and setup.monitors then
        S.monitor_list = setup.monitors
    end
    dofile(config_path)
    return S
end

-- The rule Hyprland 0.56 uses for monitor `m` ({ name, description }): the
-- last one added that names it, by its name or desc: and the start of its
-- description, else the catch-all.
local function rule_for(m)
    for i = #S.monitor_rules, 1, -1 do
        local r = S.monitor_rules[i]
        local desc = r.output:match("^desc:(.*)$")
        if r.output == m.name or (desc and (m.description or ""):sub(1, #desc) == desc) then
            return r
        end
    end
    for _, r in ipairs(S.monitor_rules) do
        if r.output == "" then
            return r
        end
    end
    return nil
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
    eq("swapwithmaster master", bind("ALT + Tab").target.args)
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
    eq(qs.toggle_monocle, bind("SUPER + O").target, "Super+O")
    eq(qs.grow, bind("SUPER + backslash").target, "Super+\\")
    eq(qs.shrink, bind("SUPER + slash").target, "Super+/")
    eq(qs.swap_with_master, bind("ALT + Tab").target, "Alt+Tab")
    run("SUPER + J")
    run("SUPER + SHIFT + K")
    eq("focus", qs.calls[1][1])
    eq(1, qs.calls[1][2])
    eq("move", qs.calls[2][1])
    eq(-1, qs.calls[2][2])
end)

test("floating windows resize from an 8 px zone outside their edges", function()
    load()
    local g = S.config.general
    eq(true, g.resize_on_border, "resize_on_border")
    eq(8, g.extend_border_grab_area, "extend_border_grab_area")
    eq(true, g.hover_icon_on_border, "a resize cursor on hover")
end)

test("with the tide layout, a plain left-drag on a split edge is the layout's", function()
    load({ layout = FAKE_LAYOUT })
    local qs = _G.fake_layout
    local press, release = bind("mouse:272"), bind("release:mouse:272")
    eq(qs.drag_press, press.target, "press")
    eq(nil, press.opts.non_consuming, "the press is taken only when drag_press says so")
    eq(qs.drag_release, release.target, "release")
    eq(true, release.opts.release, "on release")
    eq(true, release.opts.non_consuming, "a release never takes a click")
    eq(true, release.opts.ignore_mods, "Shift pressed mid-drag still ends it")
    eq(true, release.opts.locked, "so does locking mid-drag")
    eq(qs.grow, bind("SUPER + backslash").target, "the keys still resize too")
end)

test("without the drag helpers, the plain left button stays unbound", function()
    load()
    eq(nil, S.binds["|mouse:272"], "master fallback")
    load({ layout = FAKE_LAYOUT:gsub('"drag_press", "drag_release" ', "") })
    eq("lua:tide", S.config.general.layout, "an older layout still loads")
    eq(nil, S.binds["|mouse:272"], "older layout: press")
    eq(nil, S.binds["|release:mouse:272"], "older layout: release")
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
        "SUPER + Space", "SUPER + T", "SUPER + W", "SUPER + V", "SUPER + G", "SUPER + F",
        "SUPER + SHIFT + G", "SUPER + E", "SUPER + B", "SUPER + C", "SUPER + SHIFT + C",
        "SUPER + H", "SUPER + I", "SUPER + M", "SUPER + N", "SUPER + R", "SUPER + Y",
        "SUPER + BackSpace", "SUPER + Z", "SUPER + L", "SUPER + S", "SUPER + P",
        "SUPER + Left", "SUPER + Right", "SUPER + SHIFT + Left", "SUPER + SHIFT + Right",
        "SUPER + Page_Up", "SUPER + Page_Down", "SUPER + SHIFT + Page_Up", "SUPER + SHIFT + Page_Down",
        "SUPER + J", "SUPER + K", "SUPER + SHIFT + J", "SUPER + SHIFT + K",
        "SUPER + Return", "SUPER + SHIFT + Return", "SUPER + backslash", "SUPER + slash", "SUPER + equal", "SUPER + minus",
        "SUPER + period", "SUPER + comma", "SUPER + grave", "SUPER + O",
        "SUPER + Up", "SUPER + SHIFT + Up", "SUPER + Down",
        "SUPER + SHIFT + F", "SUPER + Insert", "SUPER + SHIFT + R",
        "SUPER + Tab", "SUPER + Home", "SUPER + End", "SUPER + A", "ALT + Tab",
        "SUPER + 1", "SUPER + 5", "SUPER + 9", "SUPER + SHIFT + 1", "SUPER + SHIFT + 9",
        "SUPER + SHIFT + N", "SUPER + ALT + Space",
        "Print", "ALT + Print", "SHIFT + Print", "SUPER + Print",
        "XF86AudioMicMute", "SUPER + SHIFT + M",
        "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute",
        "XF86MonBrightnessUp", "XF86MonBrightnessDown",
        "XF86AudioPlay", "XF86AudioPause", "XF86AudioNext", "XF86AudioPrev",
    }
    for _, k in ipairs(keys) do
        bind(k)
    end
end)

test("the dropped keys stay unbound", function()
    load()
    -- BSP toggle, rotate master, and a tenth workspace. Super+O, which
    -- rotated the master, is monocle now, and Super+P, which pseudo-tiled,
    -- presenter mode.
    for _, k in ipairs({ "SUPER + SHIFT + backslash",
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

-- The bar's order (tide SPEC.md §6.5): the standing workspaces, home
-- first, made or not, then the others in the order they were made, then
-- numbered ones.
local function named(...)
    local out = {}
    for i, name in ipairs({ ... }) do
        table.insert(out, { id = -1337 - i, name = name })
    end
    return out
end
local STANDING = [[return { home = "in", standing = { "in", "re", "oc", "me" }, in_apps = {} }]]

test("Super+1…9 go to the Nth workspace on the bar, Super+1 home", function()
    load({ workspaces = STANDING })
    S.workspace_list = named("in", "PR-12", "re", "docs")
    table.insert(S.workspace_list, { id = 2, name = "2" })
    table.insert(S.workspace_list, { id = -98, name = "special:scratch" })
    -- in, re, oc, me, PR-12, docs, 2
    S.active_workspace = { id = -1340, name = "re" }
    local d = run("SUPER + 1")
    eq(1, #d)
    truthy(is_dsp(d[1], "focus"))
    eq("name:in", d[1].args.workspace, "Super+1 is home, as Super+Home is")
    eq("name:oc", run("SUPER + 3")[1].args.workspace, "a standing one, made or not")
    eq("name:PR-12", run("SUPER + 5")[1].args.workspace, "then the made ones")
    eq("name:2", run("SUPER + 7")[1].args.workspace)
    eq(0, #run("SUPER + 8"), "past the last, nothing")
    eq(0, #run("SUPER + 9"))
end)

test("Super+1 goes home whatever it's called", function()
    load({ workspaces = [[return { home = "mail", standing = { "mail" }, in_apps = {} }]] })
    eq("name:mail", run("SUPER + 1")[1].args.workspace)
end)

test("Super+Shift+1…9 send the window to the Nth workspace and stay", function()
    load({ workspaces = STANDING })
    S.workspace_list = named("in", "docs")
    S.active_workspace = { id = -1338, name = "in" }
    local d = run("SUPER + SHIFT + 2")
    eq(1, #d)
    truthy(is_dsp(d[1], "window.move"))
    eq("name:re", d[1].args.workspace)
    eq(false, d[1].args.follow)
    eq("name:docs", run("SUPER + SHIFT + 5")[1].args.workspace)
    eq(0, #run("SUPER + SHIFT + 6"), "past the last, nothing")
end)

test("Super+PgUp/PgDn step through the bar's order and stop at the ends", function()
    load({ workspaces = STANDING })
    S.workspace_list = named("in", "PR-12", "re", "docs")
    table.insert(S.workspace_list, { id = 2, name = "2" })
    table.insert(S.workspace_list, { id = -98, name = "special:scratch" })
    -- in, re, oc, me, PR-12, docs, 2
    S.active_workspace = { id = -1338, name = "in" }
    local d = run("SUPER + Page_Down")
    eq(1, #d)
    truthy(is_dsp(d[1], "focus"))
    eq("name:re", d[1].args.workspace, "a standing workspace comes next")
    eq(0, #run("SUPER + Page_Up"), "nothing before home")
    S.active_workspace = { id = -1340, name = "re" }
    eq("name:oc", run("SUPER + Page_Down")[1].args.workspace, "next, made or not")
    eq("name:in", run("SUPER + Page_Up")[1].args.workspace, "previous")
    S.active_workspace = { id = -1339, name = "PR-12" }
    eq("name:me", run("SUPER + Page_Up")[1].args.workspace, "back past the made ones")
    eq("name:docs", run("SUPER + Page_Down")[1].args.workspace)
    S.active_workspace = { id = 2, name = "2" }
    eq(0, #run("SUPER + Page_Down"), "past the last")
    S.active_workspace = { id = -98, name = "special:scratch" }
    eq(0, #run("SUPER + Page_Down"), "from a special workspace")
    S.active_workspace = nil
    eq(0, #run("SUPER + Page_Down"), "with no workspace")
end)

test("Super+Shift+PgUp/PgDn move the window there and follow it", function()
    load({ workspaces = STANDING })
    S.workspace_list = named("in")
    S.active_workspace = { id = -1338, name = "in" }
    local d = run("SUPER + SHIFT + Page_Down")
    truthy(is_dsp(d[1], "window.move"))
    eq("name:re", d[1].args.workspace)
    eq(true, d[1].args.follow)
    eq(0, #run("SUPER + SHIFT + Page_Up"), "nothing before home")
end)

-- Two monitors, the laptop panel main (home's there) and DP-2 focused
-- unless a test says otherwise.
local function two_monitors()
    S.monitor_list = { { id = 0, name = "eDP-1" }, { id = 1, name = "DP-2" } }
    S.active_monitor = { name = "eDP-1" }
    S.workspace_list = {
        { id = -1338, name = "in", monitor = { name = "eDP-1" } },
        { id = -1339, name = "in@DP-2", monitor = { name = "DP-2" } },
        { id = -1340, name = "re", monitor = { name = "eDP-1" } },
        { id = -1341, name = "docs@DP-2", monitor = { name = "DP-2" } },
    }
    S.active_workspace = { id = -1338, name = "in" }
end

local function targets(d)
    local out = {}
    for _, x in ipairs(d) do
        table.insert(out, x.dsp .. " " .. tostring(x.args.workspace or x.args.window))
    end
    return table.concat(out, ", ")
end

test("with span.lua on two monitors, a workspace key shows the workspace on both", function()
    load({ workspaces = STANDING, span = FAKE_SPAN })
    two_monitors()
    eq("focus name:re@DP-2, focus name:re", targets(run("SUPER + Page_Down")),
        "the other monitor's part first, the focused one's last")
    truthy(S.workspace_rules["name:re@DP-2"], "a rule binds its part to DP-2")
    eq("DP-2", S.workspace_rules["name:re@DP-2"].monitor)
    eq("eDP-1", S.workspace_rules["name:re"].monitor, "and the main part to the main monitor")
    S.active_monitor = { name = "DP-2" }
    eq("focus name:in, focus name:in@DP-2", targets(run("SUPER + Home")), "focus stays on DP-2")
    -- The lid closes on a third monitor's desk: DP-2 now shows home, so
    -- it's main, and the plain part's rule follows it.
    S.monitor_list = { { id = 1, name = "DP-2" }, { id = 2, name = "DP-3" } }
    S.workspace_list[1].monitor = { name = "DP-2" }
    S.active_monitor = { name = "DP-2" }
    run("SUPER + Page_Down")
    eq("DP-2", S.workspace_rules["name:re"].monitor, "the plain part's rule moves to the new main")
end)

test("with span.lua, each monitor's part is one workspace on the bar's order", function()
    load({ workspaces = STANDING, span = FAKE_SPAN })
    two_monitors()
    -- in, re, oc, me, docs: docs is listed once, from its part on DP-2.
    eq("focus name:docs@DP-2, focus name:docs", targets(run("SUPER + 5")))
    eq(0, #run("SUPER + 6"), "no workspace past docs")
    S.active_workspace = { id = -1341, name = "docs@DP-2" }
    S.active_monitor = { name = "DP-2" }
    eq("focus name:me, focus name:me@DP-2", targets(run("SUPER + Page_Up")),
        "a part's neighbors are its workspace's")
end)

test("with span.lua, a moved window goes to its own monitor's part and keeps focus", function()
    load({ workspaces = STANDING, span = FAKE_SPAN })
    two_monitors()
    S.active_monitor = { name = "DP-2" }
    S.active_workspace = { id = -1339, name = "in@DP-2" }
    S.active_window = { address = "0xabc" }
    eq("window.move name:re@DP-2, focus name:re, focus name:re@DP-2, focus address:0xabc",
        targets(run("SUPER + SHIFT + Page_Down")))
    eq("window.move name:oc@DP-2", targets(run("SUPER + SHIFT + 3")), "Super+Shift+N stays")
end)

test("with span.lua, Super+Tab's history counts a workspace once, whichever part", function()
    load({ workspaces = STANDING, span = FAKE_SPAN })
    two_monitors()
    fire("workspace.active", { name = "re@DP-2" })
    fire("workspace.active", { name = "re" })
    fire("workspace.active", { name = "in@DP-2" })
    eq("focus name:re@DP-2, focus name:re", targets(run("SUPER + Tab")), "home back to re")
end)

test("after home changes, going back to the old home binds its part to the main monitor again", function()
    load({ workspaces = STANDING, span = FAKE_SPAN })
    two_monitors()
    S.active_workspace = { id = -1340, name = "re" }
    run("SUPER + Home")
    eq(true, S.workspace_rules["name:in"].enabled)
    -- The settings name re home now, which turns in's rule off.
    write(TIDE_WORKSPACES, [[return { home = "re", standing = { "re", "in" }, in_apps = {} }]])
    conf_workspaces.reload()
    eq(false, S.workspace_rules["name:in"].enabled, "the old home's rule is off")
    S.workspace_list[3].monitor = { name = "eDP-1" }
    run("SUPER + 2")
    eq(true, S.workspace_rules["name:in"].enabled, "a fresh rule binds in again")
    eq("eDP-1", S.workspace_rules["name:in"].monitor)
end)

test("conf_workspaces.go is the workspace keys' switch, for tide's bar", function()
    load({ workspaces = STANDING, span = FAKE_SPAN })
    two_monitors()
    S.dispatched = {}
    conf_workspaces.go("docs")
    eq("focus name:docs@DP-2, focus name:docs", targets(S.dispatched))
    local ok, err = pcall(conf_workspaces.go, "")
    eq(false, ok)
    truthy(tostring(err):find("takes a workspace's name", 1, true))
end)

test("with span.lua on one monitor, the workspace keys are as before", function()
    load({ workspaces = STANDING, span = FAKE_SPAN })
    S.monitor_list = { { id = 0, name = "eDP-1" } }
    S.active_monitor = { name = "eDP-1" }
    S.workspace_list = named("in")
    S.active_workspace = { id = -1338, name = "in" }
    eq("focus name:re", targets(run("SUPER + Page_Down")))
    eq(nil, S.workspace_rules["name:re@DP-2"], "no rule for a part")
end)

test("a span.lua missing a function is reported, and the keys switch one monitor", function()
    load({ workspaces = STANDING, span = "return { part = function() end }" })
    two_monitors()
    local found
    for _, n in ipairs(S.notifications) do
        if tostring(n.text):find("span model failed to load", 1, true) then
            found = true
        end
    end
    truthy(found, "a notification says so")
    eq("focus name:re", targets(run("SUPER + Page_Down")))
end)

test("Super+Left/Right and Super+Shift+Left/Right are the tide layout's window keys", function()
    load({ layout = FAKE_LAYOUT })
    local qs = _G.fake_layout
    run("SUPER + Left")
    run("SUPER + Right")
    run("SUPER + SHIFT + Left")
    run("SUPER + SHIFT + Right")
    eq("focus_side -1", qs.calls[1][1] .. " " .. qs.calls[1][2])
    eq("focus_side 1", qs.calls[2][1] .. " " .. qs.calls[2][2])
    eq("move_side -1", qs.calls[3][1] .. " " .. qs.calls[3][2])
    eq("move_side 1", qs.calls[4][1] .. " " .. qs.calls[4][2])
    eq("Focus the window to the left", bind("SUPER + Left").opts.description)
    eq("Move the window right", bind("SUPER + SHIFT + Right").opts.description)
end)

test("without them, Super+Left/Right are Hyprland's movefocus and movewindow", function()
    for _, layout in ipairs({ false, (FAKE_LAYOUT:gsub('"focus_side", "move_side", ', "")) }) do
        load(layout and { layout = layout } or nil)
        local what = layout and "an older tide layout" or "master"
        local l, r = bind("SUPER + Left").target, bind("SUPER + Right").target
        truthy(is_dsp(l, "focus"), what)
        eq("left", l.args.direction, what)
        eq("right", r.args.direction, what)
        S.active_window = { address = "0x55aa01", floating = false }
        local ml, mr = run("SUPER + SHIFT + Left"), run("SUPER + SHIFT + Right")
        truthy(is_dsp(ml[1], "window.move"), what)
        eq("left", ml[1].args.direction, what)
        eq("right", mr[1].args.direction, what)
        S.active_window = nil
        eq("left", run("SUPER + SHIFT + Left")[1].args.direction, what .. ", with no window")
    end
    -- So movefocus stops past the last monitor rather than wrapping.
    eq(true, S.config.general.no_focus_fallback, "no_focus_fallback")
end)

test("without them, Super+Shift+Left/Right move a floating window to the monitor that way", function()
    load()
    S.active_window = { address = "0x55aa01", floating = true }
    S.monitor_that_way = { r = { name = "DP-2" } }
    local d = run("SUPER + SHIFT + Right")
    eq(1, #d, "one dispatch")
    truthy(is_dsp(d[1], "window.move"))
    eq("r", d[1].args.monitor, "to the monitor on the right")
    eq(true, d[1].args.follow, "keeping focus")
    eq(nil, d[1].args.direction, "not movewindow's push to the edge")
    eq(0, #run("SUPER + SHIFT + Left"), "past the last monitor, nothing")
    S.monitor_that_way = "raise"
    eq(0, #run("SUPER + SHIFT + Right"), "nothing when the monitors can't be read")
    eq(1, #S.notifications, "and says so")
    S.active_window = "raise"
    eq(0, #run("SUPER + SHIFT + Right"), "nothing when the window can't be read")
    eq(2, #S.notifications, "and says so")
end)

test("a standing name matches a workspace made in another case, as the bar's does", function()
    load({ workspaces = STANDING })
    S.workspace_list = named("in", "RE")
    S.active_workspace = { id = -1338, name = "in" }
    eq("name:RE", run("SUPER + Page_Down")[1].args.workspace)
end)

test("Super+Home goes home, whatever it's called", function()
    load({ workspaces = [[return { home = "mail", standing = { "mail" }, in_apps = {} }]] })
    local d = run("SUPER + Home")
    eq(1, #d)
    eq("name:mail", d[1].args.workspace)
end)

test("Super+Tab flips between home and the last other workspace", function()
    load({ workspaces = STANDING })
    S.workspace_list = named("in", "PR-12", "docs")
    S.active_workspace = { id = -1338, name = "in" }
    eq(0, #run("SUPER + Tab"), "from home with nowhere used yet, nothing")
    fire("workspace.active", { id = -1339, name = "PR-12" })
    fire("workspace.active", { id = -1338, name = "in" })
    fire("workspace.active", { id = -1340, name = "docs" })
    S.active_workspace = { id = -1340, name = "docs" }
    eq("name:in", run("SUPER + Tab")[1].args.workspace, "to home")
    fire("workspace.active", { id = -1338, name = "in" })
    S.active_workspace = { id = -1338, name = "in" }
    eq("name:docs", run("SUPER + Tab")[1].args.workspace, "and back")
    -- docs is removed since: from home, the one before it.
    S.workspace_list = named("in", "PR-12")
    eq("name:PR-12", run("SUPER + Tab")[1].args.workspace, "skipping a removed one")
    S.workspace_list = named("in")
    eq(0, #run("SUPER + Tab"), "and nothing when all are gone")
    -- A standing workspace is always there to go back to.
    fire("workspace.active", { id = -1341, name = "oc" })
    eq("name:oc", run("SUPER + Tab")[1].args.workspace, "a standing one, emptied and gone, made again")
end)

test("a workspace that becomes home is left out of Super+Tab's and Super+End's history", function()
    load({ workspaces = STANDING })
    S.workspace_list = named("in", "PR-12", "docs")
    fire("workspace.active", { id = -1339, name = "PR-12" })
    fire("workspace.active", { id = -1340, name = "docs" })
    -- The settings name docs home now.
    write(TIDE_WORKSPACES, [[return { home = "docs", standing = { "docs" }, in_apps = {} }]])
    conf_workspaces.reload()
    S.active_workspace = { id = -1340, name = "docs" }
    eq("name:PR-12", run("SUPER + Tab")[1].args.workspace, "from the new home, not to it")
    S.active_workspace = { id = -1339, name = "PR-12" }
    eq(0, #run("SUPER + End"), "Super+End has nowhere but home to go")
end)

test("Super+End toggles between the last two workspaces other than home", function()
    load({ workspaces = STANDING })
    S.workspace_list = named("in", "PR-12", "docs")
    fire("workspace.active", { id = -1339, name = "PR-12" })
    fire("workspace.active", { id = -1338, name = "in" })
    fire("workspace.active", { id = -1340, name = "docs" })
    S.active_workspace = { id = -1340, name = "docs" }
    eq("name:PR-12", run("SUPER + End")[1].args.workspace, "the one before")
    fire("workspace.active", { id = -1339, name = "PR-12" })
    S.active_workspace = { id = -1339, name = "PR-12" }
    eq("name:docs", run("SUPER + End")[1].args.workspace, "and back, never home")
    S.active_workspace = { id = -1338, name = "in" }
    eq("name:PR-12", run("SUPER + End")[1].args.workspace, "from home, where Super+Tab goes")
end)

test("Super+Return goes to a workspace through tide's name prompt, and Super+Shift+Return moves the window", function()
    load()
    for keys, want in pairs({
        ["SUPER + Return"] = { "qs -c tide ipc call prompt go ", "Go to a workspace" },
        ["SUPER + SHIFT + Return"] = { "qs -c tide ipc call prompt move ", "Move the window to a workspace" },
    }) do
        local t = bind(keys).target
        truthy(t.args:find(want[1], 1, true), t.args)
        truthy(t.args:find("|| notify-send -a tide 'No name prompt'", 1, true), t.args)
        eq(want[2], bind(keys).opts.description, keys)
        local script = tmp .. "/super-return.sh"
        local f = assert(io.open(script, "w"))
        f:write(t.args, "\n")
        f:close()
        truthy(os.execute("sh -n '" .. script .. "'"), keys .. ": the command parses as sh")
    end
end)

test("Super+Z asks tide's shell to minimize the window, and says so when there's no shell", function()
    load()
    local t = bind("SUPER + Z").target
    truthy(t.args:find("qs -c tide ipc call windows minimize", 1, true), t.args)
    truthy(t.args:find("|| notify-send -a tide 'No minimize'", 1, true), t.args)
    eq("Minimize the window", bind("SUPER + Z").opts.description)
    local script = tmp .. "/super-z.sh"
    local f = assert(io.open(script, "w"))
    f:write(t.args, "\n")
    f:close()
    truthy(os.execute("sh -n '" .. script .. "'"), "the command parses as sh")
end)

test("Super+C opens tide's picker, says so when there's no shell, and Calendar has no key", function()
    load()
    local t = bind("SUPER + C").target
    truthy(t.args:find("qs -c tide ipc call picker toggle clipboard", 1, true), t.args)
    truthy(t.args:find("|| notify-send -a tide 'No picker'", 1, true), t.args)
    eq("Clipboard and characters", bind("SUPER + C").opts.description)
    for k, b in pairs(S.binds) do
        local args = type(b.target) == "table" and b.target.args or ""
        eq(nil, tostring(args):find("google-calendar", 1, true), "Calendar is bound on " .. k)
    end
    eq(true, bind("SUPER + SHIFT + C").target.args:find("google-chat", 1, true) ~= nil, "Super+Shift+C is still Chat")
    eq(true, bind("SUPER + H").target.args:find(" home", 1, true) ~= nil, "Super+H is still home")
    local script = tmp .. "/super-c.sh"
    local f = assert(io.open(script, "w"))
    f:write(t.args, "\n")
    f:close()
    truthy(os.execute("sh -n '" .. script .. "'"), "the command parses as sh")
end)

for _, case in ipairs({
    { key = "SUPER + S", call = "keepawake toggle", title = "No keep awake", does = "Keep awake" },
    { key = "SUPER + P", call = "presenter toggle", title = "No presenter mode", does = "Presenter mode" },
}) do
    test(case.key .. " asks tide's shell for " .. case.does:lower() .. ", and says so when there's no shell", function()
        load()
        local t = bind(case.key).target
        truthy(t.args:find("qs -c tide ipc call " .. case.call .. " ||", 1, true), t.args)
        truthy(t.args:find("|| notify-send -a tide '" .. case.title .. "'", 1, true), t.args)
        eq(case.does, bind(case.key).opts.description)
        local script = tmp .. "/super-" .. case.call:gsub(" ", "-") .. ".sh"
        local f = assert(io.open(script, "w"))
        f:write(t.args, "\n")
        f:close()
        truthy(os.execute("sh -n '" .. script .. "'"), "the command parses as sh")
    end)
end

test("Super+D stays free for hyprland.local.lua", function()
    load()
    eq(nil, S.binds["|SUPER + D"], "SUPER + D")
end)

test("Alt+Tab swaps with the master, and Super+Return no longer does", function()
    load({ layout = FAKE_LAYOUT })
    eq(_G.fake_layout.swap_with_master, bind("ALT + Tab").target)
    load()
    eq("swapwithmaster master", bind("ALT + Tab").target.args)
end)

test("a broken standing list is reported", function()
    for _, text in ipairs({
        [[return { home = "in", standing = {} }]],
        [[return { home = "in", standing = { "re", "in" } }]],
        [[return { home = "in", standing = { "in", 3 } }]],
        [[return { home = "in", standing = "in" }]],
    }) do
        load({ workspaces = text })
        eq(1, #S.notifications, text)
        truthy(S.notifications[1].text:find("standing", 1, true), S.notifications[1].text)
        eq("in", conf_workspaces.standing()[1], text)
    end
    -- A file from before standing workspaces names home alone.
    load({ workspaces = [[return { home = "in", in_apps = {} }]] })
    eq(0, #S.notifications)
    eq("in", table.concat(conf_workspaces.standing(), " "))
end)

test("a failed workspace lookup is reported, not silently ignored", function()
    load()
    S.active_workspace = "raise"
    eq(0, #run("SUPER + Page_Down"), "nothing dispatched")
    eq(1, #S.notifications, "notifications")
    truthy(S.notifications[1].text:find("active workspace", 1, true), S.notifications[1].text)
    S.active_workspace = nil
    run("SUPER + Page_Down")
    eq(1, #S.notifications, "no workspace at all is quiet")
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

test("float toggles on Super+Shift+F and Super+Insert, telling tide's shell when the window floats now", function()
    for _, keys in ipairs({ "SUPER + SHIFT + F", "SUPER + Insert" }) do
        load()
        local fn = bind(keys).target
        eq("function", type(fn), keys)
        -- Floated by the toggle.
        S.active_window = { address = "0x55aa01", floating = true }
        fn()
        truthy(is_dsp(S.dispatched[1], "window.float"), keys)
        eq("toggle", S.dispatched[1].args.action)
        truthy(is_dsp(S.dispatched[2], "event"), keys .. ": an event")
        eq("tide-floated>>0x55aa01", S.dispatched[2].args)
        -- Tiled by it: nothing to ask.
        S.dispatched = {}
        S.active_window = { address = "0x55aa01", floating = false }
        fn()
        eq(1, #S.dispatched, keys .. ": the toggle alone")
        -- No window, or one going away: the toggle, and no question.
        S.dispatched = {}
        S.active_window = nil
        fn()
        eq(1, #S.dispatched)
        S.dispatched = {}
        S.active_window = "raise"
        fn()
        eq(1, #S.dispatched)
        eq(1, #S.notifications, "a failed query is reported")
    end
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
    eq("Home workspace", bind("SUPER + Home").opts.description)
    -- Bindings that share an options table each keep their own description,
    -- and the table's options.
    eq("Mute", bind("XF86AudioMute").opts.description)
    eq("Play or pause", bind("XF86AudioPlay").opts.description)
    eq(true, bind("XF86AudioMute").opts.locked)
end)

test("Super+A opens tide's switcher on its Attention tab", function()
    load()
    local t = bind("SUPER + A").target
    truthy(t.args:find("qs -c tide ipc call switcher toggle attention", 1, true), t.args)
    truthy(t.args:find("notify-send -a tide 'No Attention tab'", 1, true), "says so without the shell")
    truthy(t.args:find("hyprctl eval 'conf_attention.without_shell()'", 1, true), "and falls back")
    local script = tmp .. "/super-a.sh"
    local f = assert(io.open(script, "w"))
    f:write(t.args, "\n")
    f:close()
    truthy(os.execute("sh -n '" .. script .. "'"), "the command parses as sh")
    -- The attention cycle and its Super release are gone.
    eq(nil, S.binds["|SUPER + Super_L"], "no release binding")
    eq(nil, S.binds["|SUPER + Super_R"], "no release binding")
end)

test("without the shell, Super+A brings up the urgent window, or the last one", function()
    load()
    S.urgent_window = nil
    S.dispatched = {}
    conf_attention.without_shell()
    eq(true, S.dispatched[1].args.last, "none urgent goes back")
    S.urgent_window = { address = "0xabc" }
    S.dispatched = {}
    conf_attention.without_shell()
    eq("address:0xabc", S.dispatched[1].args.window, "the urgent window")
    S.urgent_window = "raise"
    S.dispatched = {}
    conf_attention.without_shell()
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("urgent window", 1, true))
    eq(true, S.dispatched[1].args.last, "a failed lookup goes back")
    S.urgent_window = nil
end)

test("tide's notification popups are blacked out of screen shares", function()
    load()
    local r = S.layer_rules["no-share-notifications"]
    truthy(r, "the rule")
    eq("^tide-notifications$", r.match.namespace)
    eq(true, r.no_screen_share)
end)

test("tide's share picker is blacked out of screen shares", function()
    load()
    local r = S.layer_rules["no-share-share-picker"]
    truthy(r, "the rule")
    eq("^tide-share-picker$", r.match.namespace)
    eq(true, r.no_screen_share)
end)

test("tide's launcher is blacked out of screen shares", function()
    load()
    local r = S.layer_rules["no-share-launcher"]
    truthy(r, "the rule")
    eq("^tide-launcher$", r.match.namespace)
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
    -- Docked as the config loads, so home's monitor is known (a
    -- monitor.added then is a monitor coming back, not the first).
    load({ monitors = { { name = "eDP-1" }, { name = "DP-1" } } })
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
    eq(false, rule_for({ name = "eDP-1" }).disabled, "the panel's rule no longer turns it off")
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

local function undocked()
    S.monitor_list = { { name = "eDP-1" } }
    S.workspace_list = { { id = 1, monitor = S.monitor_list[1] } }
end

test("undocked, closing the lid leaves the panel to logind's suspend by default", function()
    load({ env = TIDE })
    undocked()
    lid("on")
    eq(0, #S.dispatched, "nothing locks here")
    eq(0, #S.monitors, "the panel is left alone")
end)

test("undocked, tide's Lock locks as the lid closes", function()
    load({ env = TIDE, power = [[return { lid_close = "lock" }]] })
    undocked()
    lid("on")
    eq(1, #S.dispatched)
    eq("exec_cmd", S.dispatched[1].dsp)
    eq("loginctl lock-session", S.dispatched[1].args)
    eq(0, #S.monitors, "the panel is left alone")
end)

test("undocked, tide's Do nothing does nothing", function()
    load({ env = TIDE, power = [[return { lid_close = "nothing" }]] })
    undocked()
    lid("on")
    eq(0, #S.dispatched)
end)

test("docked, the lid turns the panel off whatever tide's Power page says", function()
    load({ monitors = { { name = "eDP-1" }, { name = "DP-1" } }, power = [[return { lid_close = "lock" }]] })
    docked()
    lid("on")
    eq(0, #S.dispatched, "no lock")
    eq(true, S.monitors[1].disabled)
end)

test("a bad tide-power.lua is reported and taken as suspend", function()
    load({ env = TIDE, power = [[return { lid_close = "hibernate" }]] })
    undocked()
    S.notifications = {}
    lid("on")
    eq(0, #S.dispatched)
    truthy(S.notifications[1] and S.notifications[1].text:find("lid_close should be suspend, lock or nothing, not hibernate", 1, true),
        S.notifications[1] and S.notifications[1].text)
end)

test("a reload with the lid closed keeps the panel off, and opening restores it", function()
    -- Docked as the config loads, so home's monitor is known (a
    -- monitor.added then is a monitor coming back, not the first).
    load({ monitors = { { name = "eDP-1" }, { name = "DP-1" } } })
    docked()
    lid("on")
    truthy(exists(LID_FILE), "the closed lid is saved")
    -- A reload: a new Lua state, the same Hyprland instance.
    load({ reload = true, monitors = { { name = "eDP-1", enabled = false }, { name = "DP-1" } } })
    eq(2, #S.monitors, "the catch-all plus the panel's disabled rule")
    eq("eDP-1", S.monitors[2].output)
    eq(true, S.monitors[2].disabled)
    docked()
    S.monitor_list[1].enabled = false
    lid("off")
    eq("eDP-1", S.monitors[1].output)
    eq("preferred", S.monitors[1].mode)
    eq(false, rule_for({ name = "eDP-1" }).disabled, "the panel's rule no longer turns it off")
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
    -- Docked as the config loads, so home's monitor is known (a
    -- monitor.added then is a monitor coming back, not the first).
    load({ monitors = { { name = "eDP-1" }, { name = "DP-1" } } })
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
    -- Docked as the config loads, so home's monitor is known (a
    -- monitor.added then is a monitor coming back, not the first).
    load({ monitors = { { name = "eDP-1" }, { name = "DP-1" } } })
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
    -- Docked as the config loads, so home's monitor is known (a
    -- monitor.added then is a monitor coming back, not the first).
    load({ monitors = { { name = "eDP-1" }, { name = "DP-1" } } })
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

test("with no saved state, opening the lid turns on HYPR_INTERNAL_OUTPUT's panel, which Hyprland doesn't list while it's off", function()
    load({ env = { XDG_RUNTIME_DIR = "", HYPR_INTERNAL_OUTPUT = "eDP-1" } })
    S.on_only = true
    S.monitor_list = { { name = "eDP-1", enabled = false }, { name = "DP-1" } }
    lid("off")
    eq(1, #S.monitors)
    eq("eDP-1", S.monitors[1].output)
    eq(false, S.monitors[1].disabled == true, "on")
    fire("monitor.added", { name = "eDP-1" })
    S.monitor_list[1].enabled = true
    lid("off")
    eq(0, #S.monitors, "a panel that is on is left alone")
end)

test("with no saved state and no HYPR_INTERNAL_OUTPUT, a panel Hyprland doesn't list stays as it is", function()
    load({ env = { XDG_RUNTIME_DIR = "" } })
    S.on_only = true
    S.monitor_list = { { name = "eDP-1", enabled = false }, { name = "DP-1" } }
    lid("off")
    eq(0, #S.monitors, "nothing names the panel")
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
-- tide's display settings (tide SPEC.md §16)
--------------------------------------------------------------------------------
local DELL = { name = "DP-1", description = "Dell Inc. DELL U2720Q 1234ABC" }
local PANEL = { name = "eDP-1", description = "BOE 0x0BCA" }
local DELL_SETTINGS = 'return { ["desc:Dell Inc. DELL U2720Q 1234ABC"] = { scale = 1.5, position = "auto-left" } }'

test("tide's display settings are a rule for each monitor by its description", function()
    load({ outputs = 'return { ["desc:Dell Inc. DELL U2720Q 1234ABC"] = { scale = 1.5, position = "auto-left" },'
        .. ' ["desc:BOE 0x0BCA"] = { scale = 2 } }' })
    eq(0, #S.notifications, "notifications")
    eq(3, #S.monitors, "the catch-all, then one each")
    eq("", S.monitors[1].output)
    eq("desc:BOE 0x0BCA", S.monitors[2].output, "in order")
    local dell = rule_for(DELL)
    eq("1.5", dell.scale, "hl.monitor takes a scale as a string")
    eq("auto-left", dell.position)
    eq("preferred", dell.mode)
    eq("2", rule_for(PANEL).scale)
    eq("auto", rule_for(PANEL).position, "a place it doesn't set is automatic")
    eq("auto", rule_for({ name = "HDMI-A-1", description = "Other" }).scale, "the rest take the catch-all")
end)

test("a tide display setting that's wrong is reported and left out", function()
    load({ outputs = 'return { ["desc:A"] = { scale = 0.1, position = "left", size = 1 }, ["DP-1"] = {}, ["desc:B"] = 2 }' })
    local texts = {}
    for _, n in ipairs(S.notifications) do
        table.insert(texts, n.text)
    end
    table.sort(texts)
    eq(5, #texts, "notifications: " .. table.concat(texts, " | "))
    truthy(texts[1]:find("DP-1 should be desc:", 1, true), texts[1])
    truthy(texts[2]:find("desc:A.position should be auto", 1, true), texts[2])
    truthy(texts[3]:find("desc:A.scale should be a number from 0.25 to 10", 1, true), texts[3])
    truthy(texts[4]:find("desc:B should be a table", 1, true), texts[4])
    truthy(texts[5]:find("unknown setting desc:A.size", 1, true), texts[5])
    eq(2, #S.monitors, "desc:A still gets its rule, at the catch-all's settings")
    eq("auto", rule_for({ name = "X", description = "A" }).scale)
    load({ outputs = "return {" })
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("tide-outputs.lua (none of it applied)", 1, true), S.notifications[1].text)
    eq(1, #S.monitors, "only the catch-all")
    load({ outputs = "os.exit(1)" })
    truthy(S.notifications[1].text:find("none of it applied", 1, true), "nothing in scope: " .. S.notifications[1].text)
end)

test("the local file's monitor rules win over tide's, before and after tide applies a change", function()
    load({ outputs = DELL_SETTINGS, ["local"] = 'hl.monitor({ output = "DP-1", scale = "2" })' })
    eq("2", rule_for(DELL).scale, "the local file loads last")
    write(TIDE_OUTPUTS, 'return { ["desc:Dell Inc. DELL U2720Q 1234ABC"] = { scale = 1.25 }, ["desc:BOE 0x0BCA"] = { scale = 1.75 } }')
    conf_outputs.reload()
    eq("2", rule_for(DELL).scale, "still the local file's")
    eq("1.75", rule_for(PANEL).scale, "a monitor the local file doesn't set takes tide's change")
    eq(0, #S.notifications, "notifications")
end)

test("a monitor tide stops setting goes back to the catch-all's settings", function()
    load({ outputs = DELL_SETTINGS })
    write(TIDE_OUTPUTS, "return {}")
    conf_outputs.reload()
    eq("auto", rule_for(DELL).scale)
    eq("auto", rule_for(DELL).position)
    -- The local file's catch-all, when it has one.
    load({ outputs = DELL_SETTINGS, ["local"] = 'hl.monitor({ output = "", scale = "1.25" })' })
    remove(TIDE_OUTPUTS)
    conf_outputs.reload()
    eq("1.25", rule_for(DELL).scale)
end)

test("a closed lid's panel stays off when tide applies a change, and opens with tide's scale", function()
    load({ outputs = 'return { ["desc:BOE 0x0BCA"] = { scale = 2 } }' })
    docked()
    S.monitor_list[1].description = PANEL.description
    lid("on")
    write(TIDE_OUTPUTS, 'return { ["desc:BOE 0x0BCA"] = { scale = 1.75 } }')
    conf_outputs.reload()
    eq(true, rule_for(PANEL).disabled, "still off")
    lid("off")
    eq(false, rule_for(PANEL).disabled == true, "on again")
    eq("1.75", rule_for(PANEL).scale, "with tide's scale, not the lid's auto")
end)

-- The rules hyprctl eval's reload added for output `name`, by name.
local function by_name(name)
    local out = {}
    for _, r in ipairs(S.monitors) do
        if r.output == name then
            table.insert(out, r)
        end
    end
    return out
end

test("tide's change also goes to a connected monitor by its name", function()
    -- Hyprland 0.56.2 doesn't apply a desc: rule added at runtime to a
    -- monitor already connected (hyprwm/Hyprland#15961).
    load({ outputs = DELL_SETTINGS })
    S.monitor_list = { DELL, { name = "HDMI-A-1", description = "Other" } }
    S.monitors = {}
    write(TIDE_OUTPUTS, 'return { ["desc:Dell Inc. DELL U2720Q 1234ABC"] = { scale = 1.25 } }')
    conf_outputs.reload()
    eq(1, #by_name("DP-1"), "one rule for DP-1")
    eq("1.25", by_name("DP-1")[1].scale)
    eq(0, #by_name("HDMI-A-1"), "none for a monitor tide doesn't set")
    eq("1.25", rule_for(DELL).scale)
end)

test("a monitor the local file sets gets no rule from tide by its name", function()
    load({ outputs = DELL_SETTINGS, ["local"] = 'hl.monitor({ output = "desc:Dell Inc.", scale = "2" })' })
    S.monitor_list = { DELL }
    S.monitors = {}
    conf_outputs.reload()
    eq(0, #by_name("DP-1"))
    eq("2", rule_for(DELL).scale)
end)

test("a monitor tide stops setting goes back to the catch-all by its name too", function()
    load({ outputs = DELL_SETTINGS })
    S.monitor_list = { DELL }
    S.monitors = {}
    write(TIDE_OUTPUTS, "return {}")
    conf_outputs.reload()
    eq(1, #by_name("DP-1"), "though the config loaded its rule, not a reload")
    eq("auto", by_name("DP-1")[1].scale)
    eq("auto", rule_for(DELL).scale)
end)

test("a name tide gave a rule goes back to the catch-all when another monitor takes it", function()
    load({ outputs = DELL_SETTINGS })
    S.monitor_list = { DELL }
    conf_outputs.reload()
    eq("1.5", rule_for(DELL).scale)
    -- The Dell goes, and a reload while it's away keeps DP-1 marked.
    S.monitor_list = {}
    conf_outputs.reload()
    local other = { name = "DP-1", description = "Other" }
    S.monitor_list = { other }
    S.monitors = {}
    fire("monitor.added", other)
    eq("auto", rule_for(other).scale, "not the Dell's scale")
    -- Put right once, it gets no more rules by name.
    S.monitors = {}
    fire("monitor.added", other)
    eq(0, #by_name("DP-1"))
end)

test("opening the lid gives the panel the local file's catch-all", function()
    load({ ["local"] = 'hl.monitor({ output = "", scale = "1.25" })' })
    docked()
    lid("on")
    lid("off")
    eq(false, rule_for(PANEL).disabled == true, "on again")
    eq("1.25", rule_for(PANEL).scale, "not conf's auto")
end)

test("a monitor the local file sets by its full description gets no rule from tide by name", function()
    -- hyprctl monitors and hl.get_monitors give the short description;
    -- Hyprland also matches the full one, as hl.get_monitor resolves it.
    load({ outputs = DELL_SETTINGS, ["local"] = 'hl.monitor({ output = "desc:Dell Inc. DELL U2720Q 1234ABC (DP-1)", scale = "2" })' })
    S.monitor_list = { { name = "DP-1", description = DELL.description, full_description = DELL.description .. " (DP-1)" } }
    S.monitors = {}
    conf_outputs.reload()
    eq(0, #by_name("DP-1"))
end)

test("a tide entry takes the local catch-all for what it leaves out, at load and on reload alike", function()
    load({
        outputs = 'return { ["desc:Dell Inc. DELL U2720Q 1234ABC"] = { position = "auto-left" } }',
        ["local"] = 'hl.monitor({ output = "", scale = "1.25" })',
    })
    eq("1.25", rule_for(DELL).scale, "at load")
    eq("auto-left", rule_for(DELL).position)
    conf_outputs.reload()
    eq("1.25", rule_for(DELL).scale, "a reload changes nothing")
end)

test("the panel takes tide's rule by name when it comes back on", function()
    -- Hyprland 0.56.2's hl.get_monitors lists only the monitors on, so the
    -- panel's rule by name waits for monitor.added.
    load({ outputs = 'return { ["desc:BOE 0x0BCA"] = { scale = 2 } }' })
    docked()
    S.on_only = true
    S.monitor_list[1].description = PANEL.description
    lid("on")
    S.monitor_list[1].enabled = false
    lid("off")
    S.monitor_list[1].enabled = true
    S.monitors = {}
    fire("monitor.added", S.monitor_list[1])
    eq(1, #by_name("eDP-1"), "one rule for the panel by name")
    eq("2", by_name("eDP-1")[1].scale)
    eq(false, rule_for(PANEL).disabled == true, "and on")
end)

test("opening the lid keeps the local file's rule for the panel", function()
    load({ ["local"] = 'hl.monitor({ output = "eDP-1", scale = "1.5" })' })
    docked()
    lid("on")
    lid("off")
    eq(false, rule_for(PANEL).disabled == true, "on again")
    eq("1.5", rule_for(PANEL).scale)
end)

--------------------------------------------------------------------------------
-- Window rules (SPEC.md §6.2, §6.4)
--------------------------------------------------------------------------------
test("dialogs float centered", function()
    load()
    for _, name in ipairs({ "float-modal", "float-pavucontrol", "float-nm-connection-editor",
                            "float-blueman-manager", "float-portal-file-chooser",
                            "float-file-dialog-title", "float-unnamed" }) do
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
    -- Both must be empty, so an app with a class and no title yet still
    -- tiles. Hyprland matches the whole string, so "^$" is only "".
    local unnamed = S.rules["float-unnamed"].match
    eq("^$", unnamed.class)
    eq("^$", unnamed.title)
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

test("Super+Alt+Space switches to the next keyboard layout, on the lock screen too", function()
    load()
    local b = bind("SUPER + ALT + Space")
    eq("~/.config/hypr/scripts/next-layout.sh", b.target.args)
    eq("Next keyboard layout", b.opts.description)
    eq(true, b.opts.locked)
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

test("apply-input's conf_input.keyboard gives a keyboard every keyboard option", function()
    load()
    S.calls = {}
    conf_input.keyboard("at-keyboard")
    local d = devices()
    eq(1, #d)
    eq("at-keyboard", d[1].name)
    eq("us", d[1].kb_layout)
    eq("dvorak", d[1].kb_variant)
    eq(600, d[1].repeat_delay)
    eq(25, d[1].repeat_rate)
end)

local TIDE_KEYBOARDS = [[
return {
    mouse = { sensitivity = -0.5 },
    keyboard = { kb_layout = "us,de", kb_variant = "dvorak,", repeat_rate = 40 },
    devices = {
        ["logitech-usb-receiver"] = { sensitivity = 0.75, kb_layout = "gb", kb_variant = "" },
    },
}
]]

test("a keyboard tide's settings name gets its own over every keyboard's", function()
    load({ input = TIDE_KEYBOARDS })
    eq(0, #S.notifications)
    S.calls = {}
    conf_input.keyboard("logitech-usb-receiver")
    conf_input.keyboard("at-keyboard")
    conf_input.mouse("logitech-usb-receiver", 3)
    local d = devices()
    eq(3, #d)
    eq("gb", d[1].kb_layout, "its own layout")
    eq("", d[1].kb_variant, "its own variant, none")
    eq(40, d[1].repeat_rate, "the rest as every keyboard's")
    eq(600, d[1].repeat_delay, "and the config's where tide sets none")
    eq(nil, d[1].sensitivity, "a keyboard takes no mouse setting")
    eq("us,de", d[2].kb_layout, "another keyboard keeps every keyboard's")
    eq("dvorak,", d[2].kb_variant)
    eq(0.75, d[3].sensitivity, "the same name as a mouse takes its mouse setting")
    eq(nil, d[3].kb_layout, "and no keyboard setting")
end)

test("a keyboard's own layout that tide stops setting goes back to every keyboard's on reload", function()
    load({ input = TIDE_KEYBOARDS })
    write(TIDE_INPUT, 'return { keyboard = { kb_layout = "us,de", kb_variant = "dvorak," } }')
    conf_input.reload()
    S.calls = {}
    conf_input.keyboard("logitech-usb-receiver")
    local d = devices()
    eq("us,de", d[1].kb_layout)
    eq("dvorak,", d[1].kb_variant)
    eq(25, d[1].repeat_rate, "the config's again")
end)

test("hyprland.local.lua still wins over a keyboard's tide settings", function()
    load({
        input = TIDE_KEYBOARDS,
        ["local"] = 'hl.device({ name = "logitech usb receiver", kb_layout = "fr" })\n'
            .. 'hl.config({ input = { repeat_delay = 250 } })',
    })
    S.calls = {}
    conf_input.keyboard("logitech-usb-receiver")
    conf_input.keyboard("at-keyboard")
    local d = devices()
    eq(nil, d[1].kb_layout, "the local file's field for that keyboard (spaces as dashes)")
    eq("", d[1].kb_variant, "its own tide setting for the rest")
    eq(250, d[2].repeat_delay, "the local file's keyboard option, as input has it")
end)

test("a keyboard setting of the wrong type in devices is reported and left out", function()
    load({ input = 'return { devices = { ["at-keyboard"] = { kb_layout = 5, repeat_rate = 30 } } }' })
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("devices.at-keyboard.kb_layout should be a string", 1, true), S.notifications[1].text)
    S.calls = {}
    conf_input.keyboard("at-keyboard")
    local d = devices()
    eq("us", d[1].kb_layout)
    eq(30, d[1].repeat_rate)
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

test("tide-appearance.lua sets the inactive dim's strength", function()
    load({ appearance = "return { dim_strength = 0.12 }" })
    eq(0.12, S.config.decoration.dim_strength)
    eq(0, #S.notifications)
    load({ appearance = "return {}" })
    eq(0.07, S.config.decoration.dim_strength, "nothing set keeps the config's")
end)

test("conf_appearance.reload reads tide's dim again, and goes back to the config's without it", function()
    load()
    write(TIDE_APPEARANCE, "return { dim_strength = 0.2 }")
    conf_appearance.reload()
    eq(0.2, S.config.decoration.dim_strength)
    write(TIDE_APPEARANCE, "return {}")
    conf_appearance.reload()
    eq(0.07, S.config.decoration.dim_strength, "a setting tide stops making")
    write(TIDE_APPEARANCE, "return { dim_strength = 0.2 }")
    conf_appearance.reload()
    remove(TIDE_APPEARANCE)
    conf_appearance.reload()
    eq(0.07, S.config.decoration.dim_strength, "no file")
end)

test("hyprland.local.lua's dim strength wins over tide's, at load and on a reload", function()
    load({ appearance = "return { dim_strength = 0.12 }", ["local"] = "hl.config({ decoration = { dim_strength = 0.25 } })" })
    eq(0.25, S.config.decoration.dim_strength)
    write(TIDE_APPEARANCE, "return { dim_strength = 0.2 }")
    conf_appearance.reload()
    eq(0.25, S.config.decoration.dim_strength)
end)

test("a broken or wrong tide-appearance.lua is reported and leaves the config's dim", function()
    for _, text in ipairs({
        "return {",
        "return 5",
        'return { dim_strength = "strong" }',
        "return { dim_strength = 2 }",
        "return { dim_strength = 0 / 0 }",
        "return { dim = 0.1 }",
        'os.execute("true") return {}',
    }) do
        load({ appearance = text })
        eq(1, #S.notifications, text)
        truthy(S.notifications[1].text:find("tide-appearance.lua", 1, true), S.notifications[1].text)
        eq(0.07, S.config.decoration.dim_strength, text)
    end
end)

test("home is in, kept and the first monitor's default, until tide names another", function()
    load()
    local rule = S.workspace_rules["name:in"]
    truthy(rule, "a rule for name:in")
    eq(true, rule.persistent, "kept when empty")
    eq(true, rule.default, "a monitor's default")
    eq(nil, rule.monitor, "none yet: no monitor has connected")
    eq(0, #S.notifications)
    eq("in", conf_workspaces.home())
end)

test("home is the default of the first monitor, whenever that connects", function()
    load()
    eq(nil, S.workspace_rules["name:in"].monitor)
    fire("monitor.added", { name = "eDP-1", id = 0 })
    eq("eDP-1", S.workspace_rules["name:in"].monitor, "the first to connect")
    local last = S.dispatched[#S.dispatched]
    truthy(last and is_dsp(last, "focus"), "and it shows home")
    fire("monitor.added", { name = "DP-1", id = 1 })
    eq("eDP-1", S.workspace_rules["name:in"].monitor, "not a second")
end)

test("home is the first monitor's default when monitors are there as the config loads", function()
    load({ monitors = { { name = "DP-2", id = 1 }, { name = "eDP-1", id = 0 } } })
    eq("eDP-1", S.workspace_rules["name:in"].monitor, "by Hyprland's ID")
end)

test("tide-workspaces.lua names home and sends its apps there without switching", function()
    load({ workspaces = [[return { home = "mail", in_apps = { "(?i)(.*\\.)?thunderbird", "(?i)spotify" } }]] })
    eq(nil, S.workspace_rules["name:in"], "no rule for in")
    eq(true, S.workspace_rules["name:mail"].persistent)
    eq("(?i)(.*\\.)?thunderbird", S.rules["tide-home-app-1"].match.class)
    eq("name:mail silent", S.rules["tide-home-app-1"].workspace)
    eq("(?i)spotify", S.rules["tide-home-app-2"].match.class)
    eq(nil, S.rules["tide-home-app-3"])
    eq("mail", conf_workspaces.home())
    eq(0, #S.notifications)
end)

test("conf_workspaces.reload follows a new home and fewer apps", function()
    load({ workspaces = 'return { home = "in", in_apps = { "a", "b" } }' })
    write(TIDE_WORKSPACES, 'return { home = "home", in_apps = { "c" } }')
    conf_workspaces.reload()
    eq(false, S.workspace_rules["name:in"].enabled, "the old home's rule is off, through its handle")
    eq(true, S.workspace_rules["name:home"].persistent)
    eq("c", S.rules["tide-home-app-1"].match.class)
    eq("name:home silent", S.rules["tide-home-app-1"].workspace)
    eq(false, S.rules["tide-home-app-2"].enabled, "the rule a shorter list doesn't need is off")
    eq("home", conf_workspaces.home())
end)

test("a broken or wrong tide-workspaces.lua is reported, and home is in with no apps", function()
    for _, text in ipairs({
        "return {",
        "return 5",
        "return { home = 3 }",
        'return { home = "  " }',
        'return { home = "a\\nb" }',
        'return { home = "in", in_apps = "x" }',
        'return { home = "in", in_apps = { 1 } }',
        'return { home = "in", apps = {} }',
        'os.execute("true") return { home = "in" }',
    }) do
        load({ workspaces = text })
        eq(1, #S.notifications, text)
        truthy(S.notifications[1].text:find("tide-workspaces.lua", 1, true), S.notifications[1].text)
        truthy(S.workspace_rules["name:in"], text)
        eq(nil, S.rules["tide-home-app-1"], text)
    end
end)

test("with no tide-floating.lua only the dialogs float, and conf_floating is defined", function()
    load()
    eq(nil, S.rules["tide-float-1"])
    eq("function", type(conf_floating.reload))
    eq(0, #S.notifications)
end)

test("tide-floating.lua's rules float their windows, after the dialog rules, which stand", function()
    load({ floating = [[return { rules = {
        { class = "(?i)org\\.gnome\\.Calculator", title = ".*" },
        { class = "(?i)firefox", title = ".*(?:^Library$).*" },
    } }]] })
    local r = S.rules["tide-float-1"]
    eq("(?i)org\\.gnome\\.Calculator", r.match.class)
    eq(".*", r.match.title)
    eq(true, r.float)
    eq(true, r.enabled)
    eq(".*(?:^Library$).*", S.rules["tide-float-2"].match.title)
    eq(nil, S.rules["tide-float-3"])
    eq(true, S.rules["float-pavucontrol"].float, "conf's own rules stand")
    local order = {}
    for i, c in ipairs(S.calls) do
        if c[1] == "window_rule" then
            order[c[2].name] = i
        end
    end
    truthy(order["float-unnamed"] < order["tide-float-1"], "the dialogs' rules come first")
    eq(0, #S.notifications)
end)

test("conf_floating.reload replaces each rule's class and title, adds float once, and turns off what a shorter list drops", function()
    load({ floating = [[return { rules = {
        { class = "(?i)a", title = ".*(?:x).*" },
        { class = "(?i)b", title = ".*" },
    } }]] })
    write(TIDE_FLOATING, [[return { rules = { { class = "(?i)c", title = ".*" } } }]])
    conf_floating.reload()
    local r = S.rules["tide-float-1"]
    eq("(?i)c", r.match.class)
    eq(".*", r.match.title, "the old title pattern doesn't linger")
    eq(true, r.enabled)
    eq(1, r.added.float, "float is added once, not again at each reload")
    eq(false, S.rules["tide-float-2"].enabled, "the rule a shorter list doesn't need is off")
    write(TIDE_FLOATING, [[return { rules = {
        { class = "(?i)c", title = ".*" },
        { class = "(?i)d", title = ".*" },
    } }]])
    conf_floating.reload()
    eq(true, S.rules["tide-float-2"].enabled, "turned on again")
    eq("(?i)d", S.rules["tide-float-2"].match.class)
    eq(1, S.rules["tide-float-2"].added.float)
    eq(0, #S.notifications)
end)

test("a broken or wrong tide-floating.lua is reported, and only the dialogs float", function()
    local many = {}
    for i = 1, 65 do
        many[i] = '{ class = "c' .. i .. '", title = ".*" }'
    end
    for _, text in ipairs({
        "return {",
        "return 5",
        "return { rules = 5 }",
        "return { rule = {} }",
        'return { rules = { "x" } }',
        'return { rules = { { class = "x" } } }',
        'return { rules = { { class = "x", title = "" } } }',
        'return { rules = { { class = "x", title = ".*", workspace = "2" } } }',
        'return { rules = { [2] = { class = "x", title = ".*" } } }',
        "return { rules = { " .. table.concat(many, ", ") .. " } }",
        'os.execute("true") return { rules = {} }',
    }) do
        load({ floating = text })
        eq(1, #S.notifications, text)
        truthy(S.notifications[1].text:find("tide-floating.lua", 1, true), S.notifications[1].text)
        eq(nil, S.rules["tide-float-1"], text)
        eq(true, S.rules["float-modal"].float, text)
    end
end)

test("Super+Alt+F asks tide's shell for a floating rule for the window, and says so when there's no shell", function()
    load()
    local b = bind("SUPER + ALT + F")
    truthy(b.target.args:find("qs -c tide ipc call floating remember", 1, true), b.target.args)
    truthy(b.target.args:find("|| notify-send -a tide 'No floating rules'", 1, true), b.target.args)
    eq("Floating rule for this window", b.opts.description)
    local script = tmp .. "/super-alt-f.sh"
    local f = assert(io.open(script, "w"))
    f:write(b.target.args, "\n")
    f:close()
    truthy(os.execute("sh -n '" .. script .. "'"), "the command parses as sh")
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
