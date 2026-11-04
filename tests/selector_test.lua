-- Tests for selector.lua (the selection overlay) against a fake crengine
-- document: three pages of six words, two lines of three words each.
-- Run from the repo root: lua tests/selector_test.lua
--
--   page 1: t1 t2 t3 / t4 t5 t6      sentences  S1 = t1-t4 (paragraph 1)
--   page 2: t7 t8 t9 / t10 t11 t12              S2 = t5-t8 (paragraph 1)
--   page 3: t13 t14 t15 / t16 t17 t18           S3 = t9-t10 (paragraph 2)
--                                               S4 = t11-t13 (paragraph 2)
--                                               S5 = t14-t16, S6 = t17-t18 (paragraph 3)
-- S2 and S4 run over a page edge. Xpointers: "w<i>" = start of word i,
-- "w<i>e" = its end.
package.path = "./?.lua;" .. package.path

local SENT = { 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6 }
local PARA = { [1] = 1, [2] = 1, [3] = 2, [4] = 2, [5] = 3, [6] = 3 }
local N, PER_PAGE, PER_LINE = 18, 6, 3

local function idx(xp) return tonumber(xp:match("^w(%d+)")) end

local Doc = { page = 1 }
Doc.__index = Doc
function Doc:first() return (self.page - 1) * PER_PAGE + 1 end
function Doc:last() return self.page * PER_PAGE end
function Doc:box(i)
    local k = i - self:first()
    return { x = 10 + (k % PER_LINE) * 100, y = 10 + math.floor(k / PER_LINE) * 40, w = 80, h = 20 }
