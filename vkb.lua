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
skipped. Tapping the field or the dialog's keyboard toggle still opens it.

The second way in is the focus: on a D-pad device InputText:onFocus (sent by
FocusManager whenever the D-pad / L-stick brings the focus back onto the
field, or kopad does before dictating) calls onShowKeyboard() itself, and in
a MultiInputDialog it goes through onSwitchFocus, which does the same. While
the keyboard is hidden, the wrapped onFocus only focuses the field (the
physical-keyboard branch of stock). InputText.initInputEvents() redefines
onFocus, so the wrapper is checked again on every InputDialog init.

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
    return M._state_fn ~= nil and M._state_fn() and M.pad_connected() or false
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

function M.install(state_fn)
    M._state_fn = state_fn
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
