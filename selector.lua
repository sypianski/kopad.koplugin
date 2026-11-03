--[[
Selector — gamepad text-selection overlay for EPUB (crengine/rolling)
documents and, through PagedOverlay below (TASK-30), PDF / DjVu pages with a
text layer, driven by the handlers in padnav.lua. Four modes: sentences
("struct", Y + D-pad), words ("walk", A + D-pad), the page's saved
highlights ("hl", Y) and "point from-to" ("point", A tapped, TASK-29 / TASK-35: pad
labels at the sentences pick the start and the end, R-stick ↓ refines a step
to a word, then it is a word walk);
R-stick ↓/↑ switches between sentence and word. The
arrows move a cursor; while A is held padnav passes range = true and an
anchor stays where the range began. Without a range the cursor crosses the
page edge in both directions.

This file owns the overlay widget and its drawing/selection logic; it does
not bind its own gamepad keys (key_events is intentionally left empty — see
`self.key_events = {}` below) — every button press is routed in from
padnav.lua, which is the canonical, up-to-date source for the key map.
]]

local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Event          = require("ui/event")
local Geom           = require("ui/geometry")
local InfoMessage    = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget     = require("ui/widget/textwidget")
local UIManager      = require("ui/uimanager")
local util           = require("util")
local _              = require("gettext")
local Screen         = Device.screen

local Pluginaro  = require("pluginaro")
local WordSource = require("paginmapo")
local Hints      = require("kopad_hints")
local PdfWords   = require("pdfwords")
local StatusBar  = require("statusbar")

local STATUS_FACE = require("ui/font"):getFace("infofont", 14)
local LABEL_FACE  = require("ui/font"):getFace("infofont", 12)

local SEL_RADIUS = 8

local function invert_rounded_rect(bb, ox, oy, x, y, w, h)
    local r = math.min(SEL_RADIUS, math.floor(w / 2), math.floor(h / 2))
    bb:invertRect(ox + x, oy + y, w, h)
    if r < 2 then return end
    for py = 0, r - 1 do
        local dy  = r - py
        local dx  = math.floor(math.sqrt(r * r - dy * dy))
        local ow  = r - dx
        if ow > 0 then
            local ay = y + py
            local by = y + h - 1 - py
            bb:invertRect(ox + x,           oy + ay, ow, 1)
            bb:invertRect(ox + x + w - ow,  oy + ay, ow, 1)
            bb:invertRect(ox + x,           oy + by, ow, 1)
            bb:invertRect(ox + x + w - ow,  oy + by, ow, 1)
        end
    end
end

----------------------------------------------------------------------
-- SelectorOverlay (display widget, no key handling)
----------------------------------------------------------------------

local SelectorOverlay = InputContainer:extend{
    name = "kopad_selector_overlay",
    doc  = nil,
    ui   = nil,
}

function SelectorOverlay:init()
    self.dimen = Geom:new{ x = 0, y = 0,
                           w = Screen:getWidth(), h = Screen:getHeight() }
    self.covers_fullscreen = false

    -- "struct" = sentences (Y + D-pad), "walk" = words (A + D-pad), "hl" =
    -- the page's saved highlights (Y), "point" = the labels of "point
    -- from-to" (A tapped; self.pointer, ends as "walk"). Opens as struct;
    -- Selector:_open_walk / _open_highlights / _open_point switch before
    -- showing it.
    self.mode = "struct"

    self.sel_sent = nil      -- first sentence of the selection
    self.sel_tail = nil      -- last sentence of the selection
    self.sel_cur = nil       -- sentence the arrows move
    self.sel_anchor = nil    -- fixed end of a sentence range (A held), nil = none

    self.ww_word = nil       -- word the arrows move in walk mode {pos0, pos1, sbox, word}
    self.ww_anchor = nil     -- fixed end of a word range (A held), nil = none

    self.hl_items = {}       -- on-screen highlights { ann, boxes, sbox }
    self.hl_cur   = 0        -- focused highlight index in mode "hl" (0 = none)

    -- RTL: reverse ↔ direction for right-to-left scripts
    local rtl_langs = { ar=true, he=true, fa=true, ur=true }
    local ok_p, props = pcall(function() return self.ui.document:getProps() end)
    local lang_raw = (ok_p and props and props.language) or ""
    local lang_base = lang_raw:lower():match("^([a-z]+)") or ""
    self.is_rtl = rtl_langs[lang_base] or false

    self:_collect()
    self:_collect_highlights()
    if #self.sentences > 0 then self:_set_sent(1) end
end

