-- Tests for hyprland.lua, run against a stub of Hyprland's `hl` API.
--
-- Usage: lua hyprland_test.lua TIDE_CONFIG [path/to/hyprland.lua]
--
-- hyprland.lua is tide's Hyprland config with my changes, so it loads
-- tide's: TIDE_CONFIG is tide's hypr/tide/config.lua, which each case puts
-- where tide's `make install` would. tide's own tests cover tide's config;
-- these cover what this file changes, and that the two load together. Each
-- case loads the config fresh under a fake $HOME, so tide's layout and
-- hyprland.local.lua can be present, missing or broken. The stub records
-- every call; bound functions are then called against stubbed getters to
-- check what they dispatch.

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local tide_config = assert(arg[1], "usage: lua hyprland_test.lua TIDE_CONFIG [hyprland.lua]")
local config_path = arg[2] or (here .. "/hyprland.lua")

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
assert(os.execute("mkdir -p '" .. tmp .. "/.config/hypr/tide' '" .. tmp .. "/run/hypr/sig1'"))

local function write(rel, text)
    local f = assert(io.open(tmp .. "/" .. rel, "w"))
    f:write(text)
    f:close()
end

local TIDE = ".config/hypr/tide/config.lua"
local LAYOUT = ".config/hypr/tide/layout.lua"
local LOCAL = ".config/hypr/hyprland.local.lua"
local TIDE_INPUT = ".config/hypr/tide-input.lua"
local TIDE_KEYS = ".config/hypr/tide-keys.lua"
local KEYS_FILE = "run/hypr/sig1/tide-keys.json"

local tide_text
do
    local f = assert(io.open(tide_config))
    tide_text = f:read("a")
    f:close()
end

