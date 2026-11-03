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

-- 6. pad check on a non-SDL device: false without touching SDL
package.loaded.vkb = nil
package.preload["device"] = function() return { isSDL = function() return false end } end
local V2 = require("vkb")
assert(V2.pad_connected() == false, "non-SDL: no pad")

print("vkb_test: all tests passed")
