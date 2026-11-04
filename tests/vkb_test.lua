-- Tests for vkb.lua (InputDialog.init wrapper), KOReader stubbed.
-- Run from the repo root:  lua tests/vkb_test.lua
package.path = "./?.lua;" .. package.path

local inits = {}
local ID = { keyboard_visible = true }
function ID.init(self, reinit)
    inits[#inits + 1] = { kv = self.keyboard_visible, skip = self.skip_first_show_keyboard, reinit = reinit }
end
package.preload["ui/widget/inputdialog"] = function() return ID end

local V = require("vkb")
local enabled, pad = true, true
V.pad_connected = function() return pad end

assert(V.install(function() return enabled end) == true)
assert(ID._kopad_stock_init ~= nil and ID.init ~= ID._kopad_stock_init, "init wrapped")

local function new_dlg(o) return setmetatable(o or {}, { __index = ID }) end

-- 1. kopad on + pad: the keyboard starts hidden, the caller's first show is skipped
local d = new_dlg()
d:init()
assert(inits[1].kv == false and inits[1].skip == true, "hidden with a pad")

-- 2. reinit (keyboard toggled by the user): untouched
d.keyboard_visible = true; d.skip_first_show_keyboard = nil
d:init(true)
assert(inits[2].kv == true and inits[2].skip == nil and inits[2].reinit == true, "reinit untouched")

-- 3. no pad / kopad off / read-only: stock
pad = false
new_dlg():init()
assert(inits[3].kv == true and inits[3].skip == nil, "no pad: stock")
pad, enabled = true, false
new_dlg():init()
assert(inits[4].kv == true, "kopad off: stock")
enabled = true
new_dlg({ readonly = true }):init()
assert(inits[5].kv == true, "read-only: stock")

-- 4. a second install only replaces the state function, never wraps twice
local wrapped = ID.init
assert(V.install(function() return false end) == true and ID.init == wrapped, "installed once")
new_dlg():init()
assert(inits[6].kv == true, "new state function used")

-- 5. the focus coming back to the field (D-pad) does not open the keyboard
V.install(function() return enabled end)
local shown = 0
local IT = {}
function IT.onFocus(self)
    shown = shown + 1 -- stock: onShowKeyboard + focus
    self.focused = true
    return true
end
function IT.focus(self) self.focused = true end
function IT.isKeyboardVisible(self) return self.kb == true end
package.preload["ui/widget/inputtext"] = function() return IT end
local stock_focus = IT.onFocus
assert(V.wrap_focus() == true and IT.onFocus ~= stock_focus, "onFocus wrapped")
local function new_input(o) return setmetatable(o, { __index = IT }) end
local box = new_input({ parent = new_dlg() })
assert(box:onFocus() == true and box.focused == true and shown == 0, "focus without keyboard")
box.kb = true
box:onFocus()
assert(shown == 1, "keyboard already up (tap / toggle): stock")
pad = false
new_input({ parent = new_dlg() }):onFocus()
assert(shown == 2, "no pad: stock")
pad = true
-- MultiInputDialog: onSwitchFocus runs, its onShowKeyboard is skipped once
local switched
local multi = new_dlg({ onSwitchFocus = function(self, ib)
    switched = { skip = self.skip_first_show_keyboard, ib = ib }
end })
local field2 = new_input({ parent = multi })
field2:onFocus()
assert(switched and switched.skip == true and switched.ib == field2, "switch with the skip flag")
assert(multi.skip_first_show_keyboard == nil and shown == 2, "flag cleared, no keyboard")
-- initInputEvents() redefines onFocus: the next dialog init wraps it again
IT.onFocus = stock_focus
new_dlg():init()
assert(IT.onFocus ~= stock_focus, "re-wrapped on init")
new_input({ parent = new_dlg() }):onFocus()
assert(shown == 2, "still quiet after re-wrap")

-- 6. Steam's keyboard (SDL_StartTextInput on a Deck): the screen-keyboard hint
-- is "0" in pad mode, reset otherwise; text input itself still starts
do
    local hints, started = {}, 0
    package.preload["ffi/SDL3"] = function()
        return { SDL = {
            SDL_SetHint = function(k, v) hints[#hints + 1] = k .. "=" .. v end,
            SDL_ResetHint = function(k) hints[#hints + 1] = k .. "=reset" end,
        } }
    end
    package.loaded["ffi/SDL3"] = nil
    local Dev = { isSDL = function() return true end }
    Dev.startTextInput = function() started = started + 1 end
    package.loaded["device"] = Dev
    V._sti_wrapped = nil
    assert(V.wrap_text_input() == true, "startTextInput wrapped")
    enabled, pad = true, true
    Dev:startTextInput()
    assert(started == 1 and hints[1] == "SDL_ENABLE_SCREEN_KEYBOARD=0", "pad mode: hint 0")
    pad = false
    Dev:startTextInput()
    assert(started == 2 and hints[2] == "SDL_ENABLE_SCREEN_KEYBOARD=reset", "no pad: hint reset")
    pad, enabled = true, false
    Dev:startTextInput()
    assert(hints[3] == "SDL_ENABLE_SCREEN_KEYBOARD=reset", "kopad off: hint reset")
    enabled = true
    local wrapped = Dev.startTextInput
    assert(V.wrap_text_input() == true and Dev.startTextInput == wrapped, "wrapped once")
    package.loaded["device"], package.loaded["ffi/SDL3"], package.preload["ffi/SDL3"] = nil, nil, nil
end

-- 8. a Back key (Steam's keyboard hiding = Escape) does not close a dialog
-- whose B kopad handles; the pad path only (Gamepad* events), pad mode only
do
    local closed, typed = 0, {}
    function ID.onCloseDialog() closed = closed + 1; return true end
    function IT.onKeyPress(self, key)
        typed[#typed + 1] = key
        if key["Back"] and not key["Shift"] then return self.parent:onCloseDialog() end
        return true
    end
    package.loaded["device/sdl/gamepad"] = {}
    assert(V.wrap_back() == true, "Back wrapped")
    local BACK, SHIFT_BACK = { Back = true }, { Back = true, Shift = true }
    local dlg = new_dlg({ _kopad_confirm = { A = true, B = true } })
    local field = new_input({ parent = dlg, focused = true })
    assert(field:onKeyPress(BACK) == true and closed == 0 and #typed == 0, "field: Back swallowed")
    field:onKeyPress(SHIFT_BACK)
    assert(#typed == 1, "field: Shift + Back stock")
    assert(dlg:onCloseDialog(nil, BACK) == true and closed == 0, "dialog key event: swallowed")
    dlg:onCloseDialog()
    assert(closed == 1, "tap outside / direct call: closes")
    pad = false
    dlg:onCloseDialog(nil, BACK)
    assert(closed == 2, "no pad: Back closes")
    pad = true
    new_dlg({ _kopad_confirm = { A = true } }):onCloseDialog(nil, BACK)
    assert(closed == 3, "no B label: Back closes")
    package.loaded["device/sdl/gamepad"] = nil
    package.preload["device/sdl/gamepad"] = function() error("old build") end
    dlg:onCloseDialog(nil, BACK)
    assert(closed == 4, "legacy key path (pad B = Back): closes")
    package.preload["device/sdl/gamepad"] = nil
    local w = IT.onKeyPress
    assert(V.wrap_back() == true and IT.onKeyPress == w, "wrapped once")
end

-- 9. toggle_keyboard (Y): shows past the startup skip flag, hides when up
do
    local d9 = new_dlg({ skip_first_show_keyboard = true })
    function d9:isKeyboardVisible() return self.kb == true end
    function d9:onShowKeyboard()
        if self.skip_first_show_keyboard then self.skip_first_show_keyboard = nil; return end
        self.kb = true
    end
    function d9:onCloseKeyboard() self.kb = false end
    assert(V.toggle_keyboard(d9) == true and d9.kb == true, "Y shows the keyboard")
    assert(V.toggle_keyboard(d9) == true and d9.kb == false, "Y hides it")
    assert(V.toggle_keyboard(new_dlg({ readonly = true })) == false, "read-only: nothing")
end

-- 7. pad check on a non-SDL device: false without touching SDL
package.loaded.vkb = nil
package.preload["device"] = function() return { isSDL = function() return false end } end
local V2 = require("vkb")
assert(V2.pad_connected() == false, "non-SDL: no pad")

print("vkb_test: all tests passed")
