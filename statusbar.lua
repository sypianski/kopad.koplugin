--[[
statusbar.lua -- where the selector's status bar goes so that it never
covers the book text (the user's rule; exception: a PDF page is an image, but
after TASK-30 its word boxes are in screen coordinates too, so the same
measure works there).

Pure Lua, no KOReader dependency (tests/statusbar_test.lua). selector.lua
measures the text (M.extent over its word boxes) and draws what M.layout says.

Rules (chosen in the /ux selector, 2026-11-03):
  1. The compact bar (text + rule, M.full_height) goes ABOVE the first line of
     text if the free strip there is tall enough, else BELOW the last line
     (down to the footer, or the screen edge without one).
  2. If neither strip holds it, a shortened bar (mode + two buttons, no rule,
     M.short_height) goes into the larger strip, if that is at least one text
     line tall.
  3. Otherwise nothing is drawn: the mode is readable from the selection.
Never drawn over text; "no text boxes" (nothing to measure) = nothing.

API:
  M.PAD_TOP, M.PAD_GAP, M.RULE, M.PAD_SHORT   pixel constants of the layout
  M.full_height(text_h) / M.short_height(text_h)
  M.extent(words, screen_h, footer_h) -> { first_y, last_y, limit_y } or nil
  M.layout(ext, text_h) -> { kind = "top"|"bottom"|"none", y, h, short, rule }
]]

local M = {}

M.PAD_TOP   = 5    -- above the text of the full bar
M.PAD_GAP   = 3    -- text to rule
M.RULE      = 2    -- rule thickness
M.PAD_SHORT = 2    -- extra pixels around the text of the short bar

function M.full_height(text_h)  return M.PAD_TOP + text_h + M.PAD_GAP + M.RULE end
function M.short_height(text_h) return text_h + M.PAD_SHORT end

-- The vertical extent of the page text, in screen pixels. `words` = items
-- with an `sbox` ({y, h}, as paginmapo / the PDF adapter give them);
-- `limit_y` is where the free strip below the text ends (top of the footer,
-- else the screen height). nil when no word has a box.
function M.extent(words, screen_h, footer_h)
    local first, last
    for _, w in ipairs(words or {}) do
        local b = type(w) == "table" and w.sbox
        if type(b) == "table" and b.y and b.h then
            local top, bottom = b.y, b.y + b.h
            if not first or top < first then first = top end
            if not last or bottom > last then last = bottom end
        end
    end
    if not first then return nil end
    return {
        first_y = math.max(0, first),
        last_y  = math.min(screen_h, last),
        limit_y = screen_h - math.max(0, footer_h or 0),
    }
end

function M.layout(ext, text_h)
    if type(ext) ~= "table" then return { kind = "none" } end
    local top_gap = math.max(0, ext.first_y)
    local bottom_gap = math.max(0, ext.limit_y - ext.last_y)
    local full = M.full_height(text_h)

    if top_gap >= full then
        return { kind = "top", y = 0, h = full, short = false, rule = true }
    end
    if bottom_gap >= full then
        return { kind = "bottom", y = ext.limit_y - full, h = full, short = false, rule = true }
    end
    local at_bottom = bottom_gap > top_gap
    local gap = at_bottom and bottom_gap or top_gap
    if gap < text_h then return { kind = "none" } end
    local h = math.min(M.short_height(text_h), gap)
    return {
        kind = at_bottom and "bottom" or "top",
        y = at_bottom and (ext.limit_y - h) or 0,
        h = h, short = true, rule = false,
    }
end

return M