-- A stand-in for the tide layout: every helper is a function that
-- records its own name when called.
local FAKE_LAYOUT = [[
local M = { calls = {} }
local function helper(name)
    return function(...) table.insert(M.calls, { name, ... }) end
end
for _, n in ipairs({ "cycle_next", "cycle_prev", "last_mode", "toggle_monocle", "grow", "shrink",
                     "add_master", "remove_master", "swap_with_master", "focus", "move",
                     "focus_side", "move_side", "drag_press", "drag_release" }) do
    M[n] = helper(n)
end
function M.setup(opts) M.setup_opts = opts end
_G.fake_layout = M
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
        -- The running Hyprland's version, as hl.version() gives it.
        version = function() return S.version end,
        notification = {
            create = function(t) table.insert(S.notifications, t) end,
        },
        -- A getter set to "raise" fails, as Hyprland's can mid-transition.
        get_active_workspace = function()
            if S.active_workspace == "raise" then error("workspace gone") end
            return S.active_workspace
        end,
        get_active_monitor = function() return S.active_monitor end,
        -- By "address:0x…", from S.windows_by_address.
        get_window = function(selector)
            return (S.windows_by_address or {})[(selector or ""):gsub("^address:", "")]
        end,
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
        get_windows = function() return S.window_list or {} end,
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

-- A fresh Hyprland instance each time, with tide's config installed
-- unless `no_tide`.
local function load(setup)
    setup = setup or {}
    assert(os.execute("rm -rf '" .. tmp .. "/.config' '" .. tmp .. "/run' && mkdir -p '" .. tmp .. "/.config/hypr/tide' '" .. tmp .. "/run/hypr/sig1'"))
    if not setup.no_tide then
        write(TIDE, tide_text)
    end
    for rel, text in pairs({ [LAYOUT] = setup.layout, [LOCAL] = setup["local"], [TIDE_INPUT] = setup.input, [TIDE_KEYS] = setup.keys }) do
        write(rel, text)
    end
    env_overrides = { XDG_RUNTIME_DIR = tmp .. "/run", HYPRLAND_INSTANCE_SIGNATURE = "sig1", XDG_CURRENT_DESKTOP = false }
    for k, v in pairs(setup.env or {}) do
        env_overrides[k] = v
    end
    _G.fake_layout = nil
    _G.hl = new_hl()
    S.version = setup.version or "0.57.1"
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

-- tide-keys.json as { name = { does, defaults, keys, at } }, at its place in
-- the list.
local function listed_keys()
    local f = assert(io.open(tmp .. "/" .. KEYS_FILE))
    local text = f:read("a")
    f:close()
    local function strings(list)
        local out = {}
        for v in list:gmatch('"(.-)"') do
            table.insert(out, v)
        end
        return out
    end
    local out, n = {}, 0
    for name, does, defaults, keys in text:gmatch('{"name":"(.-)","does":"(.-)","defaults":(%b[]),"keys":(%b[])}') do
        n = n + 1
        out[name] = { does = does, defaults = strings(defaults), keys = strings(keys), at = n }
    end
    return out, n
end

-- Two lists of strings are the same, in order.
local function same(want, got, what)
    eq(table.concat(want, " | "), table.concat(got or { "(nil)" }, " | "), what)
end

local function bound(keys)
    return S.binds["|" .. keys]
end

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

--------------------------------------------------------------------------------
-- tide's config, and this file's changes to it
--------------------------------------------------------------------------------
test("without tide's config installed, the config stops and says how to get it", function()
    local ok, err = pcall(load, { no_tide = true })
    eq(false, ok)
    truthy(tostring(err):find("tide's Hyprland config isn't installed", 1, true), tostring(err))
    truthy(tostring(err):find("run make install in tide", 1, true), tostring(err))
end)

test("every hl.config key is one Hyprland accepts", function()
    load({ layout = FAKE_LAYOUT })
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

test("every key in tide's spec is bound, with mine", function()
    load({ layout = FAKE_LAYOUT })
    for _, k in ipairs({
        "SUPER + Space", "SUPER + T", "SUPER + W", "SUPER + V", "SUPER + G", "SUPER + F",
        "SUPER + SHIFT + G", "SUPER + E", "SUPER + B", "SUPER + C", "SUPER + SHIFT + C", "SUPER + SHIFT + V", "SUPER + semicolon",
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
    }) do
        bind(k)
    end
    eq(0, #S.notifications, "nothing to report")
end)

test("launchers run the scripts repo's helpers through runenv", function()
    load()
    for keys, cmd in pairs({
        ["SUPER + W"] = "terminal_on_workstation", ["SUPER + G"] = "browser1", ["SUPER + SHIFT + G"] = "browser3",
        ["SUPER + F"] = "browser2", ["SUPER + B"] = "bluetooth-connect", ["SUPER + SHIFT + B"] = "pulseprofile.py",
        ["SUPER + C"] = "google-chat", ["SUPER + SHIFT + C"] = "google-calendar", ["SUPER + H"] = "home",
        ["SUPER + I"] = "irc", ["SUPER + M"] = "google-meet", ["SUPER + N"] = "notepad",
        ["SUPER + R"] = "remote-desktop", ["SUPER + Y"] = "youtube-music",
    }) do
        eq("~/scripts/runenv " .. cmd, bind(keys).target.args, keys)
    end
    eq("kitty", bind("SUPER + T").target.args, "tide's terminal")
    eq("kitty -e yazi", bind("SUPER + E").target.args)
    truthy(bind("SUPER + Space").target.args:find("runenv", 1, true), "launcher through runenv")
end)

test("in the tide session, app keys go through tide launch", function()
    load({ env = { XDG_CURRENT_DESKTOP = "tide:Hyprland" } })
    eq("tide launch --app '*' -- ~/scripts/runenv browser1", bind("SUPER + G").target.args)
    eq("tide launch --app 'kitty' -- kitty -e yazi", bind("SUPER + E").target.args)
    -- Not apps: these stay plain commands.
    eq("~/scripts/runenv bluetooth-connect", bind("SUPER + B").target.args)
    eq("qs -c tide ipc call notifications toggle || swaync-client -t -sw", bind("SUPER + SHIFT + N").target.args)
end)

test("Super+D stays free for hyprland.local.lua", function()
    load()
    eq(nil, S.binds["|SUPER + D"], "SUPER + D")
end)

test("screenshots run the scripts repo's screenshot through runenv", function()
    load()
    for keys, args in pairs({
        ["Print"] = "", ["ALT + Print"] = " --window",
        ["SHIFT + Print"] = " --region", ["SUPER + Print"] = " --region",
    }) do
        eq("~/scripts/runenv screenshot" .. args, bind(keys).target.args, keys)
    end
end)

-- Runs binding `keys`'s command with qs exiting `status`, and a fake
-- `fallback` on PATH and at ~/scripts/runenv: what it printed.
local function with_fakes(keys, status)
    local cmd = bind(keys).target.args
    local script = "d=$(mktemp -d) || exit 1; mkdir \"$d/scripts\"; "
        .. "printf '#!/bin/sh\\necho fallback \"$@\"\\n' >\"$d/scripts/runenv\"; "
        .. "cp \"$d/scripts/runenv\" \"$d/swaync-client\"; "
        .. "chmod +x \"$d/scripts/runenv\" \"$d/swaync-client\"; HOME=\"$d\"; PATH=\"$d:$PATH\"; "
        .. "qs() { echo \"$*\"; return " .. status .. "; }; " .. cmd .. "; rm -rf \"$d\""
    local p = io.popen("sh -c '" .. script:gsub("'", "'\\''") .. "'")
    local out = p:read("a")
    p:close()
    return out
end

test("Super+Space opens tide's launcher, else fuzzel", function()
    load()
    for status, fallback in pairs({ [0] = false, [1] = true, [255] = true, [127] = true }) do
        local out = with_fakes("SUPER + Space", status)
        truthy(out:find("-c tide ipc call launcher toggle", 1, true), "qs called")
        eq(fallback, out:find("fallback", 1, true) ~= nil, "fallback after exit " .. status)
        if fallback then
            truthy(out:find("launch-fuzzel.sh", 1, true), "fallback is fuzzel")
        end
    end
end)

test("Super+Shift+N opens tide's notification center, else swaync's", function()
    load()
    for status, fallback in pairs({ [0] = false, [1] = true, [255] = true, [127] = true }) do
        local out = with_fakes("SUPER + SHIFT + N", status)
        truthy(out:find("-c tide ipc call notifications toggle", 1, true), "qs called")
        eq(fallback, out:find("fallback -t -sw", 1, true) ~= nil, "fallback after exit " .. status)
    end
end)

test("my bindings are named for tide's Keyboard shortcuts, after tide's, and it can give them keys", function()
    load({ keys = [[return { keys = { browser = { "SUPER + D" }, files = {} } }]] })
    local keys, n = listed_keys()
    eq(1, keys.terminal.at, "tide's first")
    eq("Browser", keys.browser.does)
    same({ "SUPER + G" }, keys.browser.defaults)
    same({ "SUPER + D" }, keys.browser.keys)
    eq("~/scripts/runenv browser1", bind("SUPER + D").target.args)
    eq(nil, S.binds["|SUPER + G"])
    eq(nil, S.binds["|SUPER + E"], "files is off")
    eq(n, keys.files.at, "mine last, in this file's order")
    eq(2, keys.launcher.at, "my launcher in tide's place")
    eq(0, #S.notifications)
end)

test("the keyboard is US Dvorak with Caps Lock as Compose and Menu as Super, under tide's settings", function()
    load()
    eq("us", S.config.input.kb_layout)
    eq("dvorak", S.config.input.kb_variant)
    eq("compose:caps,altwin:menu_win", S.config.input.kb_options)
    S.calls = {}
    conf_input.keyboard("at-keyboard")
    eq("dvorak", devices()[1].kb_variant)
    load({ input = [[return { keyboard = { kb_layout = "us,de", kb_variant = "dvorak," } }]] })
    eq("us,de", S.config.input.kb_layout)
    eq("dvorak,", S.config.input.kb_variant, "tide's settings win")
    eq("compose:caps,altwin:menu_win", S.config.input.kb_options, "what tide doesn't set stays")
end)

test("mice have the right button first, with apply-input's wheel speed, unless tide's settings say", function()
    load()
    S.calls = {}
    conf_input.mouse("logitech-usb-receiver", 3)
    conf_input.touchpad("synps/2-synaptics-touchpad")
    local d = devices()
    eq(true, d[1].left_handed)
    eq(3, d[1].scroll_factor)
    eq(false, d[2].left_handed, "a touchpad keeps the left button first")
    load({ input = [[return { mouse = { left_handed = false } }]] })
    S.calls = {}
    conf_input.mouse("logitech-usb-receiver", 3)
    eq(false, devices()[1].left_handed)
end)

test("the input setup runs through runenv, after a load and each change to tide's settings", function()
    for _, desktop in ipairs({ "tide:Hyprland", "Hyprland" }) do
        load({ env = { XDG_CURRENT_DESKTOP = desktop } })
        fire("config.reloaded")
        same({ "~/scripts/runenv ~/.config/hypr/scripts/apply-input.sh" }, S.execs, desktop)
    end
    S.execs = {}
    conf_input.reload()
    same({ "~/scripts/runenv ~/.config/hypr/scripts/apply-input.sh" }, S.execs, "a change")
end)

test("a plain Hyprland login starts the transitional desktop, and the tide session only uwsm's", function()
    load()
    eq(0, #S.execs, "nothing runs while the config loads")
    fire("hyprland.start")
    local all = table.concat(S.execs, "\n")
    for _, cmd in ipairs({ "hypridle", "swww-daemon", "runenv ~/.config/hypr/scripts/apply-input.sh",
        "runenv ~/.config/hypr/scripts/watch-input.sh", "theme-daemon.sh", "nm-applet", "blueman-applet" }) do
        truthy(all:find(cmd, 1, true), cmd)
    end
    load({ env = { XDG_CURRENT_DESKTOP = "tide:Hyprland" } })
    fire("hyprland.start")
    same({ "uwsm finalize" }, S.execs)
end)

test("GTK keeps classic scrollbars, and PATH is never set (runenv owns it)", function()
    load()
    eq("0", S.config.env.GTK_OVERLAY_SCROLLING)
    eq(nil, S.config.env.PATH, "env PATH")
end)

--------------------------------------------------------------------------------
-- Per-machine overrides
--------------------------------------------------------------------------------
test("hyprland.local.lua loads last, so its settings win, over tide's too", function()
    load({ ["local"] = "hl.config({ decoration = { dim_strength = 0.25 } })\nhl.unbind('SUPER + E')\nhl.bind('SUPER + E', hl.dsp.exec_cmd('nautilus'))" })
    eq(0.25, S.config.decoration.dim_strength)
    eq("nautilus", bind("SUPER + E").target.args)
    same({}, listed_keys().files.keys, "Files gave up Super+E")
    local last = S.calls[#S.calls]
    eq("bind", last[1], "nothing comes after the local file's calls")
    write(".config/hypr/tide-appearance.lua", "return { dim_strength = 0.05 }")
    conf_appearance.reload()
    eq(0.25, S.config.decoration.dim_strength, "tide's dim doesn't take it back")
end)

test("a broken hyprland.local.lua is reported, and the rest stands", function()
    load({ ["local"] = "this is not lua" })
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("hyprland.local.lua (none of it applied)", 1, true), S.notifications[1].text)
    load({ ["local"] = 'hl.config({ decoration = { dim_strength = 0.3 } })\nerror("late")' })
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("hyprland.local.lua stopped (the calls before this applied)", 1, true), S.notifications[1].text)
    eq(0.3, S.config.decoration.dim_strength)
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

--------------------------------------------------------------------------------
-- Lua 5.5, Hyprland's, makes a for loop's variables constant, so assigning
-- to one stops the config at load. The tests run on 5.4 too, which allows
-- it, so the source is checked instead. A loop's body is the lines indented
-- under it, up to its `end` at its own indent; a one-line loop is skipped.
--------------------------------------------------------------------------------
local function loop_var_assignments(text)
    local found, open = {}, {}
    local n = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local code = line:gsub("%-%-.*$", "")
        local indent = #code:match("^(%s*)")
        while #open > 0 and indent <= open[#open].indent and code:match("^%s*end") do
            if indent == open[#open].indent then
                table.remove(open)
                break
            end
            table.remove(open)
        end
        local names = code:match("^%s*for%s+([%w_%s,]-)%s+in%s") or code:match("^%s*for%s+([%w_]+)%s*=")
        if names and not code:match("%f[%w_]end%f[^%w_]%s*[%),]*%s*$") then
            local vars = {}
            for v in names:gmatch("[%w_]+") do
                vars[#vars + 1] = v
            end
            open[#open + 1] = { indent = indent, vars = vars }
        elseif not code:match("^%s*local%s") then
            local lhs = code:match("^%s*([%w_%s,%.%[%]\"]-)%s*=[^=]")
            if lhs then
                for _, loop in ipairs(open) do
                    for _, v in ipairs(loop.vars) do
                        for target in lhs:gmatch("[^,]+") do
                            if target:match("^%s*(.-)%s*$") == v then
                                found[#found + 1] = string.format("%d: %s", n, line:match("^%s*(.-)%s*$"))
                            end
                        end
                    end
                end
            end
        end
    end
    return found
end

test("the loop-variable check finds an assignment to a loop's variable", function()
    same({ "2: part = part:upper()" }, loop_var_assignments(table.concat({
        "for part in s:gmatch('x') do",
        "    part = part:upper()",
        "end",
    }, "\n")))
    same({ "2: a, i = 1, 2" }, loop_var_assignments("for i = 1, 3 do\n    a, i = 1, 2\nend"))
    same({ "3: k = 1" }, loop_var_assignments("for k, v in pairs(t) do\n    if v then\n        k = 1\n    end\nend"))
end)

test("the loop-variable check allows a local of the same name, and code after the loop", function()
    same({}, loop_var_assignments(table.concat({
        "for raw in s:gmatch('x') do",
        "    local part = raw  -- part = nothing",
        "    t.part = part",
        "    ok = part == raw",
        "end",
        "raw = 1",
        "for i = 1, 2 do f(i) end",
        "i = 3",
    }, "\n")))
end)

test("hyprland.lua assigns to no loop's variable (Lua 5.5 makes them constant)", function()
    local f = assert(io.open(config_path))
    local text = f:read("a")
    f:close()
    same({}, loop_var_assignments(text))
end)

os.execute("rm -rf '" .. tmp .. "'")
io.write(string.format("hyprland_test.lua: %d passed, %d failed\n", passes, failures))
os.exit(failures == 0 and 0 or 1)
