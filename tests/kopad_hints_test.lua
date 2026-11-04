-- Tests for kopad_hints.lua ("point from-to", TASK-29): label assignment by
-- position and the pointer over the sentence labels (TASK-35; sentence
-- labels only since TASK-42 / PC-024: the word level of TASK-36..41 is
-- gone). Pure Lua, no KOReader.
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

-- 4. The pointer (TASK-35, TASK-42): labels at the sentence starts, a label
-- = that sentence and its first visible word. Page: 4 lines of 5 words (x =
-- 20 + k * 60, y = line * 30); sentences S1 = 1-3, S2 = 4-12, S3 = 13-14, S4
-- = 15-20.
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
local SENTS = { { first = 1, last = 3, para = 1 }, { first = 4, last = 12, para = 1 },
                { first = 13, last = 14, para = 1 }, { first = 15, last = 20, para = 2 } }
do
    local boxes = page(20)
    local p = H.Pointer.new(SENTS, boxes)
    assert(p.step == "start" and p.level == nil and p.stage == nil and p.preview == nil,
        "no word level, no stages, no preview (TASK-42)")
    assert(H.word_labels == nil and H.dashes == nil and H.lines_from_boxes == nil)
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
    -- a whole label = done: the sentence and its first word, nothing more
    assert(p:press(lab[2]) == "done" and p.step == "done" and p.sent == 2 and p.start == 4)
    assert(#p:visible() == 0)
    assert(p:press("A") == "ignored" and p:press("left") == "ignored" and p:press("B") == "ignored",
        "done: nothing more")
    -- every sentence: its first word
    for si, s in ipairs(SENTS) do
        p = H.Pointer.new(SENTS, boxes)
        assert(pick(p, "sent", si) == "done" and p.start == s.first and p.sent == si)
    end
    -- B with nothing typed = cancel
    p = H.Pointer.new(SENTS, boxes)
    assert(p:press("B") == "cancel")

    -- a sentence over the page edge / out of a zoomed view: the label at its
    -- first VISIBLE word; a sentence with no visible word gets none
    local zb = page(20)
    for i = 1, 5 do zb[i] = false end   -- the first line is off the screen
    p = H.Pointer.new(SENTS, zb)
    assert(label_for(p, "sent", 1) == nil, "S1 has no visible word: no label")
    assert(label_for(p, "sent", 2) and p:visible()[1].word == 6, "S2 labelled at its first visible word")
    assert(pick(p, "sent", 2) == "done" and p.start == 6, "the cursor goes to word 6")
    assert(#H.Pointer.new(SENTS, page(0)):visible() == 0)

    -- RTL: sentence labels on the right of the first word
    p = H.Pointer.new(SENTS, boxes, { rtl = true })
    local r = p:visible()[1]
    assert(r.side == "right" and r.x == boxes[1].x + boxes[1].w)
    assert(pick(p, "sent", 3) == "done" and p.start == 13)

    -- no sentences: no labels, B closes
    p = H.Pointer.new({}, {})
    assert(#p:visible() == 0 and p:press("up") == "ignored" and p:press("B") == "cancel")

    -- more sentences than labels: 56 at most
    local many, mb = {}, page(70, 1)
    for i = 1, 70 do many[i] = { first = i, last = i } end
    p = H.Pointer.new(many, mb)
    assert(#p:visible() == H.MAX_LABELS and H.MAX_LABELS == 56)
end

print("kopad_hints_test: OK")
