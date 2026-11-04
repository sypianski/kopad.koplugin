--[[
vkb.lua — no on-screen keyboard popping up in text-input dialogs while kopad
is enabled and a gamepad is connected.

With a pad the text comes from dictation (RT held, diktonoti) and editing is
X = backspace / A = accept (padnav: _text_field_button), so the virtual
keyboard only covers half of the screen. install(state_fn) wraps
InputDialog.init ONCE per KOReader run (MultiInputDialog calls it too) and,
on a first init (not a reinit) of an editable dialog, does what stock does for
a physical keyboard with "virtual_keyboard_enabled" off: keyboard_visible =
false + skip_first_show_keyboard, so the caller's onShowKeyboard() is
skipped. Y, tapping the field or the dialog's keyboard toggle still opens it.

The second way in is the focus: on a D-pad device InputText:onFocus (sent by
FocusManager whenever the D-pad / L-stick brings the focus back onto the
field, or kopad does before dictating) calls onShowKeyboard() itself, and in
a MultiInputDialog it goes through onSwitchFocus, which does the same. While
the keyboard is hidden, the wrapped onFocus only focuses the field (the
physical-keyboard branch of stock). InputText.initInputEvents() redefines
onFocus, so the wrapper is checked again on every InputDialog init.

The third keyboard is not KOReader's: InputText:focus() calls
Device:startTextInput() = SDL_StartTextInput, and SDL3 on a Steam Deck then
opens STEAM's keyboard (steam://open/keyboard). While it is up Steam switches
the pad to its own "Keyboard" action set (RT = press the key under the right
trackpad, B / hide = Back), so the pad no longer reaches kopad and Back
closes the dialog under it. wrap_text_input sets the SDL hint
SDL_ENABLE_SCREEN_KEYBOARD = "0" before every start while kopad is enabled
and a pad is connected (text input itself stays on: a physical keyboard still
types), and resets it otherwise.

The keyboard stays the user's choice: Y or Start on the pad (padnav:
_text_field_button; system_keyboard = Steam's on a Deck), a tap on the field or Steam's own keyboard (Steam + X)
open one by hand, and dictation keeps working under KOReader's. What must not
happen is that hiding a keyboard closes the dialog: Steam's keyboard hides
with a Back (Escape) key, and stock InputDialog / InputText answer a Back key
with onCloseDialog. wrap_back drops that Back while back_guarded(dlg): the
Gamepad* path (>= 2026.07), pad mode, and a dialog whose B padconfirm
labelled -- kopad's B then presses that button itself, so a Back key there
never comes from the pad. A tap outside and the buttons still close it.

`state_fn` (kopad enabled) is replaced by every kopad instance, like
wheel.install. The pad check asks SDL directly (SDL_GetJoysticks +
SDL_IsGamepad): ffi/SDL3's own `S.controller` keeps a stale handle after the
last pad is unplugged. Non-SDL devices (e-readers) never have a pad here.
]]

local M = {}

local function is_sdl()
    local ok, Device = pcall(require, "device")
    if not ok or type(Device) ~= "table" or type(Device.isSDL) ~= "function" then return false end
    local ok2, res = pcall(Device.isSDL, Device)
    return ok2 and res and true or false
end
M.is_sdl = is_sdl

-- True when SDL reports at least one connected gamepad.
function M.pad_connected()
    if not is_sdl() then return false end
    local ok, res = pcall(function()
        local ffi = require("ffi")
        local SDL = require("ffi/SDL3").SDL
        local n = ffi.new("int[1]")
        local ids = SDL.SDL_GetJoysticks(n)
        if ids == nil then return false end
        local found = false
        for i = 0, n[0] - 1 do
            if SDL.SDL_IsGamepad(ids[i]) then
                found = true
                break
            end
        end
        SDL.SDL_free(ids)
        return found
    end)
    return ok and res or false
end

function M.should_hide(dlg)
    if type(dlg) ~= "table" or dlg.readonly then return false end
    return M.pad_mode()
