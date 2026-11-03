--[[
kopad_hints.lua -- "point from-to" (TASK-29): pad labels next to the lines of the
page, then a start and an end chosen by pressing the label's two symbols.

Pure Lua, no KOReader dependency (tests/kopad_hints_test.lua). It knows nothing
about documents: an ADAPTER turns the page into a list of lines in screen
coordinates and maps the chosen lines back to words. The EPUB adapter lives
in selector.lua (paginmapo word boxes -> lines_from_boxes); a PDF / DjVu
adapter (TASK-30, getTextBoxes) builds the same line list and uses this
module unchanged.

Symbols and placement follow the Vivaldi-on-the-Deck labels
(~/aparati/steamdeck/vivaldi-deck/ext/hints.js): eight symbols, the D-pad
(up, down, left, right) and A / B / X / Y; the left part of a region starts
with a D-pad symbol, the right part with a letter, and the direction of the
button tells where in that part the target lies (Y on top, A at the bottom, X
left, B right -- like the arrows). Differences, both on purpose:
  - every label has TWO symbols, also when the page has few lines (always
    the same rhythm; a lone target in its group repeats the symbol: "↑↑");
  - a label never STARTS with B: B with nothing typed is "back" (close the
    mode / no end = one word). So a page takes at most 7 * 8 = 56 lines;
    lines past that (tiny fonts) get no label.
Coordinates are snapped to 1/GRID of the region before the anchors are
compared, so an indent of a few pixels does not reorder a column of lines:
neighbouring lines share their first symbol.

Line (the contract with the adapters):
  { x, y, w, h,        -- screen box of the whole line
    first, last }      -- the adapter's word indices (opaque here)
  Lines are in reading order.

API:
  M.SYMBOLS / M.DIRS / M.BACK / M.FIRST    the vocabulary
  M.assign(points, first) -> labels         points = { {x, y}, ... }; labels[i]
                                            = { s1, s2 } or nil (overflow)
  M.lines_from_boxes(boxes) -> lines        boxes in reading order (nil boxes
                                            skipped); first / last = indices
  M.Pointer.new(lines, opts) -> pointer     opts.rtl = right-to-left script
  pointer:press(sym) -> result              see Pointer below
  pointer:visible() -> { {line, label, x, y, side, typed}, ... }
]]

local M = {}

M.GRID = 16

