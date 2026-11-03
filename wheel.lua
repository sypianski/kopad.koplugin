--[[
Wheel -- a ButtonDialog drawn as a radial menu (TASK-19).

While kopad is enabled (and "Dialogs as a wheel" is on: device setting
`wheel_dialogs`, default on), every plain ButtonDialog -- the centred grid of
buttons in two columns: kopad's own action menu, a highlight's menu, a file's
long-press menu, ... -- is shown as a wheel instead, cut into as many
sectors as there are buttons (at most 8 a page). Each button becomes a
monochrome glyph (Nerd Font symbols, a fallback font of stock KOReader) in its
sector; the selected sector is black and pops out of the rim, its label is
printed in the hub. No frame (TASK-20): a white disc over the page, the title
-- or the text the dialog is about -- in a pill above, the buttons in a pill
below. The dialog object stays the same ButtonDialog: only its content
(self[1]) and self.movable are replaced after the stock init, so button
callbacks that UIManager:close(dlg) or dlg:reinit() keep working.

Pad (routed by padnav.lua, context "wheel"):
  L-stick / R-stick     point at a sector (8 directions, the nearest sector;
                        a tie goes clockwise)
  D-pad ← ↑ / → ↓       previous / next sector
  LB / RB, LT / RT      previous / next page (more than 8 buttons)
  A                     run the selected button    X   its long-press action
  B                     close (as stock Back; not when the dialog is not
                        dismissable)
Touch: tap a sector = run it, tap the hub = next page, tap the page around
the disc and the pills = close.
Keys (keyboard): arrows = previous / next sector, Press / Hold = A / X.

Why 8 directions and not the analog angle: KOReader >= 2026.07 broadcasts a
stick axis only when it crosses the dead zone (frontend/device/sdl/
gamepad.lua), with no value afterwards and no release. The held direction of
every axis is kept in Gamepad.held_axis_directions, updated on every SDL
motion event, so the wheel polls it (POLL_S) while a stick is pushed and
combines X and Y into one of 8 directions. A direction counts once it has been
stable for STABLE_S: when a diagonal stick snaps back its two axes cross the
dead zone at slightly different times, and that brief straight direction must
not move the selection. A released stick keeps the selection.

kopad's quick-action wheel (padnav.lua, TASK-26) is a ButtonDialog too: it is
always a wheel (`_kopad_force_wheel`, even with "Dialogs as a wheel" off),
opens aimed at the R-stick's direction (`_kopad_stick`, Ctl:aim) and gives
each button `kopad_glyph` and `kopad_hint` (a line under the label in the hub).

Not converted (stay stock): subclasses of ButtonDialog, dialogs with added
widgets (check boxes, inputs: addWidget), fewer than 2 or more than MAX_ITEMS
buttons, and builds without device/sdl/gamepad.lua (no Gamepad* events).

The top part (sectors, pages, directions, titles, glyphs, items) is pure Lua and tested
in tests/wheel_test.lua; KOReader modules are required lazily below it.
]]

local _ = require("gettext")

local M = {}

M.SLOTS = 8        -- most sectors on one page (8 stick directions)
M.MAX_ITEMS = 16
M.POLL_S = 0.03
M.STABLE_S = 0.05

-- Centre angle (degrees, 0 = up, clockwise) of item i (1-based) on a page of
-- n items: the wheel is cut into n equal sectors, the first one at the top
-- (TASK-20: only the buttons there are, no empty slots).
function M.angle_of(i, n)
    return (i - 1) * 360 / n
end

-- n items -> pages { {first=, last=}, ... }: as few pages as possible, filled
-- evenly (9 items = 5 + 4, not 8 + 1).
function M.paginate(n)
    local count = math.max(1, math.ceil(n / M.SLOTS))
    local per = math.ceil(n / count)
    local pages, first = {}, 1
    for p = 1, count do
        local last = math.min(n, first + per - 1)
        pages[p] = { first = first, last = last }
        first = last + 1
    end
    return pages
end

-- Held direction of the two axes of a stick ("minus" / "plus" / nil, as in
-- Gamepad.held_axis_directions; SDL: x- = left, y- = up) -> direction 0..7
-- (0 = up, clockwise, 45 degrees each), or nil when the stick is centred.
local DIR_OF = {
    ["0,-1"] = 0, ["1,-1"] = 1, ["1,0"] = 2, ["1,1"] = 3,
    ["0,1"] = 4, ["-1,1"] = 5, ["-1,0"] = 6, ["-1,-1"] = 7,
}
local function sign(h) return h == "minus" and -1 or (h == "plus" and 1 or 0) end
function M.dir_from_axes(hx, hy)
    return DIR_OF[sign(hx) .. "," .. sign(hy)]
