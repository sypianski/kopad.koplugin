--[[
pdftext.lua -- words of a PDF page that are split by the GAP between glyphs,
not only by space characters.

Why: document:getTextBoxes(page) (KOReader) comes from ffi/mupdf.lua
page:getPageText(), which cuts words ONLY at space characters. Many PDFs
(TeX / XeTeX / Typst output, tight justified lines) have no space characters
in the text layer: the word gap is just a gap between glyph positions, and
mupdf adds a synthetic space only from about 0.15 em. A squeezed line has a gap
of about 0.13 em, so the whole line came out as ONE "word" (one box, no spaces
in its text) and the pad could select nothing smaller than the line.
Measured on such a PDF (papeteria, Alegreya): gaps inside words <= 0.066 em,
gaps between words >= 0.125 em; M.GAP_EM = 0.10 sits between the two.

The fix has to be where the words are made, not in pdfwords.lua: the selection
is saved through getTextFromPositions, which takes its word boundaries from
the same boxes, so kopad and KOReader must see the same words.

install() replaces page:getPageText of the mupdf page class (once per run,
only while the state function says kopad is on, original on any error). The
splitting itself (split_line) is pure Lua over plain chars, tested by
tests/pdftext_test.lua; the FFI adapter (page_text) is a copy of koreader-base
getPageText with that splitting in place of the inner loop.
]]

local M = {}

-- A gap wider than this many em (of the larger of the two glyph sizes) between
-- neighbouring glyphs of a line is a word gap.
M.GAP_EM = 0.10

-- Same sets as ffi/mupdf.lua (keep in step; they are local there).
local B = string.byte
local function is_wspace(c)
    return c == 9 or c == 0x0a or c == 0x0b or c == 0x0c or c == 0x0d or c == 0x20
        or c == 0x85 or c == 0xA0 or c == 0x1680
        or (c >= 0x2000 and c <= 0x200A) or c == 0x2028 or c == 0x2029
        or c == 0x202F or c == 0x205F or c == 0x3000
        or c == 149 or c == B("*")
end

local function is_bullet(c)
    return c == 0x2022 or c == 0x2023 or c == 0x25a0 or c == 0x25cb or c == 0x25cf
        or c == 0x25e6 or c == 0x2043 or c == 0x2219 or c == 149 or c == B("*")
end

-- Characters that are a word on their own in koreader-base (CJK, general
-- punctuation, full-width forms).
local function ends_word_alone(c)
    return (c >= 0x4e00 and c <= 0x9FFF) or (c >= 0x2000 and c <= 0x206F)
        or (c >= 0x3000 and c <= 0x303F) or (c >= 0x3400 and c <= 0x4DBF)
        or (c >= 0xF900 and c <= 0xFAFF) or (c >= 0xFF01 and c <= 0xFFEE)
        or (c >= 0x20000 and c <= 0x2A6DF)
end

-- True when the space between two glyphs, measured along the line, is a word
-- gap. prev / cur = { s0, s1, size } (extent along the line, font size). The
-- gap is taken on whichever side is free, so a right-to-left line (glyphs in
-- logical order, moving left) works as well; overlaps (accents, ligatures)
-- give a negative gap.
function M.is_gap(prev, cur, gap_em)
    local size = math.max(prev.size or 0, cur.size or 0)
    if size <= 0 then return false end
    local gap = math.max(cur.s0 - prev.s1, prev.s0 - cur.s1)
    return gap > (gap_em or M.GAP_EM) * size
end

