--[[
focushand -- the hand (☞) on the menu item the pad has focused. kopad's own,
independent of keyreader's menupage (which paints one as well, in its own
shortcut box).

Why it needs no layout of its own: KOReader already reserves a square on every
item of a Menu / file browser for a keyboard-shortcut letter
(`menu:getItemShortCutIcon`: a slot in MenuItem, a corner over the cover in
the list and mosaic views), and TouchMenuItem (the top menu) reserves a slot
for the check mark. The hand goes into those:

  * Menu, BookList (file browser, history, collections), ListMenu, MosaicMenu:
    the icon the factory returns gets its `paintTo` replaced. On the focused
    item it paints a white square with the hand over the slot; on the others
    it paints what it painted (the letter), or nothing when `hidden`
    (keyhints.lua: no Q W E R T Y over the covers while kopad is on).
  * TouchMenuItem: the class `paintTo` is wrapped (once, found the first time
    such an item is focused) and paints the hand over the check mark slot.

The focused item is learned from FocusManager: `onFocusMove` and `moveFocusTo`
are the only two places that send Focus / Unfocus (verified in KOReader
2026.07.1). The icon does not know its item, so it asks "is the icon being
painted inside the focused item's rectangle" (items do not overlap, and
InputContainer:paintTo sets `dimen.x/y` before it paints the children). An
item counts as focused while its `_underline_container.color` is black --
what Focus sets in all four item classes -- so a stale reference to a menu
that was closed never paints anything.

RTL UI: ☜ instead of ☞. The pure half (geometry, hit test, wrapping) is
tested by tests/focushand_test.lua; KOReader modules are required lazily.
Everything on the paint path is pcall-guarded: a failure only warns once.
]]

local M = {}

M.HAND     = "\u{261E}" -- ☞
M.HAND_RTL = "\u{261C}" -- ☜

-- Replaced by every kopad instance (the patches below are installed once per run).
local state_fn = function() return false end
-- Weak: a closed menu must not be kept alive by us.
local focus = setmetatable({}, { __mode = "v" })
local patched_classes = setmetatable({}, { __mode = "k" })
local warned = false

local function warn(msg)
    if warned then return end
    warned = true
    local ok, logger = pcall(require, "logger")
    if ok then logger.warn("kopad focushand: " .. tostring(msg)) end
end

function M.active()
    local ok, v = pcall(state_fn)
    return ok and v and true or false
end

-- ---------------------------------------------------------------------------
-- Pure part
-- ---------------------------------------------------------------------------

function M.contains(d, x, y)
    return type(d) == "table" and type(d.x) == "number" and type(d.y) == "number"
        and type(d.w) == "number" and type(d.h) == "number"
        and x >= d.x and x < d.x + d.w and y >= d.y and y < d.y + d.h
end

-- NOTE: Blitbuffer colors are cdata with an __eq that indexes both operands:
-- `color == nil` / `color ~= nil` raises. Compare colors only with each other,
-- test presence by truthiness and use rawequal against nil.
local function black()
    if rawequal(M._black, nil) then
        local ok, Blitbuffer = pcall(require, "ffi/blitbuffer")
        M._black = ok and Blitbuffer.COLOR_BLACK or false
    end
    return M._black
end

-- Stock Focus sets the underline black in MenuItem, TouchMenuItem, ListMenuItem
-- and MosaicMenuItem, Unfocus sets it back.
function M.is_focused(item)
    local u = type(item) == "table" and item._underline_container
    if not u then return false end
    local color, b = u.color, black()
    if not color or not b then return false end
    return color == b
end

-- Is the point (x, y) inside the focused item?
function M.focus_hits(x, y)
    local item = focus.item
    return M.is_focused(item) and M.contains(item.dimen, x, y) or false
end

-- The same, on the paint path: whatever goes wrong here must never take the
-- paint loop down (it once did: the cdata __eq above).
local function hits_safe(x, y)
    local ok, hit = pcall(M.focus_hits, x, y)
    if not ok then warn(hit) return false end
    return hit
end

-- The check mark slot of a TouchMenuItem painted at (x, y): its left edge,
-- `pad` (Size.padding.default) in, as wide as the check mark, 70 % of the
-- row high, centred.
function M.touch_slot(item, x, y, pad)
    local h = math.floor(item.dimen.h * 0.7)
    return {
        x = x + pad,
        y = y + math.floor((item.dimen.h - h) / 2),
        w = item.checkmark_tap_width - 2 * pad,
        h = h,
    }
end

