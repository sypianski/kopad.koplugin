-- pdfpara.lua -- paragraph detection for PDF / DjVu pages (TASK-32).
--
-- A pure module (no KOReader dependencies, requirable in bare Lua). PDF and
-- DjVu know no paragraphs, only text lines with rectangles, so the paragraphs
-- are guessed from the geometry.
--
-- INPUT: the native format of `document:getTextBoxes(pageno)` (KOReader
-- frontend/document/koptinterface.lua; readerhighlight.lua iterates it as
-- `for i, line in ipairs(boxes) do for j, box in ipairs(line) do ... end end`):
--
--   lines = {                       -- array of text lines
--     { {x0=, y0=, x1=, y1=, word="Foo"}, {x0=, ..., word="bar."}, ... },
--     { ... },
--   }
--
-- Every line is an array of word boxes in native page coordinates (zoom 1.0,
-- y grows downwards). The lines carry no rectangle of their own, so it is
-- computed here from the words (x: min / max; y: median, which is robust to
-- superscripts). Words of one line may come out of order (DjVu) and lines may
-- come out of reading order -- both are handled. KOReader also emits
-- placeholder lines like `{ {word = ""} }`; boxes with an empty / blank word,
-- without numeric coordinates or with an empty rectangle are skipped, and a
-- line left without boxes is skipped whole (it gets no paragraph).
--
-- All indices below are indices into the INPUT array `lines`, unless stated
-- otherwise.
--
-- API
--   M.columns(lines, opts)    -> layout
--       layout.ncols     1 or 2
--       layout.gap       { x0, x1 } of the gutter (ncols == 2), else nil
--       layout.col_of    [line index] = 1 (single / left column), 2 (right
--                        column), 0 (full-width line crossing the gutter:
--                        title, abstract, footer)
--       layout.order     line indices in reading order: with two columns the
--                        whole left column, then the right one, per band
--                        between full-width lines
--   M.paragraphs(lines, opts) -> paras, info
--       paras[n] = { first = <pos>, last = <pos>, lines = { idx, ... } }
--                  <pos> = position in info.order, `lines` = the input line
--                  indices of the paragraph in reading order
--       info.order       line indices in reading order (valid lines only)
--       info.pos         [line index] = position in info.order
--       info.para_of     [line index] = paragraph number (nil: skipped line)
--       info.col_of, info.ncols, info.gap   as in `columns`
--     nil / empty page / lines without words -> `{}`, info with empty tables.
--   opts.rtl = true mirrors x (right-to-left script: the indent is on the right
--   and the first column is the right one).
--
-- Heuristics (thresholds relative to the median line height `hmed`, the
-- typical line pitch and the column width, never absolute points). A new
-- paragraph starts at a line when, compared to the previous line in reading
-- order:
--   a) it is a clearly different height (heading, footnote, caption),
--   b) it starts with a list marker (bullet, dash, "1.", "a)"),
--   c) the line pitch is clearly larger than the typical one,
--   d) its first line is indented against the column's left margin,
--   e) the previous line is clearly shorter than the column (justified text
--      0.8, ragged-right text 0.55) and ends a sentence (. ! ? : ... possibly
--      followed by closing quotes / brackets),
--   f) a full-width line (two-column page) meets a column line.
-- Between two columns the pitch rule (c) does not apply -- a paragraph may
-- continue from the bottom of the left column to the top of the right one.

local M = {}

-- Tunables (fractions of the quantities named in the header).
M.OPTS = {
    narrow = 0.7,       -- a line narrower than this x the text span is column text
    gutter = 0.8,       -- min gutter width, in median line heights
    gutter_zone = 0.3,  -- gutter centre within [zone, 1 - zone] of the text span
    min_side = 3,       -- min lines on each side of the gutter ...
    min_side_frac = 0.2, -- ... and this fraction of all lines
    max_cross = 0.25,   -- max fraction of lines crossing the gutter
    min_lines = 8,      -- fewer lines than this: always one column
    height_ratio = 1.3, -- line height ratio (either way) = different style
    pitch = 1.3,        -- pitch > this x typical pitch = paragraph gap
    indent = 0.8,       -- first-line indent, in line heights ...
    indent_max = 0.4,   -- ... and at most this fraction of the column width
    short_justified = 0.8,
    short_ragged = 0.55,
}