end

-- A focus coming to `input` (InputText) should not open the keyboard: the
-- dialog qualifies and the keyboard is not up already (opened by a tap or
-- the toggle: then stock keeps it, also when the focus moves between fields).
function M.quiet_focus(input)
    if type(input) ~= "table" or input.readonly then return false end
    if type(input.isKeyboardVisible) == "function" and input:isKeyboardVisible() then return false end
    return M.should_hide(input.parent)
end

local function focus_wrapper(self, ...)
    local ok, quiet = pcall(M.quiet_focus, self)
    if not (ok and quiet) then return M._stock_focus(self, ...) end
    local parent = self.parent
    if type(parent) == "table" and type(parent.onSwitchFocus) == "function" then
        -- MultiInputDialog: switch the field, its closing onShowKeyboard is
        -- eaten by the startup skip flag, cleared again right after.
        parent.skip_first_show_keyboard = true
        local ok2, err = pcall(parent.onSwitchFocus, parent, self)
        parent.skip_first_show_keyboard = nil
        if not ok2 then error(err) end
    else
        self:focus()
    end
    return true
end

-- (Re)wrap InputText.onFocus; it exists only on D-pad / touch devices.
function M.wrap_focus()
    local ok, IT = pcall(require, "ui/widget/inputtext")
    if not ok or type(IT) ~= "table" then return false end
    local cur = rawget(IT, "onFocus")
    if cur == focus_wrapper then return true end
    if type(cur) ~= "function" then return false end
    M._stock_focus = cur
    IT.onFocus = focus_wrapper
    return true
end

-- kopad enabled and a pad connected: no screen keyboard of any kind pops up
-- by itself.
function M.pad_mode()
    return M._state_fn ~= nil and M._state_fn() and M.pad_connected() or false
end

local SCREEN_KB_HINT = "SDL_ENABLE_SCREEN_KEYBOARD"

-- Set (off = true: "0") or reset SDL's screen-keyboard hint. SDL_ResetHint is
-- missing from koreader-base's SDL3_h, so it is declared here (once, guarded).
function M.screen_kb_hint(off)
    local ok, err = pcall(function()
        local SDL = require("ffi/SDL3").SDL
        if off then
            SDL.SDL_SetHint(SCREEN_KB_HINT, "0")
            return
        end
        if not M._reset_cdef then
            pcall(function() require("ffi").cdef("bool SDL_ResetHint(const char *name);") end)
            M._reset_cdef = true
        end
        SDL.SDL_ResetHint(SCREEN_KB_HINT)
    end)
    return ok, err
end

-- Wrap Device.startTextInput once (SDL only): the hint follows pad_mode() at
-- the moment SDL decides whether to show the keyboard.
function M.wrap_text_input()
    if M._sti_wrapped then return true end
    if not is_sdl() then return false end
    local ok, Device = pcall(require, "device")
    if not ok or type(Device) ~= "table" or type(Device.startTextInput) ~= "function" then return false end
    local stock = Device.startTextInput
    Device.startTextInput = function(...)
        local okm, off = pcall(M.pad_mode)
        M.screen_kb_hint(okm and off)
        return stock(...)
    end
    M._sti_wrapped = true
    return true
end