-- Put the hand on a shortcut icon. Idempotent: wrapping an icon again only
-- adds the `hidden` flag. `orig` is whatever painted the icon.
function M.wrap_icon(icon, hidden)
    if type(icon) ~= "table" then return icon end
    if hidden then icon._kopad_hidden = true end
    if icon._kopad_hand then return icon end
    icon._kopad_hand = true
    local orig = icon.paintTo
    icon.paintTo = function(self, bb, x, y)
        if M.active() then
            if hits_safe(x, y) then
                local d = self.dimen
                if d and d.w and d.h then
                    M.paint_safe(bb, x, y, d.w, d.h)
                    return
                end
            elseif self._kopad_hidden then
                return
            end
        end
        return orig(self, bb, x, y)
    end
    return icon
end

-- A getItemShortCutIcon replacement. `parent` is asked on every call for the
-- factory to delegate to (so a menupage installed later is not bypassed).
function M.wrap_factory(parent, hidden)
    return function(menu, dimen, key, style)
        local f = parent()
        return M.wrap_icon(f(menu, dimen, key, style), hidden)
    end
end

-- ---------------------------------------------------------------------------
-- Painting (KOReader)
-- ---------------------------------------------------------------------------

local cache = {}

-- Overridable in tests.
function M.paint(bb, x, y, w, h)
    local Blitbuffer = require("ffi/blitbuffer")
    local Font       = require("ui/font")
    local TextWidget = require("ui/widget/textwidget")
    local BD         = require("ui/bidi")
    local Screen     = require("device").screen

    bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)

    local ch = BD.mirroredUILayout() and M.HAND_RTL or M.HAND
    -- Font:getFace takes unscaled sizes
    local scale = Screen:scaleBySize(1000000) / 1000000
    local size = math.max(8, math.floor(math.min(w, h) * 0.8 / scale))
    local key = ch .. size
    local tw = cache[key]
    if not tw then
        tw = TextWidget:new{ text = ch, face = Font:getFace("NotoSans-Regular", size) }
        cache[key] = tw
    end
    local sz = tw:getSize()
    tw:paintTo(bb, x + math.floor((w - sz.w) / 2), y + math.floor((h - sz.h) / 2))
end

function M.paint_safe(bb, x, y, w, h)
    local ok, err = pcall(M.paint, bb, x, y, w, h)
    if not ok then warn(err) end
end

-- ---------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------

-- TouchMenuItem is local to touchmenu.lua: reached through an instance.
function M.patch_touch_class(item)
    local mt = getmetatable(item)
    local cls = mt and mt.__index
    if type(cls) ~= "table" or patched_classes[cls] or type(cls.paintTo) ~= "function" then
        return
    end
    patched_classes[cls] = true
    local orig = cls.paintTo
    rawset(cls, "paintTo", function(self, bb, x, y)
        orig(self, bb, x, y)
        if M.active() and self.checkmark_tap_width and self.dimen then
            local ok, err = pcall(function()
                if not M.is_focused(self) then return end
                local Size = require("ui/size")
                local s = M.touch_slot(self, x, y, Size.padding.default)
                M.paint(bb, s.x, s.y, s.w, s.h)
            end)
            if not ok then warn(err) end
        end
    end)
end

-- Called after every focus move of a FocusManager (Menu, TouchMenu, ...).
function M.note_focus(fm)
    local item = fm.getFocusItem and fm:getFocusItem()
    if type(item) ~= "table" or not item._underline_container then return end
    focus.item = item
    if item.item_frame and item.checkmark_tap_width then
        M.patch_touch_class(item)
    end
end

local function after(orig)
    return function(self, ...)
        local r = orig(self, ...)
        local ok, err = pcall(M.note_focus, self)
        if not ok then warn(err) end
        return r
    end
end

-- Once per run; `fn` is replaced by every kopad instance. Returns true when the
-- hooks are in place.
function M.install(fn)
    state_fn = fn or state_fn
    if M.installed then return true end

    local FocusManager = require("ui/widget/focusmanager")
    FocusManager.onFocusMove = after(FocusManager.onFocusMove)
    FocusManager.moveFocusTo = after(FocusManager.moveFocusTo)

    -- Every Menu, so the hand also shows in the TOC, history and so on. A
    -- menupage installed after this replaces the factory and paints its own.
    local Menu = require("ui/widget/menu")
    if type(Menu.getItemShortCutIcon) == "function" and not rawget(Menu, "_kopad_hand") then
        local orig = Menu.getItemShortCutIcon
        rawset(Menu, "getItemShortCutIcon", M.wrap_factory(function() return orig end, false))
        rawset(Menu, "_kopad_hand", true)
    end

    M.installed = true
    return true
end

return M
