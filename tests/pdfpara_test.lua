-- Tests for pdfpara.lua (paragraph detection from getTextBoxes lines, TASK-32):
-- the pure module on synthetic pages. Run from the repo root:
--   lua tests/pdfpara_test.lua
package.path = "./?.lua;" .. package.path

local P = require("pdfpara")

local H, PITCH = 12, 15

-- One text line as getTextBoxes gives it: an array of word boxes.
local function line(x0, x1, y, h, last, first)
    local words, n = {}, 5
    local gap = 3
    local ww = ((x1 - x0) - gap * (n - 1)) / n
    for k = 1, n do
        local wx = x0 + (k - 1) * (ww + gap)
        local text = "w" .. k
        if k == 1 and first then text = first end
        if k == n then text = last or "word" end
        words[k] = { x0 = wx, x1 = wx + ww, y0 = y, y1 = y + (h or H), word = text }
    end
    return words
end

-- A paragraph of n lines in a column [x, x + w] starting at y. Options:
-- indent (first line), last (width fraction of the last line), tail (its last
-- word), pitch, full (last line as long as the others).
local function para(x, w, y, n, o)
    o = o or {}
    local out = {}
    local pitch = o.pitch or PITCH
    for i = 1, n do
        local x0 = x + (i == 1 and (o.indent or 0) or 0)
        local x1 = x + w
        if i == n and not o.full then x1 = x + w * (o.last or 0.45) end
        if n == 1 and o.last == nil and not o.full then x1 = x + w * 0.45 end
        out[i] = line(x0, x1, y + (i - 1) * pitch, H, i == n and (o.tail or "end.") or "word")
    end
    return out, y + n * pitch
end