-- KOReader >= 2026.07: pad buttons come as Gamepad* events (older patched
-- builds turn the pad's B into a Back key, which must keep closing).
function M.gamepad_events()
    local ok, G = pcall(require, "device/sdl/gamepad")
    return ok and type(G) == "table"
end

-- A Back key in `dlg` comes from a keyboard, not from the pad (see the header).
function M.back_guarded(dlg)
    if type(dlg) ~= "table" then return false end
    local keys = rawget(dlg, "_kopad_confirm")
    if not (type(keys) == "table" and keys.B) then return false end
    return M.gamepad_events() and M.pad_mode()
end

local function plain_back(key)
    return type(key) == "table" and key["Back"]
        and not (key["Ctrl"] or key["Shift"] or key["Alt"] or key["ScreenKB"]) and true or false
end

-- Wrap once: InputText.onKeyPress (a focused field closes its dialog on Back)
-- and InputDialog.onCloseDialog, which the key event reaches with the key as
-- its second argument (a tap outside calls it with none).
function M.wrap_back()
    if M._back_wrapped then return true end
    local ok, IT = pcall(require, "ui/widget/inputtext")
    local ok2, ID = pcall(require, "ui/widget/inputdialog")
    if not (ok and type(IT) == "table" and type(IT.onKeyPress) == "function"
            and ok2 and type(ID) == "table" and type(ID.onCloseDialog) == "function") then
        return false
    end
    local stock_key, stock_close = IT.onKeyPress, ID.onCloseDialog
    IT.onKeyPress = function(self, key, ...)
        if self.focused and plain_back(key) then
            local okg, guarded = pcall(M.back_guarded, self.parent)
            if okg and guarded then return true end
        end
        return stock_key(self, key, ...)
    end
    ID.onCloseDialog = function(self, args, key, ...)
        if key ~= nil then
            local okg, guarded = pcall(M.back_guarded, self)
            if okg and guarded then return true end
        end
        return stock_close(self, args, key, ...)
    end
    M._back_wrapped = true
    return true
end

-- Open the system's screen keyboard (Steam's on a Deck) the way SDL does it
-- for a focused field: SDL_StartTextInput with the hint on, then the hint
-- back to "0" so later focus changes do not open it. A stop first, because
-- SDL does not show a keyboard it believes is up (Steam's own hide button
-- does not tell SDL). False when SDL has no screen keyboard (a desktop).
function M.system_keyboard()
    if not is_sdl() then return false end
    local ok, res = pcall(function()
        local S = require("ffi/SDL3")
        local SDL = S.SDL
        if not M._has_skb_cdef then
            pcall(function() require("ffi").cdef("bool SDL_HasScreenKeyboardSupport(void);") end)
            M._has_skb_cdef = true
        end
        if not SDL.SDL_HasScreenKeyboardSupport() then return false end
        SDL.SDL_StopTextInput(S.screen)
        SDL.SDL_SetHint(SCREEN_KB_HINT, "1")
        SDL.SDL_StartTextInput(S.screen)
        SDL.SDL_SetHint(SCREEN_KB_HINT, "0")
        return true
    end)
    return ok and res == true
end

-- Y / Start on the pad: the system's screen keyboard (Steam's on a Deck),
-- else KOReader's for `dlg`; KOReader's, when up (a tap opened it), is hidden.
-- The startup skip flag (should_hide) would eat the first show, so it goes.
function M.toggle_keyboard(dlg)
    if type(dlg) ~= "table" or dlg.readonly then return false end
    if type(dlg.isKeyboardVisible) == "function" and dlg:isKeyboardVisible() then
        dlg:onCloseKeyboard()
        return true
    end
    if M.system_keyboard() then return true end
    if type(dlg.onShowKeyboard) ~= "function" then return false end
    dlg.skip_first_show_keyboard = nil
    dlg:onShowKeyboard()
    return true
end

function M.install(state_fn)
    M._state_fn = state_fn
    pcall(M.wrap_text_input)
    pcall(M.wrap_back)
    if M._installed then return true end
    local ok, ID = pcall(require, "ui/widget/inputdialog")
    if not ok or type(ID) ~= "table" or type(ID.init) ~= "function" then return false end
    local stock_init = rawget(ID, "_kopad_stock_init") or ID.init
    ID._kopad_stock_init = stock_init
    ID.init = function(self, reinit, ...)
        if not reinit then
            local ok2, hide = pcall(M.should_hide, self)
            if ok2 and hide then
                self.keyboard_visible = false
                self.skip_first_show_keyboard = true
            end
        end
        pcall(M.wrap_focus)
        return stock_init(self, reinit, ...)
    end
    pcall(M.wrap_focus)
    M._installed = true
    return true
end

return M
