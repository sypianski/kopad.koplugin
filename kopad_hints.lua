--[[
kopad_hints.lua -- "point from-to" (TASK-29; on sentences since TASK-35;
letters on the words and arrows as shortcuts since TASK-36 / PC-023; the
words as a tree of threes since TASK-39): pad labels at the sentences of the
page, then over the words of one sentence; a start and an end chosen by
pressing a label's symbols.

Pure Lua, no KOReader dependency (tests/kopad_hints_test.lua). It knows nothing
about documents: an ADAPTER turns the page into word boxes in screen
coordinates plus the sentences as word-index ranges (with their paragraph),
and maps the chosen word indices back to words. The EPUB adapter lives in
selector.lua (SelectorOverlay:_point_begin: paginmapo words and sentences);
the PDF / DjVu adapter (PagedOverlay:_point_begin, pdfwords.lua) builds the
same lists and uses this module unchanged.

Sentence labels follow the Vivaldi-on-the-Deck labels
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

Word labels (M.word_labels, TASK-39) are LETTERS only, A / X / Y: a tree of
threes in reading order. n words = k stages (the smallest k with 3^k >= n);
stage i cuts the current range into pieces of 3^(k-i) words from its start
(the last one shorter), A = the first piece, X = the second, Y = the third.
A word's label = k letters (2 up to 9 words, 3 up to 27, 4 up to 81). The
arrows are never in a label (on the word level they are shortcuts, see
Pointer), nor is B (B = back one stage).

The contract with the adapters (see Pointer below):
  sentences = { { first, last, para }, ... }  word indices, reading order;
                                              para = paragraph id (any value,
                                              compared with ==; nil = the
                                              sentence is its own paragraph)
  boxes[i]  = { x, y, w, h } | false          screen box of word i (false =
                                              off the screen)

API:
  M.SYMBOLS / M.DIRS / M.BACK / M.FIRST    the vocabulary
  M.WORD_LETTERS                            { "A", "X", "Y" }: the word labels
  M.MAX_LABELS                              56 sentence labels
  M.BADGE_RATIO                             default badge size / word height
  M.assign(points, first) -> labels         points = { {x, y}, ... }; labels[i]
                                            = { s1, s2 } or nil (overflow)
  M.word_stages(n) -> k                     the number of stages (letters)
  M.word_labels(n) -> labels                n words in reading order -> labels
                                            of k letters (the tree of threes)
  M.lines_from_boxes(boxes) -> lines        word boxes in reading order ->
                                            { x, y, w, h, first, last } lines
                                            (nil boxes skipped; selector.lua
                                            draws the end step's preview with it)
  M.Pointer.new(sentences, boxes, opts)     opts.rtl = right-to-left script,
                                            opts.badge = function(h) -> the
                                            badge size in px for a word of
                                            height h (default BADGE_RATIO * h)
  pointer:press(sym) -> result              see Pointer below
  pointer:preview() -> from, to             the end step's range (word indices)
  pointer:visible() -> { {sent, word, label, x, y, side, h, typed}, ... }
                                            the labels still in play (logic)
  pointer:stage() -> { kind, typed, items } what to DRAW for the typed prefix
                                            (TASK-39): sentence labels, or one
                                            one-letter badge per piece of the
                                            current stage, above its first
                                            word; see "Stages" below
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
-- Word labels (TASK-39): a tree of threes, letters only
----------------------------------------------------------------------
-- In reading order, not by position (a sentence is a few lines). Since the
-- pieces of a stage are 3^(k-i) words from the start of the range, a word's
-- label is just its index (from 0) in base 3 with k digits, A = 0, X = 1,
-- Y = 2: the first piece of every stage is A, the next X, the next Y. A piece
-- shorter than the others (the end of the range) has fewer sub-pieces, so a
-- stage may show only A, or A and X. The TASK-36 / TASK-38 labels (letters
-- before arrows, 21 / 147 words, blocks of up to 7) are gone: they were hard
-- to predict on the Deck.

M.WORD_LETTERS = { "A", "X", "Y" }

-- The number of stages for n words: the smallest k with 3^k >= n, at least 1.
function M.word_stages(n)
    local k, cap = 1, 3
    while cap < (n or 0) do k, cap = k + 1, cap * 3 end
    return k
end

-- Labels for n words in reading order: k letters each (M.word_stages).
function M.word_labels(n)
    local out = {}
    n = n or 0
    if n <= 0 then return out end
    local k = M.word_stages(n)
    for i = 1, n do
        local l, v = {}, i - 1
        for pos = k, 1, -1 do
            l[pos] = M.WORD_LETTERS[v % 3 + 1]
            v = math.floor(v / 3)
        end
        out[i] = l
    end
    return out
end

----------------------------------------------------------------------
-- Pointer: the two steps (TASK-35 sentences, TASK-36 words + shortcuts)
----------------------------------------------------------------------
-- Sentence (the contract with the adapters): { first, last, para } =
-- indices into `boxes`, the words of the page in reading order; boxes[i] =
-- the word's screen box { x, y, w, h }, or false / nil when it is not on the
-- screen (a zoomed PDF). Only the visible words of a sentence count, so a
-- sentence running over the page edge (or out of a zoomed view) is labelled
-- at its visible part, and one with no visible word gets no label.
--
-- step "start", level "sentence": labels at the sentence STARTS (left of the
--   first visible word, right of it in RTL), M.assign. A label = that
--   sentence's words (level "word"), it does not set the start yet.
-- step "start", level "word": letter labels over the words of the sentence
--   (self.sent). A label = the start on that word -> step "end". Shortcuts
--   (an arrow, at every stage, also after typed letters; a move drops them;
--   ← and → swapped in RTL): ← = the sentence's first word, ↑ = the first
--   word of its paragraph (the first visible word of the run of sentences
--   with the same `para` up to it); → / ↓ nothing.
-- step "end" (always level "word"): the current end sentence E (self.sent,
--   at first the start sentence) and letter labels over its words (in the
--   start sentence from the start word on). A label = the end on that word ->
--   "done". Shortcuts: ← = the end of E, done; → = E + 1 (the labels move
--   there; nothing on the page's last sentence: a range never leaves the
--   page); ↑ = E - 1 (never before the start sentence); ↓ = the end of E's
--   paragraph, done. preview() = start .. the end of E (what ← gives).
-- Word labels: M.word_labels over the step's visible words of the sentence
--   (in the end step's start sentence from the start word on): every word
--   has one, however long the sentence (more stages).
-- press(sym) results:
--   "prefix"    a symbol of a label typed: only the labels with it stay
--               (on the word level: the next stage)
--   "unprefix"  B with a prefix that no label continues: last symbol dropped
--               (on the word level: back one stage)
--   "sentence"  word labels of a sentence now (a sentence label picked, or
--               → / ↑ in the end step)
--   "back"      B with nothing typed on the start step's word labels: the
--               sentence labels again
--   "start"     start chosen, now the end step
--   "done"      finished: self.start, self.stop (stop nil = no end, one word)
--   "cancel"    B with nothing typed on the sentence labels: close
--   "ignored"   a symbol no label has, a shortcut with nowhere to go
-- B with nothing typed in the end step = "done" without a stop.

M.MAX_LABELS = #M.FIRST * #M.DIRS

local Pointer = {}
Pointer.__index = Pointer
M.Pointer = Pointer

-- A letter (A / B / X / Y) rather than an arrow ("up", ...).
local function is_letter(c) return #c == 1 end

M.BADGE_RATIO = 0.65

function Pointer.new(sentences, boxes, opts)
    local self = setmetatable({
        sentences = sentences or {}, boxes = boxes or {},
        rtl = opts and opts.rtl or false,
        badge = opts and opts.badge or nil,
    }, Pointer)
    self:_sentence_labels()
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

function Pointer:_vis(si) return self:_visible_words(si, self:_from_word(si)) end

-- Same paragraph: equal non-nil `para` (nil = a paragraph of its own).
function Pointer:_same_para(a, b)
    local pa = self.sentences[a] and self.sentences[a].para
    local pb = self.sentences[b] and self.sentences[b].para
    return pa ~= nil and pa == pb
end

-- Labels for `targets` ({ sent, word, x, y, side, h }) from a label list.
function Pointer:_set_targets(targets, labels)
    self.targets, self.typed = {}, {}
    for k, t in ipairs(targets) do
        if labels[k] then
            t.label = labels[k]
            self.targets[#self.targets + 1] = t
        end
    end
end

-- Sentence labels (step "start", level "sentence").
function Pointer:_sentence_labels()
    self.step, self.level, self.sent = "start", "sentence", nil
    local side = self.rtl and "right" or "left"
    local targets, points = {}, {}
    for si = 1, #self.sentences do
        local wi = self:_vis(si)[1]
        local b = wi and box_of(self, wi)
        if b then
            local x = self.rtl and (b.x + b.w) or b.x
            local y = b.y + b.h / 2
            targets[#targets + 1] = { sent = si, word = wi, x = x, y = y, side = side, h = b.h }
            points[#points + 1] = { x = x, y = y }
        end
    end
    self:_set_targets(targets, M.assign(points))
end

-- Word labels of sentence si (level "word"), one per visible word; (x, y) =
-- the top centre of the word (side "top"), for visible().
function Pointer:_word_labels(si)
    self.level, self.sent = "word", si
    local vis = self:_vis(si)
    local targets = {}
    for k = 1, #vis do
        local b = box_of(self, vis[k])
        targets[k] = { sent = si, word = vis[k], x = b.x + b.w / 2, y = b.y,
                       side = "top", h = b.h }
    end
    self:_set_targets(targets, M.word_labels(#targets))
end

-- The next / previous sentence (dir) from si with a visible word in this
-- step, not before `min`.
function Pointer:_next_sent(si, dir, min)
    local j = si + dir
    while j >= (min or 1) and j <= #self.sentences do
        if #self:_vis(j) > 0 then return j end
        j = j + dir
    end
end

-- The first / last sentence of si's paragraph (consecutive equal `para`).
function Pointer:_para_bound(si, dir)
    local j = si
    while self.sentences[j + dir] and self:_same_para(j, j + dir) do j = j + dir end
    return j
end

function Pointer:_set_start(wi, si)
    self.start, self.start_sent = wi, si
    self.step = "end"
    self:_word_labels(si)
    return "start"
end

function Pointer:_done(stop)
    self.stop = stop
    self.step = "done"
    self.targets, self.typed = {}, {}
    return "done"
end

-- An arrow on the word level, at any stage. `sym` is the physical symbol; in
-- RTL ← and → swap (back = right). A move drops the typed letters.
function Pointer:_shortcut(sym)
    if self.rtl then
        if sym == "left" then sym = "right" elseif sym == "right" then sym = "left" end
    end
    local E = self.sent
    if self.step == "start" then
        if sym == "left" then
            local wi = self:_vis(E)[1]
            if wi then return self:_set_start(wi, E) end
        elseif sym == "up" then
            for j = self:_para_bound(E, -1), E do
                local wi = self:_vis(j)[1]
                if wi then return self:_set_start(wi, j) end
            end
        end
        return "ignored"
    end
    if sym == "left" then
        local vis = self:_vis(E)
        return self:_done(vis[#vis])
    elseif sym == "right" or sym == "up" then
        local j = self:_next_sent(E, sym == "right" and 1 or -1, self.start_sent)
        if not j then return "ignored" end
        self:_word_labels(j)
        return "sentence"
    elseif sym == "down" then
        for j = self:_para_bound(E, 1), E, -1 do
            local vis = self:_vis(j)
            if #vis > 0 then return self:_done(vis[#vis]) end
        end
    end
    return "ignored"
end

function Pointer:_pick(t)
    if self.level == "sentence" then
        self:_word_labels(t.sent)
        return "sentence"
    end
    if self.step == "start" then return self:_set_start(t.word, t.sent) end
    return self:_done(t.word)
end

local function continues(label, typed, sym)
    for i = 1, #typed do if label[i] ~= typed[i] then return false end end
    return label[#typed + 1] == sym
end

function Pointer:press(sym)
    if self.step == "done" then return "ignored" end
    local typed = self.typed
    if self.level == "word" and not is_letter(sym) then
        return self:_shortcut(sym)
    end
    for _, t in ipairs(self.targets) do
        if continues(t.label, typed, sym) then
            if #t.label == #typed + 1 then return self:_pick(t) end
            typed[#typed + 1] = sym
            return "prefix"
        end
    end
    if sym ~= M.BACK then return "ignored" end
    if #typed > 0 then
        typed[#typed] = nil
        return "unprefix"
    end
    if self.step == "end" then return self:_done(nil) end
    if self.level == "word" then
        self:_sentence_labels()
        return "back"
    end
    return "cancel"
end

-- The end step's range: the start word .. the last visible word of E (word
-- indices; nil outside the end step).
function Pointer:preview()
    if self.step ~= "end" or not self.start then return nil end
    local vis = self:_vis(self.sent)
    return self.start, vis[#vis] or self.start
end

-- The labels still in play: all of them, or those that continue the typed
-- prefix (the label LOGIC; what is drawn is stage() below). `typed` = how
-- many of the label's symbols are already pressed. side: "left" / "right" =
-- the label goes on that side of (x, y) (sentence labels), "top" = (x, y) is
-- the top centre of the word (word labels). h = the word's height.
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

----------------------------------------------------------------------
-- Stages: what is drawn for the typed prefix (TASK-39)
----------------------------------------------------------------------
-- The word labels are never painted whole: the tree is shown one stage at a
-- time. On the word level every piece of the current stage gets ONE small
-- badge with its letter (A, X, Y in reading order), at the start of the
-- piece's first word: its left edge (right in RTL), always ABOVE the word, in
-- the space between the lines; below it only when above would leave the
-- screen (y < 0). No underline, nothing before the word, no alternation. A
-- letter = that piece (the next stage: its sub-pieces get the badges), on the
-- last stage the word itself. B = back one stage. The sentence level is drawn
-- as before (whole labels at the sentence starts).
--
-- stage() -> st
--   st.kind  = "sentence" | "words" | "done"
--   st.typed = the typed symbols (a copy)
--   st.items:
--     sentence: the entries of visible()
--     words:    one per piece, in reading order: { symbol, word (the
--                 piece's first word), last (its last word), label (the
--                 first word's), box (its box), side ("left", RTL "right"),
--                 x (that edge of the word), d (the badge size, opts.badge),
--                 place ("above" | "below"), y (the badge's top: box.y - d
--                 above, box.y + box.h below), h (the word's height) }

local function copy_box(b) return { x = b.x, y = b.y, w = b.w, h = b.h } end

function Pointer:_badge(h)
    if self.badge then return self.badge(h) end
    return math.floor((h or 0) * M.BADGE_RATIO + 0.5)
end

function Pointer:stage()
    local typed = {}
    for i, c in ipairs(self.typed or {}) do typed[i] = c end
    if self.step == "done" then return { kind = "done", typed = typed, items = {} } end
    local vis = self:visible()
    if self.level ~= "word" then
        return { kind = "sentence", typed = typed, items = vis }
    end
    local t = #typed
    local side = self.rtl and "right" or "left"
    local items, by = {}, {}
    for _, v in ipairs(vis) do
        local sym = v.label[t + 1]
        local g = sym and by[sym]
        if sym and not g then
            local b = box_of(self, v.word)
            local d = self:_badge(b.h)
            local above = b.y - d >= 0
            g = { symbol = sym, word = v.word, label = v.label, box = copy_box(b), side = side,
                  x = self.rtl and (b.x + b.w) or b.x, d = d, h = b.h,
                  place = above and "above" or "below",
                  y = above and (b.y - d) or (b.y + b.h) }
            by[sym] = g
            items[#items + 1] = g
        end
        if g then g.last = v.word end
    end
    return { kind = "words", typed = typed, items = items }
end

return M