-- A leading bullet and the white space around it do not belong to the first
-- word (as koreader-base's skip_starting_bullet). Returns the first char to use.
function M.skip_starting_bullet(first)
    local ch, found = first, false
    while ch ~= nil do
        if is_bullet(ch.c) then
            found = true
        elseif not is_wspace(ch.c) then
            break
        end
        ch = ch.next
    end
    return found and ch or first
end

-- One line as words. `first` = the line's first char (a linked list through
-- `.next`; a char has c = code point, x0 y0 x1 y1 = its box, s0 s1 = extent
-- along the line, size). `utf8` = function(code) -> string. `gaps` = false
-- turns the gap rule off (vertical text). Returns words
-- { { word, x0, y0, x1, y1 }, ... } and the line box (x0, y0, x1, y1 or nil);
-- identical to koreader-base for a line with proper spaces.
function M.split_line(first, utf8, gaps)
    local words = {}
    local lx0, ly0, lx1, ly1
    local ch = M.skip_starting_bullet(first)
    while ch ~= nil do
        local parts, n = {}, 0
        local x0, y0, x1, y1
        local prev
        local gap_break = false
        while ch ~= nil do
            if is_wspace(ch.c) then break end
            if prev and gaps ~= false and M.is_gap(prev, ch) then
                gap_break = true
                break
            end
            n = n + 1
            parts[n] = utf8(ch.c)
            x0 = x0 and math.min(x0, ch.x0) or ch.x0
            y0 = y0 and math.min(y0, ch.y0) or ch.y0
            x1 = x1 and math.max(x1, ch.x1) or ch.x1
            y1 = y1 and math.max(y1, ch.y1) or ch.y1
            lx0 = lx0 and math.min(lx0, ch.x0) or ch.x0
            ly0 = ly0 and math.min(ly0, ch.y0) or ch.y0
            lx1 = lx1 and math.max(lx1, ch.x1) or ch.x1
            ly1 = ly1 and math.max(ly1, ch.y1) or ch.y1
            prev = ch
            if ends_word_alone(ch.c) then break end
            ch = ch.next
        end
        if n > 0 and x0 < x1 and y0 < y1 then
            words[#words + 1] = { word = table.concat(parts), x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
        end
        if ch == nil then break end
        -- a gap break leaves `ch` as the first glyph of the next word; at a
        -- white space (or a word-alone glyph) it is stepped over
        if gap_break then gap_break = false else ch = ch.next end
    end
    local box = lx0 and lx0 < lx1 and ly0 < ly1 and { lx0, ly0, lx1, ly1 } or nil
    return words, box
end

-- ---------------------------------------------------------------------------
-- The KOReader side (FFI). Everything below is only reached from install().

-- Extent of a quad along the line direction (dx, dy) and its page box.
local function quad_box(q, dx, dy)
    local xs = { q.ul.x, q.ur.x, q.ll.x, q.lr.x }
    local ys = { q.ul.y, q.ur.y, q.ll.y, q.lr.y }
    local x0, x1, y0, y1 = xs[1], xs[1], ys[1], ys[1]
    local s0, s1
    for i = 1, 4 do
        if xs[i] < x0 then x0 = xs[i] end
        if xs[i] > x1 then x1 = xs[i] end
        if ys[i] < y0 then y0 = ys[i] end
        if ys[i] > y1 then y1 = ys[i] end
        local s = xs[i] * dx + ys[i] * dy
        if not s0 or s < s0 then s0 = s end
        if not s1 or s > s1 then s1 = s end
    end
    return x0, y0, x1, y1, s0, s1
end

-- A lazy linked list of plain chars over an fz_stext_char chain, so that
-- split_line sees the same interface as in the tests.
local function plain_chars(first_cdata, dx, dy)
    local function wrap(c)
        if c == nil then return nil end
        local x0, y0, x1, y1, s0, s1 = quad_box(c.quad, dx, dy)
        local node = { c = c.c, x0 = x0, y0 = y0, x1 = x1, y1 = y1, s0 = s0, s1 = s1, size = c.size }
        return node, c.next
    end
    local head, tail
    local cur = first_cdata
    while cur ~= nil do
        local node, nxt = wrap(cur)
        if tail then tail.next = node else head = node end
        tail, cur = node, nxt
    end
    return head
end

-- The replacement of page:getPageText (koreader-base ffi/mupdf.lua), same
-- result table. `W` = the wrap-mupdf library, `ffi` = LuaJIT's.
local function page_text(self, W, ffi)
    local text_page = W.mupdf_new_stext_page_from_page(self.ctx, self.page, nil)
    if text_page == nil then error("cannot alloc text_page") end
    local ok, lines = pcall(function()
        local lines, size = {}, 0
        local buf = ffi.new("char[8]")
        local function utf8(c)
            return ffi.string(buf, W.fz_runetochar(buf, c))
        end
        local block = text_page.first_block
        while block ~= nil do
            if block.type == W.FZ_STEXT_BLOCK_TEXT then
                local mline = block.u.t.first_line
                while mline ~= nil do
                    local dx, dy = mline.dir.x, mline.dir.y
                    local first = plain_chars(mline.first_char, dx, dy)
                    if first then
                        local words, box = M.split_line(first, utf8, mline.wmode == 0)
                        if #words > 0 then
                            local line = {}
                            for i, w in ipairs(words) do
                                line[i] = w
                                size = size + 5 * 8 + #w.word
                            end
                            if box then
                                line.x0, line.y0, line.x1, line.y1 = box[1], box[2], box[3], box[4]
                                size = size + 5 * 8
                                lines[#lines + 1] = line
                            end
                        end
                    end
                    mline = mline.next
                end
            end
            block = block.next
        end
        lines.size = size
        return lines
    end)
    W.fz_drop_stext_page(self.ctx, text_page)
    if not ok then error(lines, 0) end
    return lines
end

-- Replaces getPageText of the mupdf page class, once per run. `doc` = the
-- open PdfDocument (only used to reach a mupdf page and its metatable);
-- `state_fn()` is asked on every call, so a disabled kopad leaves KOReader as
-- it was; `warn` gets one message on the first failure. Returns true when the
-- patch is in place (also when it already was), false when this is not a mupdf
-- document / the FFI pieces are missing (DjVu, bare Lua).
function M.install(doc, state_fn, warn)
    M._state = state_fn
    if M._patched then return true end
    local mdoc = doc and doc._document
    if type(mdoc) ~= "table" or mdoc.doc == nil or mdoc.ctx == nil
            or type(mdoc.openPage) ~= "function" then
        return false
    end
    local ok_ffi, ffi = pcall(require, "ffi")
    if not ok_ffi or not pcall(require, "ffi/mupdf") or type(ffi.loadlib) ~= "function" then
        return false
    end
    local ok_w, W = pcall(ffi.loadlib, "wrap-mupdf")
    if not ok_w or not W or not W.mupdf_new_stext_page_from_page then return false end
    local ok_p, page = pcall(mdoc.openPage, mdoc, 1)
    if not ok_p or type(page) ~= "table" then return false end
    local mt = getmetatable(page)
    local orig = mt and type(mt.__index) == "table" and mt.__index.getPageText
    local has_fields = page.ctx ~= nil and page.page ~= nil
    pcall(page.close, page)
    if type(orig) ~= "function" or not has_fields then return false end

    local failed = false
    mt.__index.getPageText = function(self)
        if failed or not (M._state and M._state()) then return orig(self) end
        local ok, res = pcall(page_text, self, W, ffi)
        if ok then return res end
        failed = true -- never retry a broken adapter; stock text from now on
        if warn then warn("kopad: pdftext fell back to stock getPageText: " .. tostring(res)) end
        return orig(self)
    end
    M._patched = true
    return true
end

return M
