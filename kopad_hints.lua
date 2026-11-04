--[[
kopad_hints.lua -- "point from-to" (TASK-29; on sentences since TASK-35;
sentence labels only since TASK-42 / PC-024): pad labels at the sentences of
the page; a label picks the sentence, and selector.lua puts the word cursor
on its first visible word (the rest is the word walk: D-pad and RT held).

Pure Lua, no KOReader dependency (tests/kopad_hints_test.lua). It knows nothing
about documents: an ADAPTER turns the page into word boxes in screen
coordinates plus the sentences as word-index ranges, and maps the chosen word
index back to a word. The EPUB adapter lives in selector.lua
(SelectorOverlay:_point_begin: paginmapo words and sentences); the PDF / DjVu
adapter (PagedOverlay:_point_begin, pdfwords.lua) builds the same lists and
uses this module unchanged.

Sentence labels follow the Vivaldi-on-the-Deck labels
(~/aparati/steamdeck/vivaldi-deck/ext/hints.js): eight symbols, the D-pad
(up, down, left, right) and A / B / X / Y; the left part of a region starts
with a D-pad symbol, the right part with a letter, and the direction of the
button tells where in that part the target lies (Y on top, A at the bottom, X
left, B right -- like the arrows). Differences, both on purpose:
  - every label has TWO symbols, also when the page has few targets (always
    the same rhythm; a lone target in its group repeats the symbol: "↑↑");
  - a label never STARTS with B: B with nothing typed closes the labels. So
    at most 7 * 8 = 56 targets get a label (M.MAX_LABELS).
Coordinates are snapped to 1/GRID of the region before the anchors are
compared, so an indent of a few pixels does not reorder a column of targets:
neighbours share their first symbol.

The word level of TASK-36..41 (letters A / X / Y over the words of a
sentence, the end step, the arrow shortcuts and their badges, the dashed
preview) is gone (PC-024 replaces PC-023): it was hard to predict on the
Deck.

The contract with the adapters (see Pointer below):
  sentences = { { first, last, ... }, ... }   word indices, reading order
                                              (other fields are ignored)
  boxes[i]  = { x, y, w, h } | false          screen box of word i (false =
                                              off the screen)

API:
  M.SYMBOLS / M.DIRS / M.BACK / M.FIRST    the vocabulary
  M.MAX_LABELS                              56 sentence labels
  M.assign(points, first) -> labels         points = { {x, y}, ... }; labels[i]
                                            = { s1, s2 } or nil (overflow)
  M.Pointer.new(sentences, boxes, opts)     opts.rtl = right-to-left script
  pointer:press(sym) -> result              see Pointer below
  pointer:visible() -> { {sent, word, label, x, y, side, h, typed}, ... }
                                            the labels still in play
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

----------------------------------------------------------------------
-- Pointer: the sentence labels of one page
----------------------------------------------------------------------
-- press(sym) results:
--   "prefix"    a symbol that goes on in some label (it is typed)
--   "unprefix"  B, when no label goes on with it: the last typed symbol is
--               dropped
--   "done"      a whole label: self.sent = the sentence (index into
--               `sentences`), self.start = its first visible word
--   "cancel"    B with nothing typed: close
--   "ignored"   a symbol no label has; anything after "done"

M.MAX_LABELS = #M.FIRST * #M.DIRS

local Pointer = {}
Pointer.__index = Pointer
M.Pointer = Pointer

function Pointer.new(sentences, boxes, opts)
    local self = setmetatable({
        sentences = sentences or {}, boxes = boxes or {},
        rtl = opts and opts.rtl or false,
    }, Pointer)
    self:_sentence_labels()
    return self
end

local function box_of(self, i)
    local b = self.boxes[i]
    if type(b) == "table" and b.x and b.y and b.w and b.h then return b end
end

-- The first visible word of sentence si (nil = none on the screen).
function Pointer:_first_visible(si)
    local s = self.sentences[si]
    if not s or not s.first or not s.last then return nil end
    for i = s.first, s.last do
        if box_of(self, i) then return i end
    end
end

-- One label left of each sentence's first visible word (right in RTL); a
-- sentence with no visible word gets none.
function Pointer:_sentence_labels()
    self.step, self.typed = "start", {}
    local side = self.rtl and "right" or "left"
    local targets, points = {}, {}
    for si = 1, #self.sentences do
        local wi = self:_first_visible(si)
        local b = wi and box_of(self, wi)
        if b then
            local x = self.rtl and (b.x + b.w) or b.x
            local y = b.y + b.h / 2
            targets[#targets + 1] = { sent = si, word = wi, x = x, y = y, side = side, h = b.h }
            points[#points + 1] = { x = x, y = y }
        end
    end
    local labels = M.assign(points)
    self.targets = {}
    for k, t in ipairs(targets) do
        if labels[k] then
            t.label = labels[k]
            self.targets[#self.targets + 1] = t
        end
    end
end

local function continues(label, typed, sym)
    for i = 1, #typed do if label[i] ~= typed[i] then return false end end
    return label[#typed + 1] == sym
end

function Pointer:press(sym)
    if self.step == "done" then return "ignored" end
    local typed = self.typed
    for _, t in ipairs(self.targets) do
        if continues(t.label, typed, sym) then
            if #t.label == #typed + 1 then
                self.sent, self.start = t.sent, t.word
                self.step, self.targets, self.typed = "done", {}, {}
                return "done"
            end
            typed[#typed + 1] = sym
            return "prefix"
        end
    end
    if sym ~= M.BACK then return "ignored" end
    if #typed > 0 then
        typed[#typed] = nil
        return "unprefix"
    end
    return "cancel"
end

-- The labels still in play: all of them, or those that continue the typed
-- prefix. `typed` = how many of the label's symbols are already pressed.
-- side "left" / "right" = the label goes on that side of (x, y), the
-- vertical middle of the sentence's first visible word; h = its height.
function Pointer:visible()
    local out = {}
    if self.step == "done" then return out end
    local typed = self.typed
    for _, t in ipairs(self.targets) do
        local ok = true
        for i = 1, #typed do if t.label[i] ~= typed[i] then ok = false; break end end
        if ok then
            out[#out + 1] = { sent = t.sent, word = t.word, label = t.label, x = t.x, y = t.y,
                              side = t.side, h = t.h, typed = #typed }
        end
    end
    return out
end

return M
