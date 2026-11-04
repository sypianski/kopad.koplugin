-- Tests for kopad_hints.lua ("point from-to", TASK-29): label assignment by
-- position, the line layer, the word labels (TASK-39: a tree of threes) and
-- the two-step pointer (TASK-35 sentences, TASK-36 letters on the words +
-- arrow shortcuts, TASK-39 stages). Pure Lua, no KOReader.
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

-- 5. Word labels (TASK-39): a tree of threes in reading order, letters A /
-- X / Y only. k stages = the smallest k with 3^k >= n (n = 1 -> 1); stage i
-- cuts the range into pieces of 3^(k-i) words from its start (the last one
-- shorter), A = the first piece, X = the second, Y = the third.
local LETTER = { Y = true, X = true, A = true }
local function keys(n)
    local out = {}
    for i, l in ipairs(H.word_labels(n)) do out[i] = table.concat(l) end
    return table.concat(out, " ")
end
do
    local STAGES = { [1] = 1, [3] = 1, [4] = 2, [9] = 2, [10] = 3, [27] = 3, [28] = 4, [81] = 4, [82] = 5 }
    for n, k in pairs(STAGES) do
        assert(H.word_stages(n) == k, n .. " words: " .. H.word_stages(n) .. " stages, want " .. k)
    end
    local IDX = { A = 0, X = 1, Y = 2 }
    for n = 1, 250 do
        local labels = H.word_labels(n)
        local k = H.word_stages(n)
        assert(#labels == n, n .. ": every word has a label")
        assert(3 ^ k >= n and (k == 1 or 3 ^ (k - 1) < n), n .. ": the smallest k")
        local seen = {}
        for i, l in ipairs(labels) do
            assert(#l == k, n .. ": label " .. i .. " has " .. #l .. " letters")
            local v = 0
            for pos = 1, k do
                assert(LETTER[l[pos]], n .. ": only A / X / Y, got " .. tostring(l[pos]))
                v = v * 3 + IDX[l[pos]]
            end
            -- the pieces of stage pos are 3^(k-pos) words from the range start:
            -- the label is the index in base 3, so reading order = label order
            assert(v == i - 1, n .. ": word " .. i .. " is piece " .. v)
            local key = table.concat(l)
            assert(not seen[key], n .. ": label " .. key .. " twice")
            seen[key] = true
        end
    end
    assert(keys(1) == "A" and keys(3) == "A X Y", keys(3))
    -- 4 words: A = 1..3 (a piece of 3), X = the short last piece (one word)
    assert(keys(4) == "AA AX AY XA", keys(4))
    assert(keys(9) == "AA AX AY XA XX XY YA YX YY", keys(9))
    -- 10: three stages; A = words 1..9, X = word 10 alone (X A A)
    assert(keys(10):match("^AAA AAX AAY AXA") and keys(10):match("XAA$"), keys(10))
    -- the smallest pieces = 3 words: the last stage cycles A X Y
    local l27 = H.word_labels(27)
    for i = 1, 27 do assert(l27[i][3] == ({ "A", "X", "Y" })[(i - 1) % 3 + 1]) end
    assert(table.concat(l27[27]) == "YYY" and table.concat(H.word_labels(28)[28]) == "XAAA")
    assert(table.concat(H.word_labels(81)[81]) == "YYYY" and table.concat(H.word_labels(82)[82]) == "XAAAA")
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

-- 7. Long sentences: more stages, every word labelled (no window any more,
-- TASK-39); B drops one letter at a time; the end step counts from the start
-- word.
do
    local boxes = page(30, 10)
    local p = H.Pointer.new({ { first = 1, last = 8 }, { first = 9, last = 30 } }, boxes)
    pick(p, "sent", 1)
    for _, v in ipairs(p:visible()) do assert(#v.label == 2, "8 words: two letters") end
    assert(p:press("B") == "back")
    pick(p, "sent", 2)
    local wv = p:visible()
    assert(#wv == 22, "22 words")
    for _, v in ipairs(wv) do assert(#v.label == 3 and LETTER[v.label[1]], "three letters") end
    local l = label_for(p, "word", 20)
    assert(p:press(l[1]) == "prefix" and p:press(l[2]) == "prefix")
    assert(p:visible()[1].typed == 2)
    assert(p:press("B") == "unprefix" and p:visible()[1].typed == 1, "B drops the last letter")
    assert(p:press(l[2]) == "prefix" and p:press(l[3]) == "start" and p.start == 20)
    -- the end step: S2 from word 20 = 11 words, three letters
    wv = p:visible()
    assert(#wv == 11 and #wv[1].label == 3 and wv[1].word == 20)

    local big = page(160, 10)
    p = H.Pointer.new({ { first = 1, last = 160 } }, big)
    pick(p, "sent", 1)
    wv = p:visible()
    assert(#wv == 160 and #wv[1].label == 5 and wv[160].word == 160, "160 words: all, five letters")
    assert(pick(p, "word", 3) == "start")
    wv = p:visible()
    assert(#wv == 158 and wv[1].word == 3 and table.concat(wv[1].label) == "AAAAA", "end: from the start word")
    assert(p:press("left") == "done" and p.stop == 160, "← = the end of the sentence")
end

-- 8. Stages (TASK-39): what is drawn for the typed prefix. The sentence
-- level = the sentence labels; the word level = one badge per piece of the
-- current stage (A, X, Y in reading order) at its FIRST word: x = the word's
-- left edge (RTL right), above the word (y = top - d), below only when above
-- leaves the screen. A letter = its piece's sub-pieces, the last stage =
-- the word. Arrows are shortcuts at every stage, B goes back one stage.
-- page(20): lines at y = 0, 30, 60, 90 (h = 20); the default badge = 13 px.
local function seq(list) return table.concat(list, ",") end
local function syms(st)
    local out = {}
    for _, v in ipairs(st.items) do out[#out + 1] = v.symbol .. v.word end
    return table.concat(out, " ")
end
do
    local boxes = page(20)
    local p = H.Pointer.new(SENTS, boxes)
    local st = p:stage()
    assert(st.kind == "sentence" and #st.items == 4 and st.items[2].word == 4, "sentence labels as visible()")
    pick(p, "sent", 2)                                  -- S2 = words 4..12: two stages
    st = p:stage()
    assert(st.kind == "words" and #st.typed == 0, "word level: " .. st.kind)
    assert(syms(st) == "A4 X7 Y10", "pieces of 3 from the start: " .. syms(st))
    for k, v in ipairs(st.items) do
        local b = boxes[v.word]
        assert(v.side == "left" and v.x == b.x, "at the word's left edge")
        assert(v.d == 13 and v.h == b.h and v.box.y == b.y)
        assert(v.last == v.word + 2, "a piece = 3 words")
        assert(table.concat(v.label) == ({ "AA", "XA", "YA" })[k])
        -- never over the word's own box
        assert(v.y + v.d <= b.y or v.y >= b.y + b.h, "outside the word's box")
    end
    -- word 4 is on the top line: above would be y = -13 -> below; 7 and 10 above
    assert(st.items[1].place == "below" and st.items[1].y == boxes[4].y + boxes[4].h, "off the screen: below")
    assert(st.items[2].place == "above" and st.items[2].y == boxes[7].y - 13, "above the word")
    assert(st.items[3].place == "above")
    -- a letter = that piece's words, one letter each; the last stage = the word
    assert(p:press("X") == "prefix")
    st = p:stage()
    assert(seq(st.typed) == "X" and syms(st) == "A7 X8 Y9", syms(st))
    for _, v in ipairs(st.items) do assert(v.last == v.word, "the last stage: one word a piece") end
    -- B = back one stage; B again = the sentence labels
    assert(p:press("B") == "unprefix" and syms(p:stage()) == "A4 X7 Y10" and #p:stage().typed == 0)
    assert(p:press("B") == "back" and p:stage().kind == "sentence")
    -- sentence -> letter -> letter -> ← = from that word to the end of the sentence
    pick(p, "sent", 2)
    assert(p:press("X") == "prefix" and p:press("Y") == "start" and p.start == 9)
    st = p:stage()
    assert(syms(st) == "A9 X12", "end step: 9..12 = pieces 9..11 and 12: " .. syms(st))
    assert(p:press("left") == "done" and p.start == 9 and p.stop == 12)
    assert(p:stage().kind == "done" and #p:stage().items == 0)

    -- arrows after a typed letter: still shortcuts (start step)
    p = H.Pointer.new(SENTS, boxes)
    pick(p, "sent", 2)
    assert(p:press("Y") == "prefix" and p:press("left") == "start" and p.start == 4, "← after Y: the sentence start")
    assert(#p.typed == 0, "a shortcut drops the typed letters")
    -- ... and in the end step: → moves the end sentence, the stage starts again
    assert(p:press("A") == "prefix" and p:press("right") == "sentence" and p.sent == 3 and #p.typed == 0)
    assert(syms(p:stage()) == "A13 X14", "S3: two words, one stage")
    p = H.Pointer.new(SENTS, boxes)
    pick(p, "sent", 2)
    assert(p:press("A") == "prefix" and p:press("up") == "start" and p.start == 1, "↑ after A: the paragraph start")
    assert(p:press("right") == "sentence" and p.sent == 2, "end step: on to S2 (two stages)")
    assert(p:press("X") == "prefix" and p:press("down") == "done" and p.stop == 14, "↓ after X: the paragraph end")
    -- an ignored shortcut keeps the stage
    p = H.Pointer.new(SENTS, boxes)
    pick(p, "sent", 2)
    assert(p:press("X") == "prefix" and p:press("right") == "ignored" and seq(p.typed) == "X")

    -- the short last piece: 4 words = A (1..3), X (4); in X only A
    p = H.Pointer.new({ { first = 1, last = 4 } }, boxes)
    pick(p, "sent", 1)
    assert(syms(p:stage()) == "A1 X4")
    assert(p:press("X") == "prefix" and syms(p:stage()) == "A4", "one piece = one badge")
    assert(p:press("X") == "ignored" and p:press("Y") == "ignored")
    assert(p:press("A") == "start" and p.start == 4)
    -- one word: one stage, A
    p = H.Pointer.new({ { first = 7, last = 7 } }, boxes)
    pick(p, "sent", 1)
    assert(syms(p:stage()) == "A7" and p:press("A") == "start" and p.start == 7)

    -- three stages (22 words): 9, 9, 4; then pieces of 3; then words
    local b30 = page(30, 10)
    p = H.Pointer.new({ { first = 1, last = 8 }, { first = 9, last = 30 } }, b30)
    pick(p, "sent", 2)
    assert(syms(p:stage()) == "A9 X18 Y27", syms(p:stage()))
    assert(p:press("Y") == "prefix" and syms(p:stage()) == "A27 X30", "the short piece Y: 27..29, 30")
    assert(p:press("A") == "prefix" and syms(p:stage()) == "A27 X28 Y29")
    assert(p:press("B") == "unprefix" and p:press("B") == "unprefix" and #p:stage().items == 3)

    -- a larger badge (opts.badge): above leaves the screen on line 2 too
    p = H.Pointer.new(SENTS, boxes, { badge = function() return 40 end })
    pick(p, "sent", 2)
    st = p:stage()
    assert(st.items[2].d == 40 and st.items[2].place == "below" and st.items[2].y == 50)
    p = H.Pointer.new({ { first = 6, last = 12 } }, boxes, { badge = function(h) return h end })
    pick(p, "sent", 1)
    assert(p:stage().items[1].place == "above" and p:stage().items[1].y == 10, "30 - 20 = 10: fits")

    -- RTL: the badge at the right edge of the first word; ← and → swap, also
    -- after a typed letter
    p = H.Pointer.new(SENTS, boxes, { rtl = true })
    pick(p, "sent", 2)
    for _, v in ipairs(p:stage().items) do
        assert(v.side == "right" and v.x == boxes[v.word].x + boxes[v.word].w, "RTL: the right edge")
    end
    assert(p:press("X") == "prefix" and p:press("left") == "ignored", "RTL ←: on, nothing in the start step")
    assert(p:press("right") == "start" and p.start == 4, "RTL → after X: the sentence start")
    assert(p:press("A") == "prefix" and p:press("right") == "done" and p.stop == 12, "RTL →: the end")
end

print("kopad_hints_test: OK")
