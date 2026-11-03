-- Tests for statusbar.lua (where the selector's status bar goes so that it
-- never covers the book text): pure Lua. Run from the repo root:
--   lua tests/statusbar_test.lua
package.path = "./?.lua;" .. package.path

local SB = require("statusbar")
local TH = 20                       -- text height; full bar = 5 + 20 + 3 + 2 = 30

local function lay(first_y, last_y, limit_y)
    return SB.layout({ first_y = first_y, last_y = last_y, limit_y = limit_y }, TH)
end

-- 1. Heights.
assert(SB.full_height(TH) == 30)
assert(SB.short_height(TH) == 22)

-- 2. A tall top strip: the full bar at the top, never taller than the strip.
do
    local l = lay(70, 700, 756)
    assert(l.kind == "top" and l.y == 0 and l.h == 30 and not l.short and l.rule)
    assert(l.y + l.h <= 70)
end

-- 3. Top strip too low, bottom strip fits: the full bar sits on the footer.
do
    local l = lay(25, 709, 756)                 -- 25 < 30, 47 >= 30
    assert(l.kind == "bottom" and l.h == 30 and not l.short)
    assert(l.y == 726 and l.y + l.h == 756 and l.y >= 709)
end

-- 4. Neither fits the full bar: the short one goes into the larger strip.
do
    local l = lay(10, 732, 756)                 -- strips 10 and 24
    assert(l.kind == "bottom" and l.short and not l.rule)
    assert(l.h == 22 and l.y == 734 and l.y >= 732)
    local t = lay(24, 740, 756)                 -- strips 24 and 16
    assert(t.kind == "top" and t.short and t.h == 22 and t.y == 0 and t.y + t.h <= 24)
    -- a strip shorter than the short bar: the bar shrinks to the strip
    local s = lay(21, 740, 756)
    assert(s.kind == "top" and s.short and s.h == 21)
end

-- 5. No strip holds even one line of text: nothing.
assert(lay(10, 740, 756).kind == "none")       -- strips 10 and 16
do
    local l = lay(8, 745, 756)                  -- strips 8 and 11
    assert(l.kind == "none")
end

-- 6. Equal strips: the top wins (as in the mock-up).
do
    local l = lay(24, 732, 756)                 -- 24 and 24
    assert(l.kind == "top" and l.short)
end

-- 7. The bar never lands on text, over a grid of strips.
for first = 0, 80, 3 do
    for below = 0, 80, 3 do
        local last, limit = 400, 400 + below
        local l = lay(first, last, limit)
        if l.kind == "top" then
            assert(l.y >= 0 and l.y + l.h <= first, "top over text")
        elseif l.kind == "bottom" then
            assert(l.y >= last and l.y + l.h <= limit, "bottom over text")
        else
            assert(first < TH and below < TH, "gave up with room")
        end
    end
end

-- 8. Nothing to measure (no word boxes): no bar.
assert(SB.layout(nil, TH).kind == "none")
assert(SB.extent({}, 800, 0) == nil)
assert(SB.extent({ { text = "a" }, { sbox = {} } }, 800, 0) == nil)

-- 9. Extent: min top, max bottom, clamped to the screen; footer lifts the limit.
do
    local words = {
        { sbox = { y = 40, h = 30 } },
        { sbox = { y = 200, h = 30 } },
        { sbox = { y = 700, h = 30 } },
        false,
    }
    local e = SB.extent(words, 800, 44)
    assert(e.first_y == 40 and e.last_y == 730 and e.limit_y == 756)
    local e2 = SB.extent({ { sbox = { y = -12, h = 30 } }, { sbox = { y = 780, h = 40 } } }, 800)
    assert(e2.first_y == 0 and e2.last_y == 800 and e2.limit_y == 800)
    assert(SB.layout(e2, TH).kind == "none")
end

print("statusbar_test: OK")
