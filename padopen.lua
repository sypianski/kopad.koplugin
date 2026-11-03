--[[
padopen.lua — every connected gamepad sends events, not only the first.

koreader-base (ffi/SDL3.lua, openGameController) opens ONE gamepad: the
first SDL_GetJoysticks entry that SDL_IsGamepad accepts, and SDL delivers
gamepad events only for opened gamepads, so a second pad is dead. On the
Deck started from Steam this is the usual case: Steam turns the built-in
controller into its virtual pad (slot 0) and hides the physical one
(SDL_GAMECONTROLLER_IGNORE_DEVICES), but a Bluetooth pad that Steam Input
does not manage (8BitDo Ultimate 2C, 2dc8:301b) stays visible as a second
gamepad that KOReader never opens.

start(state_fn, log) polls every POLL_S (SDL devices only; KOReader passes
nothing on SDL_EVENT_GAMEPAD_ADDED up to Lua) while state_fn() (kopad
enabled) and opens every gamepad not opened yet. SDL refcounts opens, so
opening the one KOReader already holds is harmless. Handles are kept by
joystick id WITHOUT ffi.gc: before a fork KOReader quits the gamepad
subsystem, which closes every gamepad, and a finalizer would then close a
freed handle. A handle is closed only when its pad is gone and
SDL_GetGamepadFromID still returns it (the subsystem was not restarted in
between); otherwise it is just dropped. Joystick ids are never reused, so a
restarted subsystem shows new ids and they get opened again.

scan(api) is pure (tests/padopen_test.lua drives it with a fake api).
]]

local M = {}

M.POLL_S = 3
M.handles = {} -- joystick id -> SDL_Gamepad* opened here
M.failed = {}  -- joystick id -> true: open failed, not retried (no log spam)

local function log(fmt, ...)
    if M._log then pcall(M._log, string.format(fmt, ...)) end
end

-- One pass: open the new gamepads, forget the gone ones. Returns the number
-- opened in this pass.
function M.scan(api)
    local ids = api.list()
    if not ids then return 0 end
    local present, opened = {}, 0
    for _, id in ipairs(ids) do
        present[id] = true
        if not M.handles[id] and not M.failed[id] and api.is_gamepad(id) then
            local h = api.open(id)
            if h then
                M.handles[id] = h
                opened = opened + 1
                log("padopen: opened gamepad %s: %s", tostring(id), tostring(api.name(id)))
            else
                M.failed[id] = true
                log("padopen: could not open gamepad %s: %s", tostring(id), tostring(api.name(id)))
            end
        end
    end
    for id, h in pairs(M.handles) do
        if not present[id] then
            if api.from_id and api.from_id(id) == h then api.close(h) end
            M.handles[id] = nil
            log("padopen: gamepad %s gone", tostring(id))
        end
    end
    for id in pairs(M.failed) do
        if not present[id] then M.failed[id] = nil end
    end
    return opened
end

-- KOReader side -------------------------------------------------------------

function M.sdl_api()
    local ffi = require("ffi")
    local SDL = require("ffi/SDL3").SDL
    -- not in koreader-base's SDL3_h; a redefinition error just means it is
    pcall(ffi.cdef, "SDL_Gamepad *SDL_GetGamepadFromID(SDL_JoystickID);")
    local has_from_id = pcall(function() return SDL.SDL_GetGamepadFromID end)
    return {
        list = function()
            local n = ffi.new("int[1]")
            local arr = SDL.SDL_GetJoysticks(n)
            if arr == nil then return nil end
            local ids = {}
            for i = 0, n[0] - 1 do ids[#ids + 1] = tonumber(arr[i]) end
            SDL.SDL_free(arr)
            return ids
        end,
        is_gamepad = function(id) return SDL.SDL_IsGamepad(id) end,
        open = function(id)
            local h = SDL.SDL_OpenGamepad(id)
            if h == nil then return nil end
            return h
        end,
        close = function(h) SDL.SDL_CloseGamepad(h) end,
        from_id = has_from_id and function(id) return SDL.SDL_GetGamepadFromID(id) end or nil,
        name = function(id)
            local s = SDL.SDL_GetGamepadNameForID(id)
            return s ~= nil and ffi.string(s) or "?"
        end,
    }
end

-- The poll runs once per KOReader run; every kopad instance replaces the
-- state function and the logger (like wheel.install / vkb.install).
function M.start(state_fn, log_fn)
    M._state_fn = state_fn
    M._log = log_fn
    if M._started then return true end
    local okv, Vkb = pcall(require, "vkb")
    if not (okv and type(Vkb) == "table" and Vkb.is_sdl()) then return false end
    local ok, api = pcall(M.sdl_api)
    if not ok then
        log("padopen: no SDL api: %s", tostring(api))
        return false
    end
    local UIManager = require("ui/uimanager")
    local function tick()
        if M._state_fn and M._state_fn() then
            local ok2, err = pcall(M.scan, api)
            if not ok2 then log("padopen: scan failed: %s", tostring(err)) end
        end
        UIManager:scheduleIn(M.POLL_S, tick)
    end
    M._started = true
    tick()
    return true
end

return M