end

-- Of `cands` ({ {idx=, angle=}, ... }) the idx whose angle is nearest to
-- angle `a`; on a tie the clockwise one (6 sectors and the stick right: 90
-- degrees lies between 60 and 120 -> 120).
function M.nearest(cands, a)
    local best, best_d, best_cw
    for _i, c in ipairs(cands) do
        local d = (c.angle - a) % 360
        local cw = d <= 180
        local dist = cw and d or 360 - d
        if best == nil or dist < best_d - 1e-6
                or (math.abs(dist - best_d) < 1e-6 and cw and not best_cw) then
            best, best_d, best_cw = c.idx, dist, cw
        end
    end
    return best
end

-- Title for a dialog about a piece of text (kopad's action menu, KOReader's
-- highlight menus): the text in quotes, whitespace collapsed, cut at about
-- `max` characters (default 120).
local function utf8_cut(s, n)
    local count, i = 0, 1
    while i <= #s do
        count = count + 1
        if count > n then return s:sub(1, i - 1), true end
        local b = s:byte(i)
        i = i + (b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1)
    end
    return s, false
end
function M.snippet_title(text, max)
    if type(text) ~= "string" then return nil end
    local s = text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if s == "" then return nil end
    local cut, more = utf8_cut(s, max or 120)
    if more then cut = cut:gsub(" ?$", "") .. "\xE2\x80\xA6" end
    return "\xE2\x80\x9C" .. cut .. "\xE2\x80\x9D"
end

-- Glyphs (Nerd Font / Font Awesome 4 code points, all present in KOReader's
-- fonts/nerdfonts/symbols.ttf) and the button labels they stand for. Labels
-- are KOReader msgids: the exact translated label matches first, then the
-- English words anywhere in the label. Order matters ("Edit note" = note).
local GLYPHS = {
    { "\u{F249}", "Note", "Add note", "Edit note", "Notes" },             -- sticky note
    { "\u{F02D}", "Dictionary", "Lookup", "Dictionary lookup" },          -- book
    { "\u{F266}", "Wikipedia" },
    { "\u{F1AB}", "Translate", "Translation" },                           -- language
    { "\u{F19D}", "Vortuyo", "Vocabulary", "Vocabulary builder" },        -- graduation cap
    { "\u{F0D0}", "AI explain", "AI", "Explain", "Assistant", "Ask" },     -- magic wand
    { "\u{F0C5}", "Copy" },
    { "\u{F0EA}", "Paste" },
    { "\u{F0C4}", "Cut" },
    { "\u{F1FC}", "Highlight", "Style", "Color", "Colour" },              -- brush
    { "\u{F07E}", "Extend" },                                             -- arrows ←→
    { "\u{F245}", "Select" },                                             -- pointer
    { "\u{F246}", "Rename" },                                             -- text cursor
    { "\u{F014}", "Delete", "Remove", "Purge" },                          -- trash
    { "\u{F002}", "Search", "Find", "Fulltext search" },
    { "\u{F1E0}", "Share", "Share text", "Send" },
    { "\u{F0C1}", "Follow link", "Link" },
    { "\u{F121}", "View HTML", "HTML" },
    { "\u{F05A}", "Book information", "Information", "Info", "Details", "Properties" },
    { "\u{F03E}", "Book cover", "Cover", "Image" },
    { "\u{F005}", "Favorites", "Favourites", "Favorite" },
    { "\u{F02C}", "Collections", "Collection", "Tags", "Tag" },
    { "\u{F02E}", "Bookmark", "Bookmarks" },
    { "\u{F0EC}", "Convert", "Move" },
    { "\u{F07C}", "Open", "Open with", "Folder" },
    { "\u{F0C7}", "Save", "Export" },
    { "\u{F0E2}", "Reset", "Undo", "Revert" },
    { "\u{F021}", "Refresh", "Reload", "Update" },
    { "\u{F013}", "Settings", "Configure", "Options" },
    { "\u{F044}", "Edit" },
    { "\u{F00C}", "OK", "Done", "Mark as read", "Finished", "Apply", "Yes" },
    { "\u{F00D}", "Cancel", "Close", "Dismiss", "No" },
    { "\u{F061}", "Go to", "Go", "Jump" },
    { "\u{F141}", "More" },                                               -- ellipsis
}
local MORE = "\u{F141}"

local ELLIPSIS = "\xE2\x80\xA6"
local CHECK = "\xE2\x9C\x93"

-- Label as compared: no check mark in front, no "…" / "..." / ":" at the end.
local function norm(s)
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("^" .. CHECK .. "%s*", "")
    s = s:gsub(ELLIPSIS .. "$", ""):gsub("%.%.%.$", ""):gsub("[:%s]+$", "")
    return s
