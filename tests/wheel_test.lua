-- Tests for wheel.lua (ButtonDialog as a radial menu, TASK-19): the pure
-- part and the controller, KOReader stubbed. Run from the repo root:
--   lua tests/wheel_test.lua
package.path = "./?.lua;" .. package.path

local clock = 0
local held = {}
package.preload["gettext"] = function() return function(s) return s end end
package.preload["ui/time"] = function()
    return { now = function() return clock end, to_s = function(t) return t end }
end
package.preload["device/sdl/gamepad"] = function() return { held_axis_directions = held } end

local W = require("wheel")

-- 1. Sectors (TASK-20): n equal sectors, the first one at the top.
do
    local function angles(n)
        local t = {}
        for i = 1, n do t[i] = string.format("%g", W.angle_of(i, n)) end
        return table.concat(t, ",")
    end
    assert(angles(2) == "0,180", angles(2))
    assert(angles(4) == "0,90,180,270", angles(4))
    assert(angles(6) == "0,60,120,180,240,300", angles(6))
    assert(angles(8) == "0,45,90,135,180,225,270,315", angles(8))
end

-- 2. Pages: as few as possible, filled evenly.
do
    local function pages(n)
        local t = {}
        for _, p in ipairs(W.paginate(n)) do t[#t + 1] = p.first .. "-" .. p.last end
        return table.concat(t, " ")
    end
    assert(pages(3) == "1-3", pages(3))
    assert(pages(8) == "1-8", pages(8))
    assert(pages(9) == "1-5 6-9", pages(9))
    assert(pages(16) == "1-8 9-16", pages(16))
end

-- 3. Stick directions (SDL: x- = left, y- = up) and the nearest slot.
do
    assert(W.dir_from_axes(nil, nil) == nil)
    assert(W.dir_from_axes(nil, "minus") == 0, "up")
    assert(W.dir_from_axes("plus", "minus") == 1, "up-right")
    assert(W.dir_from_axes("plus", nil) == 2, "right")
    assert(W.dir_from_axes("plus", "plus") == 3, "down-right")
    assert(W.dir_from_axes(nil, "plus") == 4, "down")
    assert(W.dir_from_axes("minus", "plus") == 5, "down-left")
    assert(W.dir_from_axes("minus", nil) == 6, "left")
    assert(W.dir_from_axes("minus", "minus") == 7, "up-left")
    local function cands(n)
        local t = {}
        for i = 1, n do t[i] = { idx = i, angle = W.angle_of(i, n) } end
        return t
    end
    local two = cands(2)
    assert(W.nearest(two, 0) == 1 and W.nearest(two, 45) == 1 and W.nearest(two, 135) == 2)
    assert(W.nearest(two, 90) == 2, "tie -> clockwise")
    assert(W.nearest(two, 270) == 1, "tie -> clockwise, wrapping")
    local six = cands(6)
    assert(W.nearest(six, 90) == 3, "6 sectors, right: 60 / 120 tie -> 120")
    assert(W.nearest(six, 45) == 2 and W.nearest(six, 315) == 6 and W.nearest(six, 225) == 5)
    assert(W.nearest({}, 3) == nil)
end

-- 4. Glyphs: known actions by exact label or by word, else the first letter.
do
    assert(W.glyph_for("Copy") == "\u{F0C5}")
    assert(W.glyph_for("Edit note") == "\u{F249}", "note before edit")
    assert(W.glyph_for("Edit") == "\u{F044}")
    assert(W.glyph_for("Book information\xE2\x80\xA6") == "\u{F05A}", "trailing ellipsis")
    assert(W.glyph_for("\xE2\x9C\x93 Favorites") == "\u{F005}", "check mark in front")
    assert(W.glyph_for("Add to favorites") == "\u{F005}", "word inside the label")
    assert(W.glyph_for("Bookshelf") == "B", "'ok' does not match inside a word")
    assert(W.glyph_for("zebra") == "Z")
    assert(W.glyph_for("\xC4\x85bc") == "\xC4\x85", "first UTF-8 character")
    assert(W.glyph_for(nil) == "?")
    assert(W.glyph_for("\xE2\x80\xA6") == "\u{F141}", "a lone ellipsis = more")
    assert(#W.items_from_buttons({ { { text = "\xE2\x80\xA6" }, { text = " " } } }) == 1, "'…' is a button, blank is not")
end

-- 4b. Title from a text: quoted, whitespace collapsed, cut with an ellipsis.
do
    assert(W.snippet_title("  Litwo!\n Ojczyzno  moja ") == "\u{201C}Litwo! Ojczyzno moja\u{201D}")
    assert(W.snippet_title("abcdef ghij", 7) == "\u{201C}abcdef\u{2026}\u{201D}", "cut, no space before the ellipsis")
    assert(W.snippet_title("\xC4\x85\xC4\x85\xC4\x85", 2) == "\u{201C}\xC4\x85\xC4\x85\u{2026}\u{201D}", "UTF-8 safe")
    assert(W.snippet_title("  ") == nil and W.snippet_title(nil) == nil)
end

-- 5. Items from ButtonDialog rows: text_func, enabled / enabled_func,
-- checked_func; entries without a text are left out.
local function buttons(log)
    local function b(t, extra)
        local e = { text = t, callback = function() log[#log + 1] = t end }
        for k, v in pairs(extra or {}) do e[k] = v end
        return e
    end
    return {
        { b("Dictionary"), b("Copy") },
        { b("Highlight", { enabled = false }), {} , b("Note", { hold_callback = function() log[#log + 1] = "hold" end }) },
        { { text_func = function() return "AI explain" end, callback = function() log[#log + 1] = "ai" end },
          b("Vortuyo", { checked_func = function() return true end }) },
    }
end
do
    local items = W.items_from_buttons(buttons({}))
    assert(#items == 6, #items)
    assert(items[1].label == "Dictionary" and items[1].glyph == "\u{F02D}")
    assert(items[3].label == "Highlight" and items[3].enabled == false)
    assert(items[5].label == "AI explain" and items[5].glyph == "\u{F0D0}")
    assert(items[6].checked == true and items[1].checked == false)
    assert(#W.items_from_buttons(nil) == 0)
end

-- 6. Controller: selection, rotation over disabled slots, pages, actions.
do
    local log, closed = {}, 0
    local dlg = { onClose = function() closed = closed + 1 end }
    dlg.buttons = buttons(log)
    local c = W.new_ctl(dlg, W.items_from_buttons(dlg.buttons))
    assert(c.sel == 1 and #c.pages == 1)
    -- 6 items -> 0, 60, 120, ... degrees; item 3 (120) is disabled
    assert(c:point(2) == true and c.sel == 2, "right (90) -> item 2 (60), item 3 disabled")
    assert(c:point(3) == true and c.sel == 4, "down-right (135) -> item 4 (180), item 3 disabled")
    c:point(7); assert(c.sel == 6)
    c:rotate(1); assert(c.sel == 1, "wraps clockwise")
    c:rotate(1); c:rotate(1); assert(c.sel == 4, "skips the disabled item")
    c:rotate(-1); assert(c.sel == 2)
    assert(c:page_step(1) == false, "one page")
    assert(c:activate(false) == true and log[1] == "Copy")
    assert(c:activate(true) == false, "no hold callback on Copy")
    c:select(4)
    assert(c:activate(true) == true and log[2] == "hold")
    assert(c:close() == true and closed == 1)
    dlg.dismissable = false
    assert(c:close() == false and closed == 1, "not dismissable")
    -- selection kept over a reinit
    local c2 = W.new_ctl(dlg, W.items_from_buttons(dlg.buttons), { sel = 5 })
    assert(c2.sel == 5)
    c2 = W.new_ctl(dlg, W.items_from_buttons(dlg.buttons), { sel = 3 })
    assert(c2.sel == 1, "a disabled previous selection is not kept")
end

-- 7. Pages: 12 buttons = 6 + 6, LB / RB wrap and select the page's first.
do
    local row = {}
    for i = 1, 12 do row[i] = { text = "Item " .. i, callback = function() end } end
    local c = W.new_ctl({}, W.items_from_buttons({ row }))
    assert(#c.pages == 2 and c.pages[2].first == 7)
    assert(c:page_step(1) and c.page == 2 and c.sel == 7)
    c:point(4); assert(c.sel == 10, "down on page 2")
    assert(c:page_step(1) and c.page == 1 and c.sel == 1, "wraps")
    c:page_step(-1); assert(c.page == 2)
end

-- 8. Stick polling: a direction counts once it is stable for STABLE_S; the
-- snap back of a diagonal (one axis first) does not move the selection; a
-- centred stick keeps it.
do
    local row = {}
    for i = 1, 8 do row[i] = { text = "Item " .. i, callback = function() end } end
    local c = W.new_ctl({}, W.items_from_buttons({ row }))
    local function at(t, hx, hy)
        clock = t
        held[0], held[1] = hx, hy
        c:_sample()
    end
    clock = 10
    held[0], held[1] = "plus", "minus" -- up-right
    c:stick("left")
    assert(c.sel == 1, "first sample: not stable yet")
    at(10.03, "plus", "minus"); assert(c.sel == 1)
    at(10.06, "plus", "minus"); assert(c.sel == 2, "stable up-right -> slot 1")
    -- release: X centres first, Y 20 ms later
    at(10.09, nil, "minus"); assert(c.sel == 2)
    at(10.11, nil, nil); assert(c.sel == 2, "snap back ignored, selection kept")
    assert(c._cand == nil)
    -- the right stick reads axes 2 / 3
    held[2], held[3] = "minus", nil
    clock = 20
    c:stick("right")
    at(20.06, nil, nil) -- left stick axes are not read any more
    assert(c.sel == 7, "right stick left -> slot 6")
end

-- 9. Touch: hub = next page, a sector = run it (not when disabled), the disc
-- and the pills = nothing, the page around = close.
do
    local log, closed = {}, 0
    local dlg = { onClose = function() closed = closed + 1 end }
    dlg.buttons = buttons(log)
    local c = W.new_ctl(dlg, W.items_from_buttons(dlg.buttons))
    c.widget = { cx = 500, cy = 500, r0 = 50, R_out = 110, disc_r = 120,
                 in_pill = function(_, x, y) return y > 700 and y < 740 end }
    assert(c:tap(500, 400) and log[1] == "Dictionary", "top sector")
    assert(c:tap(500 + 80, 500 - 46) and log[2] == "Copy", "60 degrees")
    c:tap(500 + 80, 500 + 46); assert(#log == 2, "120 degrees: Highlight is disabled")
    c:tap(500, 615); assert(closed == 0, "on the disc, outside the ring")
    c:tap(500, 720); assert(closed == 0, "on a pill")
    c:tap(500, 900); assert(closed == 1, "the page: close")
end

print("wheel_test: all tests passed")
