-- Tests for hyprland.lua: that it loads tide's with these preferences, and
-- what it does without tide. tide's own config is tested in tide
-- (hypr/hyprland_test.lua); here a fake stands in for it and records what
-- it's given.
--
-- Usage: lua hyprland_test.lua [path/to/hyprland.lua]

local here = arg[0]:match("^(.*)/[^/]*$") or "."
local config_path = arg[1] or (here .. "/hyprland.lua")

local passes, failures = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passes = passes + 1
    else
        failures = failures + 1
        io.stderr:write("FAIL: " .. name .. "\n  " .. tostring(err) .. "\n")
    end
end
local function eq(want, got, what)
    if want ~= got then
        error(string.format("%s: want %s, got %s", what or "value", tostring(want), tostring(got)), 2)
    end
end
local function truthy(v, what)
    if not v then
        error((what or "condition") .. " is false", 2)
    end
end

local tmp = os.tmpname()
os.remove(tmp)
assert(os.execute("mkdir -p '" .. tmp .. "'"))
local FAKE = tmp .. "/tide-hyprland.lua"
do
    local f = assert(io.open(FAKE, "w"))
    f:write("_G.tide_opts = ...\n")
    f:close()
end

-- A stub of what this file calls of Hyprland's API.
local S
local real_getenv = os.getenv
local env = {}
os.getenv = function(k)
    if env[k] ~= nil then
        return env[k] or nil
    end
    return real_getenv(k)
end
local function load(tide)
    S = { env = {}, binds = {}, notifications = {} }
    _G.tide_opts = nil
    env = { TIDE_HYPRLAND_LUA = tide }
    _G.hl = {
        env = function(k, v) S.env[k] = v end,
        bind = function(keys, target) S.binds[keys] = target end,
        notification = { create = function(t) table.insert(S.notifications, t) end },
        dsp = {
            exec_cmd = function(cmd) return { exec = cmd } end,
            exit = function() return { exit = true } end,
        },
    }
    assert(loadfile(config_path))()
    return _G.tide_opts
end

-- What the apps option binds, through a recording stand-in for tide's.
local function apps(opts)
    local bound = {}
    opts.apps({
        bind = function(name, keys, target, does) bound[name] = { keys = keys, target = target, does = does } end,
        key = function(k) return "SUPER + " .. k end,
        app = function(cmd) return { app = cmd } end,
        exec = function(cmd) return { exec = cmd } end,
        does = function(d) return d end,
    })
    return bound
end

test("loads tide's config with these preferences", function()
    local opts = load(FAKE)
    truthy(opts, "tide's config ran with options")
    eq("kitty", opts.terminal)
    eq("~/scripts/runenv", opts.run)
    eq("dvorak", opts.input.kb_variant)
    eq("compose:caps,altwin:menu_win", opts.input.kb_options)
    eq(true, opts.mouse.left_handed)
    eq(3, opts.mouse.scroll_factor)
    eq("~/scripts/runenv screenshot", opts.screenshot)
    truthy(opts.launcher:find("launch-fuzzel.sh", 1, true), "fuzzel outside tide's shell")
    eq("0", S.env.GTK_OVERLAY_SCROLLING)
    eq(0, #S.notifications, "nothing to say")
end)

test("the app keys run the scripts repo's helpers through runenv", function()
    local bound = apps(load(FAKE))
    eq("SUPER + G", bound.browser.keys)
    eq("~/scripts/runenv browser1", bound.browser.target.app)
    eq("~/scripts/runenv google-meet", bound.meet.target.app)
    eq("SUPER + SHIFT + C", bound.calendar.keys)
    eq("~/scripts/runenv bluetooth-connect", bound.headphones.target.exec)
    for name, b in pairs(bound) do
        truthy(type(b.does) == "string" and b.does ~= "", name .. " says what it does")
    end
end)

test("a plain Hyprland login also starts the wallpaper, theme and applets", function()
    local all = table.concat(load(FAKE).autostart, "\n")
    for _, cmd in ipairs({ "swww-daemon", "theme-daemon.sh", "nm-applet", "blueman-applet" }) do
        truthy(all:find(cmd, 1, true), cmd)
    end
end)

test("without tide's config, a terminal, a way out, and why", function()
    load(tmp .. "/missing.lua")
    eq("kitty", S.binds["SUPER + T"].exec)
    truthy(S.binds["SUPER + SHIFT + E"].exit, "Super+Shift+E quits")
    eq(1, #S.notifications)
    truthy(S.notifications[1].text:find("make install", 1, true), S.notifications[1].text)
end)

os.execute("rm -rf '" .. tmp .. "'")
print(string.format("hyprland_test.lua: %d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
