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
local function page_boxes(page)
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
assert(S[1].para == 1 and S[2].para == 2, "until TASK-32 every sentence is a paragraph")
assert(PdfWords.line_target(W, 2, 1) == 5 and PdfWords.line_target(W, 6, -1) == 3, "line by x")
assert(PdfWords.line_target(W, 2, -1) == nil and PdfWords.line_target(W, 5, 1) == nil, "no line beyond")
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
function Doc:getPageCount() return 3 end
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
    local ui = { document = doc, paging = { number_of_pages = 3 }, view = view,
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
-- ↓ from gamma: the nearest word of line 2 (zeta, x 340..440)
ov:line(1); assert(cur(ov) == "zeta", "line down: " .. tostring(cur(ov)))
-- AC#1: past the last word = next page (a whole page), its first word
events = {}
ov:step(1)
assert(events[1] == "GotoPage:2" and ov.page == 2 and cur(ov) == "eta", "page edge →: " .. tostring(events[1]))
ov:step(-1)
assert(ov.page == 1 and cur(ov) == "zeta", "page edge ←: the last word of the previous page")
-- ↓ on the last line = the next page's first word, ↑ on the first line = back
ov:line(1); assert(ov.page == 2 and cur(ov) == "eta", "line past the page")
ov:line(-1); assert(ov.page == 1 and cur(ov) == "zeta", "line up past the page: its last word")
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
assert(ov:_status_text() == "WORD \xC2\xB7 X hl \xC2\xB7 Y vort \xC2\xB7 A menu \xC2\xB7 B close", ov:_status_text())
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
-- ↓ / ↑ and LT / RT: by sentence until paragraphs (TASK-32)
ov:line(-1); assert(ov.page == 1 and text(ov) == "T:Alpha beta gamma.", "first page: ↑ stays")
ov:line(1); assert(text(ov) == "T:Delta eps zeta", "↓ = next sentence")
ov:para(-1); assert(text(ov) == "T:Alpha beta gamma.", "LT = previous sentence")
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

-- point from-to on a PDF page: lines from the words on the screen
local function label_of(o, line)
    for _, v in ipairs(o.pointer:visible()) do if v.line == line then return v.label end end
end
sel = fresh({ zoom = 1, vx = 0, vy = 0 })
assert(sel:_open_point() == true)
ov = sel.overlay
assert(ov.mode == "point" and #ov.pointer.lines == 2 and ov.pointer.lines[2].first == 4, "two lines")
assert(ov.words[ov.pointer.lines[1].first].sbox.x == 10 + 100, "labels at screen boxes")
painted = {}
ov:paintTo(bb, 0, 0)
local l = label_of(ov, 1)
assert(ov:point_press(l[1]) == "prefix" and ov:point_press(l[2]) == "start")
l = label_of(ov, 2)
ov:point_press(l[1])
assert(ov:point_press(l[2]) == "done" and ov.mode == "walk")
assert(text(ov) == "T:Alpha beta gamma. Delta eps zeta", "start line .. end line: " .. tostring(text(ov)))
sel:_close()
-- zoomed: only the lines on the screen get labels (line 1 of a view scrolled down)
sel = fresh({ vy = 290 })
assert(sel:_open_point() == true and #sel.overlay.pointer.lines == 1, "only visible lines")
sel:_close()
assert(claims == 0)

print("pdfwords_test: all tests passed")