local function num(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function percentile(list, p)
    if #list == 0 then return nil end
    local t = {}
    for i = 1, #list do t[i] = list[i] end
    table.sort(t)
    return t[math.floor((#t - 1) * p) + 1]
end

local function median(list) return percentile(list, 0.5) end

-- Line records -----------------------------------------------------------------

-- One record per usable input line: bounding x range, median y range, height,
-- the first and the last word in reading direction.
local function collect(lines, opts)
    local recs = {}
    if type(lines) ~= "table" then return recs end
    local rtl = opts and opts.rtl
    for i = 1, #lines do
        local ln = lines[i]
        if type(ln) == "table" then
            local y0s, y1s, hs = {}, {}, {}
            local x0, x1 = math.huge, -math.huge
            local fw, lw, fx, lx = nil, nil, math.huge, -math.huge
            for j = 1, #ln do
                local b = ln[j]
                if type(b) == "table" and num(b.x0) and num(b.x1) and num(b.y0)
                        and num(b.y1) and b.x1 > b.x0 and b.y1 > b.y0
                        and not (type(b.word) == "string" and not b.word:find("%S")) then
                    local bx0, bx1 = b.x0, b.x1
                    if rtl then bx0, bx1 = -b.x1, -b.x0 end
                    if bx0 < x0 then x0 = bx0 end
                    if bx1 > x1 then x1 = bx1 end
                    y0s[#y0s + 1], y1s[#y1s + 1] = b.y0, b.y1
                    hs[#hs + 1] = b.y1 - b.y0
                    local w = type(b.word) == "string" and b.word or ""
                    if bx0 < fx then fx, fw = bx0, w end
                    if bx1 > lx then lx, lw = bx1, w end
                end
            end
            if #hs > 0 then
                local y0, y1 = median(y0s), median(y1s)
                recs[#recs + 1] = {
                    i = i, x0 = x0, x1 = x1, y0 = y0, y1 = y1, yc = (y0 + y1) / 2,
                    h = median(hs), first = fw, last = lw,
                }
            end
        end
    end
    return recs
end

local function by_y(a, b)
    if a.yc ~= b.yc then return a.yc < b.yc end
    return a.x0 < b.x0
end

-- Columns ----------------------------------------------------------------------

-- The widest gap in the middle of the text span that no narrow (column) line
-- covers, accepted only when both sides hold enough lines overlapping in y and
-- few lines cross it. Returns { x0, x1 } or nil.
local function find_gap(recs, hmed)
    local O = M.OPTS
    local n = #recs
    if n < O.min_lines then return nil end
    local minx, maxx = math.huge, -math.huge
    for _, r in ipairs(recs) do
        if r.x0 < minx then minx = r.x0 end
        if r.x1 > maxx then maxx = r.x1 end
    end
    local span = maxx - minx
    if span <= 0 then return nil end
    local narrow = {}
    for _, r in ipairs(recs) do
        if r.x1 - r.x0 < O.narrow * span then narrow[#narrow + 1] = r end
    end
    if #narrow < 2 * O.min_side then return nil end
    table.sort(narrow, function(a, b) return a.x0 < b.x0 end)
    local best
    local reach = narrow[1].x1
    for k = 2, #narrow do
        local r = narrow[k]
        if r.x0 > reach then
            local g0, g1 = reach, r.x0
            local c = ((g0 + g1) / 2 - minx) / span
            if g1 - g0 >= O.gutter * hmed and c >= O.gutter_zone and c <= 1 - O.gutter_zone
                    and (not best or g1 - g0 > best.x1 - best.x0) then
                best = { x0 = g0, x1 = g1 }
            end
        end
        if r.x1 > reach then reach = r.x1 end
    end
    if not best then return nil end
    local nl, nr, nc = 0, 0, 0
    local l0, l1, r0, r1 = math.huge, -math.huge, math.huge, -math.huge
    for _, r in ipairs(recs) do
        if r.x0 < best.x1 and r.x1 > best.x0 then
            nc = nc + 1
        elseif r.x1 <= best.x0 then
            nl = nl + 1
            l0, l1 = math.min(l0, r.y0), math.max(l1, r.y1)
        else
            nr = nr + 1
            r0, r1 = math.min(r0, r.y0), math.max(r1, r.y1)
        end
    end
    if nl < O.min_side or nr < O.min_side then return nil end
    if nl < O.min_side_frac * n or nr < O.min_side_frac * n then return nil end
    if nc > O.max_cross * n then return nil end
    local overlap = math.min(l1, r1) - math.max(l0, r0)
    if overlap < 0.5 * math.min(l1 - l0, r1 - r0) then return nil end
    return best
end

-- Sets r.g (0 = crosses the gutter, 1 = left / only, 2 = right) and returns the
-- records in reading order.
local function arrange(recs, hmed)
    local gap = find_gap(recs, hmed)
    local sorted = {}
    for i, r in ipairs(recs) do sorted[i] = r end
    table.sort(sorted, by_y)
    if not gap then
        for _, r in ipairs(sorted) do r.g = 1 end
        return sorted, nil
    end
    local out, left, right = {}, {}, {}
    local function flush()
        for _, r in ipairs(left) do out[#out + 1] = r end
        for _, r in ipairs(right) do out[#out + 1] = r end
        left, right = {}, {}
    end
    for _, r in ipairs(sorted) do
        if r.x0 < gap.x1 and r.x1 > gap.x0 then
            r.g = 0
        elseif r.x1 <= gap.x0 then
            r.g = 1
        else
            r.g = 2
        end
    end
    -- The short last line of a full-width paragraph (abstract) can end inside one
    -- column: a column line right below a full-width line at a normal pitch with
    -- nothing on its row in the other column continues that paragraph.
    local prev
    for _, r in ipairs(sorted) do
        if r.g ~= 0 and prev and prev.g == 0 and r.yc - prev.yc < 1.8 * r.h then
            local other = false
            for _, o in ipairs(sorted) do
                if o.g == 3 - r.g and o.y0 < r.yc and r.yc < o.y1 then
                    other = true
                    break
                end
            end
            if not other then r.g = 0 end
        end
        prev = r
    end
    for _, r in ipairs(sorted) do
        if r.g == 0 then
            flush()
            out[#out + 1] = r
        elseif r.g == 1 then
            left[#left + 1] = r
        else
            right[#right + 1] = r
        end
    end
    flush()
    return out, gap
end

local function layout_of(ordered, gap)
    local lay = { ncols = gap and 2 or 1, gap = gap, col_of = {}, order = {} }
    for k, r in ipairs(ordered) do
        lay.order[k] = r.i
        lay.col_of[r.i] = r.g
    end
    return lay
end

function M.columns(lines, opts)
    local recs = collect(lines, opts)
    if #recs == 0 then return layout_of({}, nil) end
    local hs = {}
    for i, r in ipairs(recs) do hs[i] = r.h end
    local ordered, gap = arrange(recs, median(hs))
    return layout_of(ordered, gap)
end

-- Text helpers -----------------------------------------------------------------

local CLOSERS = { "»", "”", "’", "›", "\"", "'", ")", "]" }
local TERMINALS = { ".", "!", "?", ":", "…", "؟", "۔", "。", "？", "！", "։" }

local function ends_with(w, s) return #w >= #s and w:sub(-#s) == s end

-- Does the word end a sentence ("end.", "end?»", "end.)")?
local function ends_sentence(w)
    if not w or w == "" then return false end
    local again = true
    while again do
        again = false
        for _, c in ipairs(CLOSERS) do
            if ends_with(w, c) then
                w = w:sub(1, #w - #c)
                again = true
                break
            end
        end
    end
    for _, t in ipairs(TERMINALS) do
        if ends_with(w, t) then return true end
    end
    return false
end

local MARKERS = {
    ["-"] = true, ["–"] = true, ["—"] = true, ["•"] = true, ["·"] = true,
    ["▪"] = true, ["◦"] = true, ["‣"] = true, ["*"] = true,
}

local function is_marker(w)
    if not w then return false end
    return MARKERS[w] or w:match("^%d%d?[%.%)]$") ~= nil
        or w:match("^%(%d%d?%)$") ~= nil or w:match("^%l%)$") ~= nil
end

-- Per-group margins ------------------------------------------------------------

-- left margin = the most common line start (ties: the leftmost), right edge =
-- 85th percentile of the line ends, justified = many lines end at that edge.
local function group_stats(list, hmed)
    local O = M.OPTS
    local s = { n = #list }
    if #list == 0 then return s end
    local x0s, x1s = {}, {}
    for i, r in ipairs(list) do x0s[i], x1s[i] = r.x0, r.x1 end
    if #list < 3 then
        s.left, s.right = math.huge, -math.huge
        for i = 1, #list do
            s.left = math.min(s.left, x0s[i])
            s.right = math.max(s.right, x1s[i])
        end
    else
        local tol = 0.3 * hmed
        local best_n, best_x, best_set = 0, nil, nil
        for _, x in ipairs(x0s) do
            local set = {}
            for _, y in ipairs(x0s) do
                if math.abs(x - y) <= tol then set[#set + 1] = y end
            end
            if #set > best_n or (#set == best_n and x < best_x) then
                best_n, best_x, best_set = #set, x, set
            end
        end
        s.left = median(best_set)
        s.right = percentile(x1s, 0.85)
    end
    s.width = math.max(s.right - s.left, hmed)
    local full = 0
    for _, x in ipairs(x1s) do
        if x >= s.right - 0.04 * s.width then full = full + 1 end
    end
    s.justified = #list >= 4 and full / #list >= 0.4
    s.short_at = s.left + s.width * (s.justified and O.short_justified or O.short_ragged)
    return s
end

-- Paragraphs -------------------------------------------------------------------

function M.paragraphs(lines, opts)
    local O = M.OPTS
    local paras = {}
    local info = { order = {}, pos = {}, para_of = {}, col_of = {}, ncols = 1 }
    local recs = collect(lines, opts)
    if #recs == 0 then return paras, info end

    local hs = {}
    for i, r in ipairs(recs) do hs[i] = r.h end
    local hmed = median(hs)
    local ordered, gap = arrange(recs, hmed)
    info.ncols, info.gap = gap and 2 or 1, gap

    local groups = { [0] = {}, {}, {} }
    for _, r in ipairs(ordered) do
        local g = groups[r.g]
        g[#g + 1] = r
    end
    local stats = {}
    for g = 0, 2 do stats[g] = group_stats(groups[g], hmed) end

    -- typical line pitch: lower-middle of the pitches between neighbouring lines
    -- of one group and one style (paragraph gaps make the upper tail)
    local pitches = {}
    for k = 2, #ordered do
        local p, r = ordered[k - 1], ordered[k]
        local d = r.yc - p.yc
        local ratio = r.h / p.h
        if p.g == r.g and d > 0.5 * r.h and d < 3.5 * hmed
                and ratio > 1 / O.height_ratio and ratio < O.height_ratio then
            pitches[#pitches + 1] = d
        end
    end
    local ref = percentile(pitches, 0.4) or 1.2 * hmed

    local function indent(r)
        local off = r.x0 - stats[r.g].left
        return off, off > O.indent * r.h and off < O.indent_max * stats[r.g].width
    end

    local function is_break(p, r)
        local ratio = r.h / p.h
        if ratio >= O.height_ratio or ratio <= 1 / O.height_ratio then return true end
        if (p.g == 0) ~= (r.g == 0) then return true end
        if is_marker(r.first) then return true end
        local off_r, ind = indent(r)
        local sp = stats[p.g]
        local short = p.x1 < sp.short_at and ends_sentence(p.last)
        if p.g == r.g then
            local d = r.yc - p.yc
            if d < 0.5 * math.min(r.h, p.h) then return false end -- same row
            if d > O.pitch * ref then return true end
            if ind and off_r > (indent(p)) + 0.5 * r.h then return true end
            return short
        end
        -- left -> right column (or the next band): no pitch rule
        return ind or short
    end

    local cur
    for k, r in ipairs(ordered) do
        if not cur or is_break(ordered[k - 1], r) then
            cur = { first = k, last = k, lines = {} }
            paras[#paras + 1] = cur
        end
        cur.last = k
        cur.lines[#cur.lines + 1] = r.i
        info.order[k] = r.i
        info.pos[r.i] = k
        info.para_of[r.i] = #paras
        info.col_of[r.i] = r.g
    end
    return paras, info
end

return M
