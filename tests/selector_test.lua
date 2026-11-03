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

-- 5. Words (D-pad): first / last word, word and line moves over page edges
sel:_close()
sel, doc = fresh()
sel:_open_walk(false); ov = sel.overlay
assert(ov.mode == "walk" and text(ov) == "t1", "D-pad ↓/→ opens on the first word")
ov:step(1); assert(text(ov) == "t2")
ov:line(1); assert(text(ov) == "t5", "↓ = word below at the same x: " .. tostring(text(ov)))
ov:line(-1); assert(doc.page == 1 and text(ov) == "t2", "↑ = word above at the same x, not the word on the left: " .. tostring(text(ov)))
ov:line(1); assert(text(ov) == "t5")
ov:line(1); assert(doc.page == 2 and text(ov) == "t7", "↓ on the last line = next page, first word")
ov:step(-1); assert(doc.page == 1 and text(ov) == "t6", "← on the first word = previous page, last word")
ov:step(1); assert(doc.page == 2 and text(ov) == "t7", "→ on the last word = next page")
ov:line(-1); assert(doc.page == 1 and text(ov) == "t6", "↑ on the first line = previous page, last word")
assert(ov:_status_text():match("^WORD ") and not ov:_status_text():find("%d"))
sel:_close()

-- 5a. Y + D-pad ↑/← (TASK-28): the sentences from the page's last one
sel, doc = fresh()
sel:_open(true); ov = sel.overlay
assert(ov.mode == "struct" and ov.sel_cur == 2 and text(ov) == "t5 t6 t7 t8", "from_end = last sentence: " .. tostring(text(ov)))
sel:_close()

-- 5b. LT / RT in words (TASK-25): the first word of the next / this or the
-- previous paragraph, over page edges; a paragraph that began on the
-- previous page is reached at its real start
sel, doc = fresh()
sel:_open_walk(false); ov = sel.overlay
ov:para(1); assert(doc.page == 2 and text(ov) == "t9", "RT = next paragraph, over the edge: " .. tostring(text(ov)))
ov:para(1); assert(doc.page == 3 and text(ov) == "t14", "RT again: paragraph 3 on page 3: " .. tostring(text(ov)))
ov:step(1); assert(text(ov) == "t15")
ov:para(-1); assert(doc.page == 3 and text(ov) == "t14", "LT inside a paragraph = its first word")
ov:para(-1); assert(doc.page == 2 and text(ov) == "t9", "LT = previous paragraph, at its start on page 2: " .. tostring(text(ov)))
ov:para(-1); assert(doc.page == 1 and text(ov) == "t1", "LT = paragraph 1: " .. tostring(text(ov)))
ov:para(-1); assert(doc.page == 1 and text(ov) == "t1", "first paragraph of the book: stays")
-- range (A held): paragraph by paragraph on the page only
sel:_close()
sel, doc = fresh(2)
sel:_open_walk(false); ov = sel.overlay
assert(text(ov) == "t7")
ov:para(1, true); assert(doc.page == 2 and text(ov) == "t7 t8 t9", "range to the next paragraph: " .. tostring(text(ov)))
ov:para(1, true); assert(doc.page == 2 and text(ov) == "t7 t8 t9", "a paragraph range stays on the page")
-- sentences: LT / RT = ↓ / ↑; highlights: next / previous
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

-- 10. Point from-to (A tapped, TASK-29, on sentences since TASK-35 /
-- PC-022): labels at the sentences of the page (page 1: S1 = t1-t4, S2 =
-- t5-t6 visible), start + end = a word range of whole sentences, R-stick ↓
-- refines a step to a word, B = one word, then the usual word walk. The
-- labels come from kopad_hints.lua (tests/kopad_hints_test.lua).
local function label_of(ov, sent, word)
    for _, v in ipairs(ov.pointer:visible()) do
        if (sent and v.sent == sent) or (word and v.word == word) then return v.label end
    end