end
function Doc:getProps() return { language = "en" } end
function Doc:getNextVisibleWordStart(xp) local i = idx(xp); return i < N and ("w" .. (i + 1)) or nil end
function Doc:getPrevVisibleWordStart(xp) local i = idx(xp); return i > 1 and ("w" .. (i - 1)) or nil end
function Doc:getNextVisibleWordEnd(xp) return "w" .. idx(xp) .. "e" end
function Doc:isXPointerInCurrentPage(xp) local i = idx(xp); return i >= self:first() and i <= self:last() end
function Doc:getTextFromXPointers(a, b)
    local t = {}
    for i = idx(a), idx(b) do t[#t + 1] = "t" .. i end
    return table.concat(t, " ")
end
function Doc:getScreenBoxesFromPositions(a, b)
    local t = {}
    for i = math.max(idx(a), self:first()), math.min(idx(b), self:last()) do t[#t + 1] = self:box(i) end
    return t
end
-- Like CreDocument: the TOP of the word's line (doc_y - top_y), not its
-- middle. The word on the left of the cursor has the same y (TASK-24).
function Doc:getScreenPositionFromXPointer(xp)
    local i = idx(xp)
    if not self:isXPointerInCurrentPage(xp) then return nil end
    return self:box(i).y
end
function Doc:getWordFromPosition(pos)
    local best, bd
    for i = self:first(), self:last() do
        local b = self:box(i)
        if math.abs(b.y + b.h / 2 - pos.y) < 5 then
            local d = math.abs(b.x - pos.x)
            if not bd or d < bd then best, bd = i, d end
        end
    end
    return best and { pos0 = "w" .. best, pos1 = "w" .. best .. "e", word = "t" .. best } or nil
end
function Doc:compareXPointers(a, b)
    local ia, ib = idx(a), idx(b)
    return ia < ib and 1 or (ia > ib and -1 or 0)
end

-- KOReader stubs
local function stub(name, v) package.preload[name] = function() return v end end
local IC = {}
function IC:extend(o) o = o or {}; setmetatable(o, { __index = self }); o.__index = o; return o end
function IC:new(o) o = o or {}; setmetatable(o, self); if o.init then o:init() end; return o end
local events = {}
stub("ffi/blitbuffer", { COLOR_BLACK = 0, COLOR_WHITE = 1 })
stub("device", { screen = { getWidth = function() return 600 end, getHeight = function() return 800 end,
                            scaleBySize = function(_, v) return v end },
                 input = {} })
stub("ui/event", { new = function(_, name, ...) return { name = name, args = { ... } } end })
stub("ui/geometry", {
    new = function(_, t) return t end,
    boundingBox = function(boxes)
        local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
        for _, b in ipairs(boxes) do
            x0, y0 = math.min(x0, b.x), math.min(y0, b.y)
            x1, y1 = math.max(x1, b.x + b.w), math.max(y1, b.y + b.h)
        end
        return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
    end,
})
stub("ui/widget/infomessage", { new = function(_, t) return t end })
stub("ui/widget/container/inputcontainer", IC)
stub("ui/widget/textwidget", {})
stub("ui/uimanager", { show = function() end, close = function() end, setDirty = function() end })
stub("util", { cleanupSelectedText = function(s) return s end })
stub("gettext", function(s) return s end)
stub("ui/font", { getFace = function() return {} end })
local claims = 0
stub("pluginaro", { claim_overlay = function() claims = claims + 1; return true end,
                    release_overlay = function() claims = claims - 1 end })
-- paginmapo: the page's words and sentences straight from the fake document
stub("paginmapo", {
    collect_words = function(doc)
        local t = {}
        for i = doc:first(), doc:last() do
            local last_of_sent = SENT[i + 1] ~= SENT[i]
            t[#t + 1] = { text = "t" .. i, xp0 = "w" .. i, xp1 = "w" .. i .. "e",
                          next_xp0 = i < N and ("w" .. (i + 1)) or nil,
                          inter = last_of_sent and ". " or " ", sbox = doc:box(i) }
        end
        return t
    end,
    collect_sentences_from_words = function(words)
        local out = {}
        for _, w in ipairs(words) do
            local s = SENT[idx(w.xp0)]
            local cur = out[#out]
            if not cur or cur.id ~= s then
                cur = { id = s, para = PARA[s], xp0 = w.xp0, word_list = {} }
                out[#out + 1] = cur
            end
            cur.word_list[#cur.word_list + 1] = w
            cur.xp1 = w.xp1
        end
        return out
    end,
    page_starts_at_boundary = function(doc)
        local i = doc:first()
        return i == 1 or SENT[i - 1] ~= SENT[i]
    end,
    find_sentence_start = function(_, xp)
        local i = idx(xp)
        while i > 1 and SENT[i - 1] == SENT[i] do i = i - 1 end
        return "w" .. i
    end,
    find_sentence_end = function(_, xp)
        local i = idx(xp)
        while i < N and SENT[i + 1] == SENT[i] do i = i + 1 end
        return "w" .. i .. "e"
    end,
})

local Selector = require("selector")

local function fresh(page, annotations)
    local doc = setmetatable({ page = page or 1 }, Doc)
    events = {}
    local ui = { document = doc, rolling = {},
                 annotation = { annotations = annotations or {} },
                 handleEvent = function(_, ev)
                     events[#events + 1] = ev.name
                     if ev.name == "GotoViewRel" then
                         doc.page = math.max(1, math.min(3, doc.page + ev.args[1]))
                     end
                 end }
    local sel = Selector:new{ ui = ui }
    return sel, doc, ui
end
local function text(ov) local s = ov:_get_selection(); return s and s.text end

-- 1. Sentences (A): opens on the page's first sentence, ←/→ move by sentence
local sel, doc = fresh()
sel:_open()
local ov = sel.overlay
assert(ov.mode == "struct" and ov.sel_cur == 1 and text(ov) == "t1 t2 t3 t4", text(ov))
ov:step(1)
assert(text(ov) == "t5 t6 t7 t8", "the page's last sentence, completed past the edge: " .. tostring(text(ov)))

-- 2. Page edge, both directions (TASK-18). → on a sentence running over the
-- edge: the next page, the sentence AFTER it (S2 is also its first one)
ov:step(1)
assert(doc.page == 2 and text(ov) == "t9 t10", "→ over the edge: " .. tostring(text(ov)))
ov:step(-1); assert(doc.page == 2 and text(ov) == "t5 t6 t7 t8", "S2 again, on page 2")
ov:step(-1); assert(doc.page == 1 and text(ov) == "t1 t2 t3 t4", "← over the edge skips S2's other half")
-- first page: ← stays put
ov:step(-1); assert(doc.page == 1 and text(ov) == "t1 t2 t3 t4", "first page: nothing before")

-- 3. Paragraphs: ↓ next paragraph, over the edge into paragraph 2 (page 2
-- starts inside paragraph 1); ↑ start of this paragraph / the previous one
ov:line(1)
assert(doc.page == 2 and text(ov) == "t9 t10", "↓ = next paragraph on the next page: " .. tostring(text(ov)))
ov:line(-1); assert(doc.page == 2 and text(ov) == "t5 t6 t7 t8", "↑ = previous paragraph")
ov:line(-1)
assert(doc.page == 1 and text(ov) == "t1 t2 t3 t4", "↑ over the edge = start of the last paragraph")

-- 4. Range (A held): anchor + cursor, both directions, never off the page
sel:_close()
sel, doc = fresh()
sel:_open(); ov = sel.overlay
ov:step(1, true)
assert(ov.sel_anchor == 1 and text(ov) == "t1 t2 t3 t4 t5 t6 t7 t8", "range of two sentences")
ov:step(1, true)
assert(doc.page == 1 and text(ov) == "t1 t2 t3 t4 t5 t6 t7 t8", "a range stays on the page")
ov:step(-1, true); assert(text(ov) == "t1 t2 t3 t4", "back to the anchor = one sentence")
ov:step(1); assert(ov.sel_anchor == nil and text(ov) == "t5 t6 t7 t8", "a plain move drops the range")
ov:step(-1, true)
assert(ov.sel_sent == 1 and ov.sel_tail == 2 and ov.sel_cur == 1, "range backwards from the anchor")
ov:line(1, true); assert(doc.page == 1, "paragraph range stays on the page too")
assert(ov:_status_text():match("^SENTENCES"), "range in the status line")
assert(not ov:_status_text():find("%d"), "no counters: " .. ov:_status_text())

-- 5. Words (D-pad): first / last word, word moves over page edges; ↑/↓ =
-- one line, the word under the cursor's x (TASK-44 / PC-025: the D-pad and
-- the L-stick alike, no sentence jumps), over page edges too
sel:_close()
sel, doc = fresh()
sel:_open_walk(false); ov = sel.overlay
assert(ov.mode == "walk" and text(ov) == "t1", "D-pad ↓/→ opens on the first word")
assert(ov.from_labels == false and ov.sent_phase == false, "not from the labels, no sentence phase")
ov:step(1); assert(text(ov) == "t2")
ov:line(1); assert(text(ov) == "t5", "↓ = the word below at the same x: " .. tostring(text(ov)))
ov:line(-1)
assert(doc.page == 1 and text(ov) == "t2", "↑ = the word above, not the one on the left: " .. tostring(text(ov)))
ov:line(1); ov:line(1)
assert(doc.page == 2 and text(ov) == "t7", "↓ on the last line = next page, first word")
ov:line(-1); assert(doc.page == 1 and text(ov) == "t6", "↑ on the first line = previous page, last word")
ov:step(-1); ov:step(-1); ov:step(-1); ov:step(-1); ov:step(-1)
assert(text(ov) == "t1")
ov:step(1); ov:step(1); ov:step(1); ov:step(1); ov:step(1)
assert(text(ov) == "t6")
ov:step(1); assert(doc.page == 2 and text(ov) == "t7", "→ on the last word = next page")
ov:step(-1); assert(doc.page == 1 and text(ov) == "t6", "← on the first word = previous page, last word")
assert(ov:_status_text():match("^WORD ") and not ov:_status_text():find("%d"))
assert(ov:_status_text() == "WORD \xC2\xB7 \xE2\x86\x90\xE2\x86\x92 word \xE2\x86\x91\xE2\x86\x93 line"
    .. " \xC2\xB7 RT select \xC2\xB7 X hl \xC2\xB7 Y vort \xC2\xB7 A menu \xC2\xB7 B close", ov:_status_text())
assert(ov:_status_text(true) == "WORD \xC2\xB7 A menu \xC2\xB7 B close", ov:_status_text(true))
assert(ov:back() == false, "B without a range, not from the labels: padnav closes")
sel:_close()
-- the end of the book: ↓ on the last line stays, ↑ off the first line =
-- the previous page's last word
sel, doc = fresh(3)
sel:_open_walk(true); ov = sel.overlay
assert(text(ov) == "t18")
ov:line(-1); assert(text(ov) == "t15", "↑ = the word above")
ov:line(1); assert(text(ov) == "t18")
ov:line(1); assert(doc.page == 3 and text(ov) == "t18", "↓ on the book's last line: stays")
ov:line(-1); ov:line(-1); assert(doc.page == 2 and text(ov) == "t12", "↑ off the first line = page 2, last word")
sel:_close()

-- 5c. A range by a line (RT / A held, TASK-43 / TASK-44): the anchor stays,
-- both directions, never off the page; a plain move drops it.
sel, doc = fresh()
sel:_open_walk(false); ov = sel.overlay
ov:step(1)
ov:line(1, true); assert(ov.ww_anchor and text(ov) == "t2 t3 t4 t5", "RT + ↓ = range to the line below, not to the sentence end")
ov:line(1, true); assert(doc.page == 1 and text(ov) == "t2 t3 t4 t5", "range: no page turn")
ov:line(-1, true); assert(text(ov) == "t2", "RT + ↑ = back by a line")
ov:line(-1, true); assert(doc.page == 1 and text(ov) == "t2", "range: not off the page (top)")
ov:step(1, true); ov:line(1, true); assert(text(ov) == "t2 t3 t4 t5 t6", "word, then a line")
ov:line(1); assert(ov.ww_anchor == nil and doc.page == 2, "without a range the anchor goes")
sel:_close()
-- a word hyphenated over two lines (t3: head at the end of line 1, tail at
-- the start of line 2): a line move lands on the fragment under the x, and
-- from a tail the line is the tail's
sel, doc = fresh()
local SPLIT_TAIL = { x = 10, y = 50, w = 30, h = 20 }
function doc:getScreenBoxesFromPositions(a, b)
    if self.page == 1 and idx(a) == 3 and idx(b) == 3 then return { self:box(3), SPLIT_TAIL } end
    return Doc.getScreenBoxesFromPositions(self, a, b)
end
function doc:getWordFromPosition(pos)
    if self.page == 1 and math.abs(pos.y - 60) < 5 and pos.x < 40 then
        return { pos0 = "w3", pos1 = "w3e", word = "t3" }
    end
    return Doc.getWordFromPosition(self, pos)
end
sel:_open_walk(false); ov = sel.overlay
ov:line(1)
assert(text(ov) == "t3" and ov.ww_word.is_split_fragment == "tail", "↓ from t1: t3's tail on line 2: "
    .. tostring(text(ov)) .. " " .. tostring(ov.ww_word.is_split_fragment))
ov:line(-1)
assert(text(ov) == "t1", "↑ from the tail = line 1 at the tail's x: " .. tostring(text(ov)))
for _ = 1, 6 do ov:step(1) end; assert(text(ov) == "t6", "t3 counts twice (head, tail)")
ov:line(-1)
assert(text(ov) == "t3" and ov.ww_word.is_split_fragment == "head", "↑ from t6: t3's head: "
    .. tostring(ov.ww_word.is_split_fragment))
ov:line(1); assert(text(ov) == "t6", "↓ from the head = the word under it")
sel:_close()

-- 5a. Y + D-pad ↑/← (TASK-28): the sentences from the page's last one
sel, doc = fresh()
sel:_open(true); ov = sel.overlay
assert(ov.mode == "struct" and ov.sel_cur == 2 and text(ov) == "t5 t6 t7 t8", "from_end = last sentence: " .. tostring(text(ov)))
sel:_close()

-- 5b. LT / RT (TASK-25): in words nothing any more (TASK-42: RT held is the
-- range modifier there); in sentences the next / previous paragraph
sel, doc = fresh()
sel:_open_walk(false); ov = sel.overlay
ov:para(1); assert(doc.page == 1 and text(ov) == "t1", "RT in words: no move")
ov:step(1); ov:para(-1); assert(text(ov) == "t2", "LT in words: no move")
ov:para(1, true); assert(ov.ww_anchor == nil and text(ov) == "t2", "no paragraph range either")
sel:_close()
sel, doc = fresh()
sel:_open(); ov = sel.overlay
ov:para(1); assert(doc.page == 2 and text(ov) == "t9 t10", "RT in sentences = next paragraph")
sel:_close()
sel, doc = fresh()
sel:_open_walk(true); ov = sel.overlay
assert(text(ov) == "t6", "D-pad ↑/← opens on the last word")

-- 6. Word range: anchor stays, both directions, stays on the page
sel:_close()
sel, doc = fresh()
sel:_open_walk(false); ov = sel.overlay
ov:step(1)                                  -- t2
ov:step(1, true); ov:step(1, true)          -- anchor t2, cursor t4
assert(text(ov) == "t2 t3 t4", tostring(text(ov)))
ov:step(-1, true); ov:step(-1, true); ov:step(-1, true)
assert(text(ov) == "t1 t2", "back over the anchor: " .. tostring(text(ov)))
ov:step(-1, true); assert(doc.page == 1 and text(ov) == "t1 t2", "range stays on the page (start)")
for _ = 1, 6 do ov:step(1, true) end
assert(doc.page == 1 and text(ov) == "t2 t3 t4 t5 t6", "range stays on the page (end)")
assert(ov:_status_text():match("^WORDS"))

-- 6a. RT held outside the sentence phase (TASK-44 / PC-025): ↑/↓ by a
-- line (see 5c), ←/→ by a word; B drops the range, the cursor stays at its
-- moving end.
sel:_close()
sel, doc = fresh()
sel:_open_walk(false); ov = sel.overlay
ov:line(1, true)
assert(ov.ww_anchor and text(ov) == "t1 t2 t3 t4", "↓ = the line below (t4 under t1): " .. tostring(text(ov)))
assert(ov:_status_text():match("^WORDS") and ov:_status_text(true):find("B clear", 1, true))
ov:step(1, true); assert(text(ov) == "t1 t2 t3 t4 t5", "→ = by a word")
ov:line(1, true); assert(doc.page == 1 and text(ov) == "t1 t2 t3 t4 t5", "a range stays on the page")
assert(ov:back() == true and ov.ww_anchor == nil and text(ov) == "t5", "B clears the range")
sel:_close()

-- 7. Levels (TASK-17): R-stick ↓ sentence -> its first word, ↑ word -> its sentence
sel:_close()
sel, doc = fresh()
sel:_open(); ov = sel.overlay
ov:step(1)                                  -- S2
ov:to_words(); assert(ov.mode == "walk" and text(ov) == "t5", "sentence -> its first word")
ov:step(1); ov:step(1); ov:step(1)          -- t8 on page 2
assert(doc.page == 2 and text(ov) == "t8")
ov:to_sentences()
assert(ov.mode == "struct" and text(ov) == "t5 t6 t7 t8", "word -> the sentence containing it")
ov:step(1, true); ov:to_words(); assert(ov.sel_anchor == nil and ov.ww_anchor == nil, "a range is dropped")

-- 8. End of the book: → on the last word stays there
sel:_close()
sel, doc = fresh(3)
sel:_open_walk(true); ov = sel.overlay
ov:step(1); assert(doc.page == 3 and text(ov) == "t18", "last word of the book")
ov:to_sentences(); ov:step(1)
assert(doc.page == 3 and text(ov) == "t17 t18", "last sentence of the book")

-- 9. Highlights (Y): opened on the first, D-pad steps with wrapping, X removes
local anns = { { pos0 = "w2", pos1 = "w3e" }, { pos0 = "w5", pos1 = "w5e", note = "n" } }
sel:_close()
sel, doc = fresh(1, anns)
assert(sel:_open_highlights() == true and sel.overlay.mode == "hl" and claims == 1)
ov = sel.overlay
assert(text(ov) == "t2 t3")
ov:step(1); assert(text(ov) == "t5" and ov:_status_text():find("[note]", 1, true))
ov:line(1); assert(text(ov) == "t2 t3", "wraps")
ov:step(-1); assert(ov.hl_cur == 2)
ov:_do_toggle_highlight(ov:_get_selection())
assert(#anns == 1 and ov.hl_cur == 1 and text(ov) == "t2 t3", "removed, focus on the one left")
ov:_do_toggle_highlight(ov:_get_selection())
assert(#anns == 0 and ov.hl_cur == 0, "none left")
sel:_close()
assert(claims == 0)
-- a page without highlights: nothing opens, the claim is given back
sel = fresh(3, { { pos0 = "w2", pos1 = "w3e" } })
assert(sel:_open_highlights() == false and sel.overlay == nil and claims == 0)

-- 10. Point from-to (A tapped, TASK-29; sentences TASK-35; sentence labels
-- only since TASK-42 / PC-024): labels at the sentences of the page (page 1:
-- S1 = t1-t4, S2 = t5-t6 visible); a label = the word walk with the cursor
-- on that sentence's first visible word, nothing selected; B steps back:
-- range -> none -> the labels -> close. The labels come from kopad_hints.lua
-- (tests/kopad_hints_test.lua).
local function label_of(ov, sent)
    for _, v in ipairs(ov.pointer:visible()) do
        if v.sent == sent then return v.label end
    end
end
local function press(ov, l)
    assert(l, "a label")
    local res
    for _, s in ipairs(l) do res = ov:point_press(s) end
    return res
end
sel, doc = fresh()
assert(sel:_open_point() == true and claims == 1)
ov = sel.overlay
local vis = ov.pointer:visible()
assert(ov.mode == "point" and #vis == 2, "two sentences on the page")
assert(vis[1].word == 1 and vis[2].word == 5 and vis[2].x == doc:box(5).x, "at the sentence starts")
assert(ov:_status_text() == "FROM \xC2\xB7 label = sentence \xC2\xB7 B close", ov:_status_text())
assert(ov:_status_text(true) == "FROM \xC2\xB7 B close", ov:_status_text(true))
assert(ov:_get_selection() == nil, "no selection while labelling")
ov:step(1); ov:line(1); ov:para(1); ov:action_menu(); ov:to_words(); ov:to_sentences()
assert(ov.mode == "point" and doc.page == 1, "arrows / menu / levels do nothing in the labels")
assert(ov:back() == false, "back() is for the words only")
-- painting the labels: a smoke test with a recording blitbuffer
local TW = require("ui/widget/textwidget")
function TW:new(o) return setmetatable(o or {}, { __index = { getSize = function() return { w = 8, h = 10 } end,
                                                            paintTo = function() end, free = function() end } }) end
local painted = {}
local bb = setmetatable({}, { __index = function(_, k) return function() painted[k] = (painted[k] or 0) + 1 end end })
local function paint() painted = {}; ov:paintTo(bb, 0, 0); return painted end
paint()
assert(painted.paintBorder and painted.paintRect and (painted.paintCircle or 0) + painted.paintBorder >= 4,
    "two labels painted")
assert(not painted.invertRect, "labels: no selection painted")
-- a label = the words, the cursor on S2's first word, no anchor
assert(press(ov, label_of(ov, 2)) == "done")
assert(ov.mode == "walk" and ov.pointer == nil and ov.ww_anchor == nil and text(ov) == "t5",
    "S2's first word: " .. tostring(text(ov)))
assert(ov.from_labels == true and ov.sent_phase == true, "from the labels, in the sentence phase")
assert(ov:_status_text() == "START \xC2\xB7 \xE2\x86\x90\xE2\x86\x92 word \xE2\x86\x91\xE2\x86\x93 line"
    .. " \xC2\xB7 RT\xE2\x86\x93 sentence \xC2\xB7 X hl \xC2\xB7 Y vort \xC2\xB7 A menu \xC2\xB7 B back", ov:_status_text())
assert(ov:_status_text(true) == "START \xC2\xB7 A menu \xC2\xB7 B back", ov:_status_text(true))
paint()
assert(painted.invertRect, "the cursor word painted")
-- B: back to the labels on the same page
assert(ov:back() == true and ov.mode == "point" and #ov.pointer:visible() == 2, "B = the labels again")
assert(press(ov, label_of(ov, 1)) == "done" and text(ov) == "t1")
-- RT held + ↓ = a range; B clears it, then the labels, then (cancel) close
ov:line(1, true); assert(text(ov) == "t1 t2 t3 t4")
ov:para(1); ov:para(-1); assert(text(ov) == "t1 t2 t3 t4", "LT / RT: no move in words")
assert(ov:back() == true and ov.ww_anchor == nil and text(ov) == "t4", "B 1: the range goes")
assert(ov:back() == true and ov.mode == "point", "B 2: the labels")
assert(ov:point_press("B") == "cancel", "B 3: close (padnav)")
sel:_close()
-- after a page turn B goes to the labels of the page shown now
sel, doc = fresh()
sel:_open_point(); ov = sel.overlay
press(ov, label_of(ov, 2))
ov:line(1); assert(doc.page == 2 and text(ov) == "t7", "↓ off the last line = the next page (a line move)")
assert(ov.sent_phase == false, "a plain move ends the phase")
assert(ov:back() == true and ov.mode == "point" and #ov.pointer:visible() == 3 and ov.words[1].xp0 == "w7",
    "the labels of page 2")
sel:_close()
-- page 2: S2 (begun on page 1) labelled at its visible part t7
sel, doc = fresh(2)
sel:_open_point(); ov = sel.overlay
vis = ov.pointer:visible()
assert(#vis == 3 and vis[1].word == 1 and ov.words[1].xp0 == "w7", "S2's visible part: t7")
assert(press(ov, label_of(ov, 1)) == "done" and text(ov) == "t7", "the label = its first visible word")
-- the phase on page 2: RT + ↓ = S2's words on this page, then S3, S4 (its
-- last word on the page), never past the page; RT + ↑ one sentence off
ov:line(1, true); assert(text(ov) == "t7 t8", "RT↓ = S2 to its last word on the page: " .. tostring(text(ov)))
ov:line(1, true); assert(text(ov) == "t7 t8 t9 t10", "RT↓ again = to the end of S3")
ov:line(1, true); assert(text(ov) == "t7 t8 t9 t10 t11 t12", "RT↓ = S4's last word on the page")
ov:line(1, true); assert(doc.page == 2 and text(ov) == "t7 t8 t9 t10 t11 t12", "no next sentence: stays")
ov:line(-1, true); assert(text(ov) == "t7 t8 t9 t10", "RT↑ = S4 off")
ov:line(-1, true); ov:line(-1, true)
assert(ov.ww_anchor == nil and text(ov) == "t7" and ov.sent_phase, "the start sentence off: no range, phase on")
ov:line(-1); assert(doc.page == 1 and text(ov) == "t6", "↑ = a line: page 1's last word")
sel:_close()
-- 10a. The sentence phase (TASK-44 / PC-025) on page 1: S1 = t1-t4, S2 = t5-t6
sel, doc = fresh()
sel:_open_point(); ov = sel.overlay
press(ov, label_of(ov, 1)); assert(text(ov) == "t1" and ov.sent_phase)
ov:line(1, true); assert(ov.ww_anchor and text(ov) == "t1 t2 t3 t4", "RT↓ = the whole sentence")
assert(ov.ww_anchor.pos0 == "w1" and ov.sent_phase, "anchor = the start word, still in the phase")
ov:line(1, true); assert(text(ov) == "t1 t2 t3 t4 t5 t6", "RT↓ again = the end of the next sentence")
ov:line(1, true); assert(doc.page == 1 and text(ov) == "t1 t2 t3 t4 t5 t6", "never past the page")
ov:line(-1, true); assert(text(ov) == "t1 t2 t3 t4", "RT↑ = one sentence off")
ov:line(-1, true); assert(ov.ww_anchor == nil and text(ov) == "t1" and ov.sent_phase,
    "the last one off: no range, the cursor on the start, the phase goes on")
ov:line(-1, true); assert(ov.ww_anchor == nil and text(ov) == "t1" and ov.sent_phase, "RT↑ without a range: nothing")
ov:line(1, true); assert(text(ov) == "t1 t2 t3 t4")
-- RT + → ends the phase, keeps the anchor and moves the end by a word;
-- after that RT + ↑/↓ go by a line
ov:step(1, true); assert(text(ov) == "t1 t2 t3 t4 t5" and not ov.sent_phase, "RT→ = the end by a word, phase over")
assert(ov:_status_text():match("^WORDS") and ov:_status_text():find("RT select", 1, true))
ov:line(-1, true); assert(text(ov) == "t1 t2", "RT↑ now = a line up (t2 above t5): " .. tostring(text(ov)))
sel:_close()
-- a plain move ends the phase: RT + ↓ is then a line
sel, doc = fresh()
sel:_open_point(); ov = sel.overlay
press(ov, label_of(ov, 1))
ov:step(1); assert(text(ov) == "t2" and not ov.sent_phase, "→ without RT ends the phase")
ov:line(1, true); assert(text(ov) == "t2 t3 t4 t5", "RT↓ = to the line below, not the sentence end")
sel:_close()
sel, doc = fresh()
sel:_open_point(); ov = sel.overlay
press(ov, label_of(ov, 1))
ov:line(1); assert(text(ov) == "t4" and not ov.sent_phase, "↓ without RT = a line, ends the phase")
sel:_close()
-- B: dropping a sentence range ends the phase (the cursor is not on the
-- start word); the labels again and a new label = a new phase
sel, doc = fresh()
sel:_open_point(); ov = sel.overlay
press(ov, label_of(ov, 2)); assert(text(ov) == "t5")
ov:line(1, true); assert(text(ov) == "t5 t6", "RT↓ = S2 on page 1")
assert(ov:back() == true and ov.ww_anchor == nil and text(ov) == "t6" and not ov.sent_phase, "B: range off, phase over")
ov:line(1, true); assert(text(ov) == "t6", "RT↓ = a line now: none below on the page")
assert(ov:back() == true and ov:back() == true and ov.mode == "point", "B: range off, then the labels")
press(ov, label_of(ov, 1)); assert(text(ov) == "t1" and ov.sent_phase, "a new label = a new phase")
ov:to_sentences(); ov:to_words(); assert(ov.mode == "walk" and not ov.sent_phase, "the levels end the phase")
sel:_close()
-- R-stick ↓ from sentences into words: not from the labels, B closes
sel, doc = fresh()
sel:_open(); ov = sel.overlay
ov:to_words(); assert(ov.mode == "walk" and ov.from_labels == false and ov:back() == false)
sel:_close()
-- B in the start step on the sentences: cancel (padnav closes the overlay)
sel = fresh()
sel:_open_point()
assert(sel.overlay:point_press("B") == "cancel")
sel:_close()
assert(claims == 0)

-- 11. The status bar never covers the page text (statusbar.lua, the user's
-- rule): it goes into the free strip above or below the text, shortened when
-- the strips are tight, not drawn at all when no strip holds a line of text.
-- The stub text widget is 10 px tall: full bar 20 px, short bar 12 px.
do
    local sel11, _, ui11 = fresh()
    sel11:_open()
    local ov11 = sel11.overlay
    local short = ov11:_status_text(true)
    assert(short:match("^SENTENCES?") and short:find("A menu", 1, true) and not short:find("X hl", 1, true),
        "short status text: " .. short)
    ui11.view = { footer_visible = true, footer = { getHeight = function() return 44 end } }
    assert(ov11:_footer_height() == 44)
    ui11.view.footer_visible = false
    assert(ov11:_footer_height() == 0, "a hidden footer is no footer")
    ui11.view = { footer_visible = true, footer = { getHeight = function() error("boom") end } }
    assert(ov11:_footer_height() == 0, "a failing footer counts as none")
    ui11.view = nil
    assert(ov11:_footer_height() == 0)

    -- the white rectangle _draw_status paints for words spanning top..bottom
    local function bar(top, bottom, footer_h)
        ov11.words = { { sbox = { y = top, h = 10 } }, { sbox = { y = bottom - 10, h = 10 } } }
        ui11.view = footer_h and { footer_visible = true, footer = { getHeight = function() return footer_h end } } or nil
        local rects = {}
        local rec = setmetatable({}, { __index = function(_, k)
            return function(_, ...) if k == "paintRect" then rects[#rects + 1] = { ... } end end
        end })
        ov11:_draw_status(rec, 0, 0)
        return rects[1]
    end
    local r = bar(100, 700)                         -- 100 px above: the full bar on top
    assert(r and r[2] == 0 and r[4] == 20 and r[2] + r[4] <= 100, "full bar above the text")
    r = bar(10, 700)                                -- 10 above, 100 below: the full bar below
    assert(r and r[2] >= 700 and r[2] + r[4] <= 800 and r[4] == 20, "full bar below the text")
    r = bar(10, 740, 44)                            -- strips 10 and 16 above the footer: short bar
    assert(r and r[4] == 12 and r[2] >= 740 and r[2] + r[4] <= 756, "short bar above the footer")
    assert(bar(5, 795) == nil, "no strip holds a line: no bar")
    ov11.words = {}
    local none = {}
    ov11:_draw_status(setmetatable({}, { __index = function() return function() none[#none + 1] = true end end }), 0, 0)
    assert(#none == 0, "nothing to measure: nothing painted")
    sel11:_close()
end

-- 12. TASK-45: every action closes the overlay (claim given back), the
-- action still runs on the closed overlay; A held + D-pad (_open_walk) then
-- starts at the last word of the last action when it is on the page shown.
do
    local UIM = require("ui/uimanager")
    UIM.nextTick = function(_, f) f() end
    local done, shown = {}, {}
    local old_show = UIM.show
    UIM.show = function(_, w) shown[#shown + 1] = w end
    package.preload["ui/widget/inputdialog"] = function()
        return { new = function(_, t) t.getInputText = function() return "my note" end; return t end }
    end
    package.preload["ui/widget/buttondialog"] = function() return { new = function(_, t) return t end } end
    package.loaded.llm = { ask = function(_, msgs) done[#done + 1] = "ai:" .. msgs[2].content:match("Passage:\n(.*)$") end }
    require("device").input.setClipboardText = function(t) done[#done + 1] = "copy:" .. t end
    local old_dql = { name = "old popup" }
    package.loaded["ui/widget/dictquicklookup"] = { window_list = { old_dql } }

    local anns = {}
    local s, d, u = fresh(1, anns)
    u.dictionary = { onLookupWord = function(_, w) done[#done + 1] = "dict:" .. w end }
    u.highlight = { saveHighlight = function(rh)
        local t = rh.selected_text
        anns[#anns + 1] = { pos0 = t.pos0, pos1 = t.pos1, text = t.text }
        done[#done + 1] = "hl:" .. t.text
        return #anns
    end }
    u.vortpaf = { _vortpafLookup = function(_, w) done[#done + 1] = "vortuyo:" .. w end }

    -- open words on t2, the action, then: closed, claim back, action ran
    local function act(name, range_to)
        assert(s:_open_walk(false) == true and claims == 1)
        local o = s.overlay
        o:step(1)                                         -- cursor t2 (or the resume word)
        for _ = 1, range_to or 0 do o:step(1, true) end
        assert(o:act(name) == true, name)
        assert(s.overlay == nil and o.closed and claims == 0, name .. " closes the overlay")
        return o
    end
    -- copy t2: the words open there again
    act("copy")
    assert(done[#done] == "copy:t2" and shown[#shown].text == "Copied", "copied, message after the close")
    s:_open_walk(false); assert(text(s.overlay) == "t2", "resume at the copied word")
    assert(s.overlay:act("dict") == true and s.overlay == nil and done[#done] == "dict:t2")
    -- the dictionary popup: the first new one is kopad's, Y = AI there
    local dql = { name = "kopad popup" }
    package.loaded["ui/widget/dictquicklookup"].window_list[2] = dql
    assert(s:dict_selection(old_dql) == nil, "a popup open before the lookup is not kopad's")
    local o2, s2 = s:dict_selection(dql)
    assert(o2 and s2.text == "t2", "kopad's popup -> the looked-up selection")
    assert(s:dict_selection({}) == nil, "a popup opened from it is not")
    o2:_do_ai(s2); assert(done[#done] == "ai:t1 t2 t3 t4 t5 t6", "AI on the closed overlay: the page passage")
    -- highlight: the words open on t2 (resume), → t3, range to t5
    act("highlight", 2)
    assert(done[#done] == "hl:t3 t4 t5", tostring(done[#done]))
    assert(s.dict_from == nil, "another action forgets the lookup")
    s:_open_walk(true); assert(text(s.overlay) == "t5", "resume at the range's end, also for ←/↑")
    s:_close()
    -- X toggles the highlight just made: removed, closed
    s:_open_highlights(); assert(s.overlay.mode == "hl")
    local nb = #anns
    assert(s.overlay:act("toggle_highlight") and s.overlay == nil and #anns == nb - 1 and claims == 0)
    -- note: a new highlight, the note dialog shown after the close, Save reaches it
    act("note")
    local dlg = shown[#shown]
    assert(dlg.title == "Note" and s.overlay == nil, "note dialog after the close")
    dlg.buttons[1][2].callback()
    assert(anns[#anns].note == "my note", "the note is saved on its highlight")
    -- Vortuyo, AI
    act("vortuyo"); assert(done[#done]:match("^vortuyo:"))
    act("ai"); assert(done[#done]:match("^ai:"))
    -- no selection: nothing happens, the overlay stays
    s:_open_walk(false); s.overlay.ww_word = nil
    assert(s.overlay:act("copy") == false and s.overlay ~= nil and claims == 1)
    s:_close()
    -- another page: the first / last word as before; sentences never resume
    d.page, s.resume = 1, nil
    s:_open_walk(false); s.overlay:step(1); s.overlay:act("copy")   -- t2
    local resume_word = s.resume and s.resume.xp
    assert(resume_word == "w2e", tostring(resume_word))
    d.page = 2
    s:_open_walk(false); assert(text(s.overlay) == "t7", "other page: first word")
    s:_close(); s:_open_walk(true); assert(text(s.overlay) == "t12", "other page: last word")
    s:_close()
    d.page = 1
    s:_open(); assert(text(s.overlay) == "t1 t2 t3 t4", "Y + D-pad (sentences) unaffected")
    s:_close()
    s:_open_walk(false)
    assert(resume_word and s.overlay.ww_word.pos1 == resume_word, "back on the page: resumed")
    s:_close()
    -- the action menu runs the actions through act (the overlay closes)
    s:_open_walk(false)
    s.overlay:action_menu()
    local menu = shown[#shown]
    assert(menu._kopad_snippet, "the action menu")
    menu.buttons[1][2].callback()                       -- Copy
    assert(s.overlay == nil and claims == 0 and done[#done]:match("^copy:"), "menu Copy closes")

    UIM.show, UIM.nextTick = old_show, nil
    package.loaded["ui/widget/dictquicklookup"] = nil
    package.loaded.llm = nil
end

print("selector_test: all tests passed")
