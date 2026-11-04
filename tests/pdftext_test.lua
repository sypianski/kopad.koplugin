-- Tests for pdftext.lua (words split by the gap between glyphs). Pure part
-- only: split_line / is_gap over plain chars; the FFI adapter needs KOReader.
-- Run from the repo root:  lua tests/pdftext_test.lua
package.path = "./?.lua;" .. package.path

local M = require("pdftext")

local function u(c) return utf8.char(c) end

-- A line from { {char, s0, s1}, ... } (extent along the line = x), size 11 pt.
local function line(spec, size)
    local first, prev
    for _, e in ipairs(spec) do
        local c = type(e[1]) == "string" and e[1]:byte() or e[1]
        local node = { c = c, x0 = e[2], x1 = e[3], y0 = 0, y1 = 12, s0 = e[2], s1 = e[3],
                       size = size or 11 }
        if prev then prev.next = node else first = node end
        prev = node
    end
    return first
end

local function texts(words)
    local t = {}
    for i, w in ipairs(words) do t[i] = w.word end
    return table.concat(t, "|")
end

-- 1. The real thing: the first glyphs of "1. Organ przyznaje, że" from the
-- papeteria PDF (page 2), which has NO space characters. Gaps between words
-- are 1.4 pt (0.127 em), inside words at most 0.1 pt.
local real = line({
    { "1", 70.7, 74.6 }, { ".", 74.6, 77.6 },
    { "O", 79.0, 86.3 }, { "r", 86.3, 90.8 }, { "g", 90.8, 96.3 }, { "a", 96.2, 101.5 },
    { "n", 101.5, 107.6 },
    { "p", 109.0, 114.8 }, { "r", 114.8, 119.3 }, { "z", 119.3, 124.3 }, { "y", 124.3, 129.4 },
    { "z", 129.4, 134.3 }, { "n", 134.3, 140.5 }, { "a", 140.5, 145.7 }, { "j", 145.7, 148.7 },
    { "e", 148.7, 153.8 }, { ",", 153.5, 156.5 },
    { 0x17C, 157.8, 162.8 }, { "e", 162.8, 167.9 },
})
local words = M.split_line(real, u)
assert(texts(words) == "1.|Organ|przyznaje,|że", "squeezed line split by gaps: " .. texts(words))
assert(words[2].x0 == 79.0 and words[2].x1 == 107.6, "word box covers its glyphs")

-- 2. Proper space characters: same result as koreader-base (the space is
-- dropped, no gap rule needed)
local spaced = line({ { "a", 0, 5 }, { "b", 5, 10 }, { " ", 10, 13 }, { "c", 13, 18 } })
assert(texts((M.split_line(spaced, u))) == "ab|c", "spaces still split")

-- 3. Kerning stays inside the word: 0.066 em = the widest in-word gap measured
local kern = line({ { "A", 0, 7 }, { "V", 7 + 0.726, 14 } }) -- 0.726 pt = 0.066 em at 11 pt
assert(texts((M.split_line(kern, u))) == "AV", "kerning does not split")

-- 4. Overlapping glyphs (accent, ligature): negative gap, no split
local over = line({ { "a", 0, 5 }, { 0x301, 4, 5 }, { "b", 5, 10 } })
assert(texts((M.split_line(over, u))) == "a" .. utf8.char(0x301) .. "b", "overlap does not split")

-- 5. is_gap on its own: the threshold is in em of the LARGER glyph, both sides
local small = { s0 = 0, s1 = 4, size = 6 }
local big = { s0 = 5.1, s1 = 12, size = 12 }
assert(M.is_gap(small, big) == false, "1.1 pt < 0.1 * 12")
assert(M.is_gap(small, { s0 = 5.3, s1 = 12, size = 12 }) == true, "1.3 pt > 0.1 * 12")
assert(M.is_gap({ s0 = 20, s1 = 25, size = 11 }, { s0 = 10, s1 = 18, size = 11 }) == true,
    "right-to-left gap of 2 pt")
assert(M.is_gap({ s0 = 0, s1 = 5, size = 0 }, { s0 = 9, s1 = 12, size = 0 }) == false,
    "size 0: never a gap")

-- 6. Vertical text (wmode 1): the gap rule is off, as before
local vert = line({ { "a", 0, 5 }, { "b", 9, 14 } })
assert(texts((M.split_line(vert, u, false))) == "ab", "gaps=false keeps stock behaviour")

-- 7. A leading bullet is skipped with its white space, like koreader-base
local bullet = line({ { 0x2022, 0, 4 }, { " ", 4, 8 }, { "x", 8, 13 }, { "y", 13, 18 } })
assert(texts((M.split_line(bullet, u))) == "xy", "leading bullet skipped")

-- 8. A CJK glyph ends its word, and the next glyph is NOT skipped
local cjk = line({ { "a", 0, 5 }, { 0x4e2d, 5, 17 }, { "b", 17, 22 } })
assert(texts((M.split_line(cjk, u))) == "a" .. utf8.char(0x4e2d) .. "|b",
    "CJK glyph ends the word (it belongs to it, as in koreader-base)")

-- 9. Line box and empty lines
local _, box = M.split_line(real, u)
assert(box and box[1] == 70.7 and box[3] == 167.9, "line box = union of the glyphs")
local none, nbox = M.split_line(line({ { " ", 0, 3 } }), u)
assert(#none == 0 and nbox == nil, "only white space: no words, no box")

-- 11. Letter-spaced text (tracking): every pair has the same extra gap
-- (0.114 em at 8 pt = 0.91 pt, the Elsevier "journal homepage" header, which
-- a fixed 0.10 em limit cut into letters). The limit is relative to the line:
-- the real word gap is tracking + a space (here 0.91 + 2.4 pt).
local function tracked(text, size, track, word)
    local spec, x = {}, 0
    for i = 1, #text do
        local ch = text:sub(i, i)
        if ch == " " then
            x = x + word
        else
            local w = size * 0.5
            spec[#spec + 1] = { ch, x, x + w }
            x = x + w + track
        end
    end
    return line(spec, size)
end
local tr = tracked("journal homepage", 8, 0.91, 2.4)
assert(texts((M.split_line(tr, u))) == "journal|homepage", "tracking kept: " .. texts((M.split_line(tr, u))))
assert(math.abs(M.baseline(tr) - 0.114) < 0.01, "baseline = the tracking, got " .. M.baseline(tr))
assert(M.baseline(real) < 0.01, "ordinary squeezed line: baseline ~0, got " .. M.baseline(real))
assert(M.baseline(line({ { "a", 0, 5 }, { "b", 9, 14 } })) == 0, "fewer than 4 gaps: 0")
-- a line of single letters with no spaces at all: the word gaps are most
-- pairs, but the quartile (not the median) still sees the glyphs that touch
local short = line({ { "I", 0, 4 }, { "a", 4, 8 }, { "m", 8, 14 }, { "a", 15.5, 20 }, { "b", 20, 25 },
                      { "o", 25, 30 }, { "y", 31.5, 36 } })
assert(texts((M.split_line(short, u))) == "Iam|abo|y", "short words: " .. texts((M.split_line(short, u))))

-- 10. install() without KOReader: refuses, never raises
assert(M.install(nil, function() return true end) == false)
assert(M.install({ _document = {} }, function() return true end) == false)

print("pdftext_test: ok")
