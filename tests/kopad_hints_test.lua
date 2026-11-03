-- Tests for kopad_hints.lua ("point from-to", TASK-29): label assignment by
-- position, the line layer and the two-step pointer on sentences (TASK-35). Pure Lua, no KOReader.
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

-- 5. The pointer on sentences (TASK-35, PC-022): start labels at the
-- sentence starts, end labels at the sentence ends from the start sentence
-- down, refinement to a word (R-stick), B.
-- Page: 4 lines of 5 words (x = 20 + k * 60, y = line * 30); sentences
-- S1 = 1-3, S2 = 4-12, S3 = 13-14, S4 = 15-20.
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
    assert(p:press(l[1]) == "prefix", "first symbol")
    return p:press(l[2])
end
do
    local boxes = page(20)
    local sents = { { first = 1, last = 3 }, { first = 4, last = 12 },
                    { first = 13, last = 14 }, { first = 15, last = 20 } }
    local p = H.Pointer.new(sents, boxes)
    assert(p.step == "start" and p.level == "sentence" and p.refine == false)
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
    -- S2: the first symbol filters, the second picks the start (word 4)
    local lab = label_for(p, "sent", 2)
    assert(p:press(lab[1]) == "prefix")
    for _, v in ipairs(p:visible()) do assert(v.label[1] == lab[1] and v.typed == 1) end
    local has_b = false
    for _, v in ipairs(p:visible()) do if v.label[2] == "B" then has_b = true end end
    if not has_b then
        assert(p:press("B") == "unprefix" and #p:visible() == 4)
        assert(p:press(lab[1]) == "prefix")
    end
    assert(p:press(lab[2]) == "start" and p.start == 4 and p.start_sent == 2 and p.step == "end")
    -- end labels: S2 .. S4, right of each sentence's last word
    local ends = p:visible()
    assert(#ends == 3 and ends[1].sent == 2 and ends[1].word == 12 and ends[1].side == "right", "end labels")
    assert(ends[1].x == boxes[12].x + boxes[12].w)
    assert(pick(p, "sent", 3) == "done" and p.start == 4 and p.stop == 14 and #p:visible() == 0)
    assert(p:press("A") == "ignored", "done: nothing more")

    -- B: start labels = cancel, end labels = one word
    p = H.Pointer.new(sents, boxes)
    assert(p:press("B") == "cancel")
    assert(pick(p, "sent", 1) == "start")
    assert(p:press("B") == "done" and p.start == 1 and p.stop == nil)

    -- the start sentence as its own end
    p = H.Pointer.new(sents, boxes)
    pick(p, "sent", 3)
    assert(pick(p, "sent", 3) == "done" and p.start == 13 and p.stop == 14)

    -- refinement to a word: R↓ in the step, a sentence label = its words
    p = H.Pointer.new(sents, boxes)
    assert(p:refine_to_word(true) == true and p.refine and p.level == "sentence")
    assert(p:refine_to_word(true) == false, "already on")
    assert(#p:visible() == 4, "still the sentence labels")
    assert(pick(p, "sent", 2) == "sentence" and p.level == "word" and p.sent == 2)
    local wv = p:visible()
    assert(#wv == 9, "labels on S2's nine words only, got " .. #wv)
    for _, v in ipairs(wv) do assert(v.sent == 2 and v.word >= 4 and v.word <= 12 and v.side == "top") end
    assert(wv[1].x == boxes[4].x + boxes[4].w / 2 and wv[1].y == boxes[4].y, "over the word, its top edge")
    -- B on the word labels: back to the sentence labels (refine stays on)
    assert(p:press("B") == "back" and p.level == "sentence" and p.refine and #p:visible() == 4)
    pick(p, "sent", 2)
    assert(pick(p, "word", 7) == "start" and p.start == 7 and p.step == "end")
    -- a new step starts with sentences, refinement off
    assert(p.refine == false and p.level == "sentence")
    assert(label_for(p, "sent", 2) and label_for(p, "sent", 1) == nil, "end labels from S2 on")
    -- refine the end: S2 offers only the words from the start word on
    p:refine_to_word(true)
    assert(pick(p, "sent", 2) == "sentence")
    wv = p:visible()
    assert(#wv == 6 and wv[1].word == 7 and wv[6].word == 12, "S2 from the start word: " .. #wv)
    -- R↑ on the word labels: the sentence labels again, refinement off
    assert(p:refine_to_word(false) == true and p.level == "sentence" and p.refine == false)
    assert(p:refine_to_word(false) == false)
    p:refine_to_word(true)
    pick(p, "sent", 4)
    assert(pick(p, "word", 17) == "done" and p.start == 7 and p.stop == 17)
    assert(p:refine_to_word(true) == false, "done: nothing to refine")

    -- a sentence over the page edge / out of a zoomed view: labels at its
    -- visible part; a sentence with no visible word gets none
    local zb = page(20)
    for i = 1, 5 do zb[i] = false end   -- the first line is off the screen
    p = H.Pointer.new(sents, zb)
    assert(label_for(p, "sent", 1) == nil, "S1 has no visible word: no label")
    assert(label_for(p, "sent", 2) and p:visible()[1].word == 6, "S2 labelled at its first visible word")
    assert(#H.Pointer.new(sents, page(0)):visible() == 0)

    -- RTL: the start is on the right of the first word, the end on the left
    -- of the last one
    p = H.Pointer.new(sents, boxes, { rtl = true })
    local r = p:visible()[1]
    assert(r.side == "right" and r.x == boxes[1].x + boxes[1].w)
    pick(p, "sent", 1)
    r = p:visible()[1]
    assert(r.side == "left" and r.x == boxes[3].x)

    -- no sentences: no labels, B closes
    p = H.Pointer.new({}, {})
    assert(#p:visible() == 0 and p:press("up") == "ignored" and p:press("B") == "cancel")
end

-- 6. A sentence longer than 56 visible words: word labels on a window of 56,
-- the first ones in the start step, the last ones in the end step.
do
    local boxes = page(70, 10)
    local sents = { { first = 1, last = 70 } }
    local p = H.Pointer.new(sents, boxes)
    p:refine_to_word(true)
    pick(p, "sent", 1)
    local wv = p:visible()
    assert(#wv == 56 and wv[1].word == 1 and wv[56].word == 56, "start: the first 56")
    assert(pick(p, "word", 3) == "start")
    p:refine_to_word(true)
    pick(p, "sent", 1)
    wv = p:visible()
    assert(#wv == 56 and wv[1].word == 15 and wv[56].word == 70, "end: the last 56, got " .. wv[1].word)
    assert(pick(p, "word", 70) == "done" and p.start == 3 and p.stop == 70)
end

print("kopad_hints_test: OK")