function SelectorOverlay:_collect()
    local screen_h = Screen:getHeight()
    local ok_w, words = pcall(WordSource.collect_words, self.doc, screen_h)
    self.words = (ok_w and words) or {}

    local ok_s, sents = pcall(WordSource.collect_sentences_from_words, self.words)
    self.sentences = (ok_s and sents) or {}

    -- Complete first sentence if page starts mid-sentence.
    if #self.sentences > 0 and #self.words > 0 then
        local ok_clean, page_clean = pcall(
            WordSource.page_starts_at_boundary, self.doc)
        if ok_clean and not page_clean then
            local ok_start, start_xp = pcall(
                WordSource.find_sentence_start, self.doc, self.words[1].xp0)
            if ok_start and start_xp then
                self.sentences[1].xp0 = start_xp
                self.sentences[1]._extends_before = true
            end
        end
    end

    -- Extend last sentence if it continues off-screen.
    if #self.sentences > 0 and #self.words > 0 then
        local lw    = self.words[#self.words]
        local inter = lw.inter or ""
        local has_end = inter:find("[%.!%?]")
                     or inter:find("\xD8\x9F")
                     or inter:find("\xDB\x94")
                     or inter:find("\n")
        if not has_end and lw.next_xp0 then
            local ok, end_xp1 = pcall(
                WordSource.find_sentence_end, self.doc, lw.next_xp0, lw.xp0)
            if ok and end_xp1 then
                self.sentences[#self.sentences].xp1 = end_xp1
                self.sentences[#self.sentences]._extends_after = true
            end
        end
    end

    -- map word xpointer → sentence index for O(1) lookup
    self._xp_to_sent = {}
    for si, sent in ipairs(self.sentences) do
        if sent.word_list then
            for _, witem in ipairs(sent.word_list) do
                self._xp_to_sent[witem.xp0] = si
            end
        end
    end

    -- map each word index → parent sentence index
    self.word_to_sent = {}
    for wi, w in ipairs(self.words) do
        self.word_to_sent[wi] = self._xp_to_sent[w.xp0]
    end
end

function SelectorOverlay:_collect_highlights()
    self.hl_items = {}
    self.hl_cur   = 0
    local anns = self.ui and self.ui.annotation and self.ui.annotation.annotations
    if not anns then return end
    local sh = Screen:getHeight()
    for _, ann in ipairs(anns) do
        if ann.pos0 and ann.pos1 then
            local ok, boxes = pcall(function()
                return self.doc:getScreenBoxesFromPositions(ann.pos0, ann.pos1, true)
            end)
            if ok and boxes and #boxes > 0 then
                local on_screen, min_y, sbox = false, math.huge, nil
                for _, b in ipairs(boxes) do
                    if b.y < sh and b.y + b.h > 0 then
                        on_screen = true
                        if b.y < min_y then min_y = b.y; sbox = b end
                    end
                end
                if on_screen and sbox then
                    table.insert(self.hl_items, { ann = ann, boxes = boxes, sbox = sbox })
                end
            end
        end
    end
    table.sort(self.hl_items, function(a, b) return a.sbox.y < b.sbox.y end)
end

function SelectorOverlay:_nearest_word(px, py)
    local best, best_dist = 1, math.huge
    for i, w in ipairs(self.words) do
        if w.sbox then
            local wx = w.sbox.x + w.sbox.w / 2
            local wy = w.sbox.y + w.sbox.h / 2
            local d = (wx - px)^2 + (wy - py)^2
            if d < best_dist then
                best = i; best_dist = d
            end
        end
    end
    return best
end

function SelectorOverlay:_refresh()
    UIManager:setDirty("all", "ui")
end

----------------------------------------------------------------------
-- Word walk navigation
----------------------------------------------------------------------

function SelectorOverlay:_is_split_word(word)
    if not word or not word.pos0 or not word.pos1 then return false end
    if word.segments then
        return #word.segments > 1 and word.segments[1].y ~= word.segments[#word.segments].y
    end
    local ok, segs = pcall(function()
        return self.doc:getScreenBoxesFromPositions(word.pos0, word.pos1, true)
    end)
    if not ok or not segs or #segs == 0 then return false end
    word.segments = segs
    return #segs > 1 and segs[1].y ~= segs[#segs].y
end

-- Determine correct fragment (head/tail) of a split hyphenated word from probe x position.
-- LTR: right side = head (end of line). RTL: right side = tail (start of next line).
-- Returns: word (with is_split_fragment set), eval_y for Y-clamp check.
function SelectorOverlay:_resolve_split_fragment(word, x_pos)
    if not self:_is_split_word(word) then
        return word, word.sbox.y + word.sbox.h * 0.5
    end
    local right_half = x_pos > (word.sbox.x + word.sbox.w * 0.5)
    local is_head = self.is_rtl ~= right_half
    word.is_split_fragment = is_head and "head" or "tail"
    local fbox = is_head and word.segments[1] or word.segments[#word.segments]
    return word, fbox.y + fbox.h * 0.5
end

function SelectorOverlay:_ww_fragment_sbox()
    local w = self.ww_word
    if not w then return nil end
    if w.is_split_fragment and w.segments and #w.segments > 0 then
        if w.is_split_fragment == "head" then return w.segments[1] end
        return w.segments[#w.segments]
    end
    return w.sbox
end

function SelectorOverlay:_ww_word_from_xp(xp)
    local doc = self.doc
    local end_xp = doc:getNextVisibleWordEnd(xp)
    if not end_xp then return nil end
    local ok, boxes = pcall(function()
        return doc:getScreenBoxesFromPositions(xp, end_xp, true)
    end)
    if not ok or not boxes or #boxes == 0 then return nil end
    local sbox = Geom.boundingBox(boxes)
    if not sbox then return nil end
    local ok2, text = pcall(function()
        return doc:getTextFromXPointers(xp, end_xp)
    end)
    return {
        pos0 = xp, pos1 = end_xp, sbox = sbox,
        word = (ok2 and text) or "", segments = boxes,
    }
end

-- Land on the first (dir > 0) or the last word of the page.
function SelectorOverlay:_ww_land(dir)
    local w = self.words[dir > 0 and 1 or #self.words]
    self.ww_word = w and self:_ww_word_from_xp(w.xp0) or nil
    if self.ww_word and self:_is_split_word(self.ww_word) then
        self.ww_word.is_split_fragment = dir > 0 and "head" or "tail"
    end
end

-- True when xpointer a comes before b in the document.
-- CreDocument:compareXPointers(a, b) is 1 when b follows a (ReaderHighlight
-- relies on the same sign).
function SelectorOverlay:_xp_before(a, b)
    local ok, order = pcall(self.doc.compareXPointers, self.doc, a, b)
    return ok and type(order) == "number" and order > 0
end

-- The word selection as xpointers: the cursor word, or anchor .. cursor in
-- document order.
function SelectorOverlay:_ww_span()
    local w, a = self.ww_word, self.ww_anchor
    if not w then return nil end
    if not a or a.pos0 == w.pos0 then return w.pos0, w.pos1 end
    if self:_xp_before(a.pos0, w.pos0) then return a.pos0, w.pos1 end
    return w.pos0, a.pos1
end

-- Start of the next (dir > 0) / previous word, nil at the end of the book.
-- (Not `dir > 0 and next() or prev()`: a nil next word would fall through to
-- the previous one.)
function SelectorOverlay:_adjacent_word(xp, dir)
    if dir > 0 then return self.doc:getNextVisibleWordStart(xp) end
    return self.doc:getPrevVisibleWordStart(xp)
end

-- Turn the page under the overlay and collect the new one. False when the
-- document did not move (first / last page).
function SelectorOverlay:_turn_page(dir)
    local before = self.words[1] and self.words[1].xp0
    self.ui:handleEvent(Event:new("GotoViewRel", dir))
    self:_collect()
    self:_collect_highlights()
    local after = self.words[1] and self.words[1].xp0
    return before == nil or after ~= before
end

-- Words: one word forward / back (dir in document order). range (A held):
-- the anchor stays where the range began and the range never leaves the
-- page; otherwise the page edge turns the page (TASK-18).
function SelectorOverlay:_ww_step(dir, range)
    local w = self.ww_word
    if not w then
        if not range and self:_turn_page(dir) then self:_ww_land(dir) end
        return
    end
    if range then
        self.ww_anchor = self.ww_anchor or w
    else
        self.ww_anchor = nil
        -- a word hyphenated over two lines: its other half first
        if self:_is_split_word(w) and w.is_split_fragment then
            if dir > 0 and w.is_split_fragment == "head" then
                w.is_split_fragment = "tail"; return
            elseif dir < 0 and w.is_split_fragment == "tail" then
                w.is_split_fragment = "head"; return
            end
        end
    end
    local xp = self:_adjacent_word(w.pos0, dir)
    if not xp or xp == w.pos0 or not self.doc:isXPointerInCurrentPage(xp) then
        if not range and self:_turn_page(dir) then self:_ww_land(dir) end
        return
    end
    local nw = self:_ww_word_from_xp(xp)
    if not nw then return end
    if not range and self:_is_split_word(nw) then
        nw.is_split_fragment = dir > 0 and "head" or "tail"
    end
    self.ww_word = nw
end

-- Words: the word on the next / previous line nearest to the same x. Past
-- the last / first line: the next page's first word / the previous page's
-- last one (TASK-18); a range (A held) stays on the page.
function SelectorOverlay:_ww_line(delta, range)
    if not self.ww_word or not self.ww_word.sbox then
        if not range and self:_turn_page(delta) then self:_ww_land(delta) end
        return
    end
    if range then
        self.ww_anchor = self.ww_anchor or self.ww_word
    else
        self.ww_anchor = nil
    end
    local doc    = self.doc
    local fsbox  = self:_ww_fragment_sbox() or self.ww_word.sbox
    local target_x = fsbox.x
    -- getScreenPositionFromXPointer gives the TOP of a word's line, so lines
    -- are compared through that same call (start_y = the cursor's line):
    -- against the box middle, the word on the left counted as the line above
    -- and ↑ moved by one word. A split word's tail sits on another line than
    -- its pos0, so there the fragment box is the reference.
    local line_h   = fsbox.h
    local line_tol = line_h * 0.3
    local start_y  = self.ww_word.is_split_fragment ~= "tail"
        and doc:getScreenPositionFromXPointer(self.ww_word.pos0) or nil
    start_y = start_y or fsbox.y
    local box_dy = fsbox.y - start_y  -- line top -> word box top

    local current_xp    = self.ww_word.pos0
    local target_line_y = nil
    local fallback_xp   = nil
    for _ = 1, 80 do
        local next_xp = self:_adjacent_word(current_xp, delta)
        if not next_xp or next_xp == current_xp then break end
        if not doc:isXPointerInCurrentPage(next_xp) then break end
        current_xp = next_xp
        local sy = doc:getScreenPositionFromXPointer(next_xp)
        if not sy then break end
        if (delta > 0 and sy > start_y + line_tol)
            or (delta < 0 and sy < start_y - line_tol) then
            target_line_y = sy
            fallback_xp   = next_xp
            break
        end
    end
    if not target_line_y then
        if not range and self:_turn_page(delta) then self:_ww_land(delta) end
        return
    end

    -- Probe the middle of the target line (target_line_y is its top).
    local probe_y = target_line_y + box_dy + line_h * 0.5
    local ok, probe = pcall(function()
        return doc:getWordFromPosition({x = target_x, y = probe_y}, true)
    end)
    if ok and probe and probe.pos0 and probe.pos0 ~= self.ww_word.pos0 then
        local ok2, boxes = pcall(function()
            return doc:getScreenBoxesFromPositions(probe.pos0, probe.pos1, true)
        end)
        if ok2 and boxes and #boxes > 0 then
            local sbox = Geom.boundingBox(boxes)
            if sbox then
                probe.sbox = sbox; probe.segments = boxes
                local resolved, eval_y = self:_resolve_split_fragment(probe, target_x)
                if math.abs(eval_y - probe_y) <= line_tol then
                    self.ww_word = {
                        pos0 = resolved.pos0, pos1 = resolved.pos1,
                        sbox = sbox, word = resolved.word or "",
                        segments = boxes,
                        is_split_fragment = resolved.is_split_fragment,
                    }
                    return
                end
            end
        end
    end

    local word = self:_ww_word_from_xp(fallback_xp)
    if word then self.ww_word = word end
end

----------------------------------------------------------------------
-- Sentence navigation (struct)
----------------------------------------------------------------------

-- Move the sentence cursor to i; with an anchor the selection spans both.
function SelectorOverlay:_set_sent(i)
    self.sel_cur = i
    local a = self.sel_anchor or i
    self.sel_sent, self.sel_tail = math.min(a, i), math.max(a, i)
end

-- After a page turn: the first (dir > 0) / last sentence of the new page, or
-- the one after / before it when `skip` -- that one is the sentence the
-- cursor was on, running over the page edge.
function SelectorOverlay:_sent_land(dir, skip)
    local n = #self.sentences
    self.sel_anchor = nil
    if n == 0 then
        self.sel_cur, self.sel_sent, self.sel_tail = nil, nil, nil
        return
    end
    local i = dir > 0 and 1 or n
    if skip and n > 1 then i = i + dir end
    self:_set_sent(i)
end

-- Sentences: one sentence forward / back; past the page edge the next /
-- previous page (TASK-18). range (A held) stays on the page.
function SelectorOverlay:_sent_step(dir, range)
    local cur = self.sel_cur
    if not cur or #self.sentences == 0 then
        if not range and self:_turn_page(dir) then self:_sent_land(dir, false) end
        return
    end
    if range then
        self.sel_anchor = self.sel_anchor or cur
    else
        self.sel_anchor = nil
    end
    local new = cur + dir
    if new >= 1 and new <= #self.sentences then
        self:_set_sent(new)
        return
    end
    if range then return end
    local s = self.sentences[cur]
    local split = (dir > 0 and s._extends_after) or (dir < 0 and s._extends_before)
    if self:_turn_page(dir) then self:_sent_land(dir, split) end
end

-- First sentence of the paragraph of sentence i.
function SelectorOverlay:_para_start(i)
    local p = self.sentences[i].para
    while i > 1 and self.sentences[i - 1].para == p do i = i - 1 end
    return i
end

-- Paragraph target on the page: ↓ = first sentence of the next paragraph;
-- ↑ = first sentence of this paragraph, or of the previous one when already
-- there. nil = beyond the page.
function SelectorOverlay:_para_target(cur, dir)
    local s = self.sentences
    if dir > 0 then
        for j = cur + 1, #s do
            if s[j].para ~= s[cur].para then return j end
        end
        return nil
    end
    local start = self:_para_start(cur)
    if start < cur then return start end
    if start > 1 then return self:_para_start(start - 1) end
    return nil
end

-- After a page turn by paragraph: ↓ the first sentence of the new page (the
-- next paragraph on it when `skip`: the cursor's sentence ran over the edge,
-- so the page starts inside its paragraph); ↑ the start of the page's last
-- paragraph.
function SelectorOverlay:_para_land(dir, skip)
    self.sel_anchor = nil
    local i = self:_para_land_index(dir, skip)
    if not i then
        self.sel_cur, self.sel_sent, self.sel_tail = nil, nil, nil
        return
    end
    self:_set_sent(i)
end

-- The sentence _para_land lands on (nil on a page without sentences).
function SelectorOverlay:_para_land_index(dir, skip)
    local n = #self.sentences
    if n == 0 then return nil end
    if dir > 0 then return skip and self:_para_target(1, 1) or 1 end
    return self:_para_start(n)
end

-- Sentences: paragraph down / up (see _para_target); past the page edge the
-- next / previous page (TASK-18). range (A held) stays on the page.
function SelectorOverlay:_para_step(dir, range)
    local cur = self.sel_cur
    if not cur or #self.sentences == 0 then
        if not range and self:_turn_page(dir) then self:_para_land(dir, false) end
        return
    end
    if range then
        self.sel_anchor = self.sel_anchor or cur
    else
        self.sel_anchor = nil
    end
    local target = self:_para_target(cur, dir)
    if target then
        self:_set_sent(target)
        return
    end
    if range then return end
    -- no paragraph below: the cursor is in the page's last paragraph, which
    -- goes on over the edge when the last sentence does
    local split = dir > 0 and self.sentences[#self.sentences]._extends_after
    if self:_turn_page(dir) then self:_para_land(dir, split) end
end

-- Sentence (index) that contains the walk word w: by its xpointer, else the
-- sentence of the nearest collected word on screen.
function SelectorOverlay:_sent_of_word(w)
    local i = self._xp_to_sent[w.pos0]
    if i then return i end
    if not w.sbox or #self.words == 0 then return nil end
    local wi = self:_nearest_word(w.sbox.x + w.sbox.w / 2, w.sbox.y + w.sbox.h / 2)
    return self.word_to_sent[wi]
end

-- The walk word at the start of sentence i (nil when it cannot be built).
function SelectorOverlay:_sent_first_word(i)
    local s = self.sentences[i]
    local w = s and s.word_list and s.word_list[1]
    return w and self:_ww_word_from_xp(w.xp0) or nil
end

-- Words, LT / RT (TASK-25): the first word of the next paragraph; back = the
-- first word of this paragraph, or of the previous one when the cursor is
-- already there. Past the page edge the next / previous page, landing as
-- _para_land does. range (A held) stays on the page.
function SelectorOverlay:_ww_para(dir, range)
    local w = self.ww_word
    local cur = w and self:_sent_of_word(w)
    if not cur then
        if not range and self:_turn_page(dir) then
            self.ww_anchor = nil
            local i = self:_para_land_index(dir, false)
            self.ww_word = i and self:_sent_first_word(i) or nil
        end
        return
    end
    if range then
        self.ww_anchor = self.ww_anchor or w
    else
        self.ww_anchor = nil
    end
    local target
    if dir > 0 then
        target = self:_para_target(cur, 1)
    else
        local start = self:_para_start(cur)
        local first = self:_sent_first_word(start)
        if start < cur or (first and first.pos0 ~= w.pos0) then
            target = start
        else
            target = self:_para_target(cur, -1)
        end
        -- the page's first sentence began on the previous page, so its
        -- paragraph did too: the jump goes there, to the real start
        if target == 1 and self.sentences[1]._extends_before then target = nil end
    end
    local tw = target and self:_sent_first_word(target)
    if tw then
        self.ww_word = tw
        return
    end
    if range then return end
    local split = dir > 0 and self.sentences[#self.sentences]._extends_after
    if self:_turn_page(dir) then
        self.ww_anchor = nil
        local i = self:_para_land_index(dir, split)
        self.ww_word = i and self:_sent_first_word(i) or nil
    end
end

----------------------------------------------------------------------
-- Arrows and levels (called by padnav)
----------------------------------------------------------------------

-- Saved highlights (mode "hl"): the next / previous one, wrapping.
function SelectorOverlay:_hl_step(dir)
    local n = #self.hl_items
    if n == 0 then return end
    self.hl_cur = (self.hl_cur - 1 + dir) % n + 1
end

-- ←/→: one word / sentence / highlight. dir in document order (+1 =
-- forward; padnav has already flipped it for RTL). range = A held: the anchor
-- stays, the cursor moves, both directions (back over the anchor shrinks the
-- range and then grows it on the other side).
function SelectorOverlay:step(dir, range)
    if self.mode == "point" then return end
    if self.mode == "hl" then
        self:_hl_step(dir)
    elseif self.mode == "walk" then
        self:_ww_step(dir, range)
    else
        self:_sent_step(dir, range)
    end
    self:_refresh()
end

-- ↑/↓: one line / paragraph / highlight; range as in step().
function SelectorOverlay:line(dir, range)
    if self.mode == "point" then return end
    if self.mode == "hl" then
        self:_hl_step(dir)
    elseif self.mode == "walk" then
        self:_ww_line(dir, range)
    else
        self:_para_step(dir, range)
    end
    self:_refresh()
end

-- LT / RT (TASK-25): one paragraph, at every level -- the first word of the
-- next / this or previous paragraph, the same for sentences as ↑/↓, the
-- next / previous highlight.
function SelectorOverlay:para(dir, range)
    if self.mode == "point" then return end
    if self.mode == "hl" then
        self:_hl_step(dir)
    elseif self.mode == "walk" then
        self:_ww_para(dir, range)
    else
        self:_para_step(dir, range)
    end
    self:_refresh()
end

-- R-stick ↓ in sentences (TASK-17): the first word of the cursor's sentence,
-- as a word walk. A range is dropped.
function SelectorOverlay:to_words()
    if self.mode ~= "struct" then return end
    local ww = self.sel_cur and self:_sent_first_word(self.sel_cur)
    if not ww then return end
    self.mode = "walk"
    self.ww_word, self.ww_anchor, self.sel_anchor = ww, nil, nil
    self:_refresh()
end

-- R-stick ↑ in words (TASK-17): the sentence that contains the cursor word.
function SelectorOverlay:to_sentences()
    if self.mode ~= "walk" or not self.ww_word then return end
    local i = self:_sent_of_word(self.ww_word)
    if not i then return end
    self.mode = "struct"
    self.ww_anchor, self.sel_anchor = nil, nil
    self:_set_sent(i)
    self:_refresh()
end

----------------------------------------------------------------------
-- Point from-to (TASK-29, on sentences since TASK-35 / PC-022)
----------------------------------------------------------------------
-- Adapter of kopad_hints.lua, the same for EPUB and PDF: the word boxes are
-- the screen boxes of self.words (reading order; nil off the screen), the
-- sentences are word-index ranges built from self.word_to_sent (paginmapo
-- in an EPUB, pdfwords.sentences in a PDF). Only the words on the page are
-- in self.words, so a sentence over the page edge is labelled at its
-- visible part. kopad_hints.lua itself knows no document.

-- The page's sentences as { first, last } word indices, in reading order.
function SelectorOverlay:_point_sentences()
    local by, order = {}, {}
    for wi = 1, #self.words do
        local si = self.word_to_sent and self.word_to_sent[wi]
        if si then
            local s = by[si]
            if not s then
                s = { first = wi, last = wi, si = si }
                by[si] = s
                order[#order + 1] = s
            end
            if wi < s.first then s.first = wi end
            if wi > s.last then s.last = wi end
        end
    end
    table.sort(order, function(a, b) return a.si < b.si end)
    return order
end

-- Labels at the sentence starts of the page. False when the page has no
-- text (no sentence with a word on the screen).
function SelectorOverlay:_point_begin()
    local boxes = {}
    for i, w in ipairs(self.words) do boxes[i] = w.sbox or false end
    local pointer = Hints.Pointer.new(self:_point_sentences(), boxes, { rtl = self.is_rtl })
    if #pointer:visible() == 0 then return false end
    self.mode = "point"
    self.pointer = pointer
    self.ww_word, self.ww_anchor = nil, nil
    return true
end

-- One pad symbol (Hints.SYMBOLS: "up" .. "right", "A", "B", "X", "Y").
-- Returns the pointer's result (kopad_hints.lua); "cancel" = padnav closes the
-- overlay. "done" turns the overlay into a word walk.
function SelectorOverlay:point_press(sym)
    local p = self.pointer
    if self.mode ~= "point" or not p then return "ignored" end
    local res = p:press(sym)
    if res == "done" then self:_point_finish() end
    if res ~= "ignored" and res ~= "cancel" then self:_refresh() end
    return res
end

-- R-stick ↓ (on) / ↑ (off) in the labels: refinement to the word in the
-- current step (PC-022). True when the labels or the status line changed.
function SelectorOverlay:point_refine(on)
    local p = self.pointer
    if self.mode ~= "point" or not p then return false end
    local changed = p:refine_to_word(on)
    if changed then self:_refresh() end
    return changed
end

-- The chosen words as a word walk: anchor = the start word (a sentence's
-- first word, or the refined word), cursor = the end word (A + arrows move
-- the cursor, A tapped = the action menu); no end = the start word alone.
function SelectorOverlay:_point_finish()
    local p = self.pointer
    self.pointer = nil
    self.mode = "walk"
    local w0 = p.start and self.words[p.start]
    local first = w0 and self:_ww_word_from_xp(w0.xp0)
    if not first then return end
    local w1 = p.stop and self.words[p.stop]
    local last = w1 and w1 ~= w0 and self:_ww_word_from_xp(w1.xp0)
    if last then
        self.ww_anchor, self.ww_word = first, last
    else
        self.ww_anchor, self.ww_word = nil, first
    end
end

----------------------------------------------------------------------
-- Action menu (A tapped)
----------------------------------------------------------------------

function SelectorOverlay:action_menu()
    if self.mode == "point" then return end
    local sel = self:_get_selection()
    if not sel then return end

    local ButtonDialog = require("ui/widget/buttondialog")
    local overlay = self

    local dlg
    local buttons = {
            {
                {
                    text = _("Dictionary"),
                    callback = function()
                        UIManager:close(dlg)
                        overlay:_do_dict(sel)
                    end,
                },
                {
                    text = _("Copy"),
                    callback = function()
                        UIManager:close(dlg)
                        overlay:_do_copy(sel)
                    end,
                },
            },
            {
                {
                    text = _("Highlight"),
                    callback = function()
                        UIManager:close(dlg)
                        overlay:_do_highlight(sel)
                    end,
                },
                {
                    text = _("Note"),
                    callback = function()
                        UIManager:close(dlg)
                        overlay:_do_note(sel)
                    end,
                },
            },
            {
                {
                    text = _("AI explain"),
                    callback = function()
                        UIManager:close(dlg)
                        overlay:_do_ai(sel)
                    end,
                },
                {
                    text = _("Vortuyo"),
                    callback = function()
                        UIManager:close(dlg)
                        overlay:_do_vortuyo(sel)
                    end,
                },
            },
    }
    local rows = {}
    for k = 1, 3 do
        local row = buttons[k]
        if row then rows[#rows + 1] = row end
    end
    dlg = ButtonDialog:new{
        -- read only by wheel.lua: the wheel's title (TASK-20)
        _kopad_snippet = sel.text,
        buttons = rows,
    }
    UIManager:show(dlg)
end

----------------------------------------------------------------------
-- Selection helpers
----------------------------------------------------------------------

function SelectorOverlay:_get_selection()
    if self.mode == "point" then return nil end
    if self.mode == "hl" then
        local item = self.hl_items[self.hl_cur]
        if not item then return nil end
        local ann = item.ann
        local ok, text = pcall(function()
            return self.doc:getTextFromXPointers(ann.pos0, ann.pos1)
        end)
        return { text = (ok and text) or "", pos0 = ann.pos0, pos1 = ann.pos1,
                 sboxes = item.boxes }
    end
    local xp0, xp1
    if self.mode == "walk" then
        xp0, xp1 = self:_ww_span()
        if not xp0 then return nil end
    else
        local head = self.sel_sent and self.sentences[self.sel_sent]
        local tail = head and self.sentences[self.sel_tail or self.sel_sent]
        if not head or not tail then return nil end
        xp0, xp1 = head.xp0, tail.xp1
    end

    local ok, text = pcall(function()
        return self.doc:getTextFromXPointers(xp0, xp1)
    end)
    if not ok or not text or text == "" then
        if self.mode ~= "walk" then return nil end
        text = self.ww_word.word
    end
    local ok2, boxes = pcall(function()
        return self.doc:getScreenBoxesFromPositions(xp0, xp1, true)
    end)
    return { text = text, pos0 = xp0, pos1 = xp1,
             sboxes = ok2 and boxes or nil }
end

----------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------

function SelectorOverlay:_do_dict(sel)
    local word = util.cleanupSelectedText(sel.text)
    if word == "" then return end
    local dict = self.ui.dictionary
    if not dict then return end
    -- Plugins hooking the popup (Vortpaf) read the occurrence from
    -- highlight.selected_text, which only a tap/hold sets; publish it for the
    -- synchronous popup setup, then drop it so it cannot go stale.
    local rh = self.ui.highlight
    if rh and not rh.selected_text and type(sel.pos0) == "string" then
        rh.selected_text = sel
        UIManager:nextTick(function()
            if rh.selected_text == sel then rh.selected_text = nil end
        end)
    end
    dict:onLookupWord(word, false, sel.sboxes, rh)
    self:_hook_dict_widget(sel)
end

-- Inject gamepad handlers onto the DictQuickLookup widget after it is shown.
-- This bypasses the modal-stack routing problem: the dict consumes key events
-- before active_widgets (PadNav) see them, so we patch the widget directly.
-- Needed on the LEGACY key path only: on KOReader >= 2026.07 PadNav handles Y
-- itself (PadNav:_dict_button) and LB/RB are the popup's own stock keys.
-- DictQuickLookup has no `name` field; open popups are listed in the
-- class-level DictQuickLookup.window_list.
function SelectorOverlay:_hook_dict_widget(sel)
    local ok, DQL = pcall(require, "ui/widget/dictquicklookup")
    local list = ok and type(DQL) == "table" and DQL.window_list
    if type(list) ~= "table" then return end
    for i = #list, 1, -1 do
        local w = list[i]
        if type(w) == "table" then
            if not w.key_events then w.key_events = {} end
            local overlay = self

            -- Y → AI explain (close dict first so AI viewer can open)
            w.key_events.KopadDictAI = { { "ContextMenu" } }
            function w:onKopadDictAI()
                local s = overlay:_get_selection()
                UIManager:close(self)
                if s then overlay:_do_ai(s) end
                return true
            end

            -- RB → next dictionary result
            w.key_events.KopadDictNext = { { "RPgFwd" } }
            function w:onKopadDictNext()
                if self.onSwipe then self:onSwipe(nil, { direction = "west" }) end
                return true
            end

            -- LB → previous dictionary result
            w.key_events.KopadDictPrev = { { "RPgBack" } }
            function w:onKopadDictPrev()
                if self.onSwipe then self:onSwipe(nil, { direction = "east" }) end
                return true
            end

            return
        end
    end
end

function SelectorOverlay:_do_copy(sel)
    if Device.input and Device.input.setClipboardText then
        Device.input.setClipboardText(util.cleanupSelectedText(sel.text))
        UIManager:show(InfoMessage:new{ text = _("Copied"), timeout = 1 })
    end
end

function SelectorOverlay:_do_highlight(sel)
    local rh = self.ui.highlight
    if not rh then return end
    rh.selected_text = sel
    rh:saveHighlight(false)
    rh.selected_text = nil
end

-- X button: add highlight if none exists for this selection, remove if it does.
function SelectorOverlay:_do_toggle_highlight(sel)
    local annots = self.ui.annotation and self.ui.annotation.annotations
    if annots then
        for i, a in ipairs(annots) do
            if a.pos0 == sel.pos0 and a.pos1 == sel.pos1 then
                table.remove(annots, i)
                self.ui:handleEvent(Event:new("AnnotationsModified",
                    { a, nb_highlights_added = -1,
                      nb_notes_added = a.note and -1 or 0 }))
                UIManager:show(InfoMessage:new{ text = _("Highlight removed"), timeout = 1 })
                -- Rebuild hl_items so the deleted highlight is no longer drawn,
                -- focusable or actionable (otherwise X could re-add it and Y
                -- would run on a now-gone annotation). Browsing highlights,
                -- the focus stays in place; 0 = none left (padnav closes).
                local cur = self.hl_cur
                self:_collect_highlights()
                if self.mode == "hl" then self.hl_cur = math.min(cur, #self.hl_items) end
                self:_refresh()
                return
            end
        end
    end
    self:_do_highlight(sel)
    -- the new highlight gets its margin dot
    self:_collect_highlights()
    self:_refresh()
end

-- The annotation index a note goes to: a new highlight of the selection
-- (PagedOverlay: the browsed highlight itself in mode "hl").
function SelectorOverlay:_note_target(sel)
    local rh = self.ui.highlight
    if not rh then return nil end
    rh.selected_text = sel
    local ok, index = pcall(rh.saveHighlight, rh, true)
    rh.selected_text = nil
    if ok then return index end
end

-- After a note was saved (PagedOverlay: write it into the PDF, refresh).
function SelectorOverlay:_note_saved() end

function SelectorOverlay:_do_note(sel)
    local index = self:_note_target(sel)
    if not index then return end
    local ui, overlay = self.ui, self
    local InputDialog = require("ui/widget/inputdialog")
    local dlg
    dlg = InputDialog:new{
        title = _("Note"),
        input = "",
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dlg) end,
            },
            {
                text = _("Save"),
                is_enter_default = true,
                callback = function()
                    local note = dlg:getInputText()
                    UIManager:close(dlg)
                    if note == "" then return end
                    local a = ui.annotation.annotations[index]
                    if a then
                        -- a highlight that already had a note stays one
                        local had = a.note ~= nil and a.note ~= ""
                        a.note = note
                        ui:handleEvent(Event:new("AnnotationsModified",
                            { a, nb_highlights_added = had and 0 or -1,
                              nb_notes_added = had and 0 or 1 }))
                        overlay:_note_saved(a, note)
                    end
                end,
            },
        }},
    }
    UIManager:show(dlg)
end

-- The text of the collected page (the AI passage), nil when none.
function SelectorOverlay:_page_text()
    if not self.words or #self.words == 0 then return nil end
    local ok_p, p = pcall(function()
        return self.doc:getTextFromXPointers(
            self.words[1].xp0, self.words[#self.words].xp1)
    end)
    if ok_p and p and p ~= "" then return p end
end

function SelectorOverlay:_do_ai(sel)
    local text = util.cleanupSelectedText(sel.text)
    if text == "" then return end

    local passage = self:_page_text() or sel.text

    local assistant = self.ui and self.ui.assistant
    local lang = (assistant and assistant.ui_language) or "English"
    local messages = {
        { role = "system",
          content = "You are a concise literary assistant. Be brief and direct." },
        { role = "user",
          content = "Briefly explain this passage. Note difficult words. Answer in "
                 .. lang .. ". 2-4 sentences.\n\nPassage:\n" .. passage },
    }

    -- Own transport when configured, assistant.koplugin as fallback (see lib/llm.lua).
    require("llm").ask(self.ui, messages, { title = _("AI"), err_timeout = 2 })
end

function SelectorOverlay:_do_vortuyo(sel)
    local word = util.cleanupSelectedText(sel.text)
    if word == "" then return end
    local vortuyo = self.ui and self.ui.vortpaf
    if not vortuyo then
        UIManager:show(InfoMessage:new{ text = _("Vortuyo not available"), timeout = 2 })
        return
    end
    -- The occurrence being looked up: Vortpaf anchors the margin gloss at
    -- this xpointer (EPUB / rolling only; a paged selection has table
    -- positions) and puts the definition card next to its screen rows.
    local xpointer = type(sel.pos0) == "string" and sel.pos0 or nil
    local anchor
    if type(sel.sboxes) == "table" and #sel.sboxes > 0 then
        local y0, y1 = math.huge, -math.huge
        for _, b in ipairs(sel.sboxes) do
            y0 = math.min(y0, b.y)
            y1 = math.max(y1, b.y + b.h)
        end
        anchor = { y0 = y0, y1 = y1 }
    end
    vortuyo:_vortpafLookup(word, nil, xpointer, nil, nil, anchor)
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

function SelectorOverlay:paintTo(bb, x, y)
    if self.mode == "point" then
        -- status first: the labels of the top line may reach under it
        self:_draw_status(bb, x, y)
        self:_draw_point(bb, x, y)
        return
    elseif self.mode == "walk" then
        self:_draw_walk(bb, x, y)
    else
        self:_draw_struct(bb, x, y)
        self:_draw_hl_marks(bb, x, y)
    end
    self:_draw_status(bb, x, y)
end

function SelectorOverlay:_draw_walk(bb, ox, oy)
    if self.ww_anchor and self.ww_word then
        local p0, p1 = self:_ww_span()
        local ok, boxes = pcall(function()
            return self.doc:getScreenBoxesFromPositions(p0, p1, true)
        end)
        if ok and boxes then
            for _, b in ipairs(boxes) do
                invert_rounded_rect(bb, ox, oy, b.x, b.y, b.w, b.h)
            end
        end
        return
    end
    local s = self:_ww_fragment_sbox()
    if not s then return end
    invert_rounded_rect(bb, ox, oy, s.x, s.y, s.w, s.h)
end

-- The selected sentences (struct) or the focused saved highlight (hl).
function SelectorOverlay:_draw_struct(bb, ox, oy)
    if self.mode == "hl" then
        local item = self.hl_items[self.hl_cur]
        if item then
            for _, b in ipairs(item.boxes) do
                invert_rounded_rect(bb, ox, oy, b.x, b.y, b.w, b.h)
            end
        end
        return
    end

    if not self.sel_sent then return end
    local head = self.sentences[self.sel_sent]
    local tail = self.sentences[self.sel_tail or self.sel_sent]
    if not head or not tail then return end

    local ok, boxes = pcall(function()
        return self.doc:getScreenBoxesFromPositions(head.xp0, tail.xp1, true)
    end)
    if ok and boxes then
        for _, b in ipairs(boxes) do
            invert_rounded_rect(bb, ox, oy, b.x, b.y, b.w, b.h)
        end
    end
end

-- Saved highlights on the page: a dot in the right margin next to each one,
-- the focused one (hl_cur, browsed with Y and the D-pad) filled, the others a
-- ring. No numbers and no sentence labels: the pad has no digit input (visel's
-- labels are there to be typed) and the selection itself is inverted (TASK-14).
function SelectorOverlay:_draw_hl_marks(bb, ox, oy)
    if #self.hl_items == 0 then return end
    local sh = Screen:getHeight()
    local sw = Screen:getWidth()
    local page_right = 0
    for _, item in ipairs(self.hl_items) do
        for _, b in ipairs(item.boxes) do
            local edge = b.x + b.w
            if edge > page_right then page_right = edge end
        end
    end
    local margin = sw - page_right
    if margin < 8 then return end
    local r = math.min(Screen:scaleBySize(5), math.floor(margin / 2) - 2)
    if r < 3 then return end
    local cx = ox + page_right + math.floor(margin / 2)

    for i, item in ipairs(self.hl_items) do
        local sbox = item.sbox -- nil: off the screen (PDF zoomed in)
        if sbox and sbox.y >= 0 and sbox.y < sh then
            local cy = oy + sbox.y + math.floor(sbox.h / 2)
            bb:paintCircle(cx, cy, r, Blitbuffer.COLOR_BLACK, r)
            if i ~= self.hl_cur then
                bb:paintCircle(cx, cy, r - 2, Blitbuffer.COLOR_WHITE, r - 2)
            end
        end
    end
end

-- Point from-to: the labels (a pill with two badges per target: next to the
-- sentence start / end, over the text when the margin is too narrow; on the
-- word labels centred on the top edge of the word), and in the second step
-- the start word. D-pad symbols are rounded squares with an arrow, letters
-- are circles; a symbol already pressed is grey.
local POINT_GLYPHS = {
    up = "\xE2\x86\x91", down = "\xE2\x86\x93", left = "\xE2\x86\x90", right = "\xE2\x86\x92",
    A = "A", B = "B", X = "X", Y = "Y",
}

function SelectorOverlay:_draw_point(bb, ox, oy)
    local p = self.pointer
    if not p then return end
    if p.step == "end" and p.start then
        local w = self.words[p.start]
        local s = w and w.sbox
        if s then invert_rounded_rect(bb, ox, oy, s.x, s.y, s.w, s.h) end
    end
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local border = math.max(1, Screen:scaleBySize(1))
    local gap = Screen:scaleBySize(3)
    for _, v in ipairs(p:visible()) do
        local d = math.max(Screen:scaleBySize(14), math.min(v.h or 0, Screen:scaleBySize(22)))
        local pw, ph = 2 * d + 3 * gap, d + 2 * gap
        local x
        if v.side == "left" then x = v.x - pw - gap
        elseif v.side == "right" then x = v.x + gap
        else x = math.floor(v.x - pw / 2) end
        x = math.max(0, math.min(sw - pw, x))
        local y = math.max(0, math.min(sh - ph, math.floor(v.y - ph / 2)))
        bb:paintRect(ox + x, oy + y, pw, ph, Blitbuffer.COLOR_WHITE)
        bb:paintBorder(ox + x, oy + y, pw, ph, border, Blitbuffer.COLOR_BLACK, math.floor(ph / 3))
        for k = 1, 2 do
            local sym = v.label[k]
            local fg = k <= v.typed and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK
            local bx, by = ox + x + gap + (k - 1) * (d + gap), oy + y + gap
            if #sym == 1 then
                local r = math.floor(d / 2)
                bb:paintCircle(bx + r, by + r, r, fg, border)
            else
                bb:paintBorder(bx, by, d, d, border, fg, math.floor(d / 4))
            end
            local tw = TextWidget:new{ text = POINT_GLYPHS[sym] or sym, face = LABEL_FACE,
                                       bold = true, fgcolor = fg }
            local sz = tw:getSize()
            tw:paintTo(bb, bx + math.floor((d - sz.w) / 2), by + math.floor((d - sz.h) / 2))
            tw:free()
        end
    end
end

-- Status line: the level and the buttons, no counters (TASK-15). ↑ / ↓ after
-- SENTENCE: the selection runs on past the top / bottom of the page. `short`
-- = the shortened bar of statusbar.lua (mode + A / B, for a tight strip).
function SelectorOverlay:_status_text(short)
    local keys = short and " \xC2\xB7 A menu \xC2\xB7 B close"
        or " \xC2\xB7 X hl \xC2\xB7 Y vort \xC2\xB7 A menu \xC2\xB7 B close"
    if self.mode == "point" then
        -- PC-022: FROM / TO = the step, WORD = refined to the word (R-stick
        -- down on, up off); on the word labels B goes back to the sentences
        local p = self.pointer
        local step = (p and p.step == "end") and "TO" or "FROM"
        if p and p.level == "word" then
            return step .. " WORD" .. (short and "" or " \xC2\xB7 label = word \xC2\xB7 R\xE2\x86\x91 sentences")
                .. " \xC2\xB7 B sentences"
        end
        local b = step == "TO" and " \xC2\xB7 B one word" or " \xC2\xB7 B close"
        if p and p.refine then
            return step .. " WORD" .. (short and "" or " \xC2\xB7 label = sentence \xC2\xB7 R\xE2\x86\x91 off") .. b
        end
        return step .. (short and "" or (step == "TO" and " \xC2\xB7 label = sentence end"
            or " \xC2\xB7 label = sentence") .. " \xC2\xB7 R\xE2\x86\x93 word") .. b
    end
    if self.mode == "walk" then
        return (self.ww_anchor and "WORDS" or "WORD") .. keys
    end
    if self.mode == "hl" then
        local item = self.hl_items[self.hl_cur]
        local ann = item and item.ann
        local note = (ann and ann.note and ann.note ~= "") and " [note]" or ""
        return "HIGHLIGHT" .. note .. (short and keys
            or " \xC2\xB7 X del \xC2\xB7 Y vort \xC2\xB7 A menu \xC2\xB7 B close")
    end
    local ext = ""
    local hs = self.sentences[self.sel_sent]
    local ts = self.sentences[self.sel_tail or self.sel_sent]
    if hs and hs._extends_before then ext = "\xE2\x86\x91" end
    if ts and ts._extends_after  then ext = ext .. "\xE2\x86\x93" end
    if ext ~= "" then ext = " " .. ext end
    local many = self.sel_sent and self.sel_tail and self.sel_tail > self.sel_sent
    return (many and "SENTENCES" or "SENTENCE") .. ext .. keys
end

-- The segments of a status line: the mode word bold italic, a lone capital
-- letter (a button) bold lowercase. Returns the TextWidgets, their total
-- width and the tallest height; the caller paints and frees them.
local function build_status(txt)
    local mode_txt = (txt or ""):match("^(%S+)") or ""
    local rest_txt = (txt or ""):match("^%S+(.*)") or ""
    local segs = { {t=mode_txt, bold=true, italic=true} }
    local buf  = ""
    for i = 1, #rest_txt do
        local c    = rest_txt:sub(i, i)
        local prev = i > 1           and rest_txt:sub(i-1, i-1) or ""
        local nxt  = i < #rest_txt   and rest_txt:sub(i+1, i+1) or ""
        if c:match("[A-Z]") and not prev:match("[a-zA-Z]") and not nxt:match("[a-zA-Z]") then
            if buf ~= "" then table.insert(segs, {t=buf,      bold=false, italic=false}); buf="" end
            table.insert(segs,                   {t=c:lower(), bold=true,  italic=false})
        else
            buf = buf .. c
        end
    end
    if buf ~= "" then table.insert(segs, {t=buf, bold=false, italic=false}) end

    local widgets = {}
    local total_w, total_h = 0, 0
    for _, seg in ipairs(segs) do
        local tw = TextWidget:new{
            text=seg.t, face=STATUS_FACE, bold=seg.bold, italic=seg.italic,
            fgcolor=Blitbuffer.COLOR_BLACK,
        }
        local sz = tw:getSize()
        table.insert(widgets, {tw=tw, w=sz.w, h=sz.h})
        total_w = total_w + sz.w
        if sz.h > total_h then total_h = sz.h end
    end
    return widgets, total_w, total_h
end

local function free_status(widgets)
    for _, entry in ipairs(widgets) do entry.tw:free() end
end

-- Height of the reader's footer (0 when it is hidden or unknown): the free
-- strip below the text ends at its top. Overlap mode (reclaim_height) is
-- covered too, the bar never goes onto the footer either.
function SelectorOverlay:_footer_height()
    local view = self.ui and self.ui.view
    local footer = view and view.footer
    if not (view and view.footer_visible and footer and footer.getHeight) then return 0 end
    local ok, h = pcall(footer.getHeight, footer)
    return (ok and tonumber(h)) or 0
end

-- The status bar never covers the book text (statusbar.lua): it measures the
-- free strips above the first and below the last line of the page and goes
-- where it fits, shortened when it has to, drawn not at all when no strip
-- holds a line of text.
function SelectorOverlay:_draw_status(bb, ox, oy)
    local sw = Screen:getWidth()
    local widgets, total_w, total_h = build_status(self:_status_text(false))
    local ext = StatusBar.extent(self.words, Screen:getHeight(), self:_footer_height())
    local lay = StatusBar.layout(ext, total_h)
    if lay.kind == "none" then
        free_status(widgets)
        return
    end
    if lay.short then
        free_status(widgets)
        widgets, total_w, total_h = build_status(self:_status_text(true))
    end

    local y = oy + lay.y
    bb:paintRect(ox, y, sw, lay.h, Blitbuffer.COLOR_WHITE)

    local text_y = lay.rule and (y + StatusBar.PAD_TOP) or (y + math.floor((lay.h - total_h) / 2))
    local line_x = ox + math.floor((sw - total_w) / 2)
    local cx     = line_x
    for _, entry in ipairs(widgets) do
        entry.tw:paintTo(bb, cx, text_y)
        cx = cx + entry.w
        entry.tw:free()
    end

    if lay.rule then
        bb:paintRect(line_x, text_y + total_h + StatusBar.PAD_GAP, total_w, StatusBar.RULE, Blitbuffer.COLOR_BLACK)
    end
end

----------------------------------------------------------------------
-- PagedOverlay: the same overlay on a PDF / DjVu page (TASK-30)
----------------------------------------------------------------------
-- The words come from document:getTextBoxes(page) through pdfwords.lua
-- (word items with a "pdf/<page>/<idx>" key in place of the xpointers), and
-- only the methods that talk to crengine are replaced: collecting the page,
-- the word moves, the order of two positions (index on the page), the page
-- turn (GotoPage), the selection text (getTextFromPositions) and the
-- drawing. Sentences, paragraphs, levels, "point from-to" and the actions
-- run unchanged on the base class. One page at a time: self.page (the top
-- page in continuous view); a range never leaves it.
--
-- Screen boxes (word.sbox) are recomputed from the CURRENT view
-- (view:pageToScreenTransform) on every paint and every move, never cached:
-- zoom and pan change the mapping. nil = the word is not on the screen. A
-- move onto a word outside the view pans the view to it (_reveal).
-- Highlights and notes (TASK-31) go through ReaderHighlight:saveHighlight /
-- deleteHighlight, the stock path of a finger selection; paragraphs are
-- TASK-32 (pdfwords.sentences).

local PagedOverlay = SelectorOverlay:extend{
    name  = "kopad_selector_overlay",
    paged = true,
}

-- True when the page on screen is not the native page: reflow (k2pdfopt,
-- text_wrap == 1) or a reflowable document opened by MuPDF. The native text
-- boxes do not match what is drawn there, so kopad does not select.
function PagedOverlay.reflowed(doc)
    if type(doc) ~= "table" then return false end
    local cfg = doc.configurable
    if type(cfg) == "table" and cfg.text_wrap == 1 then return true end
    return doc.is_reflowable == true
end

function PagedOverlay:init()
    self._boxes = {}
    self._pinfo = {}      -- [page] = pdfpara info (paragraphs), cached with _boxes
    self.page = self.page or self:_view_page()
    SelectorOverlay.init(self)
end

-- The page the overlay starts on: the top one in continuous view (the stock
-- current_page is the bottom one there), else the view's page.
function PagedOverlay:_view_page()
    local ui, view = self.ui, self.ui.view
    if view and view.page_scroll and ui.paging and ui.paging.getTopPage then
        local ok, p = pcall(ui.paging.getTopPage, ui.paging)
        if ok and type(p) == "number" then return p end
    end
    if view and view.state and type(view.state.page) == "number" then return view.state.page end
    local ok, p = pcall(function() return ui:getCurrentPage() end)
    return (ok and type(p) == "number") and p or 1
end

function PagedOverlay:_page_count()
    local ok, n = pcall(function() return self.doc:getPageCount() end)
    if ok and type(n) == "number" then return n end
    return self.ui.paging and self.ui.paging.number_of_pages or nil
end

-- getTextBoxes of a page, nil without a text layer (cached per overlay: the
-- DjVu wrapper has no cache of its own).
function PagedOverlay:_page_boxes(page)
    if type(page) ~= "number" or page < 1 then return nil end
    local n = self:_page_count()
    if n and page > n then return nil end
    local c = self._boxes[page]
    if c == nil then
        local ok, b = pcall(self.doc.getTextBoxes, self.doc, page)
        c = (ok and PdfWords.has_text(b)) and b or false
        self._boxes[page] = c
    end
    return c or nil
end

function PagedOverlay:_collect()
    local boxes = self:_page_boxes(self.page)
    -- paragraphs are guessed from the page's line geometry once per page
    -- (TASK-32: pdfpara.lua through pdfwords); the words come out in reading order
    local info
    self.words, info = {}, nil
    if boxes then
        self.words, info = PdfWords.words_from_boxes(boxes, self.page,
            { rtl = self.is_rtl, info = self._pinfo[self.page] })
        self._pinfo[self.page] = info or nil
    end
    self.sentences = PdfWords.sentences(self.words)
    local n = #self.words
    -- a sentence over the page edge (as paginmapo's find_sentence_start/end
    -- do for an EPUB): decided with the neighbouring page's first / last word
    if #self.sentences > 0 then
        local prev = PdfWords.last_text(self:_page_boxes(self.page - 1))
        if prev and not PdfWords.ends_sentence(prev, self.words[1].text) then
            self.sentences[1]._extends_before = true
        end
        local nxt = PdfWords.first_text(self:_page_boxes(self.page + 1))
        if nxt and not PdfWords.ends_sentence(self.words[n].text, nxt) then
            self.sentences[#self.sentences]._extends_after = true
        end
    end
    self._key_idx, self._xp_to_sent, self.word_to_sent = {}, {}, {}
    for i, w in ipairs(self.words) do self._key_idx[w.pos0] = i end
    for si, s in ipairs(self.sentences) do
        for i = s.first, s.last do
            self._xp_to_sent[self.words[i].pos0] = si
            self.word_to_sent[i] = si
        end
    end
    self:_screen_boxes()
end

-- The positions (and stored boxes) of a saved highlight on `page`: its own
-- pos0 / pos1, or for a multi-page one (ann.ext) the piece on that page.
local function hl_positions(rh, ann, index, page)
    if not ann.ext then return ann.pos0, ann.pos1, ann.pboxes end
    if rh and rh.getSavedExtendedHighlightPage then
        local ok, piece = pcall(rh.getSavedExtendedHighlightPage, rh, ann, page, index)
        if ok and type(piece) == "table" and piece.pos0 then
            return piece.pos0, piece.pos1, piece.pboxes
        end
    end
    local e = type(ann.ext) == "table" and ann.ext[page]
    if type(e) == "table" then return e.pos0, e.pos1, e.pboxes end
end

-- Saved highlights on the overlay's page (TASK-31): every annotation with a
-- drawer (bookmarks have none) whose pos0.page .. pos1.page covers the page,
-- as ReaderHighlight:getPageSavedHighlights selects them, but walking
-- ui.annotation.annotations directly so `index` is the annotation index that
-- deleteHighlight takes. Native boxes from getPageBoxesFromPositions (what
-- ReaderView draws), else the stored pboxes; ordered top to bottom on the
-- page. Screen boxes: _screen_boxes, recomputed like the words'.
function PagedOverlay:_collect_highlights()
    self.hl_items, self.hl_cur = {}, 0
    local anns = self.ui and self.ui.annotation and self.ui.annotation.annotations
    if type(anns) ~= "table" then return end
    local page, rh = self.page, self.ui.highlight
    for i, ann in ipairs(anns) do
        local p0, p1 = ann.pos0, ann.pos1
        if ann.drawer and type(p0) == "table" and type(p1) == "table"
                and type(p0.page) == "number" and type(p1.page) == "number"
                and p0.page <= page and page <= p1.page then
            local q0, q1, stored = hl_positions(rh, ann, i, page)
            local pboxes
            if q0 and q1 and self.doc.getPageBoxesFromPositions then
                local ok, b = pcall(self.doc.getPageBoxesFromPositions, self.doc, page, q0, q1)
                if ok and type(b) == "table" and #b > 0 then pboxes = b end
            end
            pboxes = pboxes or (type(stored) == "table" and #stored > 0 and stored) or nil
            if pboxes then
                local top = pboxes[1]
                for _, b in ipairs(pboxes) do
                    if b.y < top.y or (b.y == top.y and b.x < top.x) then top = b end
                end
                table.insert(self.hl_items, { ann = ann, index = i, pos0 = q0, pos1 = q1,
                                              pboxes = pboxes, ptop = top, boxes = {} })
            end
        end
    end
    table.sort(self.hl_items, function(a, b)
        if a.ptop.y ~= b.ptop.y then return a.ptop.y < b.ptop.y end
        if a.ptop.x ~= b.ptop.x then return a.ptop.x < b.ptop.x end
        return a.index < b.index
    end)
    self:_screen_boxes()
end

-- A native page box on the screen now, nil when it is not visible. In page
-- view the stock transform ignores the page number, so another page than the
-- one on screen has no screen box.
function PagedOverlay:_to_screen(pbox)
    local view = self.ui and self.ui.view
    if not (view and pbox and view.pageToScreenTransform) then return nil end
    if not view.page_scroll and view.state and view.state.page ~= self.page then return nil end
    local ok, r = pcall(view.pageToScreenTransform, view, self.page,
        Geom:new{ x = pbox.x, y = pbox.y, w = pbox.w, h = pbox.h })
    if ok and type(r) == "table" and r.x and r.y and r.w and r.h then
        return { x = r.x, y = r.y, w = r.w, h = r.h }
    end
end

function PagedOverlay:_screen_boxes()
    for _, w in ipairs(self.words or {}) do w.sbox = self:_to_screen(w.pbox) end
    -- highlights: the boxes on the screen now, sbox = the top one (nil = none)
    for _, it in ipairs(self.hl_items or {}) do
        local boxes, top = {}, nil
        for _, b in ipairs(it.pboxes) do
            local r = self:_to_screen(b)
            if r then
                boxes[#boxes + 1] = r
                if not top or r.y < top.y then top = r end
            end
        end
        it.boxes, it.sbox = boxes, top
    end
end

-- Pan the view so that word w is on the screen (no-op when it is). Page
-- view: the visible area moves just past the word plus a margin (a quarter
-- of the screen vertically); continuous view: scroll by the overshoot.
function PagedOverlay:_reveal(w)
    local view = self.ui and self.ui.view
    if not (w and view) then return end
    if view.page_scroll then
        local s = self:_to_screen(w.pbox)
        local sh = Screen:getHeight()
        local paging = self.ui.paging
        if s and s.y >= 0 and s.y + s.h <= sh then return end
        if s and paging and paging.onScrollPanRel then
            local dy = s.y < 0 and (s.y - sh / 4) or (s.y + s.h - sh + sh / 4)
            pcall(paging.onScrollPanRel, paging, dy)
        elseif paging and paging.onGotoPage then
            pcall(paging.onGotoPage, paging, self.page, { x = w.pbox.x, y = w.pbox.y })
        end
        return
    end
    local va, z = view.visible_area, view.state and view.state.zoom
    if not (va and type(z) == "number" and view.PanningUpdate) then return end
    local b = w.pbox
    local x0, y0, x1, y1 = b.x * z, b.y * z, (b.x + b.w) * z, (b.y + b.h) * z
    local dx, dy = 0, 0
    if x0 < va.x then dx = x0 - va.x - va.w / 10
    elseif x1 > va.x + va.w then dx = x1 - (va.x + va.w) + va.w / 10 end
    if y0 < va.y then dy = y0 - va.y - va.h / 4
    elseif y1 > va.y + va.h then dy = y1 - (va.y + va.h) + va.h / 4 end
    if dx ~= 0 or dy ~= 0 then pcall(view.PanningUpdate, view, dx, dy) end
end

-- The word the cursor is on (walk) / the cursor sentence's first word / the
-- top box of the focused highlight (hl; only its pbox is used, by _reveal).
function PagedOverlay:_cursor_word()
    if self.mode == "walk" then return self.ww_word end
    if self.mode == "hl" then
        local it = self.hl_items[self.hl_cur]
        return it and { pbox = it.ptop } or nil
    end
    if self.mode == "struct" and self.sel_cur then
        local s = self.sentences[self.sel_cur]
        return s and self.words[s.first]
    end
end

-- Every move ends here (base step / line / para / to_words ...): bring the
-- cursor into view, then the screen boxes of the view now.
function PagedOverlay:_refresh()
    self:_reveal(self:_cursor_word())
    self:_screen_boxes()
    UIManager:setDirty("all", "ui")
end

-- The first / last word of the page shown when opening (visible = true: the
-- first / last word ON THE SCREEN, a zoomed view shows part of the page);
-- after a page turn the real first / last word of the page.
function PagedOverlay:_ww_land(dir, visible)
    local n = #self.words
    if n == 0 then self.ww_word = nil; return end
    local from, to = 1, n
    if dir < 0 then from, to = n, 1 end
    local w
    if visible then
        for i = from, to, dir < 0 and -1 or 1 do
            if self.words[i].sbox then w = self.words[i]; break end
        end
    end
    self.ww_word = w or self.words[from]
end

-- Sentences on opening: the sentence of the first / last word on the screen.
function PagedOverlay:_sent_open(from_end)
    self:_ww_land(from_end and -1 or 1, true)
    local w = self.ww_word
    self.ww_word = nil
    local i = w and self.word_to_sent[w.idx]
    if i then self:_set_sent(i) end
end

function PagedOverlay:_is_split_word() return false end

function PagedOverlay:_ww_word_from_xp(key)
    local i = key and self._key_idx and self._key_idx[key]
    return i and self.words[i] or nil
end

-- Order of two positions = their index on the page (ranges stay on it).
function PagedOverlay:_xp_before(a, b)
    local ia, ib = self._key_idx[a], self._key_idx[b]
    return ia ~= nil and ib ~= nil and ia < ib
end

-- Turn to the next / previous whole page under the overlay. False on the
-- first / last page.
function PagedOverlay:_turn_page(dir)
    local target = self.page + dir
    local n = self:_page_count()
    if target < 1 or (n and target > n) then return false end
    self.ui:handleEvent(Event:new("GotoPage", target))
    self.page = target
    self:_collect()
    self:_collect_highlights()
    return true
end

-- Words: one word forward / back; past the page edge the next / previous
-- page (the range, A held, stays on the page).
function PagedOverlay:_ww_step(dir, range)
    local w = self.ww_word
    if range then self.ww_anchor = self.ww_anchor or w else self.ww_anchor = nil end
    local nw = w and self.words[w.idx + dir]
    if nw then self.ww_word = nw; return end
    if not range and self:_turn_page(dir) then self:_ww_land(dir) end
end

-- Words: the nearest word on the next / previous line of the page's text
-- boxes; past the last / first line the next / previous page.
function PagedOverlay:_ww_line(delta, range)
    local w = self.ww_word
    if not w then
        if not range and self:_turn_page(delta) then self:_ww_land(delta) end
        return
    end
    if range then self.ww_anchor = self.ww_anchor or w else self.ww_anchor = nil end
    local i = PdfWords.line_target(self.words, w.idx, delta)
    if i then self.ww_word = self.words[i]; return end
    if not range and self:_turn_page(delta) then self:_ww_land(delta) end
end

-- Word indices of the selection (walk: cursor / anchor..cursor; struct:
-- the selected sentences), nil when none.
function PagedOverlay:_span_idx()
    if self.mode == "walk" then
        local w, a = self.ww_word, self.ww_anchor
        if not w then return nil end
        if not a then return w.idx, w.idx end
        return math.min(a.idx, w.idx), math.max(a.idx, w.idx)
    elseif self.mode == "struct" then
        local head = self.sel_sent and self.sentences[self.sel_sent]
        local tail = head and self.sentences[self.sel_tail or self.sel_sent]
        if head and tail then return head.first, tail.last end
    end
end

-- The selection for the actions: text (getTextFromPositions joins words
-- split by a hyphen; else the words), pos0 / pos1 at the centres of the end
-- words (a later saveHighlight takes these, TASK-31), pboxes (native, one per
-- line) and sboxes (screen, for the dictionary popup; nil when none shows).
function PagedOverlay:_get_selection()
    if self.mode == "hl" then
        -- the focused saved highlight: its own text and positions, hl_index =
        -- its annotation index (X removes it, Note edits it)
        local it = self.hl_items[self.hl_cur]
        if not it then return nil end
        self:_screen_boxes()
        local ann = it.ann
        return { text = ann.text or "", pos0 = ann.pos0, pos1 = ann.pos1, page = self.page,
                 pboxes = it.pboxes, sboxes = #it.boxes > 0 and it.boxes or nil,
                 hl_index = it.index, hl_ann = ann }
    end
    local i0, i1 = self:_span_idx()
    if not i0 then return nil end
    local w0, w1 = self.words[i0], self.words[i1]
    local state = self.ui.view and self.ui.view.state
    local pos0, pos1 = PdfWords.pos(w0, state), PdfWords.pos(w1, state)
    local text, pboxes
    local ok, r = pcall(self.doc.getTextFromPositions, self.doc, pos0, pos1)
    if ok and type(r) == "table" and type(r.text) == "string" and r.text:find("%S") then
        text, pboxes = r.text, r.pboxes
    end
    self:_screen_boxes()
    local sboxes = PdfWords.line_boxes(self.words, i0, i1)
    return {
        text = text or PdfWords.text(self.words, i0, i1),
        pos0 = pos0, pos1 = pos1, page = self.page,
        pboxes = pboxes or PdfWords.line_boxes(self.words, i0, i1, "pbox"),
        sboxes = #sboxes > 0 and sboxes or nil,
    }
end

function PagedOverlay:_page_text()
    if #self.words == 0 then return nil end
    return PdfWords.text(self.words, 1, #self.words)
end

-- Highlights (TASK-31). Saved exactly like a finger selection: the
-- selection becomes ReaderHighlight.selected_text ({text, pos0, pos1,
-- pboxes}; pos = {page, x, y, zoom, rotation} at the end words' centres, in
-- native page coordinates) and saveHighlight() files it: annotation:addItem
-- (the sidecar, so it is there after reopening), AnnotationsModified, the
-- user's highlight style and, with "write highlights into PDF", the PDF
-- itself. Removed by deleteHighlight(index), which also deletes it from the
-- PDF and shifts the drawn-box cache (index_modified).

-- Save `sel` as a highlight; the annotation index, nil when it failed.
function PagedOverlay:_save_highlight(sel)
    local rh = self.ui.highlight
    if not (rh and rh.saveHighlight and sel and type(sel.pos0) == "table"
            and type(sel.pos1) == "table") then return nil end
    local function copy(p)
        return { page = p.page, x = p.x, y = p.y, zoom = p.zoom, rotation = p.rotation }
    end
    local prev = rh.selected_text
    rh.selected_text = { text = sel.text, pos0 = copy(sel.pos0), pos1 = copy(sel.pos1),
                         pboxes = sel.pboxes }
    local ok, index = pcall(rh.saveHighlight, rh)
    rh.selected_text = prev
    if ok then return index end
end

-- The word index on the page nearest to a native position (0 inside a box).
function PagedOverlay:_word_at(pos)
    if type(pos) ~= "table" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then return nil end
    local best, best_d
    for i, w in ipairs(self.words) do
        local b = w.pbox
        local dx = math.max(b.x - pos.x, 0, pos.x - (b.x + b.w))
        local dy = math.max(b.y - pos.y, 0, pos.y - (b.y + b.h))
        local d = dx * dx + dy * dy
        if not best_d or d < best_d then best, best_d = i, d end
    end
    return best
end

-- The saved highlight `sel` is (mode "hl"), or the single-page one on this
-- page covering the same words (its pos0 / pos1 snap to the selection's end
-- words; a finger highlight's positions are not the word centres): the
-- hl_items entry, nil when none.
function PagedOverlay:_highlight_of(sel)
    if sel.hl_index then
        for _, it in ipairs(self.hl_items) do
            if it.ann == sel.hl_ann then return it end
        end
        return nil
    end
    local i0, i1 = self:_span_idx()
    if not i0 then return nil end
    for _, it in ipairs(self.hl_items) do
        if not it.ann.ext then
            local a, b = self:_word_at(it.pos0), self:_word_at(it.pos1)
            if a and b and math.min(a, b) == i0 and math.max(a, b) == i1 then return it end
        end
    end
end

-- Recollect the page's highlights after a change; browsing them, the focus
-- stays in place (0 = none left: padnav closes).
function PagedOverlay:_highlights_changed()
    local cur = self.hl_cur
    self:_collect_highlights()
    if self.mode == "hl" then self.hl_cur = math.min(cur, #self.hl_items) end
    self:_refresh()
end

function PagedOverlay:_do_highlight(sel)
    if not sel or sel.hl_index then return end -- already a highlight
    if self:_save_highlight(sel) then self:_highlights_changed() end
end

-- X: remove the highlight the selection is, else highlight it.
function PagedOverlay:_do_toggle_highlight(sel)
    if not sel then return end
    local it = self:_highlight_of(sel)
    if it then
        local rh = self.ui.highlight
        local anns = self.ui.annotation and self.ui.annotation.annotations
        local index = it.index
        -- the index the list was collected with, re-checked by identity
        if anns and anns[index] ~= it.ann then
            index = nil
            for i, a in ipairs(anns) do if a == it.ann then index = i; break end end
        end
        if index and rh and rh.deleteHighlight and pcall(rh.deleteHighlight, rh, index) then
            UIManager:show(InfoMessage:new{ text = _("Highlight removed"), timeout = 1 })
        end
    else
        self:_save_highlight(sel)
    end
    self:_highlights_changed()
end

-- Note: on the browsed highlight itself (mode "hl"), else on a new one.
function PagedOverlay:_note_target(sel)
    if not sel then return nil end
    if sel.hl_index then
        local it = self:_highlight_of(sel)
        local anns = self.ui.annotation and self.ui.annotation.annotations
        if it and anns then
            for i, a in ipairs(anns) do if a == it.ann then return i end end
        end
        return nil
    end
    local index = self:_save_highlight(sel)
    if index then self:_highlights_changed() end
    return index
end

-- The note also goes into the PDF's annotation (as the stock note editor
-- does; a no-op unless "write highlights into PDF" is on), then the status
-- line shows [note].
function PagedOverlay:_note_saved(a, note)
    local rh = self.ui.highlight
    if rh and rh.writePdfAnnotation then pcall(rh.writePdfAnnotation, rh, "content", a, note) end
    self:_highlights_changed()
end

-- Point from-to: the labels go at the sentences on the screen now.
function PagedOverlay:_point_begin()
    self:_screen_boxes()
    return SelectorOverlay._point_begin(self)
end

function PagedOverlay:paintTo(bb, x, y)
    self:_screen_boxes()
    SelectorOverlay.paintTo(self, bb, x, y)
end

local function invert_boxes(bb, ox, oy, boxes)
    for _, b in ipairs(boxes) do invert_rounded_rect(bb, ox, oy, b.x, b.y, b.w, b.h) end
end

function PagedOverlay:_draw_walk(bb, ox, oy)
    local i0, i1 = self:_span_idx()
    if i0 then invert_boxes(bb, ox, oy, PdfWords.line_boxes(self.words, i0, i1)) end
end

function PagedOverlay:_draw_struct(bb, ox, oy)
    if self.mode == "hl" then
        local it = self.hl_items[self.hl_cur]
        if it then invert_boxes(bb, ox, oy, it.boxes) end
        return
    end
    if self.mode ~= "struct" then return end
    local i0, i1 = self:_span_idx()
    if i0 then invert_boxes(bb, ox, oy, PdfWords.line_boxes(self.words, i0, i1)) end
end

----------------------------------------------------------------------
-- Selector (controller — key handling, in active_widgets)
----------------------------------------------------------------------

local Selector = InputContainer:extend{
    name        = "kopad_selector",
    overlay     = nil,
    enabled_ref = nil,
}

function Selector:init()
    self.overlay = nil
    self.key_events = {}
end

----------------------------------------------------------------------
-- Open / close (called by padnav)
----------------------------------------------------------------------

-- A new overlay on the current page, holding the family overlay claim (nil
-- when it cannot open). The claim is refused while visel/hilite own the
-- screen; holding it makes keyboard openers (Space/D/O/I…) stand down over the
-- gamepad overlay. padnav._is_enabled exempts our own claim, so the gamepad
-- keeps driving this overlay.
-- PDF / DjVu (ui.paging, TASK-30): PagedOverlay; nil, "reflow" in reflow
-- mode, and the openers below return false, "no_text" for a page without a
-- text layer (a scan), so padnav can say why.
function Selector:_new_overlay()
    if self.overlay then return nil end
    if not self.ui or not self.ui.document then return nil end
    local class = SelectorOverlay
    if not self.ui.rolling then
        if not self.ui.paging then return nil end
        if PagedOverlay.reflowed(self.ui.document) then return nil, "reflow" end
        class = PagedOverlay
    end
    if not Pluginaro.claim_overlay(self.ui, "kopad") then return nil end
    local ok, ov = pcall(class.new, class, {
        doc  = self.ui.document,
        ui   = self.ui,
    })
    if not ok then
        Pluginaro.release_overlay(self.ui, "kopad")
        UIManager:show(InfoMessage:new{ text = _("kopad error: ") .. tostring(ov) })
        return nil
    end
    return ov
end

-- What an opener returns when no overlay could be made: false + reason
-- (reflow), nil otherwise (already open, claim refused, no document).
function Selector._refused(why)
    if why then return false, why end
    return nil
end

-- A paged overlay on a page without words: given back, false + reason.
function Selector:_no_text(ov)
    if ov.paged and #ov.words == 0 then
        Pluginaro.release_overlay(self.ui, "kopad")
        return true
    end
    return false
end

function Selector:_show(ov)
    self.overlay = ov
    UIManager:show(ov)
    UIManager:setDirty("all", "ui")
end

-- Sentences: the first sentence of the page, or the last one with from_end
-- (Y + D-pad while reading, TASK-28; the `sentence_select` action opens the
-- first).
function Selector:_open(from_end)
    local ov, why = self:_new_overlay()
    if not ov then return Selector._refused(why) end
    if self:_no_text(ov) then return false, "no_text" end
    if ov.paged then
        ov:_sent_open(from_end)
        ov:_reveal(ov:_cursor_word())
    elseif from_end and #ov.sentences > 0 then
        ov:_set_sent(#ov.sentences)
    end
    self:_show(ov)
    return true
end

-- Words: the first word of the page, or the last one with from_end (A +
-- D-pad ↑/← while reading, TASK-28).
function Selector:_open_walk(from_end)
    local ov, why = self:_new_overlay()
    if not ov then return Selector._refused(why) end
    if self:_no_text(ov) then return false, "no_text" end
    ov.mode = "walk"
    -- PDF: the first / last word on the screen (a zoomed view)
    ov:_ww_land(from_end and -1 or 1, true)
    if ov.paged then ov:_reveal(ov.ww_word) end
    self:_show(ov)
    return true
end

-- Point from-to (A tapped while reading, TASK-29 / TASK-35): labels at the
-- sentence starts. False, with nothing shown, when the page has no text.
function Selector:_open_point()
    local ov, why = self:_new_overlay()
    if not ov then return Selector._refused(why) end
    if not ov:_point_begin() then
        Pluginaro.release_overlay(self.ui, "kopad")
        return false, "no_text"
    end
    self:_show(ov)
    return true
end

-- The page's saved highlights, the first one focused (Y while reading).
-- False, with nothing shown, when the page has none.
-- PDF / DjVu (TASK-31): the highlights of the whole page (top page in
-- continuous view), the view pans to the focused one; reflow = false,
-- "reflow".
function Selector:_open_highlights()
    local ov, why = self:_new_overlay()
    if not ov then return Selector._refused(why) end
    if #ov.hl_items == 0 then
        Pluginaro.release_overlay(self.ui, "kopad")
        return false
    end
    ov.mode, ov.hl_cur = "hl", 1
    if ov.paged then ov:_reveal(ov:_cursor_word()) end
    self:_show(ov)
    return true
end

function Selector:_close()
    if self.overlay then
        -- pcall: _close may run during document teardown (onCloseDocument),
        -- where UIManager stack / widget refs can already be partly gone.
        pcall(UIManager.close, UIManager, self.overlay)
        self.overlay = nil
        -- Owner-checked release: never drops a claim held by another
        -- family overlay (visel / hilite).
        Pluginaro.release_overlay(self.ui, "kopad")
        pcall(UIManager.setDirty, UIManager, self.ui, "ui")
    end
end

function Selector:getMenuItems()
    return {
        {
            text = _("Sentence selector"),
            callback = function() self:_open() end,
        },
    }
end

-- for the tests
Selector._PagedOverlay = PagedOverlay

return Selector