end

local exact -- translated label -> glyph, built on first use (gettext ready)
local function exact_map()
    if exact then return exact end
    exact = {}
    for _i, g in ipairs(GLYPHS) do
        for k = 2, #g do
            local tr = norm(_(g[k]))
            if exact[tr] == nil then exact[tr] = g[1] end
            local en = g[k]:lower()
            if exact[en] == nil then exact[en] = g[1] end
        end
    end
    return exact
end

-- Glyph for a button label: a known action, else the label's first letter.
function M.glyph_for(label)
    if type(label) ~= "string" then return "?" end
    local s = norm(label)
    -- "…" alone (the highlight menu's "more" button) is nothing after norm
    if s == "" then return label:find(ELLIPSIS, 1, true) and MORE or "?" end
    local map = exact_map()
    local g = map[s] or map[s:lower()]
    if g then return g end
    local low = " " .. s:lower() .. " "
    for _i, e in ipairs(GLYPHS) do
        for k = 2, #e do
            local word = e[k]:lower():gsub("%p", "%%%0")
            if low:find("%f[%w]" .. word .. "%f[%W]") then return e[1] end
        end
    end
    local first = s:match("^[%z\1-\127\194-\244][\128-\191]*")
    return first and first:upper() or "?"
end

local function call(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

-- ButtonDialog `buttons` (rows of button entries) -> wheel items in reading
-- order: { label, glyph, hint, enabled, checked, entry }. Entries without a
-- text (separators, icon-only buttons) are left out. kopad's own dialogs may
-- give an entry `kopad_glyph` (instead of the guess from the label) and
-- `kopad_hint` (a short line under the label in the hub, e.g. "X + LB").
function M.items_from_buttons(buttons)
    local items = {}
    if type(buttons) ~= "table" then return items end
    for _r, row in ipairs(buttons) do
        if type(row) == "table" then
            for _c, e in ipairs(row) do
                if type(e) == "table" then
                    local text = e.text
                    if text == nil and type(e.text_func) == "function" then text = call(e.text_func) end
                    if type(text) == "string" and text:match("%S") then
                        local enabled = e.enabled ~= false
                        if enabled and type(e.enabled_func) == "function" then
                            enabled = call(e.enabled_func) ~= false
                        end
                        local checked = type(e.checked_func) == "function" and call(e.checked_func) == true
                        local glyph = e.kopad_glyph
                        if type(glyph) ~= "string" or glyph == "" then glyph = M.glyph_for(text) end
                        local hint = type(e.kopad_hint) == "string" and e.kopad_hint ~= "" and e.kopad_hint or nil
                        items[#items + 1] = {
                            label = text, glyph = glyph, hint = hint,
                            enabled = enabled, checked = checked, entry = e,
                        }
                    end
                end
            end
        end
    end
    return items
end

----------------------------------------------------------------------
-- KOReader side (lazy requires)
----------------------------------------------------------------------

local UIManager, Blitbuffer, Font, Geom, Size, Screen, TextWidget, TextBoxWidget
local logger = { warn = function() end }

local function load_ui()
    if UIManager then return end
    UIManager     = require("ui/uimanager")
    Blitbuffer    = require("ffi/blitbuffer")
    Font          = require("ui/font")
    Geom          = require("ui/geometry")
    Size          = require("ui/size")
    Screen        = require("device").screen
    TextWidget    = require("ui/widget/textwidget")
    TextBoxWidget = require("ui/widget/textboxwidget")
    logger        = require("logger")
end

local function now_s()
    local time = require("ui/time")
    return time.to_s(time.now())
end

local function gamepad()
    local ok, G = pcall(require, "device/sdl/gamepad")
    return ok and type(G) == "table" and G or nil
end

local STICK_AXES = { left = { 0, 1 }, right = { 2, 3 } }

local atan2 = math.atan2 or math.atan

----------------------------------------------------------------------
-- Controller: selection, pages, actions. One per converted dialog
-- (dlg._kopad_wheel).
----------------------------------------------------------------------

local Ctl = {}
Ctl.__index = Ctl
M.Ctl = Ctl

function M.new_ctl(dlg, items, prev)
    local c = setmetatable({ dlg = dlg, items = items, pages = M.paginate(#items), page = 1 }, Ctl)
    c._poll_fn = function() c:_sample() end
    if prev and prev.sel and items[prev.sel] and items[prev.sel].enabled then
        c.sel = prev.sel
        c.page = c:_page_of(prev.sel)
    else
        c.sel = c:_first_enabled(1)
    end
    return c
end

function Ctl:_page_of(idx)
    for p, pg in ipairs(self.pages) do
        if idx >= pg.first and idx <= pg.last then return p end
    end
    return 1
end

function Ctl:_first_enabled(page)
    local pg = self.pages[page]
    for i = pg.first, pg.last do
        if self.items[i].enabled then return i end
    end
    return nil
end

-- Items of the current page as { {idx=, angle=}, ... } (`enabled_only`:
-- the selectable ones) and the page's item count.
function Ctl:page_items(enabled_only)
    local pg = self.pages[self.page]
    local n, list = pg.last - pg.first + 1, {}
    for i = pg.first, pg.last do
        if not enabled_only or self.items[i].enabled then
            list[#list + 1] = { idx = i, angle = M.angle_of(i - pg.first + 1, n) }
        end
    end
    return list, n
end

function Ctl:_dirty()
    local w = self.widget
    if not (UIManager and w) then return end
    UIManager:setDirty(self.dlg, function() return "ui", w.dimen end)
end

function Ctl:select(idx)
    if idx == nil or idx == self.sel then return false end
    self.sel = idx
    self:_dirty()
    return true
end

-- Point at direction `dir` (0..7, 45 degrees each): the nearest selectable
-- sector.
function Ctl:point(dir)
    local idx = M.nearest(self:page_items(true), dir * 45)
    return idx ~= nil and self:select(idx)
end

-- Previous / next selectable button on the page (clockwise = +1), wrapping.
function Ctl:rotate(step)
    local pg = self.pages[self.page]
    local n = pg.last - pg.first + 1
    local cur = self.sel and self.sel - pg.first or (step > 0 and -1 or n)
    for _k = 1, n do
        cur = (cur + step) % n
        if self.items[pg.first + cur].enabled then return self:select(pg.first + cur) end
    end
    return false
end

function Ctl:page_step(step)
    local count = #self.pages
    if count < 2 then return false end
    self.page = (self.page - 1 + step) % count + 1
    self.sel = self:_first_enabled(self.page)
    self:_dirty()
    return true
end

-- Run the selected button's callback (hold: its hold_callback), as a tap on
-- it would. A callback that keeps the dialog open (a toggle) gets the new
-- texts / states shown.
function Ctl:activate(hold)
    local it = self.items[self.sel or 0]
    if not (it and it.enabled) then return false end
    local fn = it.entry[hold and "hold_callback" or "callback"]
    if type(fn) ~= "function" then return false end
    self:_stop()
    local dlg = self.dlg
    fn()
    local c = rawget(dlg, "_kopad_wheel")
    if c and UIManager and UIManager:isWidgetShown(dlg) then c:refresh() end
    return true
end

function Ctl:refresh()
    local items = M.items_from_buttons(self.dlg.buttons)
    if #items ~= #self.items then return end -- reinit takes care of a new set
    self.items = items
    if not (self.sel and items[self.sel].enabled) then self.sel = self:_first_enabled(self.page) end
    self:_dirty()
end

-- B: close like the stock Back key (tap_close_callback included).
function Ctl:close()
    local dlg = self.dlg
    if dlg.dismissable == false then return false end
    self:_stop()
    dlg:onClose()
    return true
end

-- A stick axis crossed the dead zone: follow that stick until it is centred.
function Ctl:stick(which)
    if not STICK_AXES[which] then return end
    if which ~= self._stick then self._stick, self._cand = which, nil end
    if not self._polling then self:_sample() end
end

-- Opened by a stick push (the quick-action wheel, TASK-26): select the sector
-- of the direction stick `which` is held in right now, then follow it.
function Ctl:aim(which)
    local G = gamepad()
    local axes = STICK_AXES[which]
    local held = G and type(G.held_axis_directions) == "table" and G.held_axis_directions
    if held and axes then
        local dir = M.dir_from_axes(held[axes[1]], held[axes[2]])
        if dir then self:point(dir) end
    end
    self:stick(which)
end

function Ctl:_sample()
    self._polling = false
    if self.closed then return end
    local G = gamepad()
    local axes = STICK_AXES[self._stick]
    if not (G and axes) then return end
    local held = type(G.held_axis_directions) == "table" and G.held_axis_directions or {}
    local dir = M.dir_from_axes(held[axes[1]], held[axes[2]])
    if dir == nil then
        self._cand = nil -- centred: the selection stays
        return
    end
    local t = now_s()
    if dir ~= self._cand then
        self._cand, self._cand_t = dir, t
    elseif t - self._cand_t >= M.STABLE_S then
        self:point(dir)
    end
    self._polling = true
    if UIManager then UIManager:scheduleIn(M.POLL_S, self._poll_fn) end
end

function Ctl:_stop()
    if self._polling and UIManager then UIManager:unschedule(self._poll_fn) end
    self._polling, self._cand = false, nil
end

-- Touch: tap at screen position (x, y). Returns true when consumed.
function Ctl:tap(x, y)
    local w = self.widget
    if not (w and w.cx) then return false end
    local dx, dy = x - w.cx, y - w.cy
    local r2 = dx * dx + dy * dy
    if r2 <= w.r0 * w.r0 then
        self:page_step(1)
    elseif r2 <= w.R_out * w.R_out then
        -- the sector under the finger, a disabled one does nothing
        local all, n = self:page_items(false)
        local a = math.deg(atan2(dx, -dy)) % 360
        local it = all[math.floor(a * n / 360 + 0.5) % n + 1]
        if it and self.items[it.idx].enabled then
            self.sel = it.idx
            self:activate(false)
        end
    elseif not (r2 <= w.disc_r * w.disc_r or w:in_pill(x, y)) then
        -- no frame (TASK-20): outside the disc and the pills is the page
        self:close()
    end
    return true
end

----------------------------------------------------------------------
-- The painted panel (TASK-20): no frame -- a title pill, the wheel on a
-- white disc (the selected sector pops out of the rim, its label in the
-- hub) and a pill with the buttons. Between them the page shows through:
-- nothing is painted there, and a repaint of the dialog does not touch it.
----------------------------------------------------------------------

local Panel -- built on first use (Widget needs KOReader)

local function panel_class()
    if Panel then return Panel end
    load_ui()
    local Widget = require("ui/widget/widget")
    Panel = Widget:extend{ ctl = nil, title = nil }

    function Panel:init()
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local min_side = math.min(sw, sh)
        self.pad = Size.padding.large
        self.gap = Size.padding.default
        self.bw = Size.border.thick
        self.pill_px = Size.padding.large -- inner padding of a pill, left / right
        self.pill_py = Size.padding.small
        self.title_face = Font:getFace("x_smallinfofont")
        self.hub_face = Font:getFace("smallinfofont")
        self.key_face = Font:getFace("xx_smallinfofont")
        self.hint_face = Font:getFace("x_smallinfofont")
        local R = math.floor(min_side * 0.27)
        local W = math.min(sw - 2 * Size.margin.default, math.max(2 * R + 4 * self.pad, math.floor(min_side * 0.75)))
        self.inner_w = W - 2 * self.pad
        -- title pill: one line as wide as the text, else 2 lines at full width
        self.title_h, self.title_w, self.title_lines = 0, 0, 1
        if type(self.title) == "string" and self.title ~= "" then
            local max_w = self.inner_w - 2 * self.pill_px
            local tw = TextWidget:new{ text = self.title, face = self.title_face }
            local sz = tw:getSize()
            tw:free()
            if sz.w <= max_w then
                self.title_w, self.title_h = sz.w, sz.h
            else
                local tb = self:_textbox(self.title, self.title_face, false, max_w)
                local lh = tb.line_height_px or sz.h
                self.title_lines = 2
                self.title_w, self.title_h = max_w, math.min(tb:getSize().h, 2 * lh)
                tb:free()
            end
        end
        local probe = TextWidget:new{ text = "Ag", face = self.hint_face }
        self.keys_h = probe:getSize().h + 2 * self.pill_py
        probe:free()
        local function disc_r(r) return r + math.floor(r / 12) + self.gap end
        local function height(r)
            return self.pad + (self.title_h > 0 and self.title_h + 2 * self.pill_py + self.gap or 0)
                + 2 * disc_r(r) + self.gap + self.keys_h + self.pad
        end
        local avail = sh - 2 * Size.margin.default
        if height(R) > avail then
            R = math.max(Screen:scaleBySize(60), R - math.ceil((height(R) - avail) / 2))
        end
        self.R, self.r0 = R, math.floor(R * 0.5)
        self.pop = math.floor(R / 12)
        self.R_out = R + self.pop
        self.disc_r = disc_r(R)
        self.dimen = Geom:new{
            x = math.floor((sw - W) / 2), y = math.floor((sh - height(R)) / 2),
            w = W, h = height(R),
        }
        self.pills = {}
    end

    function Panel:_textbox(text, face, bold, width, h)
        return TextBoxWidget:new{
            text = text, face = face, bold = bold, width = width,
            alignment = "center", height = h, height_overflow_show_ellipsis = h ~= nil,
        }
    end

    function Panel:getSize() return self.dimen end

    -- Is screen point (x, y) on one of the pills painted last time?
    function Panel:in_pill(x, y)
        for _i, p in ipairs(self.pills) do
            if x >= p.x and x < p.x + p.w and y >= p.y and y < p.y + p.h then return true end
        end
        return false
    end

    -- Paint text box / widget `tw` and free it.
    local function put(tw, bb, x, y)
        tw:paintTo(bb, x, y)
        tw:free()
    end

    -- White rounded box with a black border (a pill when r = h / 2).
    function Panel:_pill(bb, x, y, w, h)
        local r = math.floor(h / 2)
        bb:paintRoundedRect(x, y, w, h, Blitbuffer.COLOR_WHITE, r)
        bb:paintBorder(x, y, w, h, self.bw, Blitbuffer.COLOR_BLACK, r)
        self.pills[#self.pills + 1] = { x = x, y = y, w = w, h = h }
    end

    -- Sector colours: 0 none, 1 black (lines, selection), 2 white.
    local function colour(k)
        return k == 1 and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
    end

    function Panel:_paint_wheel(bb, cx, cy)
        local c = self.ctl
        local R, r0, R_out = self.R, self.r0, self.R_out
        local all, n = c:page_items(false)
        local step = 360 / n
        local sel_k
        for k, it in ipairs(all) do if it.idx == c.sel then sel_k = k - 1 end end
        bb:paintCircle(cx, cy, self.disc_r, Blitbuffer.COLOR_WHITE, self.disc_r) -- w = r: filled
        -- sectors, one pixel row at a time in runs of one colour
        local half_lw = math.max(1, Screen:scaleBySize(1.5))
        local R2, Ro2, r02 = R * R, R_out * R_out, r0 * r0
        for py = -R_out, R_out do
            local run_k, run_x = 0, -R_out
            for px = -R_out, R_out + 1 do
                local k = 0
                local d2 = px * px + py * py
                if px <= R_out and d2 >= r02 and d2 <= Ro2 then
                    local a = math.deg(atan2(px, -py)) % 360
                    local sector = math.floor((a + step / 2) / step) % n
                    if d2 <= R2 or sector == sel_k then
                        local f = (a + step / 2) % step
                        if math.sqrt(d2) * math.sin(math.rad(math.min(f, step - f))) < half_lw then
                            k = 1
                        else
                            k = sector == sel_k and 1 or 2
                        end
                    end
                end
                if k ~= run_k then
                    if run_k ~= 0 then bb:paintRect(cx + run_x, cy + py, px - run_x, 1, colour(run_k)) end
                    run_k, run_x = k, px
                end
            end
        end
        bb:paintCircle(cx, cy, R, Blitbuffer.COLOR_BLACK, self.bw)
        bb:paintCircle(cx, cy, r0, Blitbuffer.COLOR_BLACK, self.bw)
        -- glyphs (the selected one further out, in its popped sector)
        -- getFace scales the size by the screen DPI itself: pass it unscaled
        local scale = Screen:scaleBySize(1000) / 1000
        local gface = Font:getFace("infofont", math.max(12, math.floor((R - r0) * 0.5 / scale)))
        for k, e in ipairs(all) do
            local it, on = c.items[e.idx], k - 1 == sel_k
            local fg = on and Blitbuffer.COLOR_WHITE
                or (it.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY)
            local tw = TextWidget:new{ text = it.glyph, face = gface, fgcolor = fg }
            local sz = tw:getSize()
            local th = math.rad(e.angle)
            local rm = (r0 + (on and R_out or R)) / 2
            put(tw, bb, math.floor(cx + rm * math.sin(th) - sz.w / 2),
                math.floor(cy - rm * math.cos(th) - sz.h / 2))
            -- checked (radio / check box button): a dot at the outer edge
            if it.checked then
                local dr = math.max(2, math.floor((R - r0) * 0.07))
                local rd = (on and R_out or R) - 3 * dr
                bb:paintCircle(math.floor(cx + rd * math.sin(th)), math.floor(cy - rd * math.cos(th)), dr, fg, dr)
            end
        end
        -- hub: the label of the selection, up to 3 lines (2 above a hint)
        local it = c.items[c.sel or 0]
        if it then
            local label = it.checked and (CHECK .. " " .. it.label) or it.label
            local w = math.floor(r0 * 1.5)
            local max_lines = it.hint and 2 or 3
            local tb = self:_textbox(label, self.hub_face, true, w)
            local lh = tb.line_height_px or math.floor(tb:getSize().h)
            if tb:getSize().h > max_lines * lh then
                tb:free()
                tb = self:_textbox(label, self.hub_face, true, w, max_lines * lh)
            end
            local hw = it.hint and TextWidget:new{ text = it.hint, face = self.key_face, max_width = w }
            local h = tb:getSize().h
            local hh = hw and hw:getSize().h or 0
            local y0 = cy - math.floor((h + hh) / 2)
            put(tb, bb, cx - math.floor(w / 2), y0)
            if hw then put(hw, bb, cx - math.floor(hw:getSize().w / 2), y0 + h) end
        end
    end

    -- The buttons row: { key(s), word } as round (A) or rounded (LB) badges.
    function Panel:_keys()
        local c = self.ctl
        local it = c.items[c.sel or 0]
        local keys = { { { "A" }, _("run") }, { { "B" }, _("close") } }
        if it and type(it.entry.hold_callback) == "function" then
            keys[#keys + 1] = { { "X" }, _("long press") }
        end
        if #c.pages > 1 then
            keys[#keys + 1] = { { "LB", "RB" }, _("page") .. " " .. c.page .. " / " .. #c.pages }
        end
        return keys
    end

    function Panel:_paint_keys(bb, cx, top)
        local keys = self:_keys()
        local th = self.keys_h - 2 * self.pill_py
        local sp, bgap = self.pad, Size.padding.small
        -- measure: badges are as high as the text line
        local parts, total = {}, 0
        for i, k in ipairs(keys) do
            local p = { badges = {} }
            for j, name in ipairs(k[1]) do
                local lw = TextWidget:new{ text = name, face = self.key_face, bold = true }
                local bw = math.max(th, lw:getSize().w + 2 * bgap)
                p.badges[j] = { tw = lw, w = bw }
                total = total + bw + bgap
            end
            p.word = TextWidget:new{ text = k[2], face = self.hint_face }
            total = total + p.word:getSize().w + (i > 1 and sp or 0)
            parts[i] = p
        end
        local pw = total + 2 * self.pill_px
        local x0 = cx - math.floor(pw / 2)
        self:_pill(bb, x0, top, pw, self.keys_h)
        local x, y = x0 + self.pill_px, top + self.pill_py
        for i, p in ipairs(parts) do
            if i > 1 then x = x + sp end
            for _j, b in ipairs(p.badges) do
                local lsz = b.tw:getSize()
                if b.w == th then
                    local r = math.floor(th / 2)
                    bb:paintCircle(x + r, y + r, r, Blitbuffer.COLOR_BLACK, Size.border.default)
                else
                    bb:paintBorder(x, y, b.w, th, Size.border.default, Blitbuffer.COLOR_BLACK, math.floor(th / 3))
                end
                put(b.tw, bb, x + math.floor((b.w - lsz.w) / 2), y + math.floor((th - lsz.h) / 2))
                x = x + b.w + bgap
            end
            local wsz = p.word:getSize()
            put(p.word, bb, x, y + math.floor((th - wsz.h) / 2))
            x = x + wsz.w
        end
    end

    function Panel:paintTo(bb, x, y)
        local d = self.dimen
        d.x, d.y = x, y
        self.pills = {}
        local cx = x + math.floor(d.w / 2)
        local top = y + self.pad
        if self.title_h > 0 then
            local pw, ph = self.title_w + 2 * self.pill_px, self.title_h + 2 * self.pill_py
            self:_pill(bb, cx - math.floor(pw / 2), top, pw, ph)
            local tx, ty = cx - math.floor(self.title_w / 2), top + self.pill_py
            if self.title_lines == 1 then
                put(TextWidget:new{ text = self.title, face = self.title_face }, bb, tx, ty)
            else
                put(self:_textbox(self.title, self.title_face, false, self.title_w, self.title_h), bb, tx, ty)
            end
            top = top + ph + self.gap
        end
        self.cx, self.cy = cx, top + self.disc_r
        self:_paint_wheel(bb, self.cx, self.cy)
        self:_paint_keys(bb, cx, top + 2 * self.disc_r + self.gap)
    end

    return Panel
end

----------------------------------------------------------------------
-- Converting ButtonDialogs
----------------------------------------------------------------------

-- Instance overrides of a converted dialog. Each falls back to the class
-- method when the dialog is not (or no longer, after a reinit that made it
-- ineligible) a wheel.
local function wheel_of(dlg) return rawget(dlg, "_kopad_wheel") end

local OVERRIDES = {
    onTapClose = function(self, arg, ges)
        local c = wheel_of(self)
        if not c then return M._ButtonDialog.onTapClose(self, arg, ges) end
        return c:tap(ges.pos.x, ges.pos.y)
    end,
    onFocusMove = function(self, args)
        local c = wheel_of(self)
        if not c then return M._ButtonDialog.onFocusMove(self, args) end
        local dx, dy = args[1] or 0, args[2] or 0
        c:rotate((dx + dy) < 0 and -1 or 1)
        return true
    end,
    onPress = function(self)
        local c = wheel_of(self)
        if not c then return M._ButtonDialog.onPress(self) end
        c:activate(false)
        return true
    end,
    onHold = function(self)
        local c = wheel_of(self)
        if not c then return M._ButtonDialog.onHold(self) end
        c:activate(true)
        return true
    end,
    onShow = function(self)
        local c = wheel_of(self)
        if c then c.closed = false end
        return M._ButtonDialog.onShow(self)
    end,
    onCloseWidget = function(self)
        local c = wheel_of(self)
        if c then c:_stop(); c.closed = true end
        return M._ButtonDialog.onCloseWidget(self)
    end,
}

-- After the stock ButtonDialog:init: turn `dlg` into a wheel when kopad wants
-- it (M._state_fn) and the dialog is eligible. `prev` = the wheel before a
-- reinit (its selection is kept). kopad's own quick-action wheel (TASK-26)
-- sets `_kopad_force_wheel` (a wheel even with "Dialogs as a wheel" off) and
-- `_kopad_stick` (the stick that opened it: aim at its direction).
function M.maybe_convert(dlg, prev)
    if not (rawget(dlg, "_kopad_force_wheel") or (M._state_fn and M._state_fn())) then return false end
    if getmetatable(dlg) ~= M._ButtonDialog or dlg._added_widgets then return false end
    local items = M.items_from_buttons(dlg.buttons)
    if #items < 2 or #items > M.MAX_ITEMS then return false end
    local c = M.new_ctl(dlg, items, prev)
    if not c.sel then return false end -- nothing selectable
    load_ui()
    local CenterContainer = require("ui/widget/container/centercontainer")
    -- no title: the text the dialog is about, if the caller said
    local title = dlg.title
    if type(title) ~= "string" or title == "" then
        title = M.snippet_title(rawget(dlg, "_kopad_snippet") or M._pending_snippet)
    end
    local widget = panel_class():new{ ctl = c, title = title }
    c.widget = widget
    local content = CenterContainer:new{ dimen = Screen:getSize(), widget }
    -- Everything built: only assignments from here on.
    for name, fn in pairs(OVERRIDES) do dlg[name] = fn end
    -- A dialog that is not dismissable has no tap handler; the sectors need one.
    if not dlg.ges_events.TapClose and require("device"):isTouchDevice() then
        local GestureRange = require("ui/gesturerange")
        dlg.ges_events.TapClose = { GestureRange:new{
            ges = "tap", range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
        } }
    end
    dlg[1] = content
    dlg.movable = widget
    dlg._kopad_wheel = c
    local stick = rawget(dlg, "_kopad_stick")
    if stick and not prev then c:aim(stick) end
    return true
end

-- KOReader's two highlight menus (a new selection's, an existing highlight's)
-- have no title and no field with their text: wrap the methods that build
-- them so the wheel can show the text (TASK-20). Once per run.
local function wrap_highlight_menus()
    local ok, RH = pcall(require, "apps/reader/modules/readerhighlight")
    if not ok or type(RH) ~= "table" or rawget(RH, "_kopad_wrapped") then return end
    local function with_snippet(name, text_of)
        local stock = RH[name]
        if type(stock) ~= "function" then return end
        RH[name] = function(self, ...)
            local ok2, text = pcall(text_of, self, ...)
            M._pending_snippet = ok2 and text or nil
            -- both return at most one value (an event handler's "consumed")
            local ok3, r = pcall(stock, self, ...)
            M._pending_snippet = nil
            if not ok3 then error(r, 0) end
            return r
        end
    end
    with_snippet("onShowHighlightMenu", function(self) return self.selected_text.text end)
    with_snippet("showHighlightDialog", function(self, index)
        return self.ui.annotation.annotations[index].text
    end)
    RH._kopad_wrapped = true
end

-- Wrap ButtonDialog.init once. `state_fn()` says whether kopad wants wheels
-- right now (enabled + setting); replaced on every call, so it follows the
-- current kopad instance. Returns false when wheels are unavailable.
function M.install(state_fn)
    M._state_fn = state_fn
    if M._installed then return true end
    if not gamepad() then return false end
    local ok, BD = pcall(require, "ui/widget/buttondialog")
    if not ok or type(BD) ~= "table" or type(BD.init) ~= "function" then return false end
    M._ButtonDialog = BD
    local stock_init = rawget(BD, "_kopad_stock_init") or BD.init
    BD._kopad_stock_init = stock_init
    BD.init = function(self, ...)
        local prev = rawget(self, "_kopad_wheel")
        self._kopad_wheel = nil
        stock_init(self, ...)
        local ok2, err = pcall(M.maybe_convert, self, prev)
        if not ok2 then
            rawset(self, "_kopad_wheel", nil)
            logger.warn("kopad: wheel conversion failed: " .. tostring(err))
        end
    end
    wrap_highlight_menus()
    M._installed = true
    return true
end

return M