end
local function press(ov, l) assert(l, "a label"); ov:point_press(l[1]); return ov:point_press(l[2]) end
sel, doc = fresh()
assert(sel:_open_point() == true and claims == 1)
ov = sel.overlay
local vis = ov.pointer:visible()
assert(ov.mode == "point" and #vis == 2, "two sentences on the page")
assert(vis[1].word == 1 and vis[2].word == 5 and vis[2].x == doc:box(5).x, "at the sentence starts")
assert(ov:_status_text():match("^FROM") and ov:_status_text():find("R\xE2\x86\x93 word", 1, true), ov:_status_text())
assert(ov:_status_text(true) == "FROM \xC2\xB7 B close", ov:_status_text(true))
assert(ov:_get_selection() == nil, "no selection while labelling")
ov:step(1); ov:line(1); ov:para(1); ov:action_menu(); ov:to_words(); ov:to_sentences()
assert(ov.mode == "point" and doc.page == 1, "arrows / menu / levels do nothing in the labels")
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
local l = label_of(ov, 1)
assert(ov:point_press(l[1]) == "prefix" and ov:point_press(l[2]) == "start")
paint()
assert(painted.invertRect, "end labels: the start word inverted")
vis = ov.pointer:visible()
assert(ov:_status_text():match("^TO") and #vis == 2 and vis[1].word == 4 and vis[2].word == 6,
    "end labels: at the ends of S1 and S2")
assert(press(ov, label_of(ov, 2)) == "done")
assert(ov.mode == "walk" and ov.pointer == nil and text(ov) == "t1 t2 t3 t4 t5 t6", "S1 start .. S2 end")
-- then the usual walk: A + arrows move the end, the anchor stays
ov:step(-1, true); assert(text(ov) == "t1 t2 t3 t4 t5", "A + ← shrinks from the end")
sel:_close()
-- one sentence as start and end: that sentence
sel, doc = fresh()
sel:_open_point(); ov = sel.overlay
press(ov, label_of(ov, 1)); press(ov, label_of(ov, 1))
assert(text(ov) == "t1 t2 t3 t4", "one sentence: " .. tostring(text(ov)))
sel:_close()
-- page 2: S2 (begun on page 1) labelled at its visible part t7; B in the end
-- step = one word
sel, doc = fresh(2)
sel:_open_point(); ov = sel.overlay
vis = ov.pointer:visible()
assert(#vis == 3 and vis[1].word == 1 and ov.words[1].xp0 == "w7", "S2's visible part: t7")
press(ov, label_of(ov, 2))
assert(ov:point_press("B") == "done" and ov.mode == "walk" and ov.ww_anchor == nil and text(ov) == "t9",
    "B = one word: " .. tostring(text(ov)))
sel:_close()
-- refinement (R-stick ↓): start on t2, the end refined to t5; B on the word
-- labels goes back to the sentences, R-stick ↑ turns it off
sel, doc = fresh()
sel:_open_point(); ov = sel.overlay
assert(ov:point_refine(true) == true and ov:_status_text():match("^FROM WORD"), ov:_status_text())
assert(ov:point_refine(true) == false, "already on")
assert(press(ov, label_of(ov, 1)) == "sentence" and #ov.pointer:visible() == 4, "S1's four words")
assert(ov:_status_text():match("^FROM WORD") and ov:_status_text():find("B sentences", 1, true))
paint()
assert(painted.paintBorder, "word labels painted")
assert(ov:point_press("B") == "back" and #ov.pointer:visible() == 2, "B: the sentence labels again")
press(ov, label_of(ov, 1))
assert(press(ov, label_of(ov, nil, 2)) == "start" and ov:_status_text():match("^TO "), "start on t2")
ov:point_refine(true)
assert(press(ov, label_of(ov, 1)) == "sentence")
assert(#ov.pointer:visible() == 3, "S1 from the start word: t2 t3 t4")
assert(ov:point_refine(false) == true and ov.pointer.level == "sentence", "R↑: sentences")
ov:point_refine(true)
press(ov, label_of(ov, 2))
assert(press(ov, label_of(ov, nil, 5)) == "done" and text(ov) == "t2 t3 t4 t5", "t2 .. t5: " .. tostring(text(ov)))
sel:_close()
-- B in the start step: cancel (padnav closes the overlay)
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

print("selector_test: all tests passed")