-- Anchors in a region (0..1): left half = D-pad, right half = the A/B/X/Y
-- diamond (Y on top, A at the bottom, X left, B right). Order = tie-break.
M.DIRS = {
    { c = "up",    ax = 0.25, ay = 0 },   { c = "down",  ax = 0.25, ay = 1 },
    { c = "left",  ax = 0,    ay = 0.5 }, { c = "right", ax = 0.42, ay = 0.5 },
    { c = "Y",     ax = 0.75, ay = 0 },   { c = "A",     ax = 0.75, ay = 1 },
    { c = "X",     ax = 0.58, ay = 0.5 }, { c = "B",     ax = 1,    ay = 0.5 },
}
M.SYMBOLS = {}
for i, d in ipairs(M.DIRS) do M.SYMBOLS[i] = d.c end
M.BACK = "B"
-- Symbols a label may start with: all but BACK.
M.FIRST = {}
for _, d in ipairs(M.DIRS) do
    if d.c ~= M.BACK then M.FIRST[#M.FIRST + 1] = d.c end
end

local function dirs_of(symbols)
    local by, out = {}, {}
    for _, d in ipairs(M.DIRS) do by[d.c] = d end
    for _, c in ipairs(symbols) do
        if by[c] then out[#out + 1] = by[c] end
    end
    return out
end

-- Split items ({x, y, order}) into one group per anchor of `dirs`, at most
-- `cap` items each (hints.js: the borders move so that a dense part of the
-- page does not lengthen the labels). The items whose choice is most obvious
-- (largest regret = second best minus best) go first; ties in reading order.
local function split(items, dirs, cap)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, t in ipairs(items) do
        x0, y0 = math.min(x0, t.x), math.min(y0, t.y)
        x1, y1 = math.max(x1, t.x), math.max(y1, t.y)
    end
    local w, h = x1 - x0, y1 - y0
    local s = math.max(w, h, 1)
    local function q(v) return math.floor(v / s * M.GRID + 0.5) end
    local function cost(t, d)
        local dx = q(t.x - x0) - q(d.ax * w)
        local dy = q(t.y - y0) - q(d.ay * h)
        return dx * dx + dy * dy
    end
    local ranked = {}
    for _, t in ipairs(items) do
        local c = {}
        for i, d in ipairs(dirs) do c[i] = cost(t, d) end
        table.sort(c)
        ranked[#ranked + 1] = { t = t, regret = (c[2] or c[1]) - c[1] }
    end
    table.sort(ranked, function(a, b)
        if a.regret ~= b.regret then return a.regret > b.regret end
        return a.t.order < b.t.order
    end)
    local groups = {}
    for i = 1, #dirs do groups[i] = {} end
    for _, r in ipairs(ranked) do
        local best, best_cost
        for i, d in ipairs(dirs) do
            if #groups[i] < cap then
                local c = cost(r.t, d)
                if not best or c < best_cost then best, best_cost = i, c end
            end
        end
        local g = groups[best]
        g[#g + 1] = r.t
    end
    for _, g in ipairs(groups) do
        table.sort(g, function(a, b) return a.order < b.order end)
    end
    return groups
end

-- Two-symbol labels for points (in reading order), by position. `first` =
-- the symbols a label may start with (default M.FIRST). Points past
-- #first * #M.DIRS get no label (nil).
function M.assign(points, first)
    local fdirs = dirs_of(first or M.FIRST)
    local all = M.DIRS
    local labels = {}
    local items = {}
    local max = #fdirs * #all
    for i, p in ipairs(points) do
        if #items >= max then break end
        items[#items + 1] = { x = p.x or 0, y = p.y or 0, order = i }
    end
    if #items == 0 then return labels end
    local cap = #items <= #fdirs and 1 or #all
    for gi, g in ipairs(split(items, fdirs, cap)) do
        local c1 = fdirs[gi].c
        if #g == 1 then
            labels[g[1].order] = { c1, c1 }
        elseif #g > 1 then
            for si, sg in ipairs(split(g, all, 1)) do
                if sg[1] then labels[sg[1].order] = { c1, all[si].c } end
            end
        end
    end
    return labels
end

-- Lines from word boxes in reading order: a word starts a new line when its
-- vertical middle is outside the current line's band (half the smaller
-- height). first / last = indices into `boxes`. A nil box is skipped.
function M.lines_from_boxes(boxes)
    local lines, cur = {}, nil
    for i = 1, #boxes do
        local b = boxes[i]
        if type(b) == "table" and b.x and b.y and b.w and b.h then
            local mid = b.y + b.h / 2
            local same = false
            if cur then
                local lmid = cur.y + cur.h / 2
                same = math.abs(mid - lmid) < math.min(b.h, cur.h) / 2
            end
            if same then
                local x0, y0 = math.min(cur.x, b.x), math.min(cur.y, b.y)
                local x1 = math.max(cur.x + cur.w, b.x + b.w)
                local y1 = math.max(cur.y + cur.h, b.y + b.h)
                cur.x, cur.y, cur.w, cur.h = x0, y0, x1 - x0, y1 - y0
                cur.last = i
            else
                cur = { x = b.x, y = b.y, w = b.w, h = b.h, first = i, last = i }
                lines[#lines + 1] = cur
            end
        end
    end
    return lines
end

----------------------------------------------------------------------
-- Pointer: the two steps
----------------------------------------------------------------------
-- step "start": labels at the line STARTS (left edge, right edge in RTL).
--   A label picks the start line -> step "end".
-- step "end": labels at the line ENDS, from the start line down (the lines
--   before it cannot end a selection).
--   A label picks the end line -> "done" (start .. stop).
-- press(sym) results:
--   "prefix"    first symbol of a label typed: only the labels with it stay
--   "unprefix"  B with a prefix that no label continues: prefix dropped
--   "start"     start line chosen, now the end labels
--   "done"      finished: self.start, self.stop (stop nil = no end, one word)
--   "cancel"    B with nothing typed in step "start": close the mode
--   "ignored"   a symbol no label has
-- B with nothing typed in step "end" = "done" without a stop.

local Pointer = {}
Pointer.__index = Pointer
M.Pointer = Pointer

function Pointer.new(lines, opts)
    local self = setmetatable({ lines = lines or {}, rtl = opts and opts.rtl or false }, Pointer)
    self:_labels("start", 1)
    return self
end

-- Labels for step `step`, lines from `from` on.
function Pointer:_labels(step, from)
    self.step, self.from, self.typed = step, from, nil
    local at_left = (step == "start") ~= self.rtl
    local points, targets = {}, {}
    for i = from, #self.lines do
        local l = self.lines[i]
        points[#points + 1] = { x = at_left and l.x or (l.x + l.w), y = l.y + l.h / 2 }
        targets[#targets + 1] = i
    end
    local labels = M.assign(points)
    self.targets = {}
    for k, i in ipairs(targets) do
        if labels[k] then
            self.targets[#self.targets + 1] = {
                line = i, label = labels[k], x = points[k].x, y = points[k].y,
                side = at_left and "left" or "right",
            }
        end
    end
end

function Pointer:_pick(i)
    if self.step == "start" then
        self.start = i
        self:_labels("end", i)
        return "start"
    end
    self.stop = i
    self.step = "done"
    return "done"
end

function Pointer:press(sym)
    if self.step == "done" then return "ignored" end
    if not self.typed then
        for _, t in ipairs(self.targets) do
            if t.label[1] == sym then self.typed = sym; return "prefix" end
        end
        if sym == M.BACK then
            if self.step == "start" then return "cancel" end
            self.step = "done"
            return "done"
        end
        return "ignored"
    end
    for _, t in ipairs(self.targets) do
        if t.label[1] == self.typed and t.label[2] == sym then return self:_pick(t.line) end
    end
    if sym == M.BACK then self.typed = nil; return "unprefix" end
    return "ignored"
end

-- The labels to draw: all of them, or those that continue the typed prefix.
-- `typed` = how many of the label's symbols are already pressed (0 or 1).
function Pointer:visible()
    local out = {}
    if self.step == "done" then return out end
    for _, t in ipairs(self.targets) do
        if not self.typed or t.label[1] == self.typed then
            out[#out + 1] = { line = t.line, label = t.label, x = t.x, y = t.y,
                              side = t.side, typed = self.typed and 1 or 0 }
        end
    end
    return out
end

return M
