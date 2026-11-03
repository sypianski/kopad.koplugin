-- Tests for padconfirm.lua (labels + presses on confirmation dialogs),
-- KOReader stubbed. Run from the repo root:  lua tests/padconfirm_test.lua
package.path = "./?.lua;" .. package.path

-- Classes as KOReader declares them: defaults on the class, read through
-- the metatable. init records the texts it sees and builds a button tree
-- (CenterContainer -> ButtonTable -> HorizontalGroup -> Button).
local log = {}
local function button(text, fn, enabled)
    return { text = text, callback = fn, enabled = enabled, frame = { invert = false } }
end
local function class(defaults, build)
    local C = defaults
    function C.init(self)
        self.seen = {}
        for k in pairs(defaults) do
            if type(k) == "string" and k:match("_text$") then self.seen[k] = self[k] end
        end
        self[1] = { { build(self) } }
    end
    return C
end
local ConfirmBox = class({ ok_text = "OK", cancel_text = "Cancel" }, function(self)
    local row = { button(self.cancel_text, function() log[#log + 1] = "cancel" end) }
    if not self.no_ok_button then row[2] = button(self.ok_text, function() log[#log + 1] = "ok" end) end
    return row
end)
local MultiConfirmBox = class({ choice1_text = "Choice 1", choice2_text = "Choice 2", cancel_text = "Cancel" }, function(self)
    local c1 = self.choice1_text_func and self.choice1_text_func() or self.choice1_text
    return { button(self.cancel_text, function() log[#log + 1] = "cancel" end),
             button(c1, function() log[#log + 1] = "c1" end),
             button(self.choice2_text, function() log[#log + 1] = "c2" end, self.choice2_enabled) }
end)
local SpinWidget = class({ ok_text = "Apply", cancel_text = "Close" }, function(self)
    return { button(self.cancel_text, function() log[#log + 1] = "close" end),
             button(self.ok_text, function() log[#log + 1] = "apply" end, self.changed or false) }
end)
local InputDialog = { init = function(self) self[1] = { { self.buttons[1][1] and {} or nil } } end }
local VortpafCard = class({ keep_text = "Keep", regenerate_text = "Regenerate", discard_text = "Discard" }, function(self)
    local ready = not self.loading
    return { button(self.discard_text, function() log[#log + 1] = "discard" end, ready),
             button(self.regenerate_text, function() log[#log + 1] = "regenerate" end, ready),
             button(self.keep_text, function() log[#log + 1] = "keep" end, ready) }
end)

local mods = {
    ["ui/widget/confirmbox"] = ConfirmBox,
    ["ui/widget/multiconfirmbox"] = MultiConfirmBox,
    ["ui/widget/spinwidget"] = SpinWidget,
    ["ui/widget/inputdialog"] = InputDialog,
    ["vortpaf_card"] = VortpafCard,
    ["gettext"] = function(s) return s end,
}
for name, m in pairs(mods) do package.preload[name] = function() return m end end
local pad = true
package.preload["vkb"] = function() return { pad_connected = function() return pad end } end

local C = require("padconfirm")
local enabled = true
assert(C.install(function() return enabled end) == true)
assert(rawget(ConfirmBox, "_kopad_confirm_init") ~= nil, "ConfirmBox.init wrapped")

local function new(Class, o)
    local d = setmetatable(o or {}, { __index = Class })
    d:init()
    return d
end

-- 1. ConfirmBox: A on OK, B on Cancel; the class defaults stay untouched
local d = new(ConfirmBox, { ok_text = "Delete" })
assert(d.seen.ok_text == "A · Delete" and d.seen.cancel_text == "B · Cancel", "labels: " .. tostring(d.seen.ok_text))
assert(ConfirmBox.ok_text == "OK" and ConfirmBox.cancel_text == "Cancel", "class defaults untouched")
assert(C.press(d, "A") == true and log[1] == "ok", "A = OK")
assert(C.press(d, "B") == true and log[2] == "cancel", "B = Cancel")
assert(C.press(d, "X") == false and #log == 2, "X: no letter -> stock")
-- a reinit (font shrink, addWidget) keeps a single prefix
d:init()
assert(d.seen.ok_text == "A · Delete", "reinit: no double prefix")

-- 2. no OK button: only B
d = new(ConfirmBox, { no_ok_button = true })
assert(d.seen.ok_text == "OK" and C.letters(d).A == nil and C.press(d, "A") == false, "no_ok_button: A stock")

-- 3. focus shown: anything inverted
d = new(ConfirmBox)
assert(C.focus_shown(d) == false, "initial focus is not painted")
d[1][1][1][1].frame.invert = true
assert(C.focus_shown(d) == true, "D-pad lit a button")

-- 4. MultiConfirmBox by content: the main choice = A, the other = X;
-- text_func read and wrapped; a pair without a main choice = X / Y, no A;
-- a disabled choice is not labelled
log = {}
d = new(MultiConfirmBox, { choice1_text_func = function() return "Discard" end, choice2_text = "Save" })
assert(d[1][1][1][2].text == "X · Discard" and d.seen.choice2_text == "A · Save", "Discard / Save")
assert(C.press(d, "X") and C.press(d, "A") and C.press(d, "B"), "multi presses")
assert(table.concat(log, ",") == "c1,c2,cancel", table.concat(log, ","))
d = new(MultiConfirmBox, { choice1_text = "Yes", choice2_text = "No" })
assert(d.seen.choice1_text == "A · Yes" and d.seen.choice2_text == "X · No", "Yes / No: the main one is left")
d = new(MultiConfirmBox, { choice1_text = "Turn Wi-Fi off", choice2_text = "Connect" })
assert(d.seen.choice2_text == "A · Connect" and d.seen.choice1_text == "X · Turn Wi-Fi off", "Wi-Fi")
d = new(MultiConfirmBox, { choice1_text = "Another", choice2_text = "Repeat" })
assert(d.seen.choice2_text == "A · Repeat", "only a side choice known: the other is main")
log = {}
d = new(MultiConfirmBox, { choice1_text = "Default", choice2_text = "Fallback" })
assert(d.seen.choice1_text == "X · Default" and d.seen.choice2_text == "Y · Fallback", "neutral: X / Y")
assert(C.letters(d).A == nil and C.press(d, "A") == false, "neutral: no A")
assert(C.press(d, "Y") == true and log[1] == "c2", "Y = right choice")
d = new(MultiConfirmBox, { choice1_text = "Discard", choice2_text = "Save", choice2_enabled = false })
assert(d.seen.choice2_text == "Save" and C.letters(d).A == nil and d.seen.choice1_text == "X · Discard",
    "disabled main choice: no letter")

-- 5. SpinWidget: Apply disabled before a change = consumed, nothing runs
log = {}
d = new(SpinWidget)
assert(C.press(d, "A") == true and #log == 0, "disabled Apply: consumed, no action")
d = new(SpinWidget, { changed = true })
assert(C.press(d, "A") == true and log[1] == "apply", "Apply")

-- 5b. Vortpaf's definition card: A = Keep, X = Regenerate, B = Discard; while
-- the answer is loading the buttons are disabled = consumed, nothing runs
log = {}
d = new(VortpafCard)
assert(d.seen.keep_text == "A · Keep" and d.seen.regenerate_text == "X · Regenerate"
    and d.seen.discard_text == "B · Discard", "vortpaf card labels")
assert(C.press(d, "X") and C.press(d, "A") and C.press(d, "B"), "vortpaf card presses")
assert(table.concat(log, ",") == "regenerate,keep,discard", table.concat(log, ","))
assert(C.press(d, "Y") == false, "vortpaf card: no Y")
log = {}
d = new(VortpafCard, { loading = true })
assert(C.press(d, "A") == true and #log == 0, "vortpaf card loading: consumed, no action")

-- 6. kopad off / no pad: no labels, presses stock
enabled = false
d = new(ConfirmBox)
assert(d.seen.ok_text == "OK" and C.letters(d) == nil and C.press(d, "A") == false, "kopad off: stock")
enabled, pad = true, false
d = new(ConfirmBox)
assert(d.seen.ok_text == "OK", "no pad: stock")
pad = true

-- 7. InputDialog: the caller's rows are copied, default = A, Cancel = B
local rows = { {
    { text = "Cancel", callback = function() end },
    { text = "Find", is_enter_default = true, callback = function() end },
} }
d = setmetatable({ buttons = rows }, { __index = InputDialog })
d:init()
assert(d.buttons ~= rows and d.buttons[1][1].text == "B · Cancel" and d.buttons[1][2].text == "A · Find", "input labels")
assert(rows[1][1].text == "Cancel" and rows[1][2].text == "Find", "caller's table untouched")
assert(d.buttons[1][2].is_enter_default == true, "fields kept")
-- no default, no cancel: nothing labelled, the table is not replaced
local plain = { { { text = "Open", callback = function() end } } }
d = setmetatable({ buttons = plain }, { __index = InputDialog })
d:init()
assert(d.buttons == plain and C.letters(d).A == nil, "nothing to label")

-- 8. circled letters when the fonts have them; the check fell back to plain
-- above (no ui/font in plain Lua)
assert(C.circled == false, "no fonts: plain letters")
C.circled = true
log = {}
d = new(ConfirmBox, { ok_text = "Delete" })
assert(d.seen.ok_text == "Ⓐ Delete" and d.seen.cancel_text == "Ⓑ Cancel", d.seen.ok_text)
assert(C.press(d, "A") == true and log[1] == "ok", "A with circled labels")
d = new(MultiConfirmBox, { choice1_text = "Default", choice2_text = "Fallback" })
assert(d.seen.choice1_text == "Ⓧ Default" and d.seen.choice2_text == "Ⓨ Fallback", "circled X / Y")
C.circled = false

-- 9. a second install only replaces the state function
local wrapped = ConfirmBox.init
assert(C.install(function() return false end) == true and ConfirmBox.init == wrapped, "installed once")
assert(new(ConfirmBox).seen.ok_text == "OK", "new state function used")

print("padconfirm_test: all tests passed")