local function append(dst, src)
    for _, l in ipairs(src) do dst[#dst + 1] = l end
end

-- Paragraphs as "first-last" ranges of reading positions, e.g. "1-4,5-9".
local function shape(paras)
    local t = {}
    for i, p in ipairs(paras) do t[i] = p.first .. "-" .. p.last end
    return table.concat(t, ",")
end

-- 1. One column, indented paragraphs, short last lines.
do
    local page, y = {}, 100
    local nlines = { 4, 5, 3, 6 }
    for _, n in ipairs(nlines) do
        local p
        p, y = para(100, 400, y, n, { indent = 24 })
        append(page, p)
    end
    local paras, info = P.paragraphs(page)
    assert(shape(paras) == "1-4,5-9,10-12,13-18", shape(paras))
    assert(info.ncols == 1)
    assert(#paras[2].lines == 5 and paras[2].lines[1] == 5)
    assert(info.para_of[7] == 2 and info.para_of[13] == 4)
    assert(info.pos[3] == 3 and info.order[3] == 3)
end

-- 2. Block style: no indent, a gap between paragraphs, still short last lines.
do
    local page, y = {}, 100
    for _, n in ipairs({ 3, 4, 2, 5 }) do
        local p
        p, y = para(100, 400, y, n)
        append(page, p)
        y = y + 9 -- extra space between paragraphs (pitch 24 = 1.6x)
    end
    local paras = P.paragraphs(page)
    assert(shape(paras) == "1-3,4-7,8-9,10-14", shape(paras))
end

-- 3. Block style, gap only: every paragraph ends with a FULL line (no short
-- last line, no punctuation).
do
    local page, y = {}, 100
    for _, n in ipairs({ 3, 3, 4 }) do
        local p
        p, y = para(100, 400, y, n, { full = true, tail = "word" })
        append(page, p)
        y = y + 10
    end
    local paras = P.paragraphs(page)
    assert(shape(paras) == "1-3,4-6,7-10", shape(paras))
end

-- 4. Justified, no indent, uniform spacing: the short last line ending a sentence
-- is the only signal.
do
    local page, y = {}, 100
    for _, n in ipairs({ 4, 3, 5 }) do
        local p
        p, y = para(100, 400, y, n)
        append(page, p)
    end
    local paras = P.paragraphs(page)
    assert(shape(paras) == "1-4,5-7,8-12", shape(paras))
end

-- 5. No false breaks: one paragraph with a full last line / short line without a
-- sentence end; a single paragraph is one paragraph.
do
    local page = para(100, 400, 100, 8, { full = true, tail = "and" })
    local paras = P.paragraphs(page)
    assert(shape(paras) == "1-8", shape(paras))
    -- a short line that does not end a sentence (before a formula, say)
    page = para(100, 400, 100, 8, { full = true })
    page[4] = line(100, 260, 100 + 3 * PITCH, H, "where")
    paras = P.paragraphs(page)
    assert(shape(paras) == "1-8", shape(paras))
end

-- 6. Ragged-right text: a line that ends a sentence at 70% of the width is not a
-- paragraph end (the short rule is stricter there); a really short one is.
do
    local ends = { 0.95, 0.78, 0.88, 0.71, 0.97, 0.70, 0.84, 0.76, 0.92, 0.50, 0.80, 0.74 }
    local page = {}
    for i, f in ipairs(ends) do
        local last = (i == 6 or i == 10) and "end." or "word"
        page[i] = line(100, 100 + 400 * f, 100 + (i - 1) * PITCH, H, last)
    end
    local paras = P.paragraphs(page)
    assert(shape(paras) == "1-10,11-12", shape(paras))
end

-- 7. Two columns, lines handed over interleaved by y (as a PDF often gives
-- them): reading order is the whole left column, then the right one.
-- Left: paragraphs A (1-5), B (6-20) running on into the right column
-- (right 1-8), then C from the right line 9.
do
    local LX, RX, W = 50, 330, 220
    local left, right = {}, {}
    local y = 100
    local a
    a, y = para(LX, W, y, 5, { indent = 14 })
    append(left, a)
    local b
    b, y = para(LX, W, y, 15, { indent = 14, full = true, tail = "word" })
    append(left, b)
    assert(#left == 20)
    y = 100
    local b2
    b2, y = para(RX, W, y, 8, {}) -- continuation: no indent, short last line
    append(right, b2)
    local c
    c, y = para(RX, W, y, 12, { indent = 14 })
    append(right, c)
    assert(#right == 20)
    local page = {}
    for i = 1, 20 do page[#page + 1] = right[i]; page[#page + 1] = left[i] end -- interleaved
    local lay = P.columns(page)
    assert(lay.ncols == 2 and lay.gap and lay.gap.x0 >= LX + W and lay.gap.x1 <= RX)
    -- input index of left line i = 2i, of right line i = 2i - 1
    assert(lay.order[1] == 2 and lay.order[20] == 40 and lay.order[21] == 1 and lay.order[40] == 39)
    assert(lay.col_of[2] == 1 and lay.col_of[1] == 2)
    local paras, info = P.paragraphs(page)
    assert(#paras == 3, shape(paras))
    assert(shape(paras) == "1-5,6-28,29-40", shape(paras)) -- B crosses the columns
    assert(info.para_of[2] == 1 and info.para_of[40] == 2 and info.para_of[39] == 3) -- left top A, left bottom B, right bottom C
    assert(info.para_of[1] == 2) -- right col line 1 continues B
    assert(info.para_of[17] == 3) -- right col line 9 (index 2*9-1) starts C
    assert(info.pos[2] == 1 and info.pos[1] == 21)
end

-- 8. Two columns, the paragraph ends exactly at the bottom of the left column:
-- the right column starts with an indented line.
do
    local LX, RX, W = 50, 330, 220
    local page = {}
    local l, r = {}, {}
    local a
    a = para(LX, W, 100, 10, { indent = 14 })
    append(l, a)
    a = para(RX, W, 100, 10, { indent = 14 })
    append(r, a)
    for i = 1, 10 do page[#page + 1] = l[i] end
    for i = 1, 10 do page[#page + 1] = r[i] end
    local paras = P.paragraphs(page)
    assert(shape(paras) == "1-10,11-20", shape(paras))
    -- the same without a short last line / indent: no break claimed from nothing
    l = para(LX, W, 100, 10, { full = true, tail = "word" })
    r = para(RX, W, 100, 10, { full = true, tail = "word" })
    page = {}
    for i = 1, 10 do page[#page + 1] = l[i] end
    for i = 1, 10 do page[#page + 1] = r[i] end
    paras = P.paragraphs(page)
    assert(shape(paras) == "1-20", shape(paras))
end

-- 9. Heading in a bigger font: its own paragraph, the body is separate too;
-- the same on a two-column page with a full-width title and abstract.
do
    local page = {}
    append(page, para(100, 400, 60, 4, { indent = 24 }))
    page[#page + 1] = line(180, 420, 130, 22, "Introduction")
    append(page, para(100, 400, 170, 4, { indent = 24 }))
    local paras = P.paragraphs(page)
    assert(shape(paras) == "1-4,5-5,6-9", shape(paras))

    local LX, RX, W = 50, 330, 220
    page = {}
    page[1] = line(120, 480, 40, 24, "Title")
    local ab = para(50, 500, 80, 3, { indent = 14 })
    append(page, ab)
    local y = 150
    local l, r = para(LX, W, y, 10, { indent = 14 }), para(RX, W, y, 10, { indent = 14 })
    for i = 1, 10 do page[#page + 1] = r[i]; page[#page + 1] = l[i] end
    local lay = P.columns(page)
    assert(lay.ncols == 2 and lay.col_of[1] == 0 and lay.col_of[2] == 0)
    paras = P.paragraphs(page)
    assert(shape(paras) == "1-1,2-4,5-14,15-24", shape(paras))
    assert(paras[1].lines[1] == 1)
end

-- 10. Lists and verse: markers split items, a stanza gap splits verse.
do
    local page = {}
    for i = 1, 5 do
        local f = (i == 2) and "-" or "•"
        page[#page + 1] = line(120, 120 + 150 + (i * 13) % 40, 100 + (i - 1) * PITCH, H, "item", f)
    end
    local paras = P.paragraphs(page)
    assert(shape(paras) == "1-1,2-2,3-3,4-4,5-5", shape(paras))

    page = {}
    local ys = { 100, 115, 130, 160, 175, 190 } -- gap between the stanzas
    for i, yy in ipairs(ys) do page[i] = line(100, 100 + 180 + (i * 17) % 30, yy, H, "verse") end
    paras = P.paragraphs(page)
    assert(shape(paras) == "1-3,4-6", shape(paras))
end

-- 11. Lines out of reading order and words out of order within a line.
do
    local page = {}
    local p = para(100, 400, 100, 6, { indent = 24 })
    append(page, p)
    local q = para(100, 400, 100 + 6 * PITCH, 3, { indent = 24 })
    append(page, q)
    local shuffled = {}
    local perm = { 7, 2, 9, 4, 1, 8, 3, 6, 5 }
    for i, k in ipairs(perm) do shuffled[i] = page[k] end
    -- reverse the words of every line (DjVu may give them in any order)
    for _, ln in ipairs(shuffled) do
        for a = 1, #ln // 2 do ln[a], ln[#ln - a + 1] = ln[#ln - a + 1], ln[a] end
    end
    local paras, info = P.paragraphs(shuffled)
    assert(shape(paras) == "1-6,7-9", shape(paras))
    -- reading position 1 is the line that was page[1] (perm index 5)
    assert(info.order[1] == 5 and info.order[9] == 3 and info.order[7] == 1)
end

-- 12. Right-to-left: the same page mirrored in x, with opts.rtl.
do
    local page, y = {}, 100
    for _, n in ipairs({ 4, 5, 3 }) do
        local p
        p, y = para(100, 400, y, n, { indent = 24 })
        append(page, p)
    end
    for _, ln in ipairs(page) do
        for _, b in ipairs(ln) do b.x0, b.x1 = 700 - b.x1, 700 - b.x0 end
    end
    local paras = P.paragraphs(page, { rtl = true })
    assert(shape(paras) == "1-4,5-9,10-12", shape(paras))
end

-- 13. Degenerate input never raises.
do
    local function empty(res_paras, info)
        assert(type(res_paras) == "table" and #res_paras == 0)
        assert(next(info.order) == nil and next(info.para_of) == nil)
    end
    empty(P.paragraphs(nil))
    empty(P.paragraphs({}))
    empty(P.paragraphs({ {} }))
    empty(P.paragraphs({ {}, {} }))
    empty(P.paragraphs({ { { word = "" } } }))
    empty(P.paragraphs({ { { x0 = 1, x1 = 2, y0 = 1, y1 = 2, word = "  " } } }))
    empty(P.paragraphs({ "x", 5, false }))
    empty(P.paragraphs({ { { x0 = "a", x1 = 2, y0 = 1, y1 = 2, word = "x" } } }))
    empty(P.paragraphs({ { { x0 = 5, x1 = 2, y0 = 1, y1 = 2, word = "x" } } }))
    local lay = P.columns(nil)
    assert(lay.ncols == 1 and #lay.order == 0)
    lay = P.columns({})
    assert(lay.ncols == 1 and #lay.order == 0)

    -- one line
    local paras, info = P.paragraphs({ line(100, 400, 100, H, "end.") })
    assert(shape(paras) == "1-1" and info.para_of[1] == 1)
    -- an empty placeholder between real lines is skipped, indices stay input ones
    local page = { line(100, 400, 100, H), { { word = "" } }, line(100, 400, 115, H, "end.") }
    paras, info = P.paragraphs(page)
    assert(shape(paras) == "1-2", shape(paras))
    assert(info.para_of[2] == nil and info.pos[2] == nil)
    assert(paras[1].lines[1] == 1 and paras[1].lines[2] == 3)
end

-- 14. A single column is not mistaken for two (short last lines on the left,
-- a right-aligned page number).
do
    local page, y = {}, 100
    for _, n in ipairs({ 5, 6, 5, 4 }) do
        local p
        p, y = para(100, 400, y, n, { indent = 24 })
        append(page, p)
    end
    page[#page + 1] = line(480, 500, y + 20, H, "12")
    local lay = P.columns(page)
    assert(lay.ncols == 1, lay.ncols)
    assert(lay.order[#lay.order] == #page)
end

print("pdfpara_test: ok")
