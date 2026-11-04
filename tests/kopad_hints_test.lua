-- Tests for kopad_hints.lua ("point from-to", TASK-29): label assignment by
-- position, the line layer, the word labels and the two-step pointer
-- (TASK-35 sentences, TASK-36 letters on the words + arrow shortcuts). Pure
-- Lua, no KOReader.
-- Run from the repo root: lua tests/kopad_hints_test.lua
package.path = "./?.lua;" .. package.path

local H = require("kopad_hints")

local function key(l) return l and (l[1] .. "," .. l[2]) or "nil" end
local function column(n, x, dy)
    local t = {}
    for i = 1, n do t[i] = { x = x or 50, y = (i - 1) * (dy or 30) } end
    return t
end
local function unique(labels, n)
    local seen = {}
    for i = 1, n do
        local k = key(labels[i])
        assert(labels[i], "point " .. i .. " has a label")
        assert(#labels[i] == 2, "two symbols")
        assert(not seen[k], "label " .. k .. " twice")
        seen[k] = true
    end
end

-- 1. The vocabulary: eight symbols, B never starts a label.
do
    assert(#H.SYMBOLS == 8 and #H.FIRST == 7, "8 symbols, 7 first ones")
    for _, c in ipairs(H.FIRST) do assert(c ~= H.BACK) end
    assert(H.BACK == "B")
end

-- 2. Always two presses, unique labels, no label starting with B; 56 at most.
do
    for _, n in ipairs({ 1, 2, 5, 7, 8, 9, 30, 42, 50, 56 }) do
        local labels = H.assign(column(n))
        unique(labels, n)
        for i = 1, n do assert(labels[i][1] ~= "B", n .. ": label " .. i .. " starts with B") end
    end
    local labels = H.assign(column(70))
    unique(labels, 56)
    assert(labels[57] == nil and labels[70] == nil, "past 56 lines: no label")
    assert(next(H.assign({})) == nil, "no points, no labels")
    -- with all eight symbols allowed first: 64
    local all = H.assign(column(64), H.SYMBOLS)
    unique(all, 64)
end

-- 3. By position, like hints.js: in a column the first symbol goes by height
-- (↑ / Y on top, ↓ / A at the bottom), neighbouring lines share it, and a
-- few lines get a doubled symbol.
do
    local labels = H.assign(column(3))
    assert(key(labels[1]) == "up,up" and key(labels[2]) == "left,left" and key(labels[3]) == "down,down",
        key(labels[1]) .. " " .. key(labels[2]) .. " " .. key(labels[3]))
    local l40 = H.assign(column(40))
    assert(l40[1][1] == "up" and l40[40][1] == "down" or l40[40][1] == "A",
        "top line starts with up, bottom one with down / A: " .. key(l40[40]))
    -- the first symbols form contiguous blocks down the page
    local seen, last = {}, nil
    for i = 1, 40 do
        local c = l40[i][1]
        if c ~= last then
            assert(not seen[c], "first symbol " .. c .. " in two blocks")
            seen[c], last = true, c
        end
    end
    -- inside a block the second symbol goes by height too: up first, down last
    local block = {}
    for i = 1, 40 do if l40[i][1] == "up" then block[#block + 1] = l40[i][2] end end
    assert(block[1] == "up", "first line of the block: up, got " .. tostring(block[1]))
    -- an indent of a few pixels does not reorder the column
    local pts = column(40)
    for i = 1, 40, 5 do pts[i].x = pts[i].x + 25 end
    local ind = H.assign(pts)
    for i = 1, 40 do assert(ind[i][1] == l40[i][1], "indent changed line " .. i) end
    -- 2D: a point on the left gets a D-pad symbol, one on the right a letter
    local two = H.assign({ { x = 0, y = 0 }, { x = 1000, y = 0 }, { x = 0, y = 1000 }, { x = 1000, y = 1000 } })
    assert(two[1][1] == "up" and two[2][1] == "Y" and two[3][1] == "down" and two[4][1] == "A",
        key(two[1]) .. " " .. key(two[2]) .. " " .. key(two[3]) .. " " .. key(two[4]))
end

-- 4. The line layer: word boxes in reading order -> lines.
do
    local boxes = {
        { x = 10, y = 10, w = 50, h = 20 }, { x = 70, y = 12, w = 40, h = 18 }, -- line 1 (baseline jitter)
        { x = 10, y = 40, w = 60, h = 20 },                                     -- line 2
        nil,
        { x = 10, y = 70, w = 30, h = 20 }, { x = 50, y = 70, w = 30, h = 20 },
    }
    boxes[4] = false -- a word without a box
    local lines = H.lines_from_boxes(boxes)
    assert(#lines == 3, "three lines, got " .. #lines)
    assert(lines[1].first == 1 and lines[1].last == 2 and lines[1].x == 10 and lines[1].w == 100, "line 1")
    assert(lines[2].first == 3 and lines[2].last == 3, "line 2")
    assert(lines[3].first == 5 and lines[3].last == 6 and lines[3].w == 70, "line 3 skips the box-less word")
    assert(#H.lines_from_boxes({}) == 0)
    -- a second column (y jumps back up) is a new line
    local cols = H.lines_from_boxes({ { x = 0, y = 0, w = 10, h = 10 }, { x = 0, y = 20, w = 10, h = 10 },
                                      { x = 300, y = 0, w = 10, h = 10 } })
    assert(#cols == 3)
end

-- 5. Word labels (TASK-36, PC-023): first symbol Y / X / A, then letters
-- before arrows, never B; two symbols up to 21 words, three up to 147.
local LETTER = { Y = true, X = true, A = true }
do
    assert(H.WORD_MAX2 == 21 and H.WORD_MAX3 == 147)
    for n = 1, 150 do
        local labels = H.word_labels(n)
        local want = math.min(n, 147)
        assert(#labels == want, n .. ": " .. #labels .. " labels")
        local len = n <= 21 and 2 or 3
        local seen, used = {}, {}
        for i, l in ipairs(labels) do
            assert(#l == len, n .. ": label " .. i .. " has " .. #l .. " symbols")
            assert(LETTER[l[1]], n .. ": label " .. i .. " starts with " .. l[1])
            local k = table.concat(l, ",")
            assert(not seen[k], n .. ": label " .. k .. " twice")
            seen[k] = true
            for p = 1, len do
                assert(l[p] ~= "B", "never B")
                local pre = table.concat(l, ",", 1, p - 1)
                used[pre] = used[pre] or {}
                used[pre][l[p]] = true
            end
        end
        -- letters before arrows: no prefix goes on with an arrow while one
        -- of the letters is left unused there
        for pre, set in pairs(used) do
            local arrow, free_letter = false, false
            for c in pairs(set) do if not LETTER[c] then arrow = true end end
            for c in pairs(LETTER) do if not set[c] then free_letter = true end end
            assert(not (arrow and free_letter), n .. ": prefix '" .. pre .. "' uses an arrow before a letter")
        end
    end
    local function keys(n)
        local out = {}
        for i, l in ipairs(H.word_labels(n)) do out[i] = table.concat(l) end
        return table.concat(out, " ")
    end
    assert(keys(1) == "YY" and keys(3) == "YY XX AA", keys(3))
    assert(keys(9) == "YY YX YA XX XY XA AA AY AX", keys(9))
    -- reading order: contiguous blocks Y, X, A
    assert(keys(10):match("^YY YX YA Yup XX"), keys(10))
    assert(#H.word_labels(0) == 0)
end

-- 6. The pointer (TASK-35 sentences, TASK-36 letters on the words + arrow
-- shortcuts). Page: 4 lines of 5 words (x = 20 + k * 60, y = line * 30);
-- sentences S1 = 1-3, S2 = 4-12, S3 = 13-14 (S1-S3 one paragraph), S4 =
-- 15-20 (another).
local function page(nwords, per_line)
    local boxes = {}
    per_line = per_line or 5
    for i = 1, nwords do
        local k, line = (i - 1) % per_line, math.floor((i - 1) / per_line)
        boxes[i] = { x = 20 + k * 60, y = line * 30, w = 50, h = 20 }
    end
    return boxes
end
local function label_for(p, field, value)
    for _, v in ipairs(p:visible()) do if v[field] == value then return v.label end end
end
local function pick(p, field, value)
    local l = label_for(p, field, value)
    assert(l, "a label for " .. field .. " " .. tostring(value))
    for k = 1, #l - 1 do assert(p:press(l[k]) == "prefix", "symbol " .. k) end
    return p:press(l[#l])
end
local function words(p)
    local out = {}
    for _, v in ipairs(p:visible()) do out[#out + 1] = v.word end
    return table.concat(out, ",")
end
local SENTS = { { first = 1, last = 3, para = 1 }, { first = 4, last = 12, para = 1 },
                { first = 13, last = 14, para = 1 }, { first = 15, last = 20, para = 2 } }
do
    local boxes = page(20)
    local p = H.Pointer.new(SENTS, boxes)
    assert(p.step == "start" and p.level == "sentence" and p.refine_to_word == nil)
    local vis = p:visible()
    assert(#vis == 4, "one label per sentence")
    assert(vis[2].sent == 2 and vis[2].word == 4 and vis[2].side == "left" and vis[2].x == boxes[4].x,
        "start label left of the sentence's first word")
    assert(vis[2].h == 20 and vis[2].y == boxes[4].y + 10)
    -- a symbol no label starts with is ignored
    local used = {}
    for _, v in ipairs(vis) do used[v.label[1]] = true end
    for _, c in ipairs(H.FIRST) do
        if not used[c] then assert(p:press(c) == "ignored"); break end
    end
    -- the first symbol filters, B (when no label goes on with it) drops it
    local lab = label_for(p, "sent", 2)
    assert(p:press(lab[1]) == "prefix")
    for _, v in ipairs(p:visible()) do assert(v.label[1] == lab[1] and v.typed == 1) end
    local has_b = false
    for _, v in ipairs(p:visible()) do if v.label[2] == "B" then has_b = true end end
    if not has_b then
        assert(p:press("B") == "unprefix" and #p:visible() == 4)
        assert(p:press(lab[1]) == "prefix")
    end
    -- a sentence label = its words (letters), not the start yet
    assert(p:press(lab[2]) == "sentence" and p.step == "start" and p.level == "word" and p.sent == 2)
    assert(p.start == nil)
    local wv = p:visible()
    assert(words(p) == "4,5,6,7,8,9,10,11,12", "labels on S2's nine words: " .. words(p))
    for _, v in ipairs(wv) do assert(v.side == "top" and LETTER[v.label[1]] and #v.label == 2) end
    assert(wv[1].x == boxes[4].x + boxes[4].w / 2 and wv[1].y == boxes[4].y, "over the word, its top edge")
    -- on the word level arrows are shortcuts, never label symbols: → / ↓ nothing
    assert(p:press("right") == "ignored" and p:press("down") == "ignored")
    -- B: a typed symbol is dropped; nothing typed = the sentence labels
    local l7 = label_for(p, "word", 7)
    assert(p:press(l7[1]) == "prefix" and p:visible()[1].typed == 1)
    assert(p:press("B") == "unprefix" and #p:visible() == 9)
    assert(p:press("B") == "back" and p.level == "sentence" and #p:visible() == 4)
    pick(p, "sent", 2)
    assert(pick(p, "word", 7) == "start" and p.start == 7 and p.start_sent == 2 and p.step == "end")
    -- the end step: at once on the start sentence's words from the start word
    assert(p.level == "word" and p.sent == 2 and words(p) == "7,8,9,10,11,12", words(p))
    local a, b = p:preview()
    assert(a == 7 and b == 12, "preview: start .. end of S2")
    -- ↑ never before the start sentence
    assert(p:press("up") == "ignored")
    -- → = the next sentence (labels move, preview grows), ↑ = back
    assert(p:press("right") == "sentence" and p.sent == 3 and words(p) == "13,14")
    a, b = p:preview(); assert(a == 7 and b == 14)
    assert(p:press("right") == "sentence" and p.sent == 4)
    assert(p:press("right") == "ignored", "S4 = the page's last sentence: a range stays on the page")
    assert(p:press("up") == "sentence" and p.sent == 3)
    assert(p:press("up") == "sentence" and p.sent == 2 and words(p) == "7,8,9,10,11,12", "from the start word again")
    p:press("right")
    -- a word label = the end there
    assert(pick(p, "word", 14) == "done" and p.start == 7 and p.stop == 14 and #p:visible() == 0)
    assert(p:press("A") == "ignored" and p:press("left") == "ignored", "done: nothing more")
    assert(p:preview() == nil)

    -- the Deck case (PC-023): from a word to the end of its sentence = sentence, word, ←
    p = H.Pointer.new(SENTS, boxes)
    pick(p, "sent", 2); pick(p, "word", 6)
    assert(p:press("left") == "done" and p.start == 6 and p.stop == 12)
    -- ← in the end step on a later sentence = its end
    p = H.Pointer.new(SENTS, boxes)
    pick(p, "sent", 1); pick(p, "word", 2)
    p:press("right")
    assert(p:press("left") == "done" and p.start == 2 and p.stop == 12)
    -- ↓ = the end of the paragraph (S1-S3), from any sentence of it
    p = H.Pointer.new(SENTS, boxes)
    pick(p, "sent", 1); pick(p, "word", 2)
    assert(p:press("down") == "done" and p.stop == 14, "end of paragraph 1: word 14")
    p = H.Pointer.new(SENTS, boxes)
    pick(p, "sent", 4); pick(p, "word", 16)
    assert(p:press("down") == "done" and p.stop == 20, "S4 is its own paragraph")
    -- start shortcuts: ← = the sentence's first word, ↑ = the paragraph's
    p = H.Pointer.new(SENTS, boxes)
    pick(p, "sent", 3)
    assert(p:press("left") == "start" and p.start == 13 and p.start_sent == 3)
    p = H.Pointer.new(SENTS, boxes)
    pick(p, "sent", 3)
    assert(p:press("up") == "start" and p.start == 1 and p.start_sent == 1 and p.sent == 1,
        "↑: the first word of S1, the paragraph's first sentence")
    assert(words(p) == "1,2,3", "the end step starts on S1")
    -- B in the end step = one word; on the start sentence labels = cancel
    assert(p:press("B") == "done" and p.start == 1 and p.stop == nil)
    p = H.Pointer.new(SENTS, boxes)
    assert(p:press("B") == "cancel")

    -- no `para`: every sentence is its own paragraph
    local np = { { first = 1, last = 3 }, { first = 4, last = 12 } }
    p = H.Pointer.new(np, boxes)
    pick(p, "sent", 2)
    assert(p:press("up") == "start" and p.start == 4)
    assert(p:press("down") == "done" and p.stop == 12)

    -- a sentence over the page edge / out of a zoomed view: labels at its
    -- visible part; a sentence with no visible word gets none, and ↑ to the
    -- paragraph start takes the first VISIBLE word of the paragraph
    local zb = page(20)
    for i = 1, 5 do zb[i] = false end   -- the first line is off the screen
    p = H.Pointer.new(SENTS, zb)
    assert(label_for(p, "sent", 1) == nil, "S1 has no visible word: no label")
    assert(label_for(p, "sent", 2) and p:visible()[1].word == 6, "S2 labelled at its first visible word")
    pick(p, "sent", 3)
    assert(p:press("up") == "start" and p.start == 6 and p.start_sent == 2)
    assert(#H.Pointer.new(SENTS, page(0)):visible() == 0)

    -- RTL: sentence labels on the right of the first word; ← and → swap
    -- (back = →, on = ←)
    p = H.Pointer.new(SENTS, boxes, { rtl = true })
    local r = p:visible()[1]
    assert(r.side == "right" and r.x == boxes[1].x + boxes[1].w)
    pick(p, "sent", 2)
    assert(p:press("left") == "ignored", "RTL ←: on, nothing in the start step")
    assert(p:press("right") == "start" and p.start == 4, "RTL →: the sentence start")
    assert(p:press("left") == "sentence" and p.sent == 3, "RTL ←: the next sentence")
    assert(p:press("right") == "done" and p.stop == 14, "RTL →: the end of the sentence")

    -- no sentences: no labels, B closes
    p = H.Pointer.new({}, {})
    assert(#p:visible() == 0 and p:press("up") == "ignored" and p:press("B") == "cancel")
end

-- 7. Long sentences: more than 21 visible words = three-symbol labels on all
-- of them (B drops one symbol at a time), more than 147 = a window of 147
-- (in the end step from the start word).
do
    local boxes = page(30, 10)
    local p = H.Pointer.new({ { first = 1, last = 8 }, { first = 9, last = 30 } }, boxes)
    pick(p, "sent", 1)
    for _, v in ipairs(p:visible()) do assert(#v.label == 2, "8 words: two symbols") end
    assert(p:press("B") == "back")
    pick(p, "sent", 2)
    local wv = p:visible()
    assert(#wv == 22, "22 words")
    for _, v in ipairs(wv) do assert(#v.label == 3 and LETTER[v.label[1]], "three symbols") end
    local l = label_for(p, "word", 20)
    assert(p:press(l[1]) == "prefix" and p:press(l[2]) == "prefix")
    assert(p:visible()[1].typed == 2)
    assert(p:press("B") == "unprefix" and p:visible()[1].typed == 1, "B drops the last symbol")
    assert(p:press(l[2]) == "prefix" and p:press(l[3]) == "start" and p.start == 20)
    -- the end step: S2 from word 20 = 11 words, two symbols again
    wv = p:visible()
    assert(#wv == 11 and #wv[1].label == 2 and wv[1].word == 20)

    local big = page(160, 10)
    p = H.Pointer.new({ { first = 1, last = 160 } }, big)
    pick(p, "sent", 1)
    wv = p:visible()
    assert(#wv == 147 and wv[1].word == 1 and wv[147].word == 147, "start: the first 147")
    assert(pick(p, "word", 3) == "start")
    wv = p:visible()
    assert(#wv == 147 and wv[1].word == 3 and wv[147].word == 149, "end: 147 from the start word")
    assert(p:press("left") == "done" and p.stop == 160, "← = the real end of the sentence")
end

print("kopad_hints_test: OK")
