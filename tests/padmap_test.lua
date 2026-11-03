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
    -- R-stick: consumed, no action (zoom moved to A + D-pad)
    for _, c in ipairs({ { 3, -20000 }, { 3, 20000 }, { 2, -20000 }, { 2, 20000 } }) do
        log.events = {}
        assert(n:onGamepadAxisMotion({ axis = c[1], value = c[2] }) == true and #log.events == 0,
            "paged R-stick " .. c[1] .. "/" .. c[2] .. " is consumed and does nothing")
    end
    n.ui.zooming.zoom = 1
    n:onGamepadButtonDown({ button = 0 }); n:onGamepadButtonDown({ button = 11 })
    n:onGamepadButtonUp({ button = 11 }); n:onGamepadButtonUp({ button = 0 })
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
    -- A held + D-pad: zoom (↑/↓) and fit (←/→); A alone does nothing, a D-pad
    -- without A still pans, and the release of A ends the modifier
    n, log = paged()
    assert(n:onGamepadButtonDown({ button = 0 }) == true and #log.events == 0, "A alone: consumed, no event")
    for btn, want in pairs({ [11] = "zoom:1.030", [13] = "SetZoomMode:page", [14] = "SetZoomMode:contentwidth" }) do
        log.events = {}
        assert(n:onGamepadButtonDown({ button = btn }) == true and log.events[1] == want,
            "A + D-pad " .. btn .. " -> " .. want .. ", got " .. tostring(log.events[1]))
        n:onGamepadButtonUp({ button = btn })
    end
    log.events = {}
    n.ui.zooming.zoom = 1
    n:onGamepadButtonDown({ button = 12 }); n:onGamepadButtonUp({ button = 12 })
    assert(log.events[1] == "zoom:0.971", "A + D-pad down zooms out: " .. tostring(log.events[1]))
    n:onGamepadButtonUp({ button = 0 })
    log.events = {}
    n:onGamepadButtonDown({ button = 11 })
    assert(log.events[1] == "Panning:0,-0.2", "after A is released the D-pad pans again")
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
    assert(n:onGamepadButtonDown({ button = 0 }) == true and log.selector[1] == "_open", "EPUB: A opens the selector")
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
    for _, a in ipairs({ 0, 1, 2, 3 }) do
        assert(n:onGamepadAxisMotion({ axis = a, value = 20000 }) == false, "filemanager: stick " .. a .. " is stock")
    end
    n:onGamepadAxisMotion({ axis = 5, value = 32767 }); n:onGamepadAxisMotion({ axis = 4, value = 32767 })
    assert(pages[1] == "next" and pages[2] == "prev", "filemanager: LT/RT = list page")
    assert(#log.events == 0)
    assert(n:onGamepadButtonDown({ button = 4 }) == true and log.events[1] == "ShowMenu", "filemanager: Select = menu")
    -- B = parent folder, never the stock "Exit KOReader?" (TASK-11)
    assert(n:onGamepadButtonDown({ button = 1 }) == true and pages[3] == "up", "filemanager: B = folder up")
    -- B while reading (EPUB and PDF, no selection): back to the previous
    -- location only, never the stock Back that ends in "Exit KOReader?"
    for _, kind in ipairs({ "epub", "pdf" }) do
        local r, rlog, rui = reader(kind)
        set_stack(rui)
        local back = 0
        rui.link = { onGoBackLink = function(_, notify) assert(notify == true); back = back + 1; return false end }
        assert(r:onGamepadButtonDown({ button = 1 }) == true and r:onGamepadButtonDown({ button = 1 }) == true
            and back == 2, kind .. ": B = previous location, consumed even when the history is empty")
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
        selector._open = function() log.sel[#log.sel + 1] = "_open"; show("struct") end
        selector._open_walk = function(_, from_end) log.sel[#log.sel + 1] = "_open_walk:" .. tostring(from_end); show("walk") end
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

    -- A opens the sentences; its own release opens no menu
    assert(down(n, 0) == true and log.sel[1] == "_open" and n:_context() == "selection")
    up(n, 0)
    assert(#log.ov == 0, "the A that opened the selection is not a tap")
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
    down(n, 0); up(n, 0)
    assert(down(n, 10) == true and log.sel[2] == "_close" and log.events[1] == "GotoViewRel:1", "RB")
    down(n, 0); up(n, 0)
    assert(down(n, 9) == true and log.events[2] == "GotoViewRel:-1", "LB")
    down(n, 0); up(n, 0)
    assert(down(n, 1) == true and sel.overlay == nil and #log.events == 2, "B closes, no page turn")

    -- LT / RT in the selection (TASK-25): a paragraph, the overlay stays open;
    -- held, the stock auto-repeat keeps jumping; with A held = range
    n, log, sel = epub()
    T.now = function() return clock end
    clock = clock + 10
    down(n, 0); up(n, 0)
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

    -- D-pad while reading: the word level, ↓/→ from the first word, ↑/← from the last
    n, log, sel = epub()
    down(n, 12); assert(log.sel[1] == "_open_walk:false" and #log.ov == 0, "D-pad ↓ only opens")
    up(n, 12); sel:_close()
    down(n, 13); assert(log.sel[3] == "_open_walk:true", "D-pad ← from the last word")
    up(n, 13)

    -- Y while reading: the page's highlights; none = a message
    n, log = epub()
    assert(down(n, 3) == true and log.sel[1] == "_open_highlights" and log.text[1] == "No highlights on this page")
    -- browsing highlights: X removing the last one closes the overlay
    n, log, sel = epub()
    sel._open_highlights = function()
        log.sel[#log.sel + 1] = "_open_highlights"
        sel._open(); sel.overlay.mode, sel.overlay.hl_cur = "hl", 1
        return true
    end
    down(n, 3)
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
    down(n, 12); assert(log.sel[1] == "_open_walk:false", "D-pad without X = words again")
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
    down(n, 1); up(n, 1)                -- role A: opens the sentences
    down(n, 1); up(n, 1)                -- role A tapped: the menu
    assert(log.sel[1] == "_open" and log.ov[1] == "menu()", "remapped A release")
    down(n, 0); up(n, 0)                -- physical south = role B: closes, no menu
    assert(log.sel[2] == "_close" and #log.ov == 1)

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

-- 15. Dictation routing (pluginaro integration B, diktonoti) in context
-- "window": R3 toggles while a text field is focused (is_active) or a
-- recording runs, B cancels only a running recording. Toggle off / no
-- focused field: R3 swallowed, B stock, nothing called.
do
    local PadNav = require("padnav")
    local PL = package.loaded.pluginaro
    local stack = require("ui/uimanager")._window_stack
    local saved_cp = PL.call_provided
    local toggle, active, recording, calls = true, true, false, {}
    PL.call_provided = function(host, provider, id, method)
        assert(host == "diktonoti" and provider == "kopad" and id == "gamepad_dictate", "contract triple")
        if not toggle then return nil end
        if method == "is_active" then return active end
        if method == "is_recording" then return recording end
        calls[#calls + 1] = method
        return true
    end
    local ui = { document = {}, rolling = {}, handleEvent = function() end }
    local note_dialog = {}
    for i = #stack, 1, -1 do stack[i] = nil end
    stack[1], stack[2] = { widget = ui }, { widget = note_dialog }
    local n = setmetatable({ ui = ui, enabled_ref = { enabled = true, subs = {} } }, { __index = PadNav })
    n:set_padmap(nil)
    assert(n:_context() == "window")

    assert(n:onGamepadButtonDown({ button = 8 }) == true and calls[1] == "toggle", "R3 starts")
    recording, active = true, false
    assert(n:onGamepadButtonDown({ button = 8 }) == true and calls[2] == "toggle", "R3 stops while recording")
    assert(n:onGamepadButtonDown({ button = 1 }) == true and calls[3] == "cancel", "B cancels while recording")
    recording, calls = false, {}
    assert(n:onGamepadButtonDown({ button = 1 }) == false and #calls == 0, "B stock when idle")
    assert(n:onGamepadButtonDown({ button = 8 }) == true and #calls == 0, "R3 swallowed without a text field")
    active, toggle = true, false
    assert(n:onGamepadButtonDown({ button = 8 }) == true and #calls == 0, "toggle off: R3 swallowed, no call")
    assert(n:onGamepadButtonDown({ button = 1 }) == false and #calls == 0, "toggle off: B stock")
    -- reading context (nothing on top): never routed
    toggle = true
    stack[2] = nil
    assert(n:_context() == "reading")
    n:onGamepadButtonDown({ button = 8 })
    assert(#calls == 0, "reading: R3 not routed")
    for i = #stack, 1, -1 do stack[i] = nil end
    PL.call_provided = saved_cp
end

print("padmap_test: all tests passed")
