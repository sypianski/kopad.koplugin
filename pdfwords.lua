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
    sent_end,           -- the word ends a sentence (M.ends_sentence)
    sbox }              -- screen box {x, y, w, h}, set by the overlay from
                        --   the current view (nil = not on the screen)
]]

local WordSource = require("paginmapo")

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

-- The page's words in reading order (the engine's line order). The last
-- word's sent_end looks only at itself; the overlay decides about the page
-- edge with the neighbouring page (M.first_text / M.last_text).
function M.words_from_boxes(boxes, page)
    local words = {}
    if type(boxes) ~= "table" then return words end
    local line_no = 0
    for _, line in ipairs(boxes) do
        if type(line) == "table" then
            local counted = false
            for _, b in ipairs(line) do
                if usable(b) then
                    if not counted then line_no, counted = line_no + 1, true end
                    local i = #words + 1
                    local ly0 = type(line.y0) == "number" and line.y0 or b.y0
                    local ly1 = type(line.y1) == "number" and line.y1 or b.y1
                    local k = M.key(page, i)
                    words[i] = {
                        text = b.word, page = page, idx = i, line = line_no,
                        pos0 = k, pos1 = k, xp0 = k, xp1 = k,
                        pbox = { x = b.x0, y = ly0, w = b.x1 - b.x0, h = ly1 - ly0 },
                        cx = (b.x0 + b.x1) / 2, cy = (b.y0 + b.y1) / 2,
                    }
                end
            end
        end
    end
    for i, w in ipairs(words) do
        local nxt = words[i + 1]
        w.sent_end = M.ends_sentence(w.text, nxt and nxt.text)
    end
    return words
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
-- and `para`. Paragraphs are TASK-32 (pdfpara.lua): until then every
-- sentence is its own paragraph, so ↑/↓ in sentences and LT / RT step by
-- sentence.
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
    for si, s in ipairs(out) do s.para = si end
    return out
end

-- The word on the line `delta` lines away from word i (nearest by centre x),
-- nil past the first / last line of the page.
function M.line_target(words, i, delta)
    local w = words[i]
    if not w then return nil end
    local target = w.line + delta
    local best, bd
    for j, o in ipairs(words) do
        if o.line == target then
            local d = math.abs(o.cx - w.cx)
            if not bd or d < bd then best, bd = j, d end
        end
    end
    return best
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
