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
    stub("pluginaro", { overlay_active = function() return false end, is_modal_active = function() return false end,
                        call_provided = function() return nil end })
    stub("gettext", function(s) return s end)
    local PadNav = require("padnav")

    local function nav(resolved)
        local calls = {}
        local o = setmetatable({ enabled_ref = { enabled = true }, ui = { document = {} } }, { __index = PadNav })
        o._is_enabled = function() return true end
        o._top_menu = function() return nil end
        for _, m in ipairs({ "_press_a", "onKPBack", "onKPExtend", "onKPMenu",
                             "onKPSelect", "onKPStart", "onKPPgBk", "onKPPgFwd",
                             "onKPPgBk2", "onKPPgFwd2" }) do
            o[m] = function() calls[#calls + 1] = m; return true end
        end
        o:set_padmap(resolved)
        return o, calls
    end

    -- identity (no padmap): physical A -> _press_a (hold control), D-pad passes through
    local n, c = nav(nil)
    assert(n:onGamepadButtonDown({ button = 0 }) == true and c[1] == "_press_a")
    assert(n:onGamepadButtonDown({ button = 11 }) == false, "D-pad passthrough")
    assert(n:onGamepadAxisMotion({ axis = 5, value = 32767 }) == true and c[2] == "onKPPgFwd2")

    -- nintendo: physical east (1) -> role A -> _press_a
    n, c = nav(P.build(nil, "nintendo"))
    n:onGamepadButtonDown({ button = 1 }); assert(c[1] == "_press_a", c[1])
    n:onGamepadButtonDown({ button = 0 }); assert(c[2] == "onKPBack", c[2])

    -- trigger -> button and button -> trigger
    n, c = nav(P.build({ version = 1, layouts = { xbox = { rtrigger = "a", rshoulder = "lt" } } }, "xbox"))
    assert(n:onGamepadAxisMotion({ axis = 5, value = 32767 }) == true and c[1] == "_press_a")
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

    -- ctx: overlay (selection overlay), doc (false = FileManager)
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
        o._selector = function() return selector end
        o._open_sentence_select = function(_, i) log.calls[#log.calls + 1] = "sentence_select:" .. tostring(i) end
        o._open_highlights = function() log.calls[#log.calls + 1] = "highlights" end
        for _, m in ipairs({ "_press_a", "onKPBack", "onKPExtend", "onKPMenu",
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
    n:onGamepadButtonDown({ button = 1 }); assert(log.calls[1] == "sentence_select:nil")
    n:onGamepadButtonDown({ button = 2 }); assert(log.calls[2] == "highlights")
    n:onGamepadButtonDown({ button = 9 }); assert(log.selector[1] == "_open_walk:false")
    -- the crosshair is gone (TASK-15): the id opens the word level
    n:onGamepadButtonDown({ button = 10 }); assert(log.selector[2] == "_open_walk:false")
    -- ...without a selector (PDF): the press is swallowed, nothing runs, no error
    n, log = nav(acts({ rb = "crosshair", b = "highlights" }))
    assert(n:onGamepadButtonDown({ button = 10 }) == true and #log.calls == 0 and #log.events == 0)

    -- none: swallowed (also for B, whose built-in passes through)
    n, log = nav(acts({ b = "none", a = "none" }))
    assert(n:onGamepadButtonDown({ button = 1 }) == true and #log.calls == 0)
    assert(n:onGamepadButtonDown({ button = 0 }) == true and #log.calls == 0)

    -- outside idle reading the BUILT-IN runs over a selection overlay
    -- (the dictionary popup never reaches the overrides, see test 11)
    n, log = nav(acts({ rb = "top_menu", a = "none" }), { overlay = true, selector = {} })
    assert(n:onGamepadButtonDown({ button = 10 }) == true and log.calls[1] == "onKPPgFwd" and #log.events == 0,
        "overlay: RB keeps its built-in")
    n:onGamepadButtonDown({ button = 0 }); assert(log.calls[2] == "_press_a", "overlay: A keeps its built-in")
    -- ...and the FileManager keeps the STOCK list navigation (TASK-9): no
    -- override, no handler, the stock key goes to the list
    n, log = nav(acts({ rb = "top_menu", a = "none" }), { doc = false })
    assert(n:onGamepadButtonDown({ button = 10 }) == false and #log.calls == 0 and #log.events == 0,
        "filemanager: RB = stock list page")
    assert(n:onGamepadButtonDown({ button = 0 }) == false and #log.calls == 0, "filemanager: A = stock")

    -- kopad off / foreign overlay: untouched pass-through (override never reached)
    for _, c in ipairs({ "off", "foreign" }) do
        n, log = nav(acts({ rb = "top_menu" }))
        n._context = function() return c end
        assert(n:onGamepadButtonDown({ button = 10 }) == false and #log.events == 0, c)
    end

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
        p._stick_bounce = function() return false end -- real filter tested below
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
    -- D-pad = slow pan (a fifth of the stock step), L-stick = stock step
    for btn, want in pairs({ [11] = "Panning:0,-0.2", [12] = "Panning:0,0.2",
                             [13] = "Panning:-0.2,0", [14] = "Panning:0.2,0" }) do
        log.events = {}
        assert(n:onGamepadButtonDown({ button = btn }) == true and log.events[1] == want,
            "paged D-pad " .. btn .. " -> " .. want .. ", got " .. tostring(log.events[1]))
    end
    for _, c in ipairs({ { 0, -20000, "Panning:-1,0" }, { 0, 20000, "Panning:1,0" },
                         { 1, -20000, "Panning:0,-1" }, { 1, 20000, "Panning:0,1" },
                       }) do
        log.events = {}
        assert(n:onGamepadAxisMotion({ axis = c[1], value = c[2] }) == true and log.events[1] == c[3],
            "paged stick " .. c[1] .. "/" .. c[2] .. " -> " .. c[3] .. ", got " .. tostring(log.events[1]))
    end
    -- R-stick: consumed, never a page turn or a zoom (it opens the quick-action
    -- wheel, section 16; zoom is A + D-pad)
    for _, c in ipairs({ { 3, -20000 }, { 3, 20000 }, { 2, -20000 }, { 2, 20000 } }) do
        log.events = {}
        assert(n:onGamepadAxisMotion({ axis = c[1], value = c[2] }) == true and #log.events == 0,
            "paged R-stick " .. c[1] .. "/" .. c[2] .. " is consumed and does not move the page")
    end
    n.ui.zooming.zoom = 1
    n:onGamepadButtonDown({ button = 1 }); n:onGamepadButtonDown({ button = 11 })
    n:onGamepadButtonUp({ button = 11 }); n:onGamepadButtonUp({ button = 1 })
    assert(n.ui.zooming.mode == "free", "small zoom step switches to free zoom")
    -- zoom_in / zoom_out actions: the same small step; nothing outside a paged document
    n, log = paged()
    n:set_padmap(P.build(acts({ b = "zoom_in", y = "zoom_out" }), "xbox"))
    n:onGamepadButtonDown({ button = 1 }); n:onGamepadButtonDown({ button = 1 }); n:onGamepadButtonDown({ button = 3 })
    assert(log.events[1] == "zoom:1.030" and log.events[2] == "zoom:1.061" and log.events[3] == "zoom:1.030", "zoom actions")
    n, log = nav(acts({ b = "zoom_in" }))
    assert(n:onGamepadButtonDown({ button = 1 }) == true and #log.events == 0, "zoom_in in an EPUB does nothing")
    -- release bounce: after a pan to the right, the L-stick snapping back
    -- (left, then down) within STICK_LOCK_S is ignored; the same direction
    -- (auto-repeat) still pans, and after the lock anything goes
    local T = package.loaded["ui/time"]
    local clock = 100
    T.now = function() return clock end
    n, log = paged()
    n._stick_bounce = nil
    n:onGamepadAxisMotion({ axis = 0, value = 6000 })       -- pan right
    clock = 100.01; n:onGamepadAxisMotion({ axis = 0, value = -6000 })  -- bounce
    clock = 100.03; n:onGamepadAxisMotion({ axis = 1, value = 5300 })   -- bounce on the other axis
    clock = 100.5;  n:onGamepadAxisMotion({ axis = 0, value = 5001 })   -- repeat
    assert(#log.events == 2 and log.events[1] == "Panning:1,0" and log.events[2] == "Panning:1,0",
        "bounce ignored, repeat kept: " .. table.concat(log.events, " "))
    clock = 101.2;  n:onGamepadAxisMotion({ axis = 0, value = -6000 })  -- real pan left
    assert(log.events[3] == "Panning:-1,0", "after the lock")
    T.now = function() return 0 end
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
    assert(log.events[1] == "SetScrollMode:false" and log.events[2] == "Panning:0,0.2", "scroll -> page view")
    n.ui.view.page_scroll = false
    n:onGamepadButtonDown({ button = 12 })
    assert(#log.events == 3, "page view: no second switch")
    -- a role override still wins over the paged default
    n, log = paged()
    n:set_padmap(P.build(acts({ rb = "toc" }), "xbox"))
    assert(n:onGamepadButtonDown({ button = 10 }) == true and log.events[1] == "ShowToc", "override over paged RB")
    -- TASK-30: A / Y held + D-pad = the selection (words / sentences), no
    -- zoom any more; A tapped = point from-to; the D-pad alone still pans.
    -- The paged selector is hidden from _selector() while nothing is open.
    local function paged_sel(opts)
        local p, plog = paged()
        local sel = { paged = true, calls = {} }
        local function rec(name, ret, why)
            return function(_, arg)
                sel.calls[#sel.calls + 1] = name .. ":" .. tostring(arg)
                return ret, why
            end
        end
        sel._open_walk = rec("walk", opts and opts.ret, opts and opts.why)
        sel._open = rec("sent", opts and opts.ret, opts and opts.why)
        sel._open_point = rec("point", opts and opts.ret, opts and opts.why)
        p.enabled_ref.subs = { selector = sel }
        p._selector = PadNav._selector
        p._show_text = function(_, t) plog.shown = t end
        return p, plog, sel
    end
    local sel
    n, log, sel = paged_sel({ ret = true })
    assert(n:_selector() == nil and n:_any_selector() == sel, "idle paged selector is hidden")
    assert(n:onGamepadButtonDown({ button = 0 }) == true and #log.events == 0, "A alone: consumed, no event")
    assert(n:onGamepadButtonDown({ button = 14 }) == true and #log.events == 0, "A + D-pad: no zoom, no pan")
    assert(sel.calls[1] == "walk:false", "A + → = words from the first: " .. tostring(sel.calls[1]))
    n:onGamepadButtonUp({ button = 14 }); n:onGamepadButtonUp({ button = 0 })
    assert(#sel.calls == 1, "the release after A + D-pad is not a tap")
    n:onGamepadButtonDown({ button = 0 }); n:onGamepadButtonDown({ button = 11 })
    assert(sel.calls[2] == "walk:true", "A + ↑ = words from the last")
    n:onGamepadButtonUp({ button = 11 }); n:onGamepadButtonUp({ button = 0 })
    n:onGamepadButtonDown({ button = 3 }); n:onGamepadButtonDown({ button = 12 })
    assert(sel.calls[3] == "sent:false" and #log.events == 0, "Y + ↓ = sentences")
    n:onGamepadButtonUp({ button = 12 }); n:onGamepadButtonUp({ button = 3 })
    -- A tapped = point from-to (context paged), Y tapped = nothing (TASK-31)
    n:onGamepadButtonDown({ button = 0 }); n:onGamepadButtonUp({ button = 0 })
    assert(sel.calls[4] == "point:nil", "A tap = point from-to: " .. tostring(sel.calls[4]))
    n:onGamepadButtonDown({ button = 3 }); n:onGamepadButtonUp({ button = 3 })
    assert(#sel.calls == 4 and #log.events == 0, "Y tap: nothing yet")
    -- after the letters are released the D-pad pans again
    n:onGamepadButtonDown({ button = 11 })
    assert(log.events[1] == "Panning:0,-0.2", "D-pad alone pans")
    -- a page without text / reflow: the opener says why, padnav shows it
    n, log, sel = paged_sel({ ret = false, why = "no_text" })
    n:onGamepadButtonDown({ button = 0 }); n:onGamepadButtonDown({ button = 13 })
    assert(log.shown == "No text on this page", "no text: " .. tostring(log.shown))
    n:onGamepadButtonUp({ button = 13 }); n:onGamepadButtonUp({ button = 0 })
    n, log, sel = paged_sel({ ret = false, why = "reflow" })
    n:onGamepadButtonDown({ button = 0 }); n:onGamepadButtonUp({ button = 0 })
    assert(sel.calls[1] == "point:nil" and log.shown == "Not in reflow mode", "reflow: " .. tostring(log.shown))
    -- the overlay open: the selector shows (context selection), and LB / RB
    -- close it and turn a whole page
    n, log, sel = paged_sel({ ret = true })
    sel.overlay = {}
    sel._close = function(s) s.overlay = nil end
    assert(n:_selector() == sel, "an open paged overlay is the selection")
    n:_turn_page(1)
    assert(sel.overlay == nil and log.events[1] == "GotoPage:6", "PDF selection: RB = whole page, got " .. tostring(log.events[1]))
    -- B held + D-pad (TASK-33): the same zoom / fit; B tapped = back on the
    -- release, never after a B combo
    n, log = paged()
    n.onKPBack = function() log.calls[#log.calls + 1] = "onKPBack"; return true end
    assert(n:onGamepadButtonDown({ button = 1 }) == true and #log.events == 0 and #log.calls == 0, "B press: nothing yet")
    for btn, want in pairs({ [11] = "zoom:1.030", [13] = "SetZoomMode:page", [14] = "SetZoomMode:contentwidth" }) do
        log.events = {}
        assert(n:onGamepadButtonDown({ button = btn }) == true and log.events[1] == want,
            "B + D-pad " .. btn .. " -> " .. want .. ", got " .. tostring(log.events[1]))
        n:onGamepadButtonUp({ button = btn })
    end
    n:onGamepadButtonUp({ button = 1 })
    assert(#log.calls == 0, "no back after B + D-pad")
    n:onGamepadButtonDown({ button = 1 }); n:onGamepadButtonUp({ button = 1 })
    assert(log.calls[1] == "onKPBack", "B tap = back")
    -- X held: X + D-pad keeps its menu combo, no pan
    n, log = paged()
    n._x_mode = true
    n.onKPUp2 = function() log.calls[#log.calls + 1] = "onKPUp2"; return true end
    assert(n:onGamepadButtonDown({ button = 11 }) == false and #log.events == 0, "X + D-pad is not a pan")
    -- dictionary popup open: D-pad and sticks pass through
    n, log = paged()
    local wstack = require("ui/uimanager")._window_stack
    wstack[1] = { widget = { name = "DictQuickLookup" } }
    assert(n:onGamepadButtonDown({ button = 11 }) == false and #log.events == 0)
    assert(n:onGamepadAxisMotion({ axis = 1, value = 20000 }) ~= true or #log.events == 0, "dict: no pan")
    wstack[1] = nil
    -- FileManager (no document) and reflowable documents: D-pad unchanged
    n, log = paged({ doc = false })
    assert(n:onGamepadButtonDown({ button = 11 }) == false and #log.events == 0, "FileManager list navigation")
    n, log = paged()
    n.ui.rolling = {}
    assert(n:onGamepadButtonDown({ button = 11 }) == false and #log.events == 0, "EPUB keeps word walk")
    n:onGamepadButtonDown({ button = 10 }); assert(log.calls[1] == "onKPPgFwd", "EPUB keeps its page turn")
end

-- 11. Context (TASK-7): menus and other windows on top of the reader get the
-- pad; the document under them is never touched. Window stack laid out as
-- KOReader does it: ReaderMenu / FileManagerMenu = CenterContainer{TouchMenu},
-- TOC / bookmarks = CenterContainer{Menu}. Real handlers, no stubs in PadNav.
do
    local PadNav = require("padnav")
    local stack = require("ui/uimanager")._window_stack
    -- a clock that moves 1 s per reading: no event counts as a stick bounce
    -- or a trigger auto-repeat unless a test sets the time itself
    local T = package.loaded["ui/time"]
    local clock = 1000
    local function ticking() clock = clock + 1; return clock end
    T.now = ticking
    local function set_stack(...)
        for i = #stack, 1, -1 do stack[i] = nil end
        for i, w in ipairs({ ... }) do stack[i] = { widget = w } end
    end

    -- kind: "epub" | "pdf" | "fm"
    local function reader(kind, padmap)
        local log = { events = {}, selector = {}, menu = {} }
        local ui = {
            handleEvent = function(_, ev) log.events[#log.events + 1] = ev.name end,
            view = { footer = { onToggleFooterMode = function() log.events[#log.events + 1] = "footer" end } },
        }
        local selector
        if kind == "epub" then
            ui.document, ui.rolling = {}, {}
            selector = {
                _open = function() log.selector[#log.selector + 1] = "_open" end,
                _open_walk = function() log.selector[#log.selector + 1] = "_open_walk" end,
                _open_point = function() log.selector[#log.selector + 1] = "_open_point"; return true end,
                _close = function() end,
            }
        elseif kind == "pdf" then
            ui.document, ui.paging = {}, { current_page = 5 }
        end
        local n = setmetatable({ ui = ui, enabled_ref = { enabled = true, subs = { selector = selector } } },
            { __index = PadNav })
        n:set_padmap(padmap and P.build(padmap, "xbox") or nil)
        local function rec(name) return function() log.menu[#log.menu + 1] = name; return true end end
        -- focus starts in the items (FocusManager row 2); row 1 = tab bar
        local touch = { tab_item_table = { {}, {}, {} }, cur_tab = 1,
                        selected = { x = 1, y = 2 }, layout = { {}, {} },
                        switchMenuTab = function(m, k)
                            m.cur_tab = k; m.selected = { x = k, y = 1 }
                            log.menu[#log.menu + 1] = "tab:" .. k
                        end,
                        moveFocusTo = function(m, x, y)
                            m.selected = { x = x, y = y }; log.menu[#log.menu + 1] = "focus:" .. x .. "," .. y
                        end,
                        onNextPage = rec("next"), onPrevPage = rec("prev"), closeMenu = rec("close") }
        local list = { onNextPage = rec("next"), onPrevPage = rec("prev") }
        return n, log, ui, selector, { touch }, { list }
    end
    local function nothing_moved(log, what)
        assert(#log.events == 0 and #log.selector == 0,
            what .. ": document untouched, got " .. table.concat(log.events, ",") .. table.concat(log.selector, ","))
    end

    for _, kind in ipairs({ "epub", "pdf", "fm" }) do
        -- top menu: stock navigation passes, LB/RB = category, LT/RT = page, Select = close
        local n, log, ui, _, top_menu = reader(kind, { version = 1, actions = { a = "next_page", x = "toc" } })
        set_stack(ui, top_menu)
        assert(n:_context() == "top_menu", kind)
        for _, b in ipairs({ 0, 1, 2, 3, 6, 11, 12, 13, 14 }) do
            assert(n:onGamepadButtonDown({ button = b }) == false, kind .. " top menu: button " .. b .. " goes to the menu")
        end
        for _, a in ipairs({ { 0, -20000 }, { 0, 20000 }, { 1, -20000 }, { 1, 20000 },
                             { 2, -20000 }, { 2, 20000 }, { 3, -20000 }, { 3, 20000 } }) do
            assert(n:onGamepadAxisMotion({ axis = a[1], value = a[2] }) == false, kind .. " top menu: stick " .. a[1])
        end
        nothing_moved(log, kind .. " top menu")
        -- LB/RB switch the category and keep the focus level: in the items -> first item
        assert(n:onGamepadButtonDown({ button = 10 }) == true and log.menu[1] == "tab:2" and log.menu[2] == "focus:2,2",
            kind .. " RB = next category, focus on its first item")
        assert(n:onGamepadButtonDown({ button = 9 }) == true and log.menu[3] == "tab:1" and log.menu[4] == "focus:1,2",
            kind .. " LB = previous category")
        assert(n:onGamepadAxisMotion({ axis = 5, value = 32767 }) == true and log.menu[5] == "next", kind .. " RT")
        assert(n:onGamepadAxisMotion({ axis = 4, value = 32767 }) == true and log.menu[6] == "prev", kind .. " LT")
        -- focus on the tab bar: D-pad ←/→ switch the tab at once, focus stays on the bar
        top_menu[1].selected = { x = 1, y = 1 }
        assert(n:onGamepadButtonDown({ button = 14 }) == true and log.menu[7] == "tab:2" and log.menu[8] == "focus:2,1",
            kind .. " → on the bar = next tab")
        assert(n:onGamepadButtonDown({ button = 13 }) == true and log.menu[9] == "tab:1" and log.menu[10] == "focus:1,1",
            kind .. " ← on the bar = previous tab")
        assert(n:onGamepadButtonDown({ button = 13 }) == true and log.menu[11] == "tab:3", kind .. " ← wraps")
        assert(n:onGamepadButtonDown({ button = 12 }) == false, kind .. " ↓ from the bar is stock")
        -- the L-stick ←/→ on the bar does the same; in the items it is stock
        top_menu[1].selected = { x = 1, y = 1 }
        local before = #log.menu
        assert(n:onGamepadAxisMotion({ axis = 0, value = 20000 }) == true and log.menu[before + 1] == "tab:1",
            kind .. " L-stick → on the bar = next tab")
        top_menu[1].selected = { x = 2, y = 3 }
        assert(n:onGamepadAxisMotion({ axis = 0, value = -20000 }) == false, kind .. " L-stick ← in the items is stock")
        -- a release bounce (other direction within 0.2 s) is eaten, so the
        -- focus does not jump back; a later reversal is a real move
        T.now = function() return clock end
        clock = clock + 5
        assert(n:onGamepadAxisMotion({ axis = 1, value = 20000 }) == false, kind .. " L-stick ↓ stock")
        clock = clock + 0.08
        assert(n:onGamepadAxisMotion({ axis = 1, value = -6000 }) == true, kind .. " bounce eaten")
        clock = clock + 0.05
        assert(n:onGamepadAxisMotion({ axis = 0, value = 6000 }) == true, kind .. " bounce on the other axis eaten")
        clock = clock + 0.5
        assert(n:onGamepadAxisMotion({ axis = 1, value = -20000 }) == false, kind .. " later ↑ is a real move")
        T.now = ticking
        assert(n:onGamepadButtonDown({ button = 4 }) == true and log.menu[#log.menu] == "close", kind .. " Select closes")
        for _, b in ipairs({ 5, 7, 8 }) do assert(n:onGamepadButtonDown({ button = b }) == true, "swallow " .. b) end
        nothing_moved(log, kind .. " top menu")
        assert(not n._x_mode, kind .. " X does not arm the modifier under a menu")

        -- TOC / bookmarks / any other window: everything stock, LT/RT = list page
        local list
        n, log, ui, _, _, list = reader(kind, { version = 1, actions = { lb = "toc" } })
        set_stack(ui, list)
        assert(n:_context() == "window", kind)
        for _, b in ipairs({ 0, 1, 2, 3, 9, 10, 11, 12, 13, 14 }) do
            assert(n:onGamepadButtonDown({ button = b }) == false, kind .. " window: button " .. b .. " goes to the window")
        end
        for _, b in ipairs({ 4, 6 }) do assert(n:onGamepadButtonDown({ button = b }) == true, "swallow " .. b) end
        for _, a in ipairs({ 0, 1, 2, 3 }) do
            assert(n:onGamepadAxisMotion({ axis = a, value = 20000 }) == false, kind .. " window: stick " .. a)
        end
        n:onGamepadAxisMotion({ axis = 5, value = 32767 }); n:onGamepadAxisMotion({ axis = 4, value = 32767 })
        assert(log.menu[1] == "next" and log.menu[2] == "prev", kind .. " window: LT/RT = list page")
        nothing_moved(log, kind .. " window")
        -- a window without pages (dialog): triggers are eaten, nothing happens
        set_stack(ui, {})
        assert(n:onGamepadAxisMotion({ axis = 5, value = 32767 }) == true)
        nothing_moved(log, kind .. " dialog")

        -- Start (TASK-13): opens the bottom menu while reading, closes it when
        -- open; in the FileManager it stays swallowed (no bottom menu there)
        n, log, ui = reader(kind)
        set_stack(ui)
        local want = kind == "fm" and 0 or 1
        assert(n:onGamepadButtonDown({ button = 6 }) == true and #log.events == want, kind .. ": Start")
        if want == 1 then assert(log.events[1] == "ShowConfigMenu", kind .. ": Start opens the bottom menu") end
        local closed = 0
        set_stack(ui, { config_options = {}, closeDialog = function() closed = closed + 1 end })
        assert(n:_context() == "window")
        assert(n:onGamepadButtonDown({ button = 6 }) == true and closed == 1, kind .. ": Start closes the bottom menu")
        assert(#log.events == want, kind .. ": closing sends no event")

        -- bottom menu tabs: LB/RB always, D-pad / L-stick ←/→ on its tab bar
        -- (the LAST layout row); the focus level is kept, visibly
        local steps = {}
        local dlg = { config_options = { {}, {}, {} }, panel_index = 1, closeDialog = function() end,
                      layout = { {}, {}, {} }, selected = { x = 1, y = 3 } }
        function dlg:onShowConfigPanel(k)
            self.panel_index = k; self.selected = { x = k, y = #self.layout }
            steps[#steps + 1] = "panel:" .. k
        end
        function dlg:moveFocusTo(x, y) self.selected = { x = x, y = y }; steps[#steps + 1] = "focus:" .. x .. "," .. y end
        set_stack(ui, { dlg })
        assert(n:onGamepadButtonDown({ button = 9 }) == true, kind .. ": LB in the bottom menu")
        assert(steps[1] == "panel:3" and steps[2] == "focus:3,3", kind .. ": LB wraps, focus stays on the bar")
        assert(n:onGamepadButtonDown({ button = 14 }) == true and steps[3] == "panel:1", kind .. ": D-pad → on the bar")
        assert(n:onGamepadAxisMotion({ axis = 0, value = 32767 }) == true and steps[5] == "panel:2", kind .. ": L-stick → on the bar")
        dlg.selected = { x = 1, y = 2 } -- in the options
        assert(n:onGamepadButtonDown({ button = 14 }) == false, kind .. ": D-pad → in the options is stock")
        assert(n:onGamepadButtonDown({ button = 10 }) == true and steps[7] == "panel:3" and steps[8] == "focus:1,1",
            kind .. ": RB in the options -> first option row of the new tab")
        assert(#log.events == want, kind .. ": tab switches send no reader event")

        -- the current tab's icon is not inverted on focus (its tab frame marks
        -- it already); other icons keep the stock invert
        local function icon(inv)
            return { image = { invert = inv }, onFocus = function(self) self.image.invert = true; return true end }
        end
        local icons = { icon(false), icon(false), icon(true) } -- current tab 3, inverted earlier
        dlg.config_menubar = { menu_items = icons }
        assert(n:onGamepadButtonDown({ button = 12 }) == false, kind .. ": D-pad ↓ in the bottom menu is stock")
        assert(icons[3].image.invert == false, kind .. ": earlier invert on the current tab is undone")
        icons[3]:onFocus(); icons[1]:onFocus()
        assert(icons[3].image.invert == false and icons[1].image.invert == true, kind .. ": only the current tab is quiet")
        local wrapped = icons[1].onFocus
        n:onGamepadButtonDown({ button = 12 })
        assert(icons[1].onFocus == wrapped, kind .. ": wrapped once")
        local top = { tab_item_table = { {}, {} }, cur_tab = 2, switchMenuTab = function() end,
                      bar = { icon_widgets = { icon(false), icon(false) } } }
        set_stack(ui, { top })
        n:onGamepadButtonDown({ button = 12 })
        top.bar.icon_widgets[2]:onFocus(); top.bar.icon_widgets[1]:onFocus()
        assert(top.bar.icon_widgets[2].image.invert == false and top.bar.icon_widgets[1].image.invert == true,
            kind .. ": top menu: only the current tab is quiet")
    end

    -- nothing on top (a toast does not count): the reading controls are back
    local n, log, ui = reader("epub")
    set_stack(ui, { toast = true })
    assert(n:_context() == "reading")
    assert(n:onGamepadButtonDown({ button = 0 }) == true, "EPUB: A consumed")
    n:onGamepadButtonUp({ button = 0 })
    assert(log.selector[1] == "_open_point", "EPUB: A tapped opens point from-to")
    -- malformed axis events pass without an error (TASK-10)
    for _, a in ipairs({ 1, 3, 4, 5 }) do
        assert(n:onGamepadAxisMotion({ axis = a, value = "x" }) == false, "non-numeric value on axis " .. a)
    end
    assert(n:onGamepadAxisMotion({ value = 1 }) == false and n:onGamepadAxisMotion(nil) == false)
    n, log, ui = reader("pdf")
    set_stack(ui)
    assert(n:_context() == "paged")
    assert(n:onGamepadButtonDown({ button = 11 }) == true and log.events[1] == "Panning", "PDF: D-pad pans")
    n, log, ui = reader("fm")
    set_stack(ui)
    assert(n:_context() == "filemanager")
    -- FileManager (TASK-9): stock list navigation, LT/RT = list page, Select = menu
    local pages = {}
    ui.file_chooser = { onNextPage = function() pages[#pages + 1] = "next" end,
                        onPrevPage = function() pages[#pages + 1] = "prev" end,
                        onFolderUp = function() pages[#pages + 1] = "up" end }
    for _, b in ipairs({ 0, 2, 3, 9, 10, 11, 12, 13, 14 }) do
        assert(n:onGamepadButtonDown({ button = b }) == false, "filemanager: button " .. b .. " is stock")
    end
    assert(not n._x_mode, "filemanager: X does not arm the modifier")
    for _, a in ipairs({ 0, 1 }) do
        assert(n:onGamepadAxisMotion({ axis = a, value = 20000 }) == false, "filemanager: stick " .. a .. " is stock")
    end
    -- the R-stick opens the quick-action wheel (TASK-26, section 16), never stock
    for _, a in ipairs({ 2, 3 }) do
        assert(n:onGamepadAxisMotion({ axis = a, value = 20000 }) == true, "filemanager: R-stick " .. a .. " is kopad's")
    end
    n:onGamepadAxisMotion({ axis = 5, value = 32767 }); n:onGamepadAxisMotion({ axis = 4, value = 32767 })
    assert(pages[1] == "next" and pages[2] == "prev", "filemanager: LT/RT = list page")
    assert(#log.events == 0)
    assert(n:onGamepadButtonDown({ button = 4 }) == true and log.events[1] == "ShowMenu", "filemanager: Select = menu")
    -- B = parent folder, never the stock "Exit KOReader?" (TASK-11)
    assert(n:onGamepadButtonDown({ button = 1 }) == true and pages[3] == "up", "filemanager: B = folder up")
    -- B while reading (EPUB and PDF, no selection): back to the previous
    -- location only, never the stock Back that ends in "Exit KOReader?";
    -- a tap, so on the release (TASK-33)
    for _, kind in ipairs({ "epub", "pdf" }) do
        local r, rlog, rui = reader(kind)
        set_stack(rui)
        local back = 0
        rui.link = { onGoBackLink = function(_, notify) assert(notify == true); back = back + 1; return false end }
        assert(r:onGamepadButtonDown({ button = 1 }) == true and back == 0, kind .. ": nothing on the B press")
        r:onGamepadButtonUp({ button = 1 })
        r:onGamepadButtonDown({ button = 1 }); r:onGamepadButtonUp({ button = 1 })
        assert(back == 2, kind .. ": B tapped = previous location, consumed even when the history is empty")
        nothing_moved(rlog, kind .. " B")
    end
    -- X modifier is dropped as soon as the pad is used outside plain reading
    n, log, ui = reader("epub")
    set_stack(ui)
    n:onGamepadButtonDown({ button = 2 }); assert(n._x_mode, "X arms the modifier while reading")
    set_stack(ui, {})
    n:onGamepadButtonDown({ button = 11 })
    assert(not n._x_mode, "a window on top drops a pending X")
    -- own overlay, dictionary, foreign overlay, kopad off
    local sel
    n, log, ui, sel = reader("epub")
    sel.overlay = {}
    set_stack(ui, sel.overlay)
    assert(n:_context() == "selection")
    -- the real popup has no `name`: it is recognised via DictQuickLookup.window_list
    local popup = {}
    package.loaded["ui/widget/dictquicklookup"] = { window_list = { popup } }
    set_stack(ui, sel.overlay, popup)
    assert(n:_context() == "dict")
    package.loaded["ui/widget/dictquicklookup"] = nil
    ui._kokb_overlay = "visel"
    package.loaded.pluginaro.overlay_active = function(u, except) return u._kokb_overlay ~= nil and u._kokb_overlay ~= except end
    assert(n:_context() == "foreign")
    package.loaded.pluginaro.overlay_active = function() return false end
    ui._kokb_overlay = nil

    -- dictionary popup (TASK-8): stock keys reach it (LB/RB = dictionaries,
    -- B closes, A / D-pad / sticks), nothing moves underneath, overrides
    -- never run; Y = AI explanation of the selection, the popup is closed.
    -- kind "pdf" = popup opened by KOReader itself, no kopad selection.
    for _, kind in ipairs({ "epub", "pdf" }) do
        local d, dlog, dui, dsel = reader(kind, { version = 1, actions = { a = "next_page", rb = "toc" } })
        local ai, closed = {}, {}
        local dpopup = {}
        package.loaded["ui/widget/dictquicklookup"] = { window_list = { dpopup } }
        local uim = require("ui/uimanager")
        uim.close = function(_, w) closed[#closed + 1] = w end
        if dsel then
            dsel.overlay = { _get_selection = function() return { text = "verbum" } end,
                             _do_ai = function(_, s) ai[#ai + 1] = s.text end }
            set_stack(dui, dsel.overlay, dpopup)
        else
            set_stack(dui, dpopup)
        end
        assert(d:_context() == "dict", kind)
        for _, b in ipairs({ 0, 1, 2, 9, 10, 11, 12, 13, 14 }) do
            assert(d:onGamepadButtonDown({ button = b }) == false, kind .. " dict: button " .. b .. " goes to the popup")
        end
        for _, a in ipairs({ 0, 1, 2, 3 }) do
            assert(d:onGamepadAxisMotion({ axis = a, value = 20000 }) == false, kind .. " dict: stick " .. a)
        end
        for _, b in ipairs({ 4, 6 }) do assert(d:onGamepadButtonDown({ button = b }) == true, "swallow " .. b) end
        assert(d:onGamepadAxisMotion({ axis = 5, value = 32767 }) == true, kind .. " dict: RT eaten")
        nothing_moved(dlog, kind .. " dict")
        if dsel then
            assert(d:onGamepadButtonDown({ button = 3 }) == true and ai[1] == "verbum" and closed[1] == dpopup,
                "Y = AI explain, popup closed")
        else
            assert(d:onGamepadButtonDown({ button = 3 }) == false and #ai == 0, "Y passes without a kopad selection")
        end
        uim.close = nil
        package.loaded["ui/widget/dictquicklookup"] = nil
    end

    n.enabled_ref.enabled = false
    assert(n:_context() == "off")
    set_stack()
    T.now = function() return 0 end
end

-- 12. Visel routing (pluginaro integration A) on KOReader >= 2026.07. The pad
-- reaches visel in two rounds: with visel's overlay claimed the context is
-- "foreign", so onGamepadButtonDown passes the event (false); stock then sends
-- its default key (D-pad Left/Right, LB/RB RPgBack/RPgFwd, B Back) and that
-- key hits PadNav's key_events handler, whose first step is _visel_route.
-- Toggle off (call_provided -> nil): the handler stands down and the key
-- keeps going to visel's own bindings.
do
    local PadNav = require("padnav")
    local PL = package.loaded.pluginaro
    local saved_oa, saved_cp = PL.overlay_active, PL.call_provided
    PL.overlay_active = function(u, except) return u._kokb_overlay ~= nil and u._kokb_overlay ~= except end
    local toggle, calls = true, {}
    PL.call_provided = function(host, provider, id, method, arg)
        assert(host == "visel" and provider == "kopad" and id == "gamepad_select", "contract triple")
        if not toggle then return nil end
        if method == "is_active" then return true end
        calls[#calls + 1] = method .. ":" .. tostring(arg)
        return true
    end
    local log = {}
    local ui = { document = {}, rolling = {}, _kokb_overlay = "visel",
                 handleEvent = function(_, ev) log[#log + 1] = ev.name end }
    local n = setmetatable({ ui = ui, enabled_ref = { enabled = true, subs = {} } }, { __index = PadNav })
    n:set_padmap(nil)
    assert(n:_context() == "foreign")
    -- { SDL button, handler of the stock key it becomes, routed call }
    local routes = {
        { 13, "onKPLeft2",  "move:-1" },  { 14, "onKPRight2", "move:1" },
        { 9,  "onKPPgBk",   "extend:-1" }, { 10, "onKPPgFwd", "extend:1" },
        { 1,  "onKPBack",   "close:nil" },
    }
    for _, r in ipairs(routes) do
        calls = {}
        assert(n:onGamepadButtonDown({ button = r[1] }) == false, "foreign: button " .. r[1] .. " goes to stock")
        assert(#calls == 0, "foreign: nothing routed in round 1")
        assert(n[r[2]](n) == true and calls[1] == r[3], r[2] .. " routes " .. r[3])
    end
    -- L-stick: passed to stock as well; both of its key names route
    assert(n:onGamepadAxisMotion({ axis = 0, value = -20000 }) == false, "foreign: L-stick goes to stock")
    calls = {}
    assert(n:onKPLeft() == true and n:onKPRight() == true and calls[1] == "move:-1" and calls[2] == "move:1",
        "LStickLeft/Right route as move")
    -- toggle off: no route, handler stands down, the document is untouched
    toggle, calls = false, {}
    for _, r in ipairs(routes) do
        assert(n[r[2]](n) == false, r[2] .. " stands down with the toggle off")
    end
    assert(#calls == 0 and #log == 0, "toggle off: nothing routed, nothing moved")
    -- kopad switched off: no route even with the toggle on
    toggle, n.enabled_ref.enabled = true, false
    assert(n:onKPPgFwd() == false and #calls == 0, "kopad off: no route")
    PL.overlay_active, PL.call_provided = saved_oa, saved_cp
end

-- 13. Wheel dialogs (wheel.lua, TASK-19): a ButtonDialog converted into a
-- radial menu (dlg._kopad_wheel) on top is context "wheel" -- even over a
-- foreign overlay -- and every pad event goes to its controller; nothing
-- reaches stock or the document.
do
    local PadNav = require("padnav")
    local stack = require("ui/uimanager")._window_stack
    local T = package.loaded["ui/time"]
    local clock = 5000
    T.now = function() clock = clock + 1; return clock end
    local PL = package.loaded.pluginaro
    local saved_oa = PL.overlay_active
    local calls = {}
    local ctl = {}
    for _, m in ipairs({ "activate", "close", "rotate", "page_step", "stick" }) do
        ctl[m] = function(_, arg) calls[#calls + 1] = m .. ":" .. tostring(arg); return true end
    end
    local log = {}
    local ui = { document = {}, rolling = {}, handleEvent = function(_, ev) log[#log + 1] = ev.name end }
    local n = setmetatable({ ui = ui, enabled_ref = { enabled = true, subs = {} } }, { __index = PadNav })
    n:set_padmap(nil)
    stack[1] = { widget = ui }
    stack[2] = { widget = { _kopad_wheel = ctl } }
    assert(n:_context() == "wheel")
    PL.overlay_active = function() return true end
    assert(n:_context() == "wheel", "wheel before foreign")
    local want = {
        { 0, "activate:false" }, { 2, "activate:true" }, { 1, "close:nil" },
        { 13, "rotate:-1" }, { 11, "rotate:-1" }, { 14, "rotate:1" }, { 12, "rotate:1" },
        { 9, "page_step:-1" }, { 10, "page_step:1" },
    }
    for _, w in ipairs(want) do
        calls = {}
        assert(n:onGamepadButtonDown({ button = w[1] }) == true and calls[1] == w[2],
            "wheel button " .. w[1] .. " -> " .. tostring(calls[1]))
    end
    calls = {}
    for _, b in ipairs({ 3, 4, 5, 6, 7, 8 }) do
        assert(n:onGamepadButtonDown({ button = b }) == true, "wheel swallows " .. b)
    end
    assert(#calls == 0, "Y / Select / Guide / Start / L3 / R3 do nothing")
    assert(n:onGamepadAxisMotion({ axis = 5, value = 32767 }) == true and calls[1] == "page_step:1", "RT = next page")
    assert(n:onGamepadAxisMotion({ axis = 4, value = 32767 }) == true and calls[2] == "page_step:-1", "LT = previous page")
    assert(n:onGamepadAxisMotion({ axis = 0, value = 9000 }) == true and calls[3] == "stick:left")
    assert(n:onGamepadAxisMotion({ axis = 1, value = -9000 }) == true and calls[4] == "stick:left")
    assert(n:onGamepadAxisMotion({ axis = 2, value = 9000 }) == true and calls[5] == "stick:right")
    assert(n:onGamepadAxisMotion({ axis = 3, value = 9000 }) == true and calls[6] == "stick:right")
    assert(#log == 0, "the document is untouched")
    -- a plain dialog (no wheel) is context "window" again
    PL.overlay_active = saved_oa
    stack[2] = { widget = {} }
    assert(n:_context() == "window")
    stack[1], stack[2] = nil, nil
    T.now = function() return 0 end
end

-- 14. The pad in an EPUB (TASK-15..18): sticks inert while reading, A / D-pad
-- open the two levels, A held = range, A tapped = menu on the release, X held
-- = modifier, held D-pad repeats, LB / RB / B close, R-stick switches the
-- level. A recording fake overlay stands in for selector.lua (its own
-- behaviour: tests/selector_test.lua).
do
    local PadNav = require("padnav")
    local UIM = require("ui/uimanager")
    local stack = UIM._window_stack
    local T = package.loaded["ui/time"]
    local clock = 9000
    T.now = function() clock = clock + 1; return clock end
    local sched = {}
    UIM.scheduleIn = function(_, s, fn) sched[#sched + 1] = { s = s, fn = fn } end
    UIM.unschedule = function(_, fn)
        for i = #sched, 1, -1 do if sched[i].fn == fn then table.remove(sched, i) end end
    end
    local function set_stack(...)
        for i = #stack, 1, -1 do stack[i] = nil end
        for i, w in ipairs({ ... }) do stack[i] = { widget = w } end
    end
    local function args(...)
        local t = {}
        for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
        return table.concat(t, ",")
    end
    local function epub(padmap, layout)
        local log = { ov = {}, events = {}, sel = {}, text = {} }
        local ui = { document = {}, rolling = {},
                     handleEvent = function(_, ev)
                         log.events[#log.events + 1] = ev.name .. (ev.args[1] ~= nil and (":" .. tostring(ev.args[1])) or "")
                     end,
                     view = { footer = { onToggleFooterMode = function() log.events[#log.events + 1] = "footer" end } } }
        local function rec(name) return function(_, ...) log.ov[#log.ov + 1] = name .. "(" .. args(...) .. ")" end end
        local selector = {}
        local function show(mode)
            local ov = { mode = mode, hl_items = {}, hl_cur = 0,
                         step = rec("step"), line = rec("line"), para = rec("para"), action_menu = rec("menu"),
                         to_words = rec("to_words"), to_sentences = rec("to_sentences"),
                         _get_selection = function() return { text = "verbum" } end,
                         _do_vortuyo = rec("vortuyo") }
            function ov:_do_toggle_highlight()
                log.ov[#log.ov + 1] = "toggle"
                if self.mode == "hl" then self.hl_cur = 0 end
            end
            selector.overlay = ov
            set_stack(ui, ov)
        end
        selector._open = function(_, from_end)
            log.sel[#log.sel + 1] = "_open" .. (from_end ~= nil and (":" .. tostring(from_end)) or "")
            show("struct")
        end
        selector._open_walk = function(_, from_end) log.sel[#log.sel + 1] = "_open_walk:" .. tostring(from_end); show("walk") end
        -- point from-to (TASK-29): a scripted pointer -- B first = cancel,
        -- the 4th symbol (start label + end label) = done, then words
        selector._open_point = function()
            log.sel[#log.sel + 1] = "_open_point"
            show("point")
            local ov, presses = selector.overlay, 0
            function ov:point_press(sym)
                log.ov[#log.ov + 1] = "point(" .. sym .. ")"
                if presses == 0 and sym == "B" then return "cancel" end
                presses = presses + 1
                if presses == 4 then self.mode = "walk"; return "done" end
                return presses == 2 and "start" or "prefix"
            end
            return true
        end
        selector._open_highlights = function() log.sel[#log.sel + 1] = "_open_highlights"; return false end
        selector._close = function() log.sel[#log.sel + 1] = "_close"; selector.overlay = nil; set_stack(ui) end
        local n = setmetatable({ ui = ui, enabled_ref = { enabled = true, subs = { selector = selector } } },
            { __index = PadNav })
        n:set_padmap(padmap and P.build(padmap, layout or "xbox") or nil)
        n._show_text = function(_, text) log.text[#log.text + 1] = text end
        set_stack(ui)
        for i = #sched, 1, -1 do sched[i] = nil end
        return n, log, selector
    end
    local function down(n, b) return n:onGamepadButtonDown({ button = b }) end
    local function up(n, b) return n:onGamepadButtonUp({ button = b }) end

    -- reading: both sticks are consumed and do nothing (TASK-12 / TASK-15)
    local n, log = epub()
    assert(n:_context() == "reading")
    for _, a in ipairs({ { 0, -20000 }, { 0, 20000 }, { 1, -20000 }, { 1, 20000 },
                         { 2, -20000 }, { 2, 20000 }, { 3, -20000 }, { 3, 20000 } }) do
        assert(n:onGamepadAxisMotion({ axis = a[1], value = a[2] }) == true, "reading: stick " .. a[1] .. " consumed")
    end
    -- ...also on the legacy key path (LStick* and the F3.. R-stick keys)
    for _, m in ipairs({ "onKPUp", "onKPDown", "onKPLeft", "onKPRight",
                         "onKPRStickUp", "onKPRStickDown", "onKPRStickLeft", "onKPRStickRight" }) do
        assert(n[m](n) == true, m .. " consumed")
    end
    assert(#log.events == 0 and #log.sel == 0 and #log.ov == 0, "reading: sticks move nothing")

    -- A tapped while reading opens "point from-to" on the release (TASK-29),
    -- and that release opens no menu
    assert(down(n, 0) == true and #log.sel == 0, "reading: nothing on the A press")
    up(n, 0)
    assert(log.sel[1] == "_open_point" and n:_context() == "selection" and #log.ov == 0,
        "A tap = point from-to, no menu")
    -- the labels: D-pad and letters are symbols on the press; a held D-pad
    -- does not repeat, A / Y / B start no hold (their release does nothing)
    assert(down(n, 12) == true and #sched == 0, "no D-pad repeat on the labels"); up(n, 12)
    down(n, 0); up(n, 0)
    down(n, 3); up(n, 3)
    assert(down(n, 1) == true); up(n, 1)
    assert(table.concat(log.ov, " ") == "point(down) point(A) point(Y) point(B)",
        "symbols, no menu / Vortuyo / close: " .. table.concat(log.ov, " "))
    assert(n:_selector().overlay.mode == "walk" and n:_context() == "selection" and #log.events == 0,
        "start + end chosen: the word walk")
    -- LT / RT and the sticks in the labels reach only the overlay's guarded
    -- moves (selector.lua ignores them in mode point), X / Y no action
    log.ov = {}
    -- a tap (down + up, no arrow) = the action menu, on the release
    down(n, 0); assert(#log.ov == 0, "nothing on the press")
    up(n, 0); assert(log.ov[1] == "menu()", "tap = menu")
    -- A held + arrows = a range; the release then opens nothing
    log.ov = {}
    down(n, 0); down(n, 14); down(n, 12)
    n:onGamepadAxisMotion({ axis = 0, value = -20000 })
    up(n, 14); up(n, 12); up(n, 0)
    assert(log.ov[1] == "step(1,true)" and log.ov[2] == "line(1,true)" and log.ov[3] == "step(-1,true)"
        and #log.ov == 3, "range moves, no menu: " .. table.concat(log.ov, " "))
    -- without A: plain moves (D-pad and L-stick alike)
    log.ov = {}
    down(n, 13); up(n, 13); down(n, 11); up(n, 11)
    n:onGamepadAxisMotion({ axis = 1, value = 20000 })
    assert(log.ov[1] == "step(-1,false)" and log.ov[2] == "line(-1,false)" and log.ov[3] == "line(1,false)",
        "plain moves: " .. table.concat(log.ov, " "))
    -- a stick snapping back within MENU_STICK_LOCK_S does not undo the move
    T.now = function() return clock end
    clock = clock + 5; n:onGamepadAxisMotion({ axis = 0, value = 20000 })
    clock = clock + 0.05
    assert(n:onGamepadAxisMotion({ axis = 0, value = -6000 }) == true and #log.ov == 4, "selection: bounce eaten")
    T.now = function() clock = clock + 1; return clock end

    -- R-stick switches the level (TASK-17); ←/→ nothing
    log.ov = {}
    n:onGamepadAxisMotion({ axis = 3, value = 20000 })
    n:onGamepadAxisMotion({ axis = 3, value = -20000 })
    n:onGamepadAxisMotion({ axis = 2, value = 20000 })
    assert(log.ov[1] == "to_words()" and log.ov[2] == "to_sentences()" and #log.ov == 2, table.concat(log.ov, " "))
    -- Y = Vortuyo, X = toggle highlight
    log.ov = {}
    down(n, 3); down(n, 2)
    assert(log.ov[1]:find("^vortuyo"), "Y = Vortuyo")
    assert(log.ov[2] == "toggle" and not n._x_mode, "X = highlight, not the modifier")

    -- held D-pad repeats (TASK-16): first after the delay, then every step;
    -- the release stops it
    log.ov = {}
    down(n, 14)
    assert(#sched == 1 and math.abs(sched[1].s - 0.45) < 1e-9, "repeat scheduled after the delay")
    local tick = table.remove(sched, 1).fn
    tick()
    assert(#log.ov == 2 and log.ov[2] == "step(1,false)" and #sched == 1 and math.abs(sched[1].s - 0.15) < 1e-9,
        "repeated step, next one scheduled")
    up(n, 14)
    assert(#sched == 0, "release unschedules")
    tick()
    assert(#log.ov == 2, "a stale tick does nothing")
    -- ...and a context change stops it too
    down(n, 12); tick = table.remove(sched, 1).fn
    set_stack(n.ui, n.enabled_ref.subs.selector.overlay, {}) -- a dialog on top
    tick()
    assert(#log.ov == 3 and #sched == 0, "no step under a dialog, repeat ended")
    set_stack(n.ui, n.enabled_ref.subs.selector.overlay)
    up(n, 12)
    -- ...and it speeds up (TASK-25): 0.15 s for the first repeats, then
    -- shorter and shorter, never below 0.05 s
    down(n, 14)
    local gaps = {}
    for _ = 1, 30 do
        tick = table.remove(sched, 1).fn; tick()
        gaps[#gaps + 1] = sched[1].s
    end
    up(n, 14)
    assert(math.abs(gaps[1] - 0.15) < 1e-9 and math.abs(gaps[4] - 0.15) < 1e-9, "first repeats at the base rate")
    assert(gaps[5] < 0.15 and gaps[6] < gaps[5], "then faster: " .. gaps[5] .. " " .. gaps[6])
    assert(math.abs(gaps[30] - 0.05) < 1e-9, "floor 0.05 s: " .. gaps[30])
    for i = 2, 30 do assert(gaps[i] <= gaps[i - 1] + 1e-12, "never slower again") end

    -- LB / RB close the selection and turn the page; B closes it
    local sel
    n, log, sel = epub()
    sel:_open() -- the sentences (A tapped = point from-to now)
    assert(down(n, 10) == true and log.sel[2] == "_close" and log.events[1] == "GotoViewRel:1", "RB")
    sel:_open()
    assert(down(n, 9) == true and log.events[2] == "GotoViewRel:-1", "LB")
    sel:_open()
    assert(down(n, 1) == true and sel.overlay == nil and #log.events == 2, "B closes, no page turn")

    -- LT / RT in the selection (TASK-25): a paragraph, the overlay stays open;
    -- held, the stock auto-repeat keeps jumping; with A held = range
    n, log, sel = epub()
    T.now = function() return clock end
    clock = clock + 10
    sel:_open()
    assert(n:onGamepadAxisMotion({ axis = 5, value = 32767 }) == true and log.ov[1] == "para(1,false)"
        and sel.overlay and #log.events == 0, "RT = next paragraph, no page turn")
    clock = clock + 0.5                                  -- first stock repeat
    n:onGamepadAxisMotion({ axis = 5, value = 32767 })
    clock = clock + 0.2                                  -- next one
    n:onGamepadAxisMotion({ axis = 5, value = 32767 })
    assert(#log.ov == 3 and log.ov[3] == "para(1,false)", "held RT repeats: " .. table.concat(log.ov, " "))
    clock = clock + 5
    down(n, 0)
    n:onGamepadAxisMotion({ axis = 4, value = 32767 })
    up(n, 0)
    assert(log.ov[4] == "para(-1,true)" and #log.ov == 4, "A + LT = range by paragraph, no menu")
    -- legacy key path (LPgBack / LPgFwd) too
    n:onKPPgFwd2(); assert(log.ov[5] == "para(1,false)")
    -- while reading the repeat is still filtered: one press = one page
    sel:_close()
    clock = clock + 5
    n:onGamepadAxisMotion({ axis = 5, value = 32767 })
    clock = clock + 0.5
    n:onGamepadAxisMotion({ axis = 5, value = 32767 })
    assert(#log.events == 1 and log.events[1] == "GotoViewRel:1", "reading: held RT = one page")
    T.now = function() clock = clock + 1; return clock end

    -- D-pad while reading (TASK-28): pages, →/↓ next, ←/↑ previous, no repeat
    n, log, sel = epub()
    for btn, want in pairs({ [14] = "GotoViewRel:1", [12] = "GotoViewRel:1",
                             [13] = "GotoViewRel:-1", [11] = "GotoViewRel:-1" }) do
        log.events = {}
        assert(down(n, btn) == true and log.events[1] == want and #log.sel == 0,
            "D-pad " .. btn .. " -> " .. want .. ", got " .. tostring(log.events[1]))
        assert(#sched == 0, "a page turn does not repeat")
        up(n, btn)
    end
    -- A held + D-pad = the words, →/↓ from the first word, ←/↑ from the last;
    -- the release of that A is no tap; while the entry A is still held the
    -- arrows only move the cursor (the start point), a range needs a new A hold
    log.events = {}
    down(n, 0); down(n, 14)
    assert(log.sel[1] == "_open_walk:false" and #log.ov == 0 and #log.events == 0, "A + → = words, first")
    assert(#sched == 0, "the press that opened the words does not repeat")
    up(n, 14); down(n, 14); up(n, 14)
    assert(log.ov[1] == "step(1,false)", "entry A still held: the cursor moves, no range")
    up(n, 0); assert(#log.ov == 1, "no menu after A + D-pad")
    down(n, 0); down(n, 14); up(n, 14)
    assert(log.ov[2] == "step(1,true)", "a new A hold + D-pad = a range")
    up(n, 0); assert(#log.ov == 2, "no menu after a range")
    sel:_close()
    down(n, 0); down(n, 13); up(n, 13); up(n, 0)
    assert(log.sel[3] == "_open_walk:true", "A + ← = words, last")
    sel:_close()
    -- Y held + D-pad = the sentences; Y's release then shows no highlights
    down(n, 3); down(n, 12); up(n, 12); up(n, 3)
    assert(log.sel[5] == "_open:false" and #log.text == 0, "Y + ↓ = sentences, first: " .. tostring(log.sel[5]))
    sel:_close()
    down(n, 3); down(n, 11); up(n, 11); up(n, 3)
    assert(log.sel[7] == "_open:true", "Y + ↑ = sentences, last")
    sel:_close()
    assert(#log.events == 0, "no page turned by a combo")
    -- legacy key path (no release): the D-pad turns pages too
    n, log = epub()
    n:onKPRight2(); assert(log.events[1] == "GotoViewRel:1" and #log.sel == 0, "legacy D-pad = page")

    -- Y tapped while reading: the page's highlights, on the release; none = a message
    n, log = epub()
    assert(down(n, 3) == true and #log.sel == 0, "nothing on the Y press")
    up(n, 3)
    assert(log.sel[1] == "_open_highlights" and log.text[1] == "No highlights on this page")
    -- browsing highlights: X removing the last one closes the overlay
    n, log, sel = epub()
    sel._open_highlights = function()
        log.sel[#log.sel + 1] = "_open_highlights"
        sel._open(); sel.overlay.mode, sel.overlay.hl_cur = "hl", 1
        return true
    end
    down(n, 3); up(n, 3)
    assert(sel.overlay and sel.overlay.mode == "hl" and #log.text == 0)
    down(n, 2)
    assert(sel.overlay == nil and log.sel[#log.sel] == "_close", "last highlight removed -> closed")

    -- X held = modifier (TASK-16): combos while held, gone on the release
    n, log = epub()
    down(n, 2); assert(n._x_mode)
    down(n, 11); down(n, 12)
    assert(log.events[1] == "ShowMenu" and log.events[2] == "footer" and n._x_mode, "two combos while X is held")
    assert(#sched == 0 and #log.sel == 0, "a combo opens nothing and does not repeat")
    up(n, 11); up(n, 12); up(n, 2)
    assert(not n._x_mode, "release ends the modifier")
    down(n, 12); assert(log.events[3] == "GotoViewRel:1" and #log.sel == 0, "D-pad without X = page again")
    -- legacy key path: X is a latch, one combo spends it
    n, log = epub()
    n:onKPExtend(); assert(n._x_mode)
    n:onKPUp2(); assert(log.events[1] == "ShowMenu" and not n._x_mode, "legacy latch spent")
    -- a trigger acting as X never reports a release: a latch too
    n, log = epub({ version = 1, layouts = { xbox = { ltrigger = "x" } } })
    n:onGamepadAxisMotion({ axis = 4, value = 32767 })
    assert(n._x_mode and n._x_hold == nil, "trigger as X = latch")
    down(n, 11); assert(log.events[1] == "ShowMenu" and not n._x_mode)
    -- x_modifier on another role: held like X
    n, log = epub({ version = 1, actions = { b = "x_modifier" } })
    down(n, 1); assert(n._x_mode and n._x_hold == 1)
    up(n, 1); assert(not n._x_mode, "role b released")

    -- the release is remapped like the press: nintendo, physical east = role A
    n, log = epub(nil)
    n:set_padmap(P.build(nil, "nintendo"))
    down(n, 1); up(n, 1)                -- role A tapped: point from-to (on the release)
    assert(log.sel[1] == "_open_point" and #log.ov == 0, "remapped A release")
    down(n, 0); up(n, 0)                -- physical south = role B: the symbol B = cancel
    assert(log.ov[1] == "point(B)" and log.sel[2] == "_close" and n:_context() == "reading",
        "remapped B on the labels: " .. table.concat(log.ov, " "))
    down(n, 1); up(n, 1)                -- role A: point from-to again, no menu
    assert(log.sel[3] == "_open_point" and #log.ov == 1)
    -- a page without text: a message, nothing opens
    local nosel
    n, log, nosel = epub()
    nosel._open_point = function() log.sel[#log.sel + 1] = "_open_point"; return false end
    down(n, 0); up(n, 0)
    assert(log.sel[1] == "_open_point" and nosel.overlay == nil and log.text[1] == "No text on this page",
        "no text: " .. tostring(log.text[1]))

    -- B held + D-pad in an EPUB (TASK-33): ↑/↓ font size, ←/→ margins (both
    -- sides, clamped), repeated while held; B tapped = back on the release
    n, log = epub()
    n.ui.document.configurable = { h_page_margins = { 10, 10 } }
    n.onKPBack = function() log.ov[#log.ov + 1] = "back" return true end
    assert(down(n, 1) == true and #log.ov == 0 and #log.events == 0, "B press: nothing yet")
    down(n, 11); assert(log.events[1] == "IncreaseFontSize:1", "B + ↑ = bigger font")
    assert(#sched == 1 and math.abs(sched[1].s - 0.45) < 1e-9, "font repeats after the delay")
    sched[1].fn(); table.remove(sched, 1)
    assert(log.events[2] == "IncreaseFontSize:1" and #sched == 1 and math.abs(sched[1].s - 0.4) < 1e-9,
        "font repeat at VIEW_REPEAT_S")
    up(n, 11); assert(#sched == 0, "release stops the repeat")
    down(n, 12); up(n, 12); assert(log.events[3] == "DecreaseFontSize:1", "B + ↓ = smaller font")
    down(n, 14); up(n, 14)
    local m = n.ui.document.configurable.h_page_margins
    assert(log.events[4]:match("^SetPageHorizMargins") and m[1] == 15 and m[2] == 15, "B + → = wider margins")
    for _ = 1, 5 do down(n, 13); up(n, 13) end
    m = n.ui.document.configurable.h_page_margins
    assert(m[1] == 0 and m[2] == 0, "B + ← = narrower, never below 0")
    up(n, 1); assert(#log.ov == 0 and #log.sel == 0, "no back, no selection after B + D-pad")
    down(n, 1); up(n, 1); assert(log.ov[1] == "back", "B tap = back")
    down(n, 12); assert(log.events[#log.events] == "GotoViewRel:1", "D-pad without B = page again")
    up(n, 12)

    -- legacy key path in the selection: A = menu on the press, RB / LB = range steps
    n, log = epub()
    n:onKPConfirm(); assert(log.sel[1] == "_open")
    n:onKPConfirm(); assert(log.ov[1] == "menu()", "legacy A = menu at once")
    n:onKPPgFwd(); n:onKPPgBk()
    assert(log.ov[2] == "step(1,true)" and log.ov[3] == "step(-1,true)" and #log.events == 0, "legacy RB / LB = range")

    UIM.scheduleIn, UIM.unschedule = nil, nil
    set_stack()
    T.now = function() return 0 end
end

-- 15. Text-input dialogs in context "window": X = backspace, A = accept (the
-- is_enter_default button) while the focus is on the field, RT held =
-- dictation through diktonoti (pluginaro integration B; start on the press,
-- stop when the polled Gamepad.held_axis_directions shows the release), B
-- cancels a running recording, else stays the stock Back.
do
    local PadNav = require("padnav")
    local PL = package.loaded.pluginaro
    local UIM = require("ui/uimanager")
    local stack = UIM._window_stack
    local saved_cp, saved_sched = PL.call_provided, UIM.scheduleIn
    local saved_gp = package.loaded["device/sdl/gamepad"]
    local held = {}
    package.loaded["device/sdl/gamepad"] = { held_axis_directions = held }
    local sched = {}
    UIM.scheduleIn = function(_, s, fn) sched[#sched + 1] = fn end
    local function run_sched()
        local list = sched; sched = {}
        for _, fn in ipairs(list) do fn() end
    end
    local toggle, recording, calls = true, false, {}
    PL.call_provided = function(host, provider, id, method)
        assert(host == "diktonoti" and provider == "kopad" and id == "gamepad_dictate", "contract triple")
        if not toggle then return nil end
        if method == "is_active" then return true end
        if method == "is_recording" then return recording end
        calls[#calls + 1] = method
        return true
    end
    local log = {}
    local input = { focused = true, charlist = {}, delChar = function() log[#log + 1] = "del" end }
    local dlg = { _input_widget = input, buttons = { {
        { text = "Cancel", callback = function() log[#log + 1] = "cancel_btn" end },
        { text = "Save", is_enter_default = true, callback = function() log[#log + 1] = "save" end },
    } } }
    local ui = { document = {}, rolling = {}, handleEvent = function() end }
    for i = #stack, 1, -1 do stack[i] = nil end
    stack[1], stack[2] = { widget = ui }, { widget = dlg }
    local n = setmetatable({ ui = ui, enabled_ref = { enabled = true, subs = {} } }, { __index = PadNav })
    n:set_padmap(nil)
    assert(n:_context() == "window")

    -- X = backspace, A = default button; with the focus on a button row A is stock
    assert(n:onGamepadButtonDown({ button = 2 }) == true and log[1] == "del", "X = backspace")
    assert(n:onGamepadButtonDown({ button = 0 }) == true and log[2] == "save", "A = Save")
    dlg.selected = { x = 1, y = 2 }
    assert(n:onGamepadButtonDown({ button = 0 }) == false and #log == 2, "A on a button row: stock")
    dlg.selected = nil

    -- RT held: start, auto-repeats consumed without new calls, release -> stop
    held[5] = "plus"
    assert(n:onGamepadAxisMotion({ axis = 5, value = 32767 }) == true and calls[1] == "start", "RT press starts")
    assert(n:onGamepadAxisMotion({ axis = 5, value = 32767 }) == true and #calls == 1, "repeat while held")
    run_sched()
    assert(#calls == 1 and #sched == 1, "still held: keep polling")
    held[5] = nil
    run_sched()
    assert(calls[2] == "stop" and #sched == 0, "release stops")
    -- the next press starts again
    held[5] = "plus"
    n:onGamepadAxisMotion({ axis = 5, value = 32767 })
    assert(calls[3] == "start", "second hold")
    held[5] = nil; run_sched()

    -- B: cancels while recording, else stock Back (false)
    recording, calls = true, {}
    assert(n:onGamepadButtonDown({ button = 1 }) == true and calls[1] == "cancel", "B cancels")
    recording, calls = false, {}
    assert(n:onGamepadButtonDown({ button = 1 }) == false and #calls == 0, "B stock when idle")

    -- toggle off: RT not routed (consumed by the window trigger rule), X / A still work
    toggle, calls = false, {}
    held[5] = "plus"
    assert(n:onGamepadAxisMotion({ axis = 5, value = 32767 }) == true and #calls == 0 and #sched == 0, "toggle off: no dictation")
    held[5] = nil
    assert(n:onGamepadButtonDown({ button = 2 }) == true and log[3] == "del", "toggle off: X still backspace")

    -- a dialog without a focused text field: X / A stock, RT no dictation
    toggle = true
    input.focused = false
    calls = {}
    assert(n:onGamepadButtonDown({ button = 2 }) == false and n:onGamepadButtonDown({ button = 0 }) == false, "no field: stock")
    held[5] = "plus"
    n:onGamepadAxisMotion({ axis = 5, value = 32767 })
    assert(#calls == 0, "no field: RT not routed")
    held[5] = nil

    for i = #stack, 1, -1 do stack[i] = nil end
    PL.call_provided, UIM.scheduleIn = saved_cp, saved_sched
    package.loaded["device/sdl/gamepad"] = saved_gp
end

-- 16. The quick-action wheel (TASK-26, PC-021): padmap `quick` and the R-stick.
do
    -- padmap: built-in sets, a set given replaces the built-in one whole, bad
    -- entries are skipped with a warning, never raised
    for _, set in ipairs(P.QUICK_SETS) do
        for d, a in pairs(P.DEFAULT_QUICK[set]) do
            assert(P.quick_allowed(set, a), set .. "." .. d .. " = " .. a .. " is allowed")
        end
    end
    for _, a in ipairs(P.QUICK_FILES_ACTIONS) do assert(P.ACTIONS[a], a .. " is an action") end
    assert(not P.quick_allowed("reading", "x_modifier") and not P.quick_allowed("files", "toc"))
    local q = P.build_quick(nil)
    assert(q.reading.up == "toc" and q.reading.up_left == "fulltext_search" and q.files.left == "top_menu")
    assert(P.build(nil, "xbox").quick.reading.down == "footer_menu", "no padmap: built-in wheel")
    assert(P.build({ version = 2 }, "xbox", function() end).quick.files.up == "history", "bad version: built-in wheel")
    local warns = {}
    local function w(m) warns[#warns + 1] = m end
    q = P.build_quick({ version = 1, quick = {
        reading = { up = "toc", down = "none", left = "x_modifier", north = "toc" },
        files = { up = "toc" }, menu = {} } }, w)
    assert(q.reading.up == "toc" and q.reading.down == nil and q.reading.left == nil and q.reading.right == nil,
        "a set given replaces the built-in one; none / x_modifier / unknown direction = empty")
    assert(next(q.files) == nil, "files: a book action is skipped, the set stays given (empty)")
    assert(#warns == 4, "4 warnings, got " .. #warns .. ": " .. table.concat(warns, " | "))
    warns = {}
    q = P.build_quick({ version = 1, quick = "x" }, w)
    assert(#warns == 1 and q.reading.up == "toc", "quick not a table: built-in")
    q = P.build_quick({ version = 1, quick = { reading = 3 } }, w)
    assert(#warns == 2 and q.reading.up == "toc", "set not a table: built-in")

    -- padnav: R-stick in plain reading opens a forced, aimed wheel
    local PadNav = require("padnav")
    local UIM = require("ui/uimanager")
    local stack = UIM._window_stack
    local saved_sched, saved_unsched, saved_show, saved_close =
        UIM.scheduleIn, UIM.unschedule, UIM.show, UIM.close
    local sched, shown, closed = {}, {}, {}
    UIM.scheduleIn = function(_, s, fn) sched[#sched + 1] = fn end
    UIM.unschedule = function() end
    UIM.show = function(_, d) shown[#shown + 1] = d end
    UIM.close = function(_, d) closed[#closed + 1] = d; d:onCloseWidget() end
    local BD = {}
    function BD:new(o) setmetatable(o, { __index = self }); return o end
    function BD:onCloseWidget() self.closed = true end
    package.loaded["ui/widget/buttondialog"] = BD
    local held = {}
    local saved_gp = package.loaded["device/sdl/gamepad"]
    package.loaded["device/sdl/gamepad"] = { held_axis_directions = held }
    local saved_dev = package.loaded["device"]
    package.loaded["device"] = { hasBattery = function() return true end,
        getPowerDevice = function() return { getCapacity = function() return 81 end } end }

    local function reader(kind, padmap)
        local log = {}
        local ui = { handleEvent = function(_, ev) log[#log + 1] = ev.name end }
        if kind ~= "fm" then
            ui.document = { getPageCount = function() return 10 end }
            ui.getCurrentPage = function() return 3 end
            ui.toc = { getTocTitleByPage = function(_, pg) return pg == 3 and "  Rozdzia\xC5\x82\n drugi  " or "" end }
            if kind == "pdf" then ui.paging = { current_page = 3 } else ui.rolling = {} end
        end
        for i = #stack, 1, -1 do stack[i] = nil end
        stack[1] = { widget = ui }
        local n = setmetatable({ ui = ui, enabled_ref = { enabled = true, subs = {} } }, { __index = PadNav })
        n:set_padmap(P.build(padmap, "xbox"))
        shown, closed, sched = {}, {}, {}
        for k in pairs(held) do held[k] = nil end
        return n, log
    end
    local function labels(d)
        local t = {}
        for i, row in ipairs(d.buttons) do t[i] = row[1].text end
        return table.concat(t, "|")
    end

    local n, log = reader("epub")
    assert(n:_context() == "reading")
    held[3] = "plus"
    assert(n:onGamepadAxisMotion({ axis = 3, value = 20000 }) == true and #shown == 1, "R-stick opens the wheel")
    local d = shown[1]
    assert(d._kopad_force_wheel == true and d._kopad_stick == "right")
    assert(labels(d) == "Table of contents|Toggle bookmark|Forward to next location|Book map|"
        .. "Footer mode toggle|History|Back to previous location|Fulltext search", labels(d))
    local b = d.buttons
    assert(b[1][1].kopad_glyph == "\u{F03A}" and b[1][1].kopad_hint == "X + LB", "toc: glyph and X combo")
    assert(b[7][1].kopad_hint == "B" and b[6][1].kopad_hint == "X + \xE2\x86\x90" and b[5][1].kopad_hint == "X + \xE2\x86\x93")
    assert(b[2][1].kopad_hint == nil, "toggle_bookmark: no other way in")
    assert(d.title:find("Rozdzia\xC5\x82 drugi", 1, true) and d.title:find("page 3 / 10", 1, true)
        and d.title:find("81%", 1, true), d.title)
    -- A on "Table of contents": the wheel closes first, then the action runs
    b[1][1].callback()
    assert(closed[1] == d and log[1] == "ShowToc", "closed, then ShowToc")
    -- the stick is still pushed: its auto-repeat must not reopen the wheel
    assert(n._quick_blocked == true and #sched == 1)
    n:onGamepadAxisMotion({ axis = 3, value = 5001 })
    assert(#shown == 1, "blocked until centred")
    held[3] = nil
    sched[1]()
    assert(n._quick_blocked == nil, "centred: re-armed")
    n:onGamepadAxisMotion({ axis = 2, value = -20000 })
    assert(#shown == 2, "a new push opens it again")
    -- closed without an action, stick already centred: no block
    shown[2]:onCloseWidget()
    assert(n._quick_blocked == nil)
    -- X modifier armed: the R-stick does nothing
    n._x_mode = true
    n:onGamepadAxisMotion({ axis = 3, value = 20000 })
    assert(#shown == 2, "X combo pending: no wheel")
    n._x_mode = false

    -- koligilo's overrides: the set from padmap, hints follow the role actions
    n, log = reader("epub", { version = 1, actions = { b = "toc" },
        quick = { reading = { up = "back_location", down = "toc", left = "none" } } })
    n:onGamepadAxisMotion({ axis = 3, value = -20000 })
    d = shown[1]
    assert(labels(d) == "Back to previous location|Table of contents", labels(d))
    assert(d.buttons[1][1].kopad_hint == nil and d.buttons[2][1].kopad_hint == "B", "B = toc now")

    -- one action: run at once, no wheel; none: nothing (still consumed)
    n, log = reader("epub", { version = 1, quick = { reading = { right = "night_mode" } } })
    assert(n:onGamepadAxisMotion({ axis = 2, value = 20000 }) == true and #shown == 0 and log[1] == "ToggleNightMode")
    n, log = reader("epub", { version = 1, quick = { reading = {} } })
    assert(n:onGamepadAxisMotion({ axis = 2, value = 20000 }) == true and #shown == 0 and #log == 0)

    -- PDF: the same reading set (the R-stick no longer zooms)
    n, log = reader("pdf")
    assert(n:_context() == "paged")
    n:onGamepadAxisMotion({ axis = 3, value = -20000 })
    assert(#shown == 1 and #shown[1].buttons == 8 and #log == 0, "PDF: reading wheel")

    -- file browser: the files set, no hints, title without chapter / page
    n, log = reader("fm")
    assert(n:_context() == "filemanager")
    n:onGamepadAxisMotion({ axis = 3, value = 20000 })
    d = shown[1]
    assert(labels(d) == "History|Favorites|Collections|Previous book|Top menu|File browser", labels(d))
    for _, row in ipairs(d.buttons) do assert(row[1].kopad_hint == nil, "no hints in the file browser") end
    assert(not d.title:find("page", 1, true) and d.title:find("81%", 1, true), d.title)
    d.buttons[4][1].callback()
    assert(log[1] == "OpenLastDoc")

    -- the selection keeps the R-stick for its levels (section 14)
    for i = #stack, 1, -1 do stack[i] = nil end
    UIM.scheduleIn, UIM.unschedule, UIM.show, UIM.close = saved_sched, saved_unsched, saved_show, saved_close
    package.loaded["ui/widget/buttondialog"] = nil
    package.loaded["device/sdl/gamepad"] = saved_gp
    package.loaded["device"] = saved_dev
end

-- 17. Confirmation dialogs labelled by padconfirm.lua (context "window"):
-- A = the "A ·" button while no focus is painted, else stock; Start = "A ·"
-- always; B / X = their buttons; unlabelled windows keep the stock keys.
do
    local PadNav = require("padnav")
    local stack = require("ui/uimanager")._window_stack
    local log = {}
    local function btn(text, name)
        return { text = text, callback = function() log[#log + 1] = name end, frame = { invert = false } }
    end
    local ok_b = btn("A · Delete", "ok")
    local dlg = { _kopad_confirm = { A = true, B = true }, { { ok_b, btn("B · Cancel", "cancel") } } }
    local ui = { document = {}, rolling = {}, handleEvent = function() end }
    for i = #stack, 1, -1 do stack[i] = nil end
    stack[1], stack[2] = { widget = ui }, { widget = dlg }
    local n = setmetatable({ ui = ui, enabled_ref = { enabled = true, subs = {} } }, { __index = PadNav })
    n:set_padmap(nil)
    assert(n:_context() == "window")

    assert(n:onGamepadButtonDown({ button = 0 }) == true and log[1] == "ok", "A = labelled OK")
    assert(n:onGamepadButtonDown({ button = 1 }) == true and log[2] == "cancel", "B = labelled Cancel")
    assert(n:onGamepadButtonDown({ button = 2 }) == false and #log == 2, "X: no letter here -> stock")
    ok_b.frame.invert = true
    assert(n:onGamepadButtonDown({ button = 0 }) == false and #log == 2, "A with a painted focus: stock")
    assert(n:onGamepadButtonDown({ button = 6 }) == true and log[3] == "ok", "Start = OK, focus or not")

    -- an unlabelled window: unchanged (A / B stock, Start swallowed)
    stack[2] = { widget = { { { btn("OK", "plain") } } } }
    assert(n:onGamepadButtonDown({ button = 0 }) == false and n:onGamepadButtonDown({ button = 1 }) == false, "unlabelled: stock")
    assert(n:onGamepadButtonDown({ button = 6 }) == true and #log == 3, "unlabelled: Start swallowed")
    for i = #stack, 1, -1 do stack[i] = nil end
end

print("padmap_test: all tests passed")
