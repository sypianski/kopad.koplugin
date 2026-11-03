-- Tests for padopen.lua (open every gamepad, not only the first), with a
-- fake SDL api. Run from the repo root:  lua tests/padopen_test.lua
package.path = "./?.lua;" .. package.path

local M = require("padopen")
local logs = {}
M._log = function(s) logs[#logs + 1] = s end

-- Fake SDL: `ids` = connected joysticks, `pads` = which are gamepads,
-- `open` = SDL's open gamepads (id -> handle), refcounted like SDL.
local ids, pads, open, refs, closed = {}, {}, {}, {}, {}
local fail = {}
local api = {
    list = function() return ids end,
    is_gamepad = function(id) return pads[id] == true end,
    open = function(id)
        if fail[id] then return nil end
        open[id] = open[id] or { id = id }
        refs[id] = (refs[id] or 0) + 1
        return open[id]
    end,
    close = function(h) closed[#closed + 1] = h.id; refs[h.id] = refs[h.id] - 1 end,
    from_id = function(id) return open[id] end,
    name = function(id) return "pad" .. id end,
}

-- 1. KOReader opened the first pad (Steam's virtual one); the 8BitDo was not
ids, pads = { 5, 9, 12 }, { [5] = true, [9] = true }
api.open(5) -- koreader-base's own open
assert(M.scan(api) == 2 and M.handles[5] and M.handles[9], "both gamepads opened")
assert(refs[5] == 2 and refs[9] == 1 and not M.handles[12], "refcounted; non-gamepad 12 skipped")
assert(M.scan(api) == 0, "second pass: nothing new")

-- 2. the 8BitDo is unplugged: closed (still open in SDL), forgotten
ids = { 5, 12 }
M.scan(api)
assert(closed[1] == 9 and refs[9] == 0 and M.handles[9] == nil, "gone pad closed")

-- 3. the gamepad subsystem restarted (fork): old handles freed by SDL, new ids
open, closed = {}, {}
ids, pads = { 20, 21 }, { [20] = true, [21] = true }
M.scan(api)
assert(#closed == 0, "stale handle dropped, never closed")
assert(M.handles[5] == nil and M.handles[20] and M.handles[21], "new ids opened")

-- 4. an open that fails is logged once and not retried while the pad stays
fail[30] = true
ids, pads[30] = { 20, 21, 30 }, true
local n = #logs
M.scan(api); M.scan(api)
assert(#logs == n + 1 and logs[#logs]:find("could not open", 1, true), "failure logged once")
ids = { 20, 21 }
M.scan(api)
assert(M.failed[30] == nil, "forgotten when gone (retried on the next connect)")

-- 5. start() off SDL: no poll
package.preload["vkb"] = function() return { is_sdl = function() return false end } end
assert(M.start(function() return true end) == false and not M._started, "non-SDL: not started")

print("padopen_test: all tests passed")
