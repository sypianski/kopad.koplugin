--[[
kopad_hints.lua -- "point from-to" (TASK-29, on sentences since TASK-35 /
PC-022): pad labels at the sentences of the page, a start and an end chosen
by pressing the label's two symbols, refined to a word on request.

Pure Lua, no KOReader dependency (tests/kopad_hints_test.lua). It knows nothing
about documents: an ADAPTER turns the page into word boxes in screen
coordinates plus the sentences as word-index ranges, and maps the chosen
word indices back to words. The EPUB adapter lives in selector.lua
(SelectorOverlay:_point_begin: paginmapo words and sentences); the PDF / DjVu
adapter (PagedOverlay:_point_begin, pdfwords.lua) builds the same lists and
uses this module unchanged.

Symbols and placement follow the Vivaldi-on-the-Deck labels
(~/aparati/steamdeck/vivaldi-deck/ext/hints.js): eight symbols, the D-pad
(up, down, left, right) and A / B / X / Y; the left part of a region starts
with a D-pad symbol, the right part with a letter, and the direction of the
button tells where in that part the target lies (Y on top, A at the bottom, X
left, B right -- like the arrows). Differences, both on purpose:
  - every label has TWO symbols, also when the page has few targets (always
    the same rhythm; a lone target in its group repeats the symbol: "↑↑");
  - a label never STARTS with B: B with nothing typed is "back" (close the
    mode / no end = one word / back to the sentences). So at most
    7 * 8 = 56 targets get a label (M.MAX_LABELS).
Coordinates are snapped to 1/GRID of the region before the anchors are
compared, so an indent of a few pixels does not reorder a column of targets:
neighbours share their first symbol.

The contract with the adapters (see Pointer below):
  sentences = { { first, last }, ... }   word indices, reading order
  boxes[i]  = { x, y, w, h } | false     screen box of word i (false = off
                                         the screen)

API:
  M.SYMBOLS / M.DIRS / M.BACK / M.FIRST    the vocabulary
  M.MAX_LABELS                              56
  M.assign(points, first) -> labels         points = { {x, y}, ... }; labels[i]
                                            = { s1, s2 } or nil (overflow)
  M.lines_from_boxes(boxes) -> lines        word boxes in reading order ->
                                            { x, y, w, h, first, last } lines
                                            (nil boxes skipped; a helper, the
                                            pointer no longer uses lines)
  M.Pointer.new(sentences, boxes, opts)     opts.rtl = right-to-left script
  pointer:press(sym) -> result              see Pointer below
  pointer:refine_to_word(on) -> changed     R-stick ↓ / ↑
  pointer:visible() -> { {sent, word, label, x, y, side, h, typed}, ... }
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
-- Pointer: the two steps, on sentences (TASK-35, PC-022)
----------------------------------------------------------------------
-- Sentence (the contract with the adapters): { first, last } = indices into
-- `boxes`, the words of the page in reading order; boxes[i] = the word's
-- screen box { x, y, w, h }, or false / nil when it is not on the screen (a
-- zoomed PDF). Only the visible words of a sentence count, so a sentence
-- running over the page edge (or out of a zoomed view) is labelled at its
-- visible part, and one with no visible word gets no label.
--
-- step "start": labels at the sentence STARTS (left of the first visible
--   word, right of it in RTL). A label = the start on the sentence's first
--   word -> step "end".
-- step "end": labels at the sentence ENDS (right of the last visible word,
--   left in RTL), from the start sentence down (the sentences before it
--   cannot end a selection). A label = the end on the sentence's last word
--   -> "done" (self.start .. self.stop, word indices).
-- Refinement ("word", R-stick ↓ / ↑): pointer:refine(true) in a step makes
--   the next sentence label open the labels of THAT sentence's words (level
--   "word"; in step "end" only the words from the start word on); a word
--   label = the start / end on that word. refine(false) goes back to the
--   sentence labels. It holds for the current step only: a new step starts
--   with sentences again. A sentence with more than MAX_LABELS visible words
--   (56) gets word labels on a window of MAX_LABELS words: the first ones in
--   step "start", the last ones in step "end" (a start is usually early in a
--   sentence, an end late); the rest is reached with A + arrows afterwards.
-- press(sym) results:
--   "prefix"    first symbol of a label typed: only the labels with it stay
--   "unprefix"  B with a prefix that no label continues: prefix dropped
--   "sentence"  a sentence picked with refine on: now its word labels
--   "back"      B with nothing typed on word labels: the sentence labels of
--               the same step again
--   "start"     start chosen, now the end labels
--   "done"      finished: self.start, self.stop (stop nil = no end, one word)
--   "cancel"    B with nothing typed on the start sentence labels: close
--   "ignored"   a symbol no label has
-- B with nothing typed on the end sentence labels = "done" without a stop.

M.MAX_LABELS = #M.FIRST * #M.DIRS

local Pointer = {}
Pointer.__index = Pointer
M.Pointer = Pointer

function Pointer.new(sentences, boxes, opts)
    local self = setmetatable({
        sentences = sentences or {}, boxes = boxes or {},
        rtl = opts and opts.rtl or false, refine = false,
    }, Pointer)
    self:_sentence_labels("start")
    return self
end

local function box_of(self, i)
    local b = self.boxes[i]
    if type(b) == "table" and b.x and b.y and b.w and b.h then return b end
end

-- Visible words of sentence si (from word `from` on), in reading order.
function Pointer:_visible_words(si, from)
    local s, out = self.sentences[si], {}
    if not s or not s.first or not s.last then return out end
    for i = math.max(s.first, from or s.first), s.last do
        if box_of(self, i) then out[#out + 1] = i end
    end
    return out
end

-- The first word a sentence may contribute in the current step.
function Pointer:_from_word(si)
    if self.step == "end" and si == self.start_sent then return self.start end
end

-- Labels for `targets` ({ sent, word, x, y, side, h, px, py }; px / py = the
-- point the label is assigned by), in reading order.
function Pointer:_set_targets(targets)
    local points = {}
    for k, t in ipairs(targets) do points[k] = { x = t.px, y = t.py } end
    local labels = M.assign(points)
    self.targets, self.typed = {}, nil
    for k, t in ipairs(targets) do
        if labels[k] then
            t.label = labels[k]
            self.targets[#self.targets + 1] = t
        end
    end
end

-- Sentence labels of step `step` ("start" / "end").
function Pointer:_sentence_labels(step)
    self.step, self.level, self.sent = step, "sentence", nil
    local at_end = step == "end"
    local left_edge = at_end == self.rtl   -- start: left (RTL right); end: right (RTL left)
    local side = left_edge and "left" or "right"
    local targets = {}
    for si = (at_end and self.start_sent or 1), #self.sentences do
        local vis = self:_visible_words(si, self:_from_word(si))
        local wi = at_end and vis[#vis] or vis[1]
        local b = wi and box_of(self, wi)
        if b then
            local x = left_edge and b.x or (b.x + b.w)
            local y = b.y + b.h / 2
            targets[#targets + 1] = { sent = si, word = wi, x = x, y = y, side = side,
                                      h = b.h, px = x, py = y }
        end
    end
    self:_set_targets(targets)
end

-- Word labels of sentence si (level "word"): over each visible word, its
-- top edge (side "top"), at most MAX_LABELS of them (see above).
function Pointer:_word_labels(si)
    self.level, self.sent = "word", si
    local vis = self:_visible_words(si, self:_from_word(si))
    local n, max = #vis, M.MAX_LABELS
    local i0 = 1
    if n > max then i0 = self.step == "end" and (n - max + 1) or 1 end
    local targets = {}
    for k = i0, math.min(n, i0 + max - 1) do
        local wi = vis[k]
        local b = box_of(self, wi)
        targets[#targets + 1] = { sent = si, word = wi, x = b.x + b.w / 2, y = b.y,
                                  side = "top", h = b.h,
                                  px = b.x + b.w / 2, py = b.y + b.h / 2 }
    end
    self:_set_targets(targets)
end

function Pointer:_pick(t)
    if self.level == "sentence" and self.refine then
        self:_word_labels(t.sent)
        return "sentence"
    end
    if self.step == "start" then
        self.start, self.start_sent = t.word, t.sent
        self.refine = false
        self:_sentence_labels("end")
        return "start"
    end
    self.stop = t.word
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
            if self.level == "word" then
                self:_sentence_labels(self.step)
                return "back"
            end
            if self.step == "start" then return "cancel" end
            self.step = "done"
            return "done"
        end
        return "ignored"
    end
    for _, t in ipairs(self.targets) do
        if t.label[1] == self.typed and t.label[2] == sym then return self:_pick(t) end
    end
    if sym == M.BACK then self.typed = nil; return "unprefix" end
    return "ignored"
end

-- R-stick ↓ (on = true) / ↑ (false): refinement to the word in the current
-- step. Off while the word labels show = the sentence labels again. True
-- when something changed (a typed prefix stays when only the flag changes).
function Pointer:refine_to_word(on)
    on = on and true or false
    if self.step == "done" or self.refine == on then return false end
    self.refine = on
    if not on and self.level == "word" then self:_sentence_labels(self.step) end
    return true
end

-- The labels to draw: all of them, or those that continue the typed prefix.
-- `typed` = how many of the label's symbols are already pressed (0 or 1).
-- side: "left" / "right" = the label goes on that side of (x, y), "top" =
-- centred on (x, y), the top edge of the word. h = the word's height.
function Pointer:visible()
    local out = {}
    if self.step == "done" then return out end
    for _, t in ipairs(self.targets) do
        if not self.typed or t.label[1] == self.typed then
            out[#out + 1] = { sent = t.sent, word = t.word, label = t.label, x = t.x, y = t.y,
                              side = t.side, h = t.h, typed = self.typed and 1 or 0 }
        end
    end
    return out
end

return M
