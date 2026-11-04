-- Tests for pdfwords.lua (the PDF / DjVu word source, pure) and the
-- selection overlay on a paged document (selector.lua PagedOverlay, TASK-30),
-- against a fake three-page PDF with a zoomed and panned view.
-- Run from the repo root: lua tests/pdfwords_test.lua
--
--   page 1: Alpha beta gamma. / Delta eps zeta       S1 = Alpha..gamma.
--                                                    S2 = Delta..zeta (runs on to page 2)
--   page 2: eta theta. / Iota kappa lam!             S1 = eta theta. (began on page 1)
--                                                    S2 = Iota kappa lam!
--   page 3: a scan: optical word boxes, no text
-- Native boxes: word j of line l at x = 100 + (j-1)*120 .. +100,
-- line y = 100 + (l-1)*50 .. +30 (the word box 2 px inside the line).
package.path = "./?.lua;" .. package.path

local TEXT = {
    { { "Alpha", "beta", "gamma." }, { "Delta", "eps", "zeta" } },
    { { "eta", "theta." }, { "Iota", "kappa", "lam!" } },
}
local custom -- a table of fake pages (section 3 below) replaces the three above
local function page_boxes(page)
    if custom then return custom[page] end
    if page == 3 then -- optical fallback: boxes, no `word`
        return { { x0 = 100, y0 = 100, x1 = 300, y1 = 130, { x0 = 100, y0 = 100, x1 = 300, y1 = 130 } } }
    end
    local t = TEXT[page]
    if not t then return nil end
    local boxes = {}
    for l, words in ipairs(t) do
        local y0 = 100 + (l - 1) * 50
        local line = { x0 = 100, y0 = y0, x1 = 100 + #words * 120 - 20, y1 = y0 + 30 }
        for j, w in ipairs(words) do
            local x0 = 100 + (j - 1) * 120
            line[j] = { word = w, x0 = x0, y0 = y0 + 2, x1 = x0 + 100, y1 = y0 + 28 }
        end
        boxes[l] = line
    end
    return boxes
end

-- KOReader stubs
local function stub(name, v) package.preload[name] = function() return v end end
local IC = {}
function IC:extend(o) o = o or {}; setmetatable(o, { __index = self }); o.__index = o; return o end
function IC:new(o) o = o or {}; setmetatable(o, self); if o.init then o:init() end; return o end
local shown = {}
stub("logger", { dbg = function() end, warn = function() end })
stub("ffi/blitbuffer", { COLOR_BLACK = 0, COLOR_WHITE = 1, COLOR_GRAY = 2 })
stub("device", { screen = { getWidth = function() return 600 end, getHeight = function() return 800 end,
                            scaleBySize = function(_, v) return v end },
                 input = {} })
stub("ui/event", { new = function(_, name, ...) return { name = name, args = { ... } } end })
stub("ui/geometry", { new = function(_, t) return t end })
stub("ui/widget/infomessage", { new = function(_, t) return t end })
stub("ui/widget/container/inputcontainer", IC)
stub("ui/widget/textwidget", { new = function(_, o)
    return setmetatable(o or {}, { __index = { getSize = function() return { w = 8, h = 10 } end,
                                               paintTo = function() end, free = function() end } })
end })
stub("ui/uimanager", { show = function(_, w) shown[#shown + 1] = w end, close = function() end,
                       setDirty = function() end })
stub("util", { cleanupSelectedText = function(s) return s end })
stub("gettext", function(s) return s end)
stub("ui/font", { getFace = function() return {} end })
local menus = {}
stub("ui/widget/buttondialog", { new = function(_, t) menus[#menus + 1] = t; return t end })
local claims = 0
stub("pluginaro", { claim_overlay = function() claims = claims + 1; return true end,
                    release_overlay = function() claims = claims - 1 end })

local PdfWords = require("pdfwords")
local Selector = require("selector")

----------------------------------------------------------------------
-- 1. pdfwords.lua (pure)
----------------------------------------------------------------------
assert(PdfWords.has_text(page_boxes(1)) and not PdfWords.has_text(page_boxes(3))
    and not PdfWords.has_text(nil) and not PdfWords.has_text({ { { word = " " } } }), "has_text")
-- the sentence rule (paginmapo's, on the word's own end)
for _, c in ipairs({ { "gamma.", "Delta", true }, { "Dr.", "who", false }, { "end.", nil, false },
                     { "why?", "x", true }, { "lam!", nil, true }, { 'said."', "Then", true },
                     { "said.\xE2\x80\x9D", "Then", true }, { "zeta", "Eta", false },
                     { "(sic.)", "Next", true }, { "\xD8\x9F", nil, true } }) do
    assert(PdfWords.ends_sentence(c[1], c[2]) == c[3],
        "ends_sentence(" .. c[1] .. ", " .. tostring(c[2]) .. ") ~= " .. tostring(c[3]))
end
local W = PdfWords.words_from_boxes(page_boxes(1), 1)
assert(#W == 6 and W[1].text == "Alpha" and W[4].line == 2 and W[3].line == 1, "words and lines")
assert(W[2].pos0 == "pdf/1/2" and W[2].xp0 == W[2].pos0 and W[2].idx == 2, "keys")
assert(W[1].pbox.x == 100 and W[1].pbox.y == 100 and W[1].pbox.w == 100 and W[1].pbox.h == 30,
    "pbox = word x, line y / h")
assert(W[1].cx == 150 and W[1].cy == 115, "centre of the word box")
assert(W[3].sent_end and not W[6].sent_end and not W[5].sent_end, "sent_end")
local S = PdfWords.sentences(W)
assert(#S == 2 and S[1].first == 1 and S[1].last == 3 and S[2].first == 4 and S[2].last == 6, "sentences")
assert(S[1].para == 1 and S[2].para == 1 and W[1].para == 1 and W[6].para == 1,
    "TASK-32: two evenly spaced lines are one paragraph")
local lb = PdfWords.line_boxes(W, 2, 5, "pbox")
assert(#lb == 2 and lb[1].x == 220 and lb[1].w == 220 and lb[2].x == 100 and lb[2].w == 220, "one box per line")
assert(PdfWords.text(W, 3, 4) == "gamma. Delta" and PdfWords.first_text(page_boxes(2)) == "eta"
    and PdfWords.last_text(page_boxes(1)) == "zeta" and PdfWords.last_text(page_boxes(3)) == nil, "texts")
local P = PdfWords.pos(W[1], { zoom = 2, rotation = 0 })
assert(P.page == 1 and P.x == 150 and P.y == 115 and P.zoom == 2, "pos")
-- paginmapo stays untouched: its grouping runs on these words as it is
assert(PdfWords.words_from_boxes(nil, 1)[1] == nil and #PdfWords.sentences({}) == 0)

----------------------------------------------------------------------
-- 2. The overlay on a fake PDF, page view zoomed 2x and panned
----------------------------------------------------------------------
local Doc = {}
Doc.__index = Doc
function Doc:getTextBoxes(page) return page_boxes(page) end
function Doc:getPageCount() return custom and #custom or 3 end
function Doc:getProps() return { language = "en" } end
-- the words whose boxes contain pos0 .. pos1, in order (KoptInterface snaps
-- the positions to the words)
function Doc:getTextFromPositions(p0, p1)
    local words = PdfWords.words_from_boxes(page_boxes(p0.page), p0.page)
    local function at(p)
        for i, w in ipairs(words) do if w.cx == p.x and w.cy == p.y then return i end end
    end
    local a, b = at(p0), at(p1)
    if not a or not b then return nil end
    if a > b then a, b = b, a end
    return { text = "T:" .. PdfWords.text(words, a, b), pboxes = { { x = 0, y = 0, w = 1, h = 1 } } }
end

local events
local function fresh(opts)
    opts = opts or {}
    events = {}
    local view = {
        page_scroll = false,
        state = { page = opts.page or 1, zoom = opts.zoom or 2, rotation = 0, offset = { x = 10, y = 20 } },
        visible_area = { x = opts.vx or 150, y = opts.vy or 100, w = 500, h = 300 },
    }
    -- ReaderView:getSinglePageRect: page box * zoom, nil outside the visible area
    function view:pageToScreenTransform(_, r)
        local z, va = self.state.zoom, self.visible_area
        local x, y, w, h = r.x * z, r.y * z, r.w * z, r.h * z
        if x + w <= va.x or x >= va.x + va.w or y + h <= va.y or y >= va.y + va.h then return nil end
        return { x = self.state.offset.x + x - va.x, y = self.state.offset.y + y - va.y, w = w, h = h }
    end
    function view:PanningUpdate(dx, dy)
        events[#events + 1] = ("pan:%d,%d"):format(dx, dy)
        self.visible_area.x, self.visible_area.y = self.visible_area.x + dx, self.visible_area.y + dy
    end
    local doc = setmetatable({ configurable = { text_wrap = opts.reflow and 1 or 0 } }, Doc)
    local lookups = {}
    local ui = { document = doc, paging = { number_of_pages = custom and #custom or 3 }, view = view,
                 dictionary = { onLookupWord = function(_, word, _, boxes) lookups[#lookups + 1] = { word, boxes } end },
                 handleEvent = function(_, ev)
                     events[#events + 1] = ev.name .. ":" .. tostring(ev.args[1])
                     if ev.name == "GotoPage" then
                         view.state.page = ev.args[1]
                         view.visible_area.x, view.visible_area.y = 150, 100 -- the page from the top
                     end
                 end }
    return Selector:new{ ui = ui, paged = true }, ui, lookups
end
local function text(ov) local s = ov:_get_selection(); return s and s.text end
local function cur(ov) return ov.ww_word and ov.ww_word.text end

-- AC#2: the screen boxes follow zoom and pan. Alpha (100..200 x 100..130)
-- at zoom 2 = 200..400 x 200..260, minus the visible area (150, 100), plus
-- the offset (10, 20)
local sel, ui, lookups = fresh()
assert(sel:_open_walk(false) == true and claims == 1)
local ov = sel.overlay
assert(ov.paged and ov.mode == "walk" and cur(ov) == "Alpha", "words from the first on the screen")
local s = ov.words[1].sbox
assert(s.x == 60 and s.y == 120 and s.w == 200 and s.h == 60, ("Alpha on screen: %d,%d %dx%d"):format(s.x, s.y, s.w, s.h))
assert(ov.words[3].sbox == nil, "gamma (x 680..880 zoomed) is right of the view: no screen box")
-- → → : onto gamma, which pans the view just past it (and a tenth of it)
ov:step(1); assert(cur(ov) == "beta")
ov:step(1); assert(cur(ov) == "gamma." and events[1] == "pan:280,0", "reveal: " .. tostring(events[1]))
s = ov.words[3].sbox
assert(s and s.x == 10 + 680 - 430 and s.w == 200, "gamma after the pan")
assert(ov.words[1].sbox == nil, "Alpha left the view")
-- painting recomputes the boxes from the view: pan back by hand, then paint
ui.view.visible_area.x = 150
local painted = {}
local bb = setmetatable({}, { __index = function(_, k) return function(_, ...) painted[#painted + 1] = { k, ... } end end })
ov:paintTo(bb, 0, 0)
assert(ov.words[1].sbox and ov.words[1].sbox.x == 60 and ov.words[3].sbox == nil, "boxes from the view at paint time")
assert(#painted > 0, "something painted")
ui.view.visible_area.x = 430
-- ↓ from gamma (TASK-42): the start of the next sentence, Delta
ov:line(1); assert(cur(ov) == "Delta", "↓ = the next sentence start: " .. tostring(cur(ov)))
ov:step(1); ov:step(1); assert(cur(ov) == "zeta")
-- AC#1: past the last word = next page (a whole page), its first word
events = {}
ov:step(1)
assert(events[1] == "GotoPage:2" and ov.page == 2 and cur(ov) == "eta", "page edge →: " .. tostring(events[1]))
ov:step(-1)
assert(ov.page == 1 and cur(ov) == "zeta", "page edge ←: the last word of the previous page")
-- ↓ on the page's last sentence = the next page's first sentence start (S2's
-- continuation "eta theta." skipped); ↑ = its visible start, then its real
-- start on the previous page
ov:line(1); assert(ov.page == 2 and cur(ov) == "Iota", "↓ past the page: " .. tostring(cur(ov)))
ov:line(-1); assert(ov.page == 2 and cur(ov) == "eta", "↑ = the visible start of S2's continuation")
ov:line(-1); assert(ov.page == 1 and cur(ov) == "Delta", "↑ again = S2's real start on page 1: " .. tostring(cur(ov)))
ov:step(1); ov:step(1); assert(cur(ov) == "zeta")
-- the dictionary gets the selection with SCREEN boxes (highlights: tests/pdfhl_test.lua)
ov:_do_dict(ov:_get_selection())
assert(lookups[1][1] == "T:zeta" and lookups[1][2][1].w == 200, "dictionary with screen boxes")
shown = {}
ov:_do_toggle_highlight(ov:_get_selection())
assert(#shown == 0, "X without ReaderHighlight: nothing, no error")
menus = {}
ov:action_menu()
assert(#menus[1].buttons == 3 and menus[1].buttons[1][1].text == "Dictionary"
    and menus[1].buttons[2][1].text == "Highlight" and menus[1].buttons[2][2].text == "Note"
    and menus[1].buttons[3][2].text == "Vortuyo", "action menu with Highlight / Note (TASK-31)")
assert(ov:_status_text():match("^WORD \xC2\xB7 .* RT select .* B close$"), ov:_status_text())
-- A held: a range from the anchor, never off the page
ov:step(-1, true); ov:step(-1, true)
assert(text(ov) == "T:Delta eps zeta", "range: " .. tostring(text(ov)))
local g = ov:_get_selection()
assert(g.page == 1 and g.pos0.x == 150 and g.pos0.y == 165 and g.pos1.x == 390 and g.pos0.zoom == 2, "pos0 / pos1")
ov:step(1, true); ov:step(1, true); ov:step(1, true)
assert(ov.page == 1 and text(ov) == "T:zeta", "a range stays on the page: " .. tostring(text(ov)))
-- R-stick: the word's sentence and back
ov:to_sentences()
assert(ov.mode == "struct" and text(ov) == "T:Delta eps zeta", "word -> sentence")
ov:to_words(); assert(ov.mode == "walk" and cur(ov) == "Delta")
sel:_close()
assert(claims == 0)

-- AC#1: sentences, over the page edge as in an EPUB
sel = fresh({ zoom = 1, vx = 0, vy = 0 })
assert(sel:_open(false) == true)
ov = sel.overlay
assert(ov.mode == "struct" and text(ov) == "T:Alpha beta gamma.", "first sentence: " .. tostring(text(ov)))
ov:step(1)
assert(text(ov) == "T:Delta eps zeta" and ov.sentences[2]._extends_after, "S2 runs on to page 2")
assert(ov:_status_text():match("^SENTENCE \xE2\x86\x93"), ov:_status_text())
ov:step(1)
assert(ov.page == 2 and text(ov) == "T:Iota kappa lam!", "→ over the edge skips the continuation")
ov:step(-1)
assert(text(ov) == "T:eta theta." and ov.sentences[1]._extends_before, "← to the continuation")
-- ← back over the edge: the sentence over the edge counts once (as in an
-- EPUB), so the previous page's last one (its first half) is skipped
ov:step(-1); assert(ov.page == 1 and text(ov) == "T:Alpha beta gamma.", "← back over the edge: " .. tostring(text(ov)))
-- ↓ / ↑ go by paragraph (TASK-32): page 1 is one paragraph, so ↓ leaves the
-- page and ↑ comes back to its start
ov:line(-1); assert(ov.page == 1 and text(ov) == "T:Alpha beta gamma.", "first page: ↑ stays")
ov:line(1); assert(ov.page == 2 and text(ov) == "T:eta theta.", "↓ = next page's paragraph")
ov:line(-1); assert(ov.page == 1 and text(ov) == "T:Alpha beta gamma.", "↑ = back to the start")
-- AI passage: the page's words
assert(ov:_page_text() == "Alpha beta gamma. Delta eps zeta")
sel:_close()
-- sentences from the end (Y + ↑): the last sentence on the screen
sel = fresh({ zoom = 1, vx = 0, vy = 0 })
sel:_open(true)
assert(text(sel.overlay) == "T:Delta eps zeta", "from the end")
sel:_close()
-- words from the end with a zoomed view: the last word ON THE SCREEN
sel = fresh()
sel:_open_walk(true)
assert(cur(sel.overlay) == "eps", "last visible word: " .. tostring(cur(sel.overlay)))
sel:_close()

-- into the scanned page 3 and back
sel = fresh({ page = 2, zoom = 1, vx = 0, vy = 0 })
sel:_open_walk(true)
ov = sel.overlay
assert(cur(ov) == "lam!")
ov:step(1)
assert(ov.page == 3 and ov.ww_word == nil, "a page without text: no cursor")
ov:step(1); assert(ov.page == 3, "the last page: stays")
ov:step(-1); assert(ov.page == 2 and cur(ov) == "lam!", "back to the text")
sel:_close()

-- AC#3: no text layer = nothing opens (padnav shows the message); reflow too
sel = fresh({ page = 3 })
local ok, why = sel:_open_walk(false)
assert(ok == false and why == "no_text" and sel.overlay == nil and claims == 0, "scan: no_text")
ok, why = sel:_open(false); assert(ok == false and why == "no_text")
ok, why = sel:_open_point(); assert(ok == false and why == "no_text" and claims == 0)
sel = fresh({ reflow = true })
ok, why = sel:_open_walk(false)
assert(ok == false and why == "reflow" and claims == 0, "reflow")

-- point from-to on a PDF page (TASK-35; TASK-42 / PC-024): labels at the
-- sentences, from the words on the screen; a label = the word walk at that
-- sentence's first word; RT held (range = true) + ↑/↓ by sentences; B back
local function label_of(o, sent)
    for _, v in ipairs(o.pointer:visible()) do
        if v.sent == sent then return v.label end
    end
end
local function press(o, l)
    assert(l, "a label")
    local res
    for _, s in ipairs(l) do res = o:point_press(s) end
    return res
end
sel = fresh({ zoom = 1, vx = 0, vy = 0 })
assert(sel:_open_point() == true)
ov = sel.overlay
local vis = ov.pointer:visible()
assert(ov.mode == "point" and #vis == 2 and vis[2].word == 4, "two sentences, S2 at Delta")
assert(vis[1].x == ov.words[1].sbox.x and ov.words[1].sbox.x == 10 + 100, "labels at screen boxes")
painted = {}
ov:paintTo(bb, 0, 0)
assert(#painted > 0, "labels painted")
assert(press(ov, label_of(ov, 2)) == "done" and ov.mode == "walk" and ov.ww_anchor == nil
    and cur(ov) == "Delta", "label = the cursor on Delta, nothing selected")
ov:line(1, true); assert(text(ov) == "T:Delta eps zeta", "RT ↓ = to the end of S2: " .. tostring(text(ov)))
ov:line(1, true); assert(ov.page == 1 and text(ov) == "T:Delta eps zeta", "a range stays on the page")
ov:line(-1, true); assert(text(ov) == "T:Delta", "↑ = the sentence off, back to the anchor")
ov:line(-1, true)
assert(text(ov) == "T:Alpha beta gamma. Delta", "on the anchor ↑ = the previous start: " .. tostring(text(ov)))
assert(ov:back() == true and ov.ww_anchor == nil and cur(ov) == "Alpha", "B: the range goes")
assert(ov:back() == true and ov.mode == "point", "B: the labels again")
assert(press(ov, label_of(ov, 1)) == "done" and cur(ov) == "Alpha")
ov:line(1); assert(cur(ov) == "Delta", "↓ = the next sentence start")
ov:para(1); ov:para(-1); assert(cur(ov) == "Delta", "LT / RT: nothing in words")
sel:_close()
-- page 2: the sentence begun on page 1 is labelled at its visible part
sel = fresh({ page = 2, zoom = 1, vx = 0, vy = 0 })
sel:_open_point(); ov = sel.overlay
vis = ov.pointer:visible()
assert(#vis == 2 and vis[1].word == 1 and ov.sentences[1]._extends_before, "eta theta. labelled at eta")
sel:_close()
-- zoomed: only the sentences on the screen get labels (a view scrolled down
-- to line 2: S1 is off the screen)
sel = fresh({ vy = 290 })
assert(sel:_open_point() == true and #sel.overlay.pointer:visible() == 1, "only visible sentences")
assert(sel.overlay.pointer:visible()[1].sent == 2)
sel:_close()
assert(claims == 0)

----------------------------------------------------------------------
-- 3. Paragraphs (TASK-32): pdfpara.lua wired into the words and sentences
----------------------------------------------------------------------
-- a line of `words` spread evenly over x0..x1, at y
local function mkline(y, x0, x1, words)
    local pitch = (x1 - x0 + 10) / #words
    local ln = { x0 = x0, y0 = y, x1 = x1, y1 = y + 12 }
    for j, w in ipairs(words) do
        local a = x0 + (j - 1) * pitch
        ln[j] = { word = w, x0 = a, y0 = y, x1 = a + pitch - 10, y1 = y + 12 }
    end
    return ln
end
local function split(str)
    local t = {}
    for w in str:gmatch("%S+") do t[#t + 1] = w end
    return t
end

-- one column, two paragraphs: the second begins with an indent after a short
-- last line. Page 2 is one more paragraph (continued across the edge).
local P1 = {
    mkline(100, 100, 580, split("The quick brown fox jumps")),
    mkline(115, 100, 580, split("over the lazy dog today.")),
    mkline(130, 100, 380, split("Then it ran.")),
    mkline(145, 120, 580, split("Next morning came again quietly")),
    mkline(160, 100, 580, split("and so on we go forever.")),
}
local P2 = {
    mkline(100, 100, 580, split("Still more text arrives here")),
    mkline(115, 100, 580, split("and ends in the end.")),
}
custom = { P1, P2 }
local Wp = PdfWords.words_from_boxes(P1, 1)
assert(Wp[1].para == 1 and Wp[#Wp].para == 2 and Wp[13].para == 1 and Wp[14].para == 2, "word paragraphs")
local Sp = PdfWords.sentences(Wp)
assert(#Sp == 3 and Sp[1].para == 1 and Sp[2].para == 1 and Sp[3].para == 2, "sentence paragraphs")
-- a broken page never raises: without paragraph data everything is paragraph 1
assert(PdfWords.words_from_boxes({ { { word = "a", x0 = 0, x1 = 5, y0 = 0, y1 = 5 } } }, 1)[1].para == 1)

sel = fresh({ zoom = 1, vx = 0, vy = 0 })
assert(sel:_open(false) == true)
ov = sel.overlay
assert(text(ov) == "T:The quick brown fox jumps over the lazy dog today.", "S1")
ov:line(1); assert(ov.page == 1 and text(ov) == "T:Next morning came again quietly and so on we go forever.",
    "↓ in sentences skips to the next paragraph: " .. tostring(text(ov)))
ov:line(-1); assert(text(ov):match("^T:The quick"), "↑ = the previous paragraph")
ov:para(1); assert(text(ov):match("^T:Next morning"), "LT / RT in sentences = ↓ / ↑")
ov:para(-1); assert(text(ov):match("^T:The quick"))
sel:_close()

-- words (TASK-42): ↑/↓ = sentence starts, over the page edge; LT / RT nothing
sel = fresh({ zoom = 1, vx = 0, vy = 0 })
assert(sel:_open_walk(false) == true)
ov = sel.overlay
assert(cur(ov) == "The")
ov:step(1); ov:step(1)
ov:para(1); assert(cur(ov) == "brown", "RT in words: no move")
ov:line(1); assert(cur(ov) == "Then", "↓: the next sentence: " .. tostring(cur(ov)))
ov:line(1); assert(cur(ov) == "Next")
ov:step(1); ov:step(1)
assert(cur(ov) == "came")
ov:line(-1); assert(cur(ov) == "Next", "↑: start of this sentence")
ov:line(-1); assert(cur(ov) == "Then", "↑ again: the previous sentence")
ov:line(1); ov:line(1)
assert(ov.page == 2 and cur(ov) == "Still", "↓ past the last sentence: next page")
ov:line(-1); assert(ov.page == 1 and cur(ov) == "Next", "↑ back over the edge: the last sentence's start")
sel:_close()

-- two columns, the engine delivers the lines row by row (left, right, left, ...)
-- but a paragraph runs from the bottom of the left column to the top of the
-- right one: P1 = l1-l3, P2 = l4-l6 + r1-r2, P3 = r3-r6
local L = {
    mkline(100, 100, 290, split("Aaa bbb ccc ddd")), mkline(115, 100, 290, split("eee fff ggg hhh")),
    mkline(130, 100, 190, split("iii jjj.")), mkline(145, 120, 290, split("Kkk lll mmm nnn")),
    mkline(160, 100, 290, split("ooo ppp qqq rrr")), mkline(175, 100, 290, split("sss ttt uuu vvv")),
}
local R = {
    mkline(100, 340, 530, split("www xxx yyy zzz")), mkline(115, 340, 440, split("abc def.")),
    mkline(130, 360, 530, split("Ghi jkl mno pqr")), mkline(145, 340, 530, split("stu vwx yza bcd")),
    mkline(160, 340, 530, split("efg hij klm nop")), mkline(175, 340, 440, split("qrs tuv.")),
}
local C = {}
for k = 1, 6 do C[#C + 1] = L[k]; C[#C + 1] = R[k] end
custom = { C }
local info = PdfWords.paragraph_info(C)
assert(info and info.ncols == 2, "two columns found: " .. tostring(info and info.ncols))
local Wc = PdfWords.words_from_boxes(C, 1)
assert(Wc[1].text == "Aaa" and Wc[11].text == "Kkk" and Wc[23].text == "www" and Wc[28].text == "def.", "reading order")
assert(Wc[1].para == 1 and Wc[11].para == 2 and Wc[23].para == 2 and Wc[29].para == 3 and Wc[#Wc].para == 3,
    "a paragraph crosses to the right column")
local Sc = PdfWords.sentences(Wc)
assert(#Sc == 3 and Sc[1].para == 1 and Sc[2].para == 2 and Sc[3].para == 3, "sentences of two columns")

sel = fresh({ zoom = 1, vx = 0, vy = 0 })
assert(sel:_open(false) == true)
ov = sel.overlay
assert(text(ov) == "T:Aaa bbb ccc ddd eee fff ggg hhh iii jjj.")
ov:line(1)
assert(text(ov) == "T:Kkk lll mmm nnn ooo ppp qqq rrr sss ttt uuu vvv www xxx yyy zzz abc def.",
    "the left column runs on into the right one: " .. tostring(text(ov)))
ov:line(1); assert(text(ov):match("^T:Ghi jkl") and text(ov):match("qrs tuv%.$"), "third paragraph")
sel:_close()
sel = fresh({ zoom = 1, vx = 0, vy = 0 })
assert(sel:_open_walk(false) == true)
ov = sel.overlay
ov:line(1); assert(cur(ov) == "Kkk")
ov:line(1); assert(cur(ov) == "Ghi", "↓ over the column break: " .. tostring(cur(ov)))
ov:line(-1); assert(cur(ov) == "Kkk", "↑: the previous sentence")
sel:_close()
custom = nil
assert(claims == 0)

print("pdfwords_test: all tests passed")
