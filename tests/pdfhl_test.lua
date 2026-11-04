-- Tests for highlights in PDF / DjVu (TASK-31): selector.lua PagedOverlay
-- saving / removing a highlight through a stub ReaderHighlight /
-- ReaderAnnotation that follows the stock code (saveHighlight, deleteHighlight,
-- annotation:addItem), browsing the page's highlights (Y), the boxes under
-- zoom and pan, and a note. The fake PDF is the one of tests/pdfwords_test.lua.
-- Run from the repo root: lua tests/pdfhl_test.lua
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
                       setDirty = function() end, nextTick = function(_, f) f() end })
stub("util", { cleanupSelectedText = function(s) return s end })
stub("gettext", function(s) return s end)
stub("ui/font", { getFace = function() return {} end })
local menus = {}
local dialogs = {}
stub("ui/widget/inputdialog", { new = function(_, t)
    t.getInputText = function(self) return self._typed or self.input or "" end
    dialogs[#dialogs + 1] = t; return t end })
stub("ui/widget/buttondialog", { new = function(_, t) menus[#menus + 1] = t; return t end })
local claims = 0
stub("pluginaro", { claim_overlay = function() claims = claims + 1; return true end,
                    release_overlay = function() claims = claims - 1 end })

local PdfWords = require("pdfwords")
local Selector = require("selector")

----------------------------------------------------------------------
-- The document, the view and the stock highlight modules (stubs)
----------------------------------------------------------------------
local Doc = {}
Doc.__index = Doc
function Doc:getTextBoxes(page) return page_boxes(page) end
function Doc:getPageCount() return 3 end
function Doc:getProps() return { language = "en" } end
-- KoptInterface snaps a position to the word whose box holds it (or the
-- nearest one): the word indices of pos0 .. pos1 on the page
local function span(p0, p1)
    local words = PdfWords.words_from_boxes(page_boxes(p0.page), p0.page)
    local function at(p)
        local best, bd
        for i, w in ipairs(words) do
            local b = w.pbox
            local dx = math.max(b.x - p.x, 0, p.x - (b.x + b.w))
            local dy = math.max(b.y - p.y, 0, p.y - (b.y + b.h))
            if not bd or dx * dx + dy * dy < bd then best, bd = i, dx * dx + dy * dy end
        end
        return best
    end
    local a, b = at(p0), at(p1)
    if not a or not b then return nil end
    if a > b then a, b = b, a end
    return words, a, b
end
function Doc:getTextFromPositions(p0, p1)
    local words, a, b = span(p0, p1)
    if not words then return nil end
    return { text = "T:" .. PdfWords.text(words, a, b), pboxes = PdfWords.line_boxes(words, a, b, "pbox") }
end
local box_calls = 0
function Doc:getPageBoxesFromPositions(page, p0, p1)
    box_calls = box_calls + 1
    assert(p0.page == page, "boxes asked for the highlight's page")
    local words, a, b = span(p0, p1)
    return words and PdfWords.line_boxes(words, a, b, "pbox") or nil
end

local events, log
local function fresh(opts)
    opts = opts or {}
    events, log = {}, { pdf = {}, deleted = {} }
    local view = {
        page_scroll = false,
        state = { page = opts.page or 1, zoom = opts.zoom or 1, rotation = 0, offset = { x = 10, y = 20 } },
        visible_area = { x = opts.vx or 0, y = opts.vy or 0, w = 580, h = 760 },
        highlight = { saved_drawer = "lighten", saved_color = "yellow" },
        footer = { maybeUpdateFooter = function() end },
    }
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
    local doc = setmetatable({ configurable = { text_wrap = 0 }, is_pdf = true }, Doc)
    local ui = { document = doc, paging = { number_of_pages = 3 }, view = view }
    function ui:handleEvent(ev)
        events[#events + 1] = ev.name .. ":" .. tostring(ev.args[1] and ev.args[1].nb_highlights_added or ev.args[1])
        if ev.name == "AnnotationsModified" then log.modified = ev.args[1] end
        if ev.name == "GotoPage" then
            view.state.page = ev.args[1]
            view.visible_area.x, view.visible_area.y = 0, 0
        end
    end
    -- ReaderAnnotation: sorted by page, then y, then x (isItemInPositionOrderPaging)
    local annotation = { annotations = opts.annotations or {} }
    function annotation:addItem(item)
        item.datetime = item.datetime or "2026-11-03 12:00:00"
        item.pageno = item.page
        local function before(a, b)
            if a.page ~= b.page then return a.page < b.page end
            if a.pos0.y ~= b.pos0.y then return a.pos0.y < b.pos0.y end
            return a.pos0.x < b.pos0.x
        end
        local index = #self.annotations + 1
        for i, a in ipairs(self.annotations) do
            if a.pos0 and before(item, a) then index = i; break end
        end
        table.insert(self.annotations, index, item)
        return index
    end
    ui.annotation = annotation
    -- ReaderHighlight: saveHighlight / deleteHighlight as the stock (paging)
    local rh = { ui = ui, view = view }
    function rh:saveHighlight()
        local st = self.selected_text
        if not (st and st.pos0 and st.pos1) then return end
        local item = { pos0 = st.pos0, pos1 = st.pos1, text = st.text, datetime = st.datetime,
                       drawer = st.drawer or view.highlight.saved_drawer,
                       color = st.color or view.highlight.saved_color, note = st.note }
        item.page, item.pboxes, item.ext = st.pos0.page, st.pboxes, st.ext
        self:writePdfAnnotation("save", item)
        local index = ui.annotation:addItem(item)
        ui:handleEvent({ name = "AnnotationsModified",
                         args = { { item, nb_highlights_added = 1, index_modified = index } } })
        return index
    end
    function rh:writePdfAnnotation(action, item, content)
        log.pdf[#log.pdf + 1] = action .. (content and (":" .. content) or "")
    end
    function rh:deleteHighlight(index)
        local item = ui.annotation.annotations[index]
        self:writePdfAnnotation("delete", item)
        table.remove(ui.annotation.annotations, index)
        log.deleted[#log.deleted + 1] = index
        ui:handleEvent({ name = "AnnotationsModified",
                         args = { { item, nb_highlights_added = -1, index_modified = -index } } })
    end
    ui.highlight = rh
    return Selector:new{ ui = ui, paged = true }, ui, rh
end
local function text(ov) local s = ov:_get_selection(); return s and s.text end
-- a highlight as KOReader stores it (a finger: positions where it was held)
local function ann(page, x0, y0, x1, y1, txt, extra)
    local a = { page = page, pageno = page, drawer = "lighten", color = "yellow", text = txt,
                pos0 = { page = page, x = x0, y = y0 }, pos1 = { page = page, x = x1, y = y1 },
                pboxes = { { x = 0, y = 0, w = 1, h = 1 } }, datetime = "2026-11-01 10:00:00" }
    for k, v in pairs(extra or {}) do a[k] = v end
    return a
end

----------------------------------------------------------------------
-- AC#1: X in a PDF selection creates / removes the highlight
----------------------------------------------------------------------
local sel, ui, rh = fresh()
assert(sel:_open_walk(false) == true and claims == 1)
local ov = sel.overlay
ov:step(1, true) -- A held: Alpha .. beta
assert(text(ov) == "T:Alpha beta")
shown = {}
ov:_do_toggle_highlight(ov:_get_selection())
local anns = ui.annotation.annotations
assert(#anns == 1, "X: one annotation (the sidecar's list)")
local a = anns[1]
assert(a.page == 1 and a.pageno == 1 and a.text == "T:Alpha beta" and a.drawer == "lighten"
    and a.color == "yellow", "the stock item: page, text, the user's style")
assert(a.pos0.page == 1 and a.pos0.x == 150 and a.pos0.y == 115
    and a.pos1.page == 1 and a.pos1.x == 270 and a.pos1.y == 115 and a.pos0.zoom == 1,
    "pos0 / pos1 = {page, x, y} at the end words' centres, native")
assert(#a.pboxes == 1 and a.pboxes[1].x == 100 and a.pboxes[1].w == 220 and a.pboxes[1].h == 30,
    "pboxes native, one per line (from getTextFromPositions)")
assert(log.pdf[1] == "save" and log.modified[1] == a and log.modified.nb_highlights_added == 1,
    "saveHighlight: written into the PDF (when on) and AnnotationsModified")
assert(rh.selected_text == nil, "selected_text given back")
assert(#ov.hl_items == 1 and ov.hl_items[1].index == 1, "the new highlight is on the page list")
assert(#shown == 0, "no message on saving")
-- the overlay's own positions are not shared with the stored item
assert(a.pos0 ~= ov:_get_selection().pos0)
-- X again on the same range: removed through deleteHighlight
ov:_do_toggle_highlight(ov:_get_selection())
assert(#anns == 0 and log.deleted[1] == 1 and log.pdf[2] == "delete", "second X: deleteHighlight(1)")
assert(shown[1] and shown[1].text == "Highlight removed" and #ov.hl_items == 0)
-- a range one word longer is another highlight, not the same one
ov:_do_toggle_highlight(ov:_get_selection())
ov:step(1, true) -- Alpha .. gamma.
ov:_do_toggle_highlight(ov:_get_selection())
assert(#anns == 2 and #log.deleted == 1, "a different range adds a second highlight")
sel:_close()
assert(claims == 0)

-- a finger highlight (positions at the words' left edges, not centres) on
-- Delta .. eps: X on the same words removes it
local finger = ann(1, 105, 160, 225, 160, "Delta eps")
local bm = { page = 1, pos0 = { page = 1, x = 0, y = 0 }, pos1 = { page = 1, x = 0, y = 0 }, text = "bookmark" }
sel, ui = fresh({ annotations = { bm, finger } })
sel:_open_walk(false)
ov = sel.overlay
assert(#ov.hl_items == 1 and ov.hl_items[1].ann == finger and ov.hl_items[1].index == 2,
    "a bookmark (no drawer) is no highlight; index = the annotation index")
ov:line(1); ov:step(1, true) -- Delta .. eps
assert(text(ov) == "T:Delta eps")
ov:_do_toggle_highlight(ov:_get_selection())
assert(#ui.annotation.annotations == 1 and ui.annotation.annotations[1] == bm and log.deleted[1] == 2,
    "finger highlight removed by its annotation index")
sel:_close()

----------------------------------------------------------------------
-- AC#2: Y while reading a PDF browses the page's highlights
----------------------------------------------------------------------
-- none on the page = false, nothing shown, the claim given back
sel = fresh({ annotations = { ann(2, 150, 115, 150, 115, "eta") } })
assert(sel:_open_highlights() == false and sel.overlay == nil and claims == 0, "no highlights on page 1")

local h2 = ann(1, 150, 165, 390, 165, "Delta eps zeta", { note = "n" }) -- line 2
local h1 = ann(1, 150, 115, 270, 115, "Alpha beta")                     -- line 1
local other = ann(2, 150, 115, 270, 115, "eta theta.")
local multi = ann(1, 390, 115, 150, 115, "gamma. ... eta",
    { ext = { [1] = { pos0 = { page = 1, x = 390, y = 115 }, pos1 = { page = 1, x = 390, y = 115 } } } })
multi.pos1 = { page = 2, x = 150, y = 115 }
-- annotation order (bookmark first, line 2 before line 1) differs from the page order
sel, ui = fresh({ annotations = { bm, h2, h1, multi, other } })
box_calls = 0
assert(sel:_open_highlights() == true and claims == 1)
ov = sel.overlay
assert(ov.mode == "hl" and #ov.hl_items == 3, "page 1: three highlights (one multi-page), not page 2's")
assert(ov.hl_items[1].ann == h1 and ov.hl_items[2].ann == multi and ov.hl_items[3].ann == h2,
    "top to bottom, then left to right")
assert(box_calls == 3, "boxes from getPageBoxesFromPositions (multi-page: its piece on this page)")
assert(ov.hl_items[2].pboxes[1].x == 340 and ov.hl_items[2].pboxes[1].w == 100, "the ext piece: gamma.")
assert(ov.hl_cur == 1 and text(ov) == "Alpha beta", "the first one focused, its stored text")
assert(ov:_get_selection().hl_index == 3, "hl_index = annotation index")
assert(ov:_status_text():find("^HIGHLIGHT \xC2\xB7 X del"), ov:_status_text())
-- the arrows step between them, wrapping
ov:step(1); assert(ov.hl_cur == 2)
ov:line(1); assert(ov.hl_cur == 3 and ov:_status_text():find("^HIGHLIGHT %[note%]"), "↓ = next; a note shows")
ov:step(1); assert(ov.hl_cur == 1, "wraps")
ov:para(-1); assert(ov.hl_cur == 3, "LT = previous, wraps")
ov:step(1)
-- hold B (TASK-46): the noted ones only, the same mode; a glossed PDF does not exist
local ov_all = ov
sel.overlay = nil -- a second overlay for the test only (claim counted twice)
assert(sel:_open_highlights("note") == true and sel.overlay.hl_kind == "note"
    and #sel.overlay.hl_items == 1 and sel.overlay.hl_items[1].ann == h2, "notes only: h2")
sel:_close()
assert(sel:_open_highlights("gloss") == false and sel.overlay == nil, "PDF: no glosses, nothing opens")
sel.overlay, ov = ov_all, ov_all

-- the boxes: page view at zoom 1, the focused one inverted on paint
local painted = {}
local bb = setmetatable({}, { __index = function(_, k) return function(_, ...) painted[#painted + 1] = { k, ... } end end })
ov:paintTo(bb, 0, 0)
local first = painted[1]
assert(first[1] == "invertRect" and first[2] == 10 + 100 and first[3] == 20 + 100 and first[4] == 220 and first[5] == 30,
    "focused highlight inverted at its screen box")
-- the margin dots (filled = focused): drawn for the three, no error
local circles = 0
for _, c in ipairs(painted) do if c[1] == "paintCircle" then circles = circles + 1 end end
assert(circles >= 3, "a dot per highlight, got " .. circles)
sel:_close()

-- zoom 2, panned: the screen boxes follow the view at every paint
sel = fresh({ annotations = { h1, h2 }, zoom = 2, vx = 150, vy = 100 })
assert(sel:_open_highlights() == true)
ov = sel.overlay
local b = ov.hl_items[1].boxes[1]
assert(b.x == 10 + 200 - 150 and b.y == 20 + 200 - 100 and b.w == 440 and b.h == 60,
    ("zoomed: %d,%d %dx%d"):format(b.x, b.y, b.w, b.h))
ui = sel.ui
ui.view.visible_area.x = 250
painted = {}
ov:paintTo(bb, 0, 0)
b = ov.hl_items[1].boxes[1]
assert(b.x == 10 + 200 - 250 and painted[1][2] == b.x, "panned: recomputed on paint")
-- scrolled down past line 1: no screen box, no dot, nothing breaks
ui.view.visible_area.x, ui.view.visible_area.y = 150, 280
ov:paintTo(bb, 0, 0)
assert(ov.hl_items[1].sbox == nil and #ov.hl_items[1].boxes == 0, "off the screen: no box")
-- moving onto it pans the view back to it (as the words do)
events = {}
ov.hl_cur = 2; ov:step(-1)
assert(ov.hl_cur == 1 and events[1] and events[1]:match("^pan:0,%-"), "reveal: " .. tostring(events[1]))
sel:_close()

-- X while browsing removes the focused one by its annotation index; the
-- last one gone = hl_cur 0 (padnav closes the overlay)
sel, ui, rh = fresh({ annotations = { bm, h1, h2 } })
sel:_open_highlights()
ov = sel.overlay
ov:step(1) -- h2, annotation 3
ov:_do_toggle_highlight(ov:_get_selection())
assert(log.deleted[1] == 3 and #ui.annotation.annotations == 2 and ov.hl_cur == 1 and #ov.hl_items == 1,
    "X in hl: deleteHighlight(3), the focus stays")
ov:_do_toggle_highlight(ov:_get_selection())
assert(log.deleted[2] == 2 and ov.hl_cur == 0 and #ui.annotation.annotations == 1, "the last one: hl_cur 0")
-- Highlight from the action menu on a browsed highlight: no duplicate
sel:_close()
sel, ui = fresh({ annotations = { h1 } })
sel:_open_highlights()
sel.overlay:_do_highlight(sel.overlay:_get_selection())
assert(#ui.annotation.annotations == 1, "no second copy of a browsed highlight")
sel:_close()

----------------------------------------------------------------------
-- Note: a new highlight with a note; on a browsed one, its own note
----------------------------------------------------------------------
sel, ui = fresh()
sel:_open_walk(false)
ov = sel.overlay
dialogs = {}
ov:_do_note(ov:_get_selection())
assert(#ui.annotation.annotations == 1 and #dialogs == 1, "Note: highlight saved, dialog open")
local dlg = dialogs[1]
dlg._typed = "my note"
dlg.buttons[1][2].callback()
a = ui.annotation.annotations[1]
assert(a.note == "my note" and log.modified.nb_notes_added == 1 and log.modified.nb_highlights_added == -1,
    "note stored, counted as a note")
assert(log.pdf[#log.pdf] == "content:my note", "note written into the PDF annotation")
sel:_close()
sel, ui = fresh({ annotations = { h2 } })
sel:_open_highlights()
dialogs = {}
sel.overlay:_do_note(sel.overlay:_get_selection())
assert(dialogs[1].input == "n", "the note window opens with the saved note")
dialogs[1]._typed = "edited"
dialogs[1].buttons[1][2].callback()
assert(#ui.annotation.annotations == 1 and h2.note == "edited" and log.modified.nb_notes_added == 0,
    "a browsed highlight's note is edited in place")
assert(sel.overlay:_status_text():find("%[note%]"))
-- saved unchanged: nothing sent; emptied: the note goes, the highlight stays
log.modified = nil
sel.overlay:_do_note(sel.overlay:_get_selection())
dialogs[2].buttons[1][2].callback()
assert(log.modified == nil and h2.note == "edited", "unchanged: no event")
sel.overlay:_do_note(sel.overlay:_get_selection())
dialogs[3]._typed = ""
dialogs[3].buttons[1][2].callback()
assert(h2.note == nil and #ui.annotation.annotations == 1, "emptied note removed")
assert(log.modified.nb_notes_added == -1 and log.modified.nb_highlights_added == 1, "counted back as a highlight")
-- the window: wide, medium height; grows to large once the text overflows
local d4
sel.overlay:_do_note(sel.overlay:_get_selection())
d4 = dialogs[4]
local w, mid = Selector._PagedOverlay._note_size(600, 800, false)
local _, big = Selector._PagedOverlay._note_size(600, 800, true)
assert(d4.width == w and d4.text_height == mid and big > mid and d4.allow_newline, "medium, wide, multi-line")
local lines, reinits = 3, 0
d4._input_widget = { text_widget = { text_widget = {
    getAllLineCount = function() return lines end, getVisLineCount = function() return 8 end } } }
d4.reinit = function(self) reinits = reinits + 1 end
d4.edited_callback(true)
assert(reinits == 0 and d4.text_height == mid, "fits: stays medium")
lines = 9
d4.edited_callback(true)
assert(reinits == 1 and d4.text_height == big and d4.orig_text_height == big, "overflow: large")
lines = 30
d4.edited_callback(true)
assert(reinits == 1, "large is the last step")
sel:_close()
assert(claims == 0)

----------------------------------------------------------------------
-- TASK-45: an action closes the overlay; A held + D-pad then starts at the
-- action's last word when it is on this page and on the screen
----------------------------------------------------------------------
sel, ui = fresh()
assert(sel:_open_walk(false) == true)
ov = sel.overlay
ov:step(1); ov:step(1, true)                  -- beta .. gamma.
assert(ov:act("toggle_highlight") == true, "X")
assert(sel.overlay == nil and ov.closed and claims == 0, "X closes the overlay")
anns = ui.annotation.annotations
assert(#anns == 1 and anns[1].text == "T:beta gamma.", "the highlight is saved")
assert(sel.resume and sel.resume.page == 1 and sel.resume.idx == 3, "resume = gamma. on page 1")
assert(sel:_open_walk(false) == true and sel.overlay.ww_word.text == "gamma.", "words open at gamma.")
-- Highlight from the action menu: the same, after the menu closes
sel.overlay:step(1)                           -- Delta
sel.overlay:action_menu()
menus[#menus].buttons[2][1].callback()        -- Highlight
assert(sel.overlay == nil and claims == 0 and #anns == 2 and sel.resume.idx == 4, "menu Highlight closes")
-- Note: the dialog after the close, Save reaches the new highlight
sel:_open_walk(true); assert(sel.overlay.ww_word.text == "Delta", "resume also for ←/↑")
sel.overlay:act("note")
local nd = dialogs[#dialogs]
assert(sel.overlay == nil and nd.title == "Note")
nd._typed = "pdf note"; nd.buttons[1][2].callback()
local noted
for _, x in ipairs(anns) do if x.note == "pdf note" then noted = x end end
assert(noted and log.pdf[#log.pdf] == "content:pdf note", "note saved on its highlight, into the PDF")
-- another page: the first word on the screen, as before
ui.view.state.page = 2
assert(sel:_open_walk(false) == true and sel.overlay.ww_word.text == "eta", "page 2: first word")
sel:_close()
-- back on page 1 but zoomed so the word is off the screen: as before
ui.view.state.page = 1
ui.view.state.zoom, ui.view.visible_area.y = 2, 200
ui.view.visible_area.h = 100                  -- only the first line shows
sel:_open_walk(false)
assert(sel.overlay.ww_word.text == "Alpha" and sel.overlay.ww_word.sbox
    and not sel.overlay.words[4].sbox, "the resume word off the screen: first word on it")
sel:_close()
ui.view.state.zoom, ui.view.visible_area.h = 1, 760
ui.view.visible_area.x, ui.view.visible_area.y = 0, 0
sel:_open_walk(false)
assert(sel.overlay.ww_word.text == "Delta", "on the screen again: resumed")
sel:_close()
assert(claims == 0)

print("pdfhl_test: all tests passed")
