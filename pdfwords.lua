--[[
pdfwords.lua -- the word source of the selection overlay in paged documents
(PDF / DjVu, TASK-30). The EPUB overlay takes its words from paginmapo
(crengine xpointers); this adapter builds the same kind of list from
document:getTextBoxes(page), so the overlay's modes (struct / walk / point)
run on it with only the document-specific methods replaced (PagedOverlay in
selector.lua).

Pure Lua apart from paginmapo (vendored, used as is): no KOReader module is
required here; the page -> screen transform is done by the caller.

getTextBoxes(page) = lines of words in native page coordinates (zoom 1.0,
origin top left): { [i] = { x0, y0, x1, y1, [j] = { word, x0, y0, x1, y1 } } }.
A scanned page without a text layer gives nil, or boxes without `word`
(KOReader's optical fallback).

Word item (the contract with selector.lua; TASK-31 / TASK-32 build on it):
  { text,               -- the word as the PDF has it (punctuation attached)
    page, idx, line,    -- page number, index on the page, line number (1..)
    pos0, pos1,         -- key "pdf/<page>/<idx>": the overlay's "xpointer"
    xp0, xp1,           --   (same key; paginmapo's sentence grouping and the
                        --   overlay's maps use these names)
    pbox,               -- {x, y, w, h} native page box: the word's x, its
                        --   LINE's y / h (as KOReader's own pboxes)
    cx, cy,             -- centre of the word's own box (native): a position
                        --   for getTextFromPositions / getWordFromPosition
    para,               -- paragraph number on the page (pdfpara.lua, TASK-32;
                        --   non-decreasing along the words)
    sent_end,           -- the word ends a sentence (M.ends_sentence)
    sbox }              -- screen box {x, y, w, h}, set by the overlay from
                        --   the current view (nil = not on the screen)
]]

local WordSource = require("paginmapo")
local Para = require("pdfpara")

local M = {}

-- True when the boxes hold at least one word with text.
function M.has_text(boxes)
    if type(boxes) ~= "table" then return false end
    for _, line in ipairs(boxes) do
        if type(line) == "table" then
            for _, b in ipairs(line) do
                if type(b) == "table" and type(b.word) == "string" and b.word:find("%S") then
                    return true
                end
            end
        end
    end
    return false
end

local function usable(b)
    return type(b) == "table" and type(b.word) == "string" and b.word:find("%S")
        and type(b.x0) == "number" and type(b.x1) == "number"
        and type(b.y0) == "number" and type(b.y1) == "number"
end

-- The sentence-end rule of paginmapo (its is_sent_boundary is local, so it is
-- replicated here; keep the two in step -- reported upstream). In a PDF the
-- punctuation is part of the word, so the rule looks at the word's end
-- instead of the gap after it: ! ? ؟ ۔ always end a sentence; a period only
-- when the next word starts with an uppercase letter (M.I.T., Dr., e.g.).
-- Closing quotes / brackets after the mark are skipped.
function M.ends_sentence(text, next_text)
    if type(text) ~= "string" or text == "" then return false end
    local t = text:gsub("\xE2\x80\x9D", '"'):gsub("\xE2\x80\x99", "'"):gsub("\xC2\xBB", '"')
    t = t:gsub("[\"')%]]+$", "")
    if t:find("[!%?]$") or t:find("\xD8\x9F$") or t:find("\xDB\x94$") then return true end
    if t:find("%.$") then
        local c = type(next_text) == "string" and next_text:sub(1, 1) or ""
        return c ~= "" and c:match("%u") ~= nil
    end
    return false
end

function M.key(page, idx) return "pdf/" .. tostring(page) .. "/" .. tostring(idx) end

-- Paragraph geometry of a page (pdfpara.paragraphs on the raw boxes), nil when
-- it cannot be computed (pcall-guarded: an odd page never breaks the overlay).
-- Callers cache it per page together with the boxes.
function M.paragraph_info(boxes, rtl)
    if type(boxes) ~= "table" then return nil end
    local ok, _, info = pcall(Para.paragraphs, boxes, { rtl = rtl })
    return ok and type(info) == "table" and info or nil
end

-- The page's words in READING order: the engine's line order, except that
-- pdfpara puts a two-column page's left column before the right one (info.order);
-- lines pdfpara does not know are appended in their own order. Every word
-- gets the paragraph number of its line (`para`; a line without one takes the
-- previous word's). opts (optional): { rtl = bool, info = a cached
-- M.paragraph_info of these boxes }. Returns words, info. The last word's
-- sent_end looks only at itself; the overlay decides about the page edge with
-- the neighbouring page (M.first_text / M.last_text).
function M.words_from_boxes(boxes, page, opts)
    local words = {}
    if type(boxes) ~= "table" then return words end
    opts = opts or {}
    local info = opts.info or M.paragraph_info(boxes, opts.rtl)
    local seq, seen = {}, {}
    if info and type(info.order) == "table" then
        for _, li in ipairs(info.order) do
            if type(boxes[li]) == "table" and not seen[li] then seq[#seq + 1], seen[li] = li, true end
        end
    end
    for li, line in ipairs(boxes) do
        if type(line) == "table" and not seen[li] then seq[#seq + 1], seen[li] = li, true end
    end
    local line_no, para = 0, 1
    for _, li in ipairs(seq) do
        local line = boxes[li]
        local counted = false
        para = info and info.para_of and info.para_of[li] or para
        for _, b in ipairs(line) do
            if usable(b) then
                if not counted then line_no, counted = line_no + 1, true end
                local i = #words + 1
                local ly0 = type(line.y0) == "number" and line.y0 or b.y0
                local ly1 = type(line.y1) == "number" and line.y1 or b.y1
                local k = M.key(page, i)
                words[i] = {
                    text = b.word, page = page, idx = i, line = line_no, para = para,
                    pos0 = k, pos1 = k, xp0 = k, xp1 = k,
                    pbox = { x = b.x0, y = ly0, w = b.x1 - b.x0, h = ly1 - ly0 },
                    cx = (b.x0 + b.x1) / 2, cy = (b.y0 + b.y1) / 2,
                }
            end
        end
    end
    for i, w in ipairs(words) do
        local nxt = words[i + 1]
        w.sent_end = M.ends_sentence(w.text, nxt and nxt.text)
    end
    return words, info
end

-- Text of the first / last word of a page's boxes (nil when none).
function M.first_text(boxes)
    if type(boxes) ~= "table" then return nil end
    for _, line in ipairs(boxes) do
        if type(line) == "table" then
            for _, b in ipairs(line) do if usable(b) then return b.word end end
        end
    end
end
function M.last_text(boxes)
    if type(boxes) ~= "table" then return nil end
    for li = #boxes, 1, -1 do
        local line = boxes[li]
        if type(line) == "table" then
            for j = #line, 1, -1 do if usable(line[j]) then return line[j].word end end
        end
    end
end

-- Sentences of the page through paginmapo's grouping (collect_sentences_from_
-- words, on the sent_end flags above). Each gets first / last = word indices
-- and `para` = the paragraph of its first word (TASK-32, from pdfpara.lua via
-- the words' `para`; a sentence running on into the next paragraph still
-- belongs to the one it began in). selector.lua's ↑/↓ in sentences and LT / RT
-- compare these numbers.
function M.sentences(words)
    if #words == 0 then return {} end
    local ok, sents = pcall(WordSource.collect_sentences_from_words, words)
    if not ok or type(sents) ~= "table" then return {} end
    local by_key = {}
    for i, w in ipairs(words) do by_key[w.xp0] = i end
    local out = {}
    for _, s in ipairs(sents) do
        local first, last = by_key[s.xp0], by_key[s.xp1]
        if first and last then
            s.first, s.last = first, last
            out[#out + 1] = s
        end
    end
    for si, s in ipairs(out) do s.para = words[s.first].para or si end
    return out
end

-- One box per line for the words i0..i1 (union of their `field` boxes,
-- default the screen box "sbox"; words without it are skipped).
function M.line_boxes(words, i0, i1, field)
    field = field or "sbox"
    local out, cur, cur_line = {}, nil, nil
    for i = i0, i1 do
        local w = words[i]
        local b = w and w[field]
        if b then
            if cur and w.line == cur_line then
                local x1 = math.max(cur.x + cur.w, b.x + b.w)
                local y1 = math.max(cur.y + cur.h, b.y + b.h)
                cur.x, cur.y = math.min(cur.x, b.x), math.min(cur.y, b.y)
                cur.w, cur.h = x1 - cur.x, y1 - cur.y
            else
                cur = { x = b.x, y = b.y, w = b.w, h = b.h }
                cur_line = w.line
                out[#out + 1] = cur
            end
        end
    end
    return out
end

-- Text of the words i0..i1 (fallback when getTextFromPositions gives none).
function M.text(words, i0, i1)
    local t = {}
    for i = i0, i1 do if words[i] then t[#t + 1] = words[i].text end end
    return table.concat(t, " ")
end

-- A page position at the centre of word w, as KOReader's paging highlights
-- keep it (pos0 / pos1: {x, y, page[, zoom, rotation]}); getTextFromPositions
-- snaps it to exactly that word. `state` = view.state (optional).
function M.pos(w, state)
    local p = { page = w.page, x = w.cx, y = w.cy }
    if type(state) == "table" then p.zoom, p.rotation = state.zoom, state.rotation end
    return p
end

return M
