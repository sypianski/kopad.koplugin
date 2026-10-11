-- Tests for padmap.lua (pure) and its wiring in padnav.lua (with KOReader
-- stubs). Run from the repo root:  lua tests/padmap_test.lua
package.path = "./?.lua;" .. package.path

local P = require("padmap")

local function warns()
    local list = {}
    return list, function(m) list[#list + 1] = m end
end

local function r(res, kind, id) return { P.resolve(res, kind, id) } end
local function eq(a, b, msg)
    assert(a[1] == b[1] and a[2] == b[2],
        (msg or "") .. ": got " .. tostring(a[1]) .. "/" .. tostring(a[2])
        .. ", want " .. tostring(b[1]) .. "/" .. tostring(b[2]))
end

-- 1. Identity: no data, no layout -> every control maps to itself.
do
    local w, warn = warns()
    local res = P.build(nil, nil, warn)
    assert(res.layout == "xbox")
    for _, id in ipairs({ 0, 1, 2, 3, 4, 6, 9, 10 }) do
        eq(r(res, "button", id), { "button", id }, "identity btn " .. id)
    end
    eq(r(res, "axis", 4), { "axis", 4 }, "identity LT")
    eq(r(res, "axis", 5), { "axis", 5 }, "identity RT")
    -- Outside the remappable set: D-pad, Guide, L3, R3, sticks.
    for _, id in ipairs({ 5, 7, 8, 11, 12, 13, 14, 99 }) do
        eq(r(res, "button", id), { "button", id }, "passthrough btn " .. id)
    end
    for _, id in ipairs({ 0, 1, 2, 3 }) do
        eq(r(res, "axis", id), { "axis", id }, "stick axis " .. id)
    end
    assert(#w == 0, "no warnings expected")
    -- nil / broken resolution table -> identity
    eq(r(nil, "button", 1), { "button", 1 }, "nil res")
    eq(r("junk", "axis", 4), { "axis", 4 }, "junk res")
    -- empty layouts table, playstation layout: still identity
    eq(r(P.build({ version = 1, layouts = {} }, "playstation"), "button", 0), { "button", 0 }, "ps")
end

-- 2. Nintendo built-in default: A<->B, X<->Y follow the printed labels.
do
    local res = P.build(nil, "nintendo")
    eq(r(res, "button", 1), { "button", 0 }, "east -> a")
    eq(r(res, "button", 0), { "button", 1 }, "south -> b")
    eq(r(res, "button", 3), { "button", 2 }, "north -> x")
    eq(r(res, "button", 2), { "button", 3 }, "west -> y")
    eq(r(res, "button", 9), { "button", 9 }, "lb unchanged")
end

-- 3. User override on top of a layout default (only for the ACTIVE layout).
do
    local pm = { version = 1, layouts = {
        xbox = { south = "b", east = "a" },
        nintendo = { south = "a", east = "b" },   -- undo the swap for A/B only
    } }
    local x = P.build(pm, "xbox")
    eq(r(x, "button", 0), { "button", 1 }, "xbox south -> b")
    eq(r(x, "button", 1), { "button", 0 }, "xbox east -> a")
    eq(r(x, "button", 2), { "button", 2 }, "xbox west untouched")
    local n = P.build(pm, "nintendo")
    eq(r(n, "button", 0), { "button", 0 }, "nintendo south back to a")
    eq(r(n, "button", 3), { "button", 2 }, "nintendo north -> x still")
    local ps = P.build(pm, "playstation")
    eq(r(ps, "button", 0), { "button", 0 }, "playstation not affected")
end

-- 4. Axis vs button: triggers can become buttons and buttons triggers.
do
    local pm = { version = 1, layouts = { xbox = {
        ltrigger = "rt", rtrigger = "a", rshoulder = "lt",
    } } }
    local res = P.build(pm, "xbox")
    eq(r(res, "axis", 4), { "axis", 5 }, "LT -> rt (axis)")
    eq(r(res, "axis", 5), { "button", 0 }, "RT -> a (button)")
    eq(r(res, "button", 10), { "axis", 4 }, "RB -> lt (axis)")
    eq(r(res, "button", 9), { "button", 9 }, "LB untouched")
    -- a button id never resolves through the axis table and vice versa
    eq(r(res, "button", 4), { "button", 4 }, "btn 4 (back) not axis 4")
end

-- 5. Malformed data is ignored with a warning, never raises.
do
    local bad = {
        42, "x", { version = 2, layouts = { xbox = { south = "b" } } },
        { layouts = { xbox = { south = "b" } } },             -- no version
        { version = 1, layouts = "x" },
        { version = 1, layouts = { xbox = "nope" } },
        { version = 1, layouts = { xbox = { [1] = "b", south = 7, east = "jump",
                                            dpad_up = "a", ["1"] = "a" } } },
    }
    for i, pm in ipairs(bad) do
        local w, warn = warns()
        local ok, res = pcall(P.build, pm, "xbox", warn)
        assert(ok, "build raised on case " .. i)
        assert(#w >= 1, "expected a warning on case " .. i)
        for _, id in ipairs({ 0, 1, 2, 3, 4, 6, 9, 10 }) do
            eq(r(res, "button", id), { "button", id }, "bad case " .. i .. " btn " .. id)
        end
    end
    -- a valid entry next to an invalid one still applies
    local w, warn = warns()
    local res = P.build({ version = 1, layouts = { xbox = { south = "b", east = "zz" } } }, "xbox", warn)
    eq(r(res, "button", 0), { "button", 1 }, "valid entry applied")
    eq(r(res, "button", 1), { "button", 1 }, "invalid entry skipped")
    assert(#w == 1)
end

-- 6. Unknown layout (data or device setting) -> warning + default layout.
do
    local w, warn = warns()
    local res = P.build({ version = 1, layouts = { gamecube = { south = "b" } } }, "gamecube", warn)
    assert(res.layout == "xbox")
    eq(r(res, "button", 0), { "button", 0 }, "unknown layout -> identity")
    assert(#w == 2, "two warnings: device layout + data layout, got " .. #w)
    local w2, warn2 = warns()
    P.build(nil, 17, warn2)
    assert(#w2 == 1)
end

-- 7. padnav.lua wiring, with minimal KOReader stubs.
do
    local function stub(name, v) package.preload[name] = function() return v end end
    local IC = {}
    function IC:extend(o) o = o or {}; setmetatable(o, { __index = self }); o.__index = o; return o end
    stub("ui/event", {}); stub("ui/widget/container/inputcontainer", IC)
    stub("ui/uimanager", { _window_stack = {} })
    stub("ui/time", { now = function() return 0 end, to_s = function(t) return t end })
    stub("logger", { warn = function() end, dbg = function() end })
    stub("pluginaro", { overlay_active = function() return false end })
    stub("gettext", function(s) return s end)
    local PadNav = require("padnav")

    local function nav(resolved)
        local calls = {}
        local o = setmetatable({ enabled_ref = { enabled = true } }, { __index = PadNav })
        o._is_enabled = function() return true end
        o._top_menu = function() return nil end
        for _, m in ipairs({ "onKPConfirm", "onKPBack", "onKPExtend", "onKPMenu",
                             "onKPSelect", "onKPStart", "onKPPgBk", "onKPPgFwd",
                             "onKPPgBk2", "onKPPgFwd2" }) do
            o[m] = function() calls[#calls + 1] = m; return true end
        end
        o:set_padmap(resolved)
        return o, calls
    end

    -- identity (no padmap): physical A -> onKPConfirm, D-pad passes through
    local n, c = nav(nil)
    assert(n:onGamepadButtonDown({ button = 0 }) == true and c[1] == "onKPConfirm")
    assert(n:onGamepadButtonDown({ button = 11 }) == false, "D-pad passthrough")
    assert(n:onGamepadAxisMotion({ axis = 5, value = 32767 }) == true and c[2] == "onKPPgFwd2")

    -- nintendo: physical east (1) -> role A -> onKPConfirm
    n, c = nav(P.build(nil, "nintendo"))
    n:onGamepadButtonDown({ button = 1 }); assert(c[1] == "onKPConfirm", c[1])
    n:onGamepadButtonDown({ button = 0 }); assert(c[2] == "onKPBack", c[2])

    -- trigger -> button and button -> trigger
    n, c = nav(P.build({ version = 1, layouts = { xbox = { rtrigger = "a", rshoulder = "lt" } } }, "xbox"))
    assert(n:onGamepadAxisMotion({ axis = 5, value = 32767 }) == true and c[1] == "onKPConfirm")
    assert(n:onGamepadButtonDown({ button = 10 }) == true and c[2] == "onKPPgBk2")
    -- kopad switched off: remapped trigger passes through
    n.enabled_ref.enabled = false
    assert(n:onGamepadAxisMotion({ axis = 5, value = 32767 }) == false)
end

-- 8. Valve layout (Steam Deck / Steam Controller; PC-013): known layout, last in
-- LAYOUT_ORDER, built-in default = identity (same positions as xbox).
do
    assert(P.LAYOUTS.valve and next(P.LAYOUTS.valve.default) == nil, "valve default is empty")
    local want = { "xbox", "playstation", "nintendo", "valve" }
    assert(#P.LAYOUT_ORDER == #want, "LAYOUT_ORDER length " .. #P.LAYOUT_ORDER)
    for i, name in ipairs(want) do assert(P.LAYOUT_ORDER[i] == name, "LAYOUT_ORDER[" .. i .. "]") end
    for _, name in ipairs(P.LAYOUT_ORDER) do assert(P.LAYOUTS[name], name .. " in LAYOUTS") end

    -- device setting padmap_layout = "valve" is accepted without a warning,
    -- with and without shared data
    local w, warn = warns()
    local v = P.build(nil, "valve", warn)
    assert(v.layout == "valve" and #w == 0, "valve accepted silently")
    local v2 = P.build({ version = 1, layouts = { valve = {} } }, "valve", warn)
    assert(v2.layout == "valve" and #w == 0, "valve data accepted silently")

    -- identity: identical to the xbox resolution on every control
    local x = P.build(nil, "xbox")
    for _, id in ipairs({ 0, 1, 2, 3, 4, 6, 9, 10, 5, 7, 11, 99 }) do
        eq(r(v, "button", id), r(x, "button", id), "valve == xbox btn " .. id)
        eq(r(v, "button", id), { "button", id }, "valve identity btn " .. id)
    end
    for _, id in ipairs({ 0, 1, 2, 3, 4, 5 }) do
        eq(r(v, "axis", id), r(x, "axis", id), "valve == xbox axis " .. id)
    end
    eq(r(v, "axis", 4), { "axis", 4 }, "valve LT/L2")
    eq(r(v, "axis", 5), { "axis", 5 }, "valve RT/R2")

    -- overrides apply only to the active valve layout, and valve data does not
    -- leak into the other layouts
    local pm = { version = 1, layouts = {
        valve = { south = "b", east = "a", ltrigger = "rt" },
        xbox = { west = "y" },
    } }
    local pv = P.build(pm, "valve")
    eq(r(pv, "button", 0), { "button", 1 }, "valve south -> b")
    eq(r(pv, "button", 1), { "button", 0 }, "valve east -> a")
    eq(r(pv, "axis", 4), { "axis", 5 }, "valve ltrigger -> rt")
    eq(r(pv, "button", 2), { "button", 2 }, "xbox override not applied to valve")
    for _, name in ipairs({ "xbox", "playstation", "nintendo" }) do
        local o = P.build(pm, name)
        local south = name == "nintendo" and { "button", 1 } or { "button", 0 }
        eq(r(o, "button", 0), south, name .. " not affected by valve data")
        eq(r(o, "axis", 4), { "axis", 4 }, name .. " LT not affected by valve data")
    end

    -- the back paddles (SDL ids 16+) are not in the vocabulary and pass through
    for _, id in ipairs({ 16, 17, 18, 19 }) do
        eq(r(v, "button", id), { "button", id }, "paddle " .. id .. " passthrough")
    end
    for _, name in ipairs({ "l4", "l5", "r4", "r5", "paddle1" }) do
        assert(P.PHYSICAL[name] == nil, name .. " must not be a physical control")
    end

    -- an unknown layout still warns and falls back to xbox (valve did not
    -- relax validation)
    local w2, warn2 = warns()
    local u = P.build({ version = 1, layouts = { steamdeck = { south = "b" } } }, "steamdeck", warn2)
    assert(u.layout == "xbox" and #w2 == 2, "unknown layout: warning + xbox, got " .. #w2)
    local w3, warn3 = warns()
    assert(P.build(nil, "Valve", warn3).layout == "xbox" and #w3 == 1, "layout ids are case-sensitive")
end

print("padmap_test: all tests passed")
