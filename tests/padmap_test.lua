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

-- 9. Role-level actions (PC-014): `actions` = role -> reading action, shared by
-- every layout, additive within version 1.
do
    -- vocabulary is consistent
    local seen = {}
    for _, id in ipairs(P.ACTION_ORDER) do
        assert(P.ACTIONS[id], id .. " in ACTIONS"); assert(not seen[id], id .. " duplicated"); seen[id] = true
    end
    local n = 0
    for _ in pairs(P.ACTIONS) do n = n + 1 end
    assert(n == #P.ACTION_ORDER, "ACTIONS and ACTION_ORDER agree")
    for role, act in pairs(P.DEFAULT_ACTIONS) do
        assert(P.ROLES[role], "default for known role " .. role)
        assert(P.ACTIONS[act], "default action " .. act .. " is in the vocabulary")
    end
    assert(P.DEFAULT_ACTIONS.b == nil, "B has no action id: KOReader's own Back runs")

    -- logical (kind, id) -> role name, both directions agree with ROLES
    for name, ro in pairs(P.ROLES) do assert(P.role_of(ro.kind, ro.id) == name, "role_of " .. name) end
    assert(P.role_of("button", 5) == nil and P.role_of("button", 11) == nil, "Guide/D-pad have no role")
    assert(P.role_of("axis", 0) == nil and P.role_of("nothing", 0) == nil)
    assert(P.role_of("button", 4) == "select" and P.role_of("axis", 4) == "lt", "button 4 != axis 4")

    -- no data / no key: empty
    assert(next(P.build(nil, "xbox").actions) == nil)
    assert(next(P.build({ version = 1 }, "xbox").actions) == nil)
    assert(next(P.build({ version = 1, actions = {} }, "xbox").actions) == nil)

    -- values equal to the built-in default are dropped, the rest kept
    local w, warn = warns()
    local res = P.build({ version = 1, actions = {
        rb = "top_menu", select = "next_page", a = "sentence_select", b = "none", lt = "prev_page",
    } }, "xbox", warn)
    assert(res.actions.rb == "top_menu" and res.actions.select == "next_page" and res.actions.b == "none")
    assert(res.actions.a == nil and res.actions.lt == nil, "defaults dropped")
    assert(#w == 0, "valid actions give no warnings")

    -- shared by every layout, independent of the layout's controls
    for _, name in ipairs(P.LAYOUT_ORDER) do
        local o = P.build({ version = 1, layouts = { [name] = { south = "b" } },
                            actions = { rb = "toc" } }, name)
        assert(o.actions.rb == "toc", name .. " has the shared actions")
        eq(r(o, "button", 0), { "button", 1 }, name .. " layouts still apply next to actions")
    end

    -- malformed: skipped with a warning, never raises; the two stages are independent
    local bad = {
        { version = 1, actions = "x" },
        { version = 1, actions = { rb = "teleport" } },
        { version = 1, actions = { rb = 7 } },
        { version = 1, actions = { rb = { "top_menu" } } },
        { version = 1, actions = { dpad = "next_page" } },
        { version = 1, actions = { [1] = "next_page" } },
    }
    for i, pm in ipairs(bad) do
        local wi, warni = warns()
        local ok, o = pcall(P.build, pm, "xbox", warni)
        assert(ok, "build raised on actions case " .. i)
        assert(#wi >= 1, "expected a warning on actions case " .. i)
        assert(next(o.actions) == nil, "nothing applied on actions case " .. i)
    end
    -- a valid entry next to an invalid one still applies
    local w2, warn2 = warns()
    local mix = P.build({ version = 1, actions = { rb = "top_menu", lb = "teleport" } }, "xbox", warn2)
    assert(mix.actions.rb == "top_menu" and mix.actions.lb == nil and #w2 == 1)
    -- broken layouts do not discard valid actions, and vice versa
    local w3, warn3 = warns()
    local a = P.build({ version = 1, layouts = "x", actions = { rb = "toc" } }, "xbox", warn3)
    assert(a.actions.rb == "toc" and #w3 == 1)
    local w4, warn4 = warns()
    local l = P.build({ version = 1, layouts = { xbox = { south = "b" } }, actions = "x" }, "xbox", warn4)
    eq(r(l, "button", 0), { "button", 1 }, "layouts apply next to broken actions")
    assert(#w4 == 1)
    -- wrong version: nothing from the table applies, actions included
    local w5, warn5 = warns()
    local v2 = P.build({ version = 2, actions = { rb = "toc" } }, "xbox", warn5)
    assert(next(v2.actions) == nil and #w5 == 1)
    assert(next(P.build(42, "xbox", warn5).actions) == nil)
end

-- 10. Action overrides in padnav.lua (idle reading context only), KOReader stubbed.
do
    local Event = require("ui/event")
    Event.new = function(_, name, ...) return { name = name, args = { ... } } end
    local PadNav = require("padnav")

    -- ctx: dict (open popup), overlay (selection overlay), doc (false = FileManager)
    local function nav(padmap, ctx)
        ctx = ctx or {}
        local log = { events = {}, calls = {}, footer = 0, selector = {} }
        local selector = ctx.selector
        if ctx.overlay then selector = selector or {}; selector.overlay = {} end
        if selector then
            selector._open = function() log.selector[#log.selector + 1] = "_open" end
            selector._open_walk = function(_, from_end) log.selector[#log.selector + 1] = "_open_walk:" .. tostring(from_end) end
        end
        local o = setmetatable({
            enabled_ref = { enabled = true },
            ui = {
                document = ctx.doc ~= false and {} or nil,
                handleEvent = function(_, ev) log.events[#log.events + 1] = ev.name .. (ev.args[1] and (":" .. tostring(ev.args[1])) or "") end,
                view = { footer = { onToggleFooterMode = function() log.footer = log.footer + 1 end } },
            },
        }, { __index = PadNav })
        o._is_enabled = function() return true end
        o._top_menu = function() return nil end
        o._find_dict_widget = function() return ctx.dict end
        o._selector = function() return selector end
        o._open_sentence_select = function(_, i) log.calls[#log.calls + 1] = "sentence_select:" .. tostring(i) end
        o._open_highlights = function() log.calls[#log.calls + 1] = "highlights" end
        for _, m in ipairs({ "onKPConfirm", "onKPBack", "onKPExtend", "onKPMenu",
                             "onKPSelect", "onKPStart", "onKPPgBk", "onKPPgFwd",
                             "onKPPgBk2", "onKPPgFwd2" }) do
            o[m] = function() log.calls[#log.calls + 1] = m; return true end
        end
        o:set_padmap(padmap and P.build(padmap, "xbox") or nil)
        return o, log
    end
    local function acts(t) return { version = 1, actions = t } end

    -- no `actions`: nothing changes (built-in handlers)
    local n, log = nav(nil)
    n:onGamepadButtonDown({ button = 10 }); assert(log.calls[1] == "onKPPgFwd" and #log.events == 0)
    n, log = nav({ version = 1 })
    assert(n._actions == nil, "no overrides -> no table")
    n:onGamepadButtonDown({ button = 10 }); assert(log.calls[1] == "onKPPgFwd")

    -- RB -> top menu in plain reading: Event ShowMenu, built-in RB handler not called
    n, log = nav(acts({ rb = "top_menu" }))
    assert(n:onGamepadButtonDown({ button = 10 }) == true)
    assert(log.events[1] == "ShowMenu" and #log.calls == 0, "RB opened the top menu")
    -- the other bumper keeps its built-in
    n:onGamepadButtonDown({ button = 9 }); assert(log.calls[1] == "onKPPgBk")

    -- every id of the vocabulary has a runner and a cheat-sheet label, and nothing else does
    for _, id in ipairs(P.ACTION_ORDER) do
        assert(type(PadNav._ACTION_RUNNERS[id]) == "function", id .. " has a runner")
        assert(type(PadNav._ACTION_LABELS[id]) == "string", id .. " has a label")
    end
    for id in pairs(PadNav._ACTION_RUNNERS) do assert(P.ACTIONS[id], "runner " .. id .. " is in the vocabulary") end
    for id in pairs(PadNav._ACTION_LABELS) do assert(P.ACTIONS[id], "label " .. id .. " is in the vocabulary") end

    -- every simple event action
    local EVENTS = {
        next_page = "GotoViewRel:1", prev_page = "GotoViewRel:-1",
        pages_forward_10 = "GotoViewRel:10", pages_back_10 = "GotoViewRel:-10",
        next_chapter = "GotoNextChapter", prev_chapter = "GotoPrevChapter",
        first_page = "GoToBeginning", last_page = "GoToEnd",
        back_location = "GoBackLink:true", forward_location = "GoForwardLink",
        goto_page = "ShowGotoDialog", skim = "ShowSkimtoDialog",
        top_menu = "ShowMenu", config_menu = "ShowConfigMenu",
        toc = "ShowToc", bookmarks = "ShowBookmark", toggle_bookmark = "ToggleBookmark",
        next_bookmark = "GotoNextBookmarkFromPage", prev_bookmark = "GotoPreviousBookmarkFromPage",
        book_map = "ShowBookMap", page_browser = "ShowPageBrowser",
        fulltext_search = "ShowFulltextSearchInput", book_status = "ShowBookStatus",
        book_info = "ShowBookInfo", reading_progress = "ShowReaderProgress",
        history = "ShowHist", file_browser = "Home", last_book = "OpenLastDoc",
        favorites = "ShowColl", collections = "ShowCollList",
        dict_lookup = "ShowDictionaryLookup",
        font_bigger = "IncreaseFontSize:1", font_smaller = "DecreaseFontSize:1",
        zoom_fit_width = "SetZoomMode:contentwidth", zoom_fit_page = "SetZoomMode:page",
        night_mode = "ToggleNightMode", rotate = "IterateRotation", full_refresh = "FullRefresh",
        frontlight_toggle = "ToggleFrontlight",
        frontlight_up = "IncreaseFlIntensity:1", frontlight_down = "DecreaseFlIntensity:1",
        screenshot = "Screenshot",
    }
    for action, want in pairs(EVENTS) do
        n, log = nav(acts({ b = action }))
        assert(n:onGamepadButtonDown({ button = 1 }) == true and #log.events == 1 and log.events[1] == want,
            action .. " -> " .. want .. ", got " .. tostring(log.events[1]))
        assert(#log.calls == 0, action .. " does not run a built-in handler")
    end
    -- the rest of the vocabulary is exactly the non-event actions tested below
    local other = { footer_menu = true, sentence_select = true, highlights = true, word_walk = true,
                    crosshair = true, cheat_sheet = true, x_modifier = true, none = true,
                    zoom_in = true, zoom_out = true }
    for _, id in ipairs(P.ACTION_ORDER) do
        assert((EVENTS[id] ~= nil) ~= (other[id] ~= nil), id .. " is covered by exactly one test group")
    end
    -- cheat_sheet: shows the reading cheat sheet (with the "changed" lines), sends no event
    n, log = nav(acts({ b = "cheat_sheet", rb = "next_chapter" }))
    local shown
    n._show_text = function(_, text) shown = text end
    assert(n:onGamepadButtonDown({ button = 1 }) == true and #log.events == 0)
    assert(type(shown) == "string" and shown:find("RB: next chapter", 1, true) and shown:find("B: button cheat sheet", 1, true),
        "cheat sheet lists the changed roles")
    n, log = nav(acts({ select = "footer_menu", start = "top_menu" }))
    n:onGamepadButtonDown({ button = 4 }); assert(log.footer == 1 and #log.events == 0)
    n:onGamepadButtonDown({ button = 6 }); assert(log.events[1] == "ShowMenu")

    -- selector openers
    local sel = {}
    n, log = nav(acts({ b = "sentence_select", x = "highlights", lb = "word_walk", rb = "crosshair" }), { selector = sel })
    n:onGamepadButtonDown({ button = 1 }); assert(log.calls[1] == "sentence_select:1")
    n:onGamepadButtonDown({ button = 2 }); assert(log.calls[2] == "highlights")
    n:onGamepadButtonDown({ button = 9 }); assert(log.selector[1] == "_open_walk:false")
    n:onGamepadButtonDown({ button = 10 }); assert(log.selector[2] == "_open")
    -- ...without a selector (PDF): the press is swallowed, nothing runs, no error
    n, log = nav(acts({ rb = "crosshair", b = "highlights" }))
    assert(n:onGamepadButtonDown({ button = 10 }) == true and #log.calls == 0 and #log.events == 0)

    -- none: swallowed (also for B, whose built-in passes through)
    n, log = nav(acts({ b = "none", a = "none" }))
    assert(n:onGamepadButtonDown({ button = 1 }) == true and #log.calls == 0)
    assert(n:onGamepadButtonDown({ button = 0 }) == true and #log.calls == 0)

    -- outside idle reading the BUILT-IN runs: selection overlay, dictionary, FileManager
    for name, ctx in pairs({ overlay = { overlay = true, selector = {} }, dict = { dict = {} }, filemanager = { doc = false } }) do
        n, log = nav(acts({ rb = "top_menu", a = "none" }), ctx)
        assert(n:onGamepadButtonDown({ button = 10 }) == true and log.calls[1] == "onKPPgFwd" and #log.events == 0,
            name .. ": RB keeps its built-in")
        n:onGamepadButtonDown({ button = 0 }); assert(log.calls[2] == "onKPConfirm", name .. ": A keeps its built-in")
    end

    -- kopad off / modal: untouched pass-through (override never reached)
    n, log = nav(acts({ rb = "top_menu" }))
    n._is_enabled = function() return false end
    assert(n:onGamepadButtonDown({ button = 10 }) == false and #log.events == 0)

    -- X-combos stay on the built-in handlers: with the modifier on, RB is X+RB
    n, log = nav(acts({ rb = "top_menu" }))
    n._x_mode = true
    n:onGamepadButtonDown({ button = 10 }); assert(log.calls[1] == "onKPPgFwd" and #log.events == 0)

    -- the modifier can move to another role: toggles on, and off again
    n, log = nav(acts({ a = "x_modifier", x = "next_page" }))
    assert(n:onGamepadButtonDown({ button = 0 }) == true and n._x_mode == true)
    n:onGamepadButtonDown({ button = 10 }); assert(log.calls[1] == "onKPPgFwd", "A+RB is the combo")
    assert(n:onGamepadButtonDown({ button = 0 }) == true and n._x_mode == false, "A toggles it off")
    -- ...and X itself (override next_page) still cancels a pending modifier
    n._x_mode = true
    n:onGamepadButtonDown({ button = 2 }); assert(log.calls[2] == "onKPExtend", "X cancels via built-in")

    -- triggers: LT/RT overrides only on a NEW press, auto-repeat does not re-run them
    n, log = nav(acts({ rt = "top_menu", lt = "toc" }))
    assert(n:onGamepadAxisMotion({ axis = 5, value = 32767 }) == true and log.events[1] == "ShowMenu")
    assert(n:onGamepadAxisMotion({ axis = 4, value = 32767 }) == true and log.events[2] == "ShowToc")
    assert(#log.calls == 0, "built-in trigger handlers not called")
    n, log = nav(acts({ rt = "top_menu" }), { overlay = true, selector = {} })
    n:onGamepadAxisMotion({ axis = 5, value = 32767 })
    assert(log.calls[1] == "onKPPgFwd2" and #log.events == 0, "trigger keeps built-in over an overlay")

    -- layout remap + action: physical RB acts as role RT, and RT's action applies
    n, log = nav({ version = 1, layouts = { xbox = { rshoulder = "rt" } }, actions = { rt = "top_menu" } })
    assert(n:onGamepadButtonDown({ button = 10 }) == true and log.events[1] == "ShowMenu")
    -- physical A acts as role A; role actions follow the ROLE, not the physical control
    n, log = nav({ version = 1, layouts = { xbox = { south = "b", east = "a" } }, actions = { b = "toc", a = "next_page" } })
    n:onGamepadButtonDown({ button = 0 }); assert(log.events[1] == "ShowToc", "south -> role b -> toc")
    n:onGamepadButtonDown({ button = 1 }); assert(log.events[2] == "GotoViewRel:1", "east -> role a -> next page")

    -- Paged documents (PDF/DjVu): D-pad / L-stick = pan, R-stick = zoom / fit,
    -- only LB/RB and LT/RT change the page (GotoPage, a whole page)
    local function paged(ctx)
        local p, plog = nav(nil, ctx)
        p.ui.paging = { current_page = 5 }
        p.ui.zooming = { zoom = 1, onSetZoomMode = function(z, m) z.mode = m end }
        p.ui.view.onZoomUpdate = function(_, zoom) plog.events[#plog.events + 1] = ("zoom:%.3f"):format(zoom) end
        p.ui.handleEvent = function(_, ev)
            local a = ev.args[1]
            if type(a) == "table" then a = a[1] .. "," .. a[2] end
            plog.events[#plog.events + 1] = ev.name .. (a ~= nil and (":" .. tostring(a)) or "")
        end
        return p, plog
    end
    n, log = paged()
    for btn, want in pairs({ [11] = "Panning:0,-1", [12] = "Panning:0,1",
                             [13] = "Panning:-1,0", [14] = "Panning:1,0" }) do
        log.events = {}
        assert(n:onGamepadButtonDown({ button = btn }) == true and log.events[1] == want,
            "paged D-pad " .. btn .. " -> " .. want .. ", got " .. tostring(log.events[1]))
    end
    for _, c in ipairs({ { 0, -20000, "Panning:-1,0" }, { 0, 20000, "Panning:1,0" },
                         { 1, -20000, "Panning:0,-1" }, { 1, 20000, "Panning:0,1" },
                         { 3, -20000, "zoom:1.100" }, { 3, 20000, "zoom:1.000" },
                         { 2, -20000, "SetZoomMode:page" }, { 2, 20000, "SetZoomMode:contentwidth" } }) do
        log.events = {}
        assert(n:onGamepadAxisMotion({ axis = c[1], value = c[2] }) == true and log.events[1] == c[3],
            "paged stick " .. c[1] .. "/" .. c[2] .. " -> " .. c[3] .. ", got " .. tostring(log.events[1]))
    end
    assert(n.ui.zooming.mode == "free", "small zoom step switches to free zoom")
    -- zoom_in / zoom_out actions: the same small step; nothing outside a paged document
    n, log = paged()
    n:set_padmap(P.build(acts({ b = "zoom_in", y = "zoom_out" }), "xbox"))
    n:onGamepadButtonDown({ button = 1 }); n:onGamepadButtonDown({ button = 1 }); n:onGamepadButtonDown({ button = 3 })
    assert(log.events[1] == "zoom:1.100" and log.events[2] == "zoom:1.210" and log.events[3] == "zoom:1.100", "zoom actions")
    n, log = nav(acts({ b = "zoom_in" }))
    assert(n:onGamepadButtonDown({ button = 1 }) == true and #log.events == 0, "zoom_in in an EPUB does nothing")
    n, log = paged()
    -- page turns: bumpers and triggers, whole page from the current one
    log.events = {}
    assert(n:onGamepadButtonDown({ button = 9 }) == true and log.events[1] == "GotoPage:4", "LB")
    assert(n:onGamepadButtonDown({ button = 10 }) == true and log.events[2] == "GotoPage:6", "RB")
    n:onGamepadAxisMotion({ axis = 4, value = 32767 })
    n:onGamepadAxisMotion({ axis = 5, value = 32767 })
    assert(log.events[3] == "GotoPage:4" and log.events[4] == "GotoPage:6", "LT / RT")
    assert(#log.calls == 0, "built-in page handlers (GotoViewRel) not called")
    -- continuous view: the first pan switches the document to page view
    n, log = paged()
    n.ui.view.page_scroll = true
    n:onGamepadButtonDown({ button = 12 })
    assert(log.events[1] == "SetScrollMode:false" and log.events[2] == "Panning:0,1", "scroll -> page view")
    n.ui.view.page_scroll = false
    n:onGamepadButtonDown({ button = 12 })
    assert(#log.events == 3, "page view: no second switch")
    -- a role override still wins over the paged default
    n, log = paged()
    n:set_padmap(P.build(acts({ rb = "toc" }), "xbox"))
    assert(n:onGamepadButtonDown({ button = 10 }) == true and log.events[1] == "ShowToc", "override over paged RB")
    -- X held: X + D-pad keeps its menu combo, no pan
    n, log = paged()
    n._x_mode = true
    n.onKPUp2 = function() log.calls[#log.calls + 1] = "onKPUp2"; return true end
    assert(n:onGamepadButtonDown({ button = 11 }) == false and #log.events == 0, "X + D-pad is not a pan")
    -- dictionary popup open: D-pad and sticks pass through
    n, log = paged({ dict = {} })
    assert(n:onGamepadButtonDown({ button = 11 }) == false and #log.events == 0)
    assert(n:onGamepadAxisMotion({ axis = 1, value = 20000 }) ~= true or #log.events == 0, "dict: no pan")
    -- FileManager (no document) and reflowable documents: D-pad unchanged
    n, log = paged({ doc = false })
    assert(n:onGamepadButtonDown({ button = 11 }) == false and #log.events == 0, "FileManager list navigation")
    n, log = paged()
    n.ui.rolling = {}
    assert(n:onGamepadButtonDown({ button = 11 }) == false and #log.events == 0, "EPUB keeps word walk")
    n:onGamepadButtonDown({ button = 10 }); assert(log.calls[1] == "onKPPgFwd", "EPUB keeps its page turn")
end

print("padmap_test: all tests passed")
