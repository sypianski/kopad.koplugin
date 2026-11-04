-- focushand.lua: the hand on the focused menu item. KOReader stubbed.
package.path = "./?.lua;" .. package.path

local BLACK, WHITE = {}, {}
local function fresh()
    package.loaded["focushand"] = nil
    local FH = require("focushand")
    FH._black = BLACK
    local painted = {}
    FH.paint = function(bb, x, y, w, h) painted[#painted + 1] = { x = x, y = y, w = w, h = h } end
    return FH, painted
end

local function item(x, y, w, h, color)
    return { dimen = { x = x, y = y, w = w, h = h }, _underline_container = { color = color } }
end

-- 1. geometry and focus test
do
    local FH = fresh()
    assert(FH.contains({ x = 10, y = 10, w = 5, h = 5 }, 10, 10))
    assert(FH.contains({ x = 10, y = 10, w = 5, h = 5 }, 14, 14))
    assert(not FH.contains({ x = 10, y = 10, w = 5, h = 5 }, 15, 10))
    assert(not FH.contains(nil, 1, 1))
    assert(FH.is_focused(item(0, 0, 1, 1, BLACK)))
    assert(not FH.is_focused(item(0, 0, 1, 1, WHITE)))
    assert(not FH.is_focused(nil))
    assert(not FH.is_focused({}))
    local s = FH.touch_slot({ dimen = { h = 100 }, checkmark_tap_width = 40 }, 7, 200, 4)
    assert(s.x == 11 and s.w == 32 and s.h == 70 and s.y == 215, "slot " .. s.x .. " " .. s.y)
end

-- 2. an icon: hand on the focused item, letter (or nothing) elsewhere
do
    local FH, painted = fresh()
    local active = true
    local focused = item(0, 100, 200, 50, BLACK)
    local fm = { getFocusItem = function() return focused end }
    FH.note_focus(fm)

    local calls = {}
    local function new_icon()
        return { dimen = { w = 20, h = 20 }, paintTo = function(_, _, x, y) calls[#calls + 1] = { x, y } end }
    end
    -- install() takes the state function (kopad enabled)
    local Menu = { getItemShortCutIcon = function() return new_icon() end }
    package.loaded["ui/widget/menu"] = Menu
    package.loaded["ui/widget/focusmanager"] = { onFocusMove = function() return true end,
                                                  moveFocusTo = function() return true end }
    FH.install(function() return active end)

    local icon = FH.wrap_icon(new_icon())
    icon:paintTo(nil, 5, 110)           -- inside the focused item -> hand
    assert(#painted == 1 and #calls == 0 and painted[1].w == 20)
    icon:paintTo(nil, 5, 10)            -- another item -> its letter
    assert(#painted == 1 and #calls == 1)

    local hidden = FH.wrap_icon(new_icon(), true)
    hidden:paintTo(nil, 5, 10)          -- hidden, not focused -> nothing
    assert(#calls == 1)
    hidden:paintTo(nil, 5, 110)         -- hidden, focused -> hand
    assert(#painted == 2)

    -- wrapping again keeps one wrapper and only adds the flag
    local again = new_icon()
    local orig = again.paintTo
    FH.wrap_icon(again)
    local first = again.paintTo
    FH.wrap_icon(again, true)
    assert(again.paintTo == first and first ~= orig and again._kopad_hidden)

    -- kopad off: stock, even for a hidden icon
    active = false
    hidden:paintTo(nil, 5, 10)
    hidden:paintTo(nil, 5, 110)
    assert(#painted == 2 and #calls == 3)
    active = true

    -- a menu closed (item unfocused): no hand
    focused._underline_container.color = WHITE
    icon:paintTo(nil, 5, 110)
    assert(#painted == 2 and #calls == 4)

    -- the Menu factory installed by install() returns wrapped icons
    local ic = Menu.getItemShortCutIcon({}, nil, "A", "square")
    assert(ic._kopad_hand)
    focused._underline_container.color = BLACK
    ic:paintTo(nil, 1, 120)
    assert(#painted == 3)

    -- wrap_factory: hidden flag, delegates to the current parent
    local fac = FH.wrap_factory(function() return Menu.getItemShortCutIcon end, true)
    local hic = fac({}, nil, "B", "square")
    assert(hic._kopad_hidden and hic._kopad_hand)
    hic:paintTo(nil, 1, 10)
    assert(#calls == 4, "hidden letter not painted")
end

-- 3. install hooks FocusManager: a focus move is noticed, the TouchMenuItem class patched once
do
    local FH, painted = fresh()
    local FM = {}
    function FM.onFocusMove(self) self.moved = true; return true end
    function FM.moveFocusTo(self) self.moved_to = true; return "r1", "r2" end
    package.loaded["ui/widget/focusmanager"] = FM
    package.loaded["ui/widget/menu"] = { getItemShortCutIcon = function() return {} end }
    package.loaded["ui/size"] = { padding = { default = 2 } }
    assert(FH.install(function() return true end))
    assert(FH.install(function() return true end), "second install is a no-op")

    local base_calls = 0
    local Cls = {}
    Cls.__index = Cls
    function Cls.paintTo() base_calls = base_calls + 1 end
    local it = setmetatable({
        dimen = { x = 0, y = 0, w = 300, h = 60 }, _underline_container = { color = BLACK },
        item_frame = {}, checkmark_tap_width = 30,
    }, Cls)
    local fm = setmetatable({ getFocusItem = function() return it end }, { __index = FM })

    assert(fm:onFocusMove({ 0, 1 }) == true and fm.moved)
    assert(fm:moveFocusTo(1, 1) == "r1" and fm.moved_to, "result passes through")
    assert(rawget(Cls, "paintTo") ~= nil)
    local patched = Cls.paintTo
    fm:moveFocusTo(1, 2)
    assert(Cls.paintTo == patched, "class patched once")

    it:paintTo(nil, 10, 20)             -- focused: base paint + hand in the check slot
    assert(base_calls == 1 and #painted == 1)
    assert(painted[1].x == 12 and painted[1].w == 26 and painted[1].h == 42)
    it._underline_container.color = WHITE
    it:paintTo(nil, 10, 20)
    assert(base_calls == 2 and #painted == 1)
end

-- 4. regression (0.1.22 crashed KOReader at the first repaint): colors can be nil/false,
-- and nothing raised while deciding may escape the paint path
do
    local FH, painted = fresh()
    assert(FH.is_focused({ _underline_container = {} }) == false, "no color")
    assert(FH.is_focused({ _underline_container = { color = false } }) == false)
    FH._black = false
    assert(FH.is_focused(item(0, 0, 1, 1, BLACK)) == false, "no black available")
    FH._black = BLACK

    package.loaded["ui/widget/menu"] = { getItemShortCutIcon = function() return {} end }
    package.loaded["ui/widget/focusmanager"] = { onFocusMove = function() end, moveFocusTo = function() end }
    FH.install(function() return true end)
    local bad = setmetatable({ _underline_container = { color = BLACK } },
        { __index = function(_, k) if k == "dimen" then error("boom") end end })
    FH.note_focus({ getFocusItem = function() return bad end })
    local calls = 0
    local icon = FH.wrap_icon({ dimen = { w = 5, h = 5 }, paintTo = function() calls = calls + 1 end })
    icon:paintTo(nil, 1, 1)
    assert(calls == 1 and #painted == 0, "falls back to the stock icon")
end

print("focushand_test: OK")
