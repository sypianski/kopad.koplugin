-- Tests for kopad_hints.lua ("point from-to", TASK-29): label assignment by
-- position, the line layer and the two-step pointer. Pure Lua, no KOReader.
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

-- 5. The pointer: start labels, end labels from the start line, B.
do
    local lines = {}
    for i = 1, 10 do lines[i] = { x = 20, y = (i - 1) * 30, w = 300 - (i % 3) * 40, h = 20, first = i, last = i } end
    local p = H.Pointer.new(lines)
    assert(p.step == "start")
    local vis = p:visible()
    assert(#vis == 10 and vis[1].side == "left" and vis[1].x == 20, "start labels on the left of every line")
    -- a symbol no label starts with is ignored
    local used = {}
    for _, v in ipairs(vis) do used[v.label[1]] = true end
    for _, c in ipairs(H.FIRST) do
        if not used[c] then assert(p:press(c) == "ignored"); break end
    end
    -- line 4: the first symbol filters, the second picks
    local lab = vis[4].label
    assert(p:press(lab[1]) == "prefix")
    local f = p:visible()
    for _, v in ipairs(f) do assert(v.label[1] == lab[1] and v.typed == 1, "only the prefix's labels") end
    assert(#f < 10)
    -- B with a prefix: drops it when no label continues with B
    local has_b = false
    for _, v in ipairs(f) do if v.label[2] == "B" then has_b = true end end
    if not has_b then
        assert(p:press("B") == "unprefix" and #p:visible() == 10)
        assert(p:press(lab[1]) == "prefix")
    end
    assert(p:press(lab[2]) == "start" and p.start == 4 and p.step == "end")
    -- end labels: lines 4..10, at the right end of each line
    local ends = p:visible()
    assert(#ends == 7 and ends[1].line == 4 and ends[1].side == "right", "end labels from the start line")
    assert(ends[1].x == lines[4].x + lines[4].w)
    local e = ends[3].label -- line 6
    assert(p:press(e[1]) == "prefix" and p:press(e[2]) == "done")
    assert(p.start == 4 and p.stop == 6 and #p:visible() == 0)
    assert(p:press("A") == "ignored", "done: nothing more")

    -- B in step end = no end (one word)
    p = H.Pointer.new(lines)
    local l1 = p:visible()[1].label
    p:press(l1[1]); p:press(l1[2])
    assert(p.step == "end" and p:press("B") == "done" and p.start == 1 and p.stop == nil)
    -- B in step start = cancel
    p = H.Pointer.new(lines)
    assert(p:press("B") == "cancel")
    -- RTL: the line start is on the right, the end on the left
    p = H.Pointer.new(lines, { rtl = true })
    local r = p:visible()[1]
    assert(r.side == "right" and r.x == lines[1].x + lines[1].w)
    p:press(r.label[1]); p:press(r.label[2])
    assert(p:visible()[1].side == "left" and p:visible()[1].x == 20)
    -- no lines: no labels, B closes
    p = H.Pointer.new({})
    assert(#p:visible() == 0 and p:press("up") == "ignored" and p:press("B") == "cancel")
end

print("kopad_hints_test: OK")
