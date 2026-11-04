--[[
padconfirm.lua — A / B / X / Y on KOReader's confirmation dialogs, with the
pad letter written on the buttons ("Ⓐ Delete", "Ⓑ Cancel").

Stock gives these dialogs no pad meaning of their own: A presses the
FocusManager's focused button, which on a touch device (the Deck) starts at
x = 1, y = 1 without being painted -- in a ConfirmBox that is Cancel, so A
silently cancelled. install(state_fn) wraps the `init` of each class in
SPECS ONCE per KOReader run and, on the first init of a dialog while kopad
is enabled and a pad is connected (vkb.pad_connected), prefixes the texts
named by the spec with the letter. padnav (_confirm_button, context
"window") then calls press(dlg, letter), which finds the Button whose text
carries that prefix and runs its callback -- the same callback a tap runs,
so cancel_callback, "keep_shown_on_apply" and friends behave as stock.

A acts only while nothing in the dialog shows the focus (focus_shown): once
the D-pad lit a button, a picker arrow or a radio item, A presses that, as
stock does. Start = the A button always, focus or not (the way out of a
radio list or a spin widget after moving the focus). B = the B button
always (stock Back closes most of them too, but SpinWidget's Back skips
cancel_callback, and a non-dismissable ConfirmBox has no Back at all).

MultiConfirmBox goes by the CONTENT of its two choices (multi_spec): the
main one (a text from PRIMARY, or the one that is not in SECONDARY) = A,
the other = X; a pair with no main choice (Default / Fallback, http /
https, unknown plugin texts) = X left, Y right, no A.

InputDialog (and its subclasses): the `is_enter_default` button gets "A",
a "Cancel" / "Close" button gets "B". Its buttons table belongs to the
caller (and is sometimes reused), so it is copied before the texts change.
A with the focus on a text field is padnav's _text_field_button; this
module only labels it.

The letters are the circled ones (Ⓐ Ⓑ Ⓧ Ⓨ) when the button font or one of
KOReader's fallback fonts has all four (glyph_check, once per run), else
plain "A · ".

The top half is pure Lua (tests/padconfirm_test.lua); KOReader modules are
required lazily.
]]

local M = {}

-- Class module -> letter -> instance text field, or a function(dlg, tr)
-- returning that map.
local OK_CANCEL = { A = "ok_text", B = "cancel_text" }
M.SPECS = {
    ["ui/widget/confirmbox"] = OK_CANCEL,
    ["ui/widget/multiconfirmbox"] = function(dlg, tr) return M.multi_spec(dlg, tr) end,
    ["ui/widget/spinwidget"] = OK_CANCEL,
    ["ui/widget/doublespinwidget"] = OK_CANCEL,
    ["ui/widget/datetimewidget"] = OK_CANCEL,
    ["ui/widget/radiobuttonwidget"] = OK_CANCEL,
    -- Vortpaf's definition card (vortpaf.koplugin/vortpaf_card.lua); not
    -- loadable = Vortpaf not installed, skipped like any missing class.
    -- Y = Other sense (Vortpaf with TASK-5, shown only when Vortuyo answered; no
    -- such button = Y goes on to stock, see press).
    ["vortpaf_card"] = { A = "keep_text", X = "regenerate_text", B = "discard_text", Y = "sense_text" },
}
M.INPUT_DIALOG = "ui/widget/inputdialog"
M.LETTERS = { "A", "X", "Y", "B" }

-- MultiConfirmBox choices (KOReader msgids, compared translated): the main
-- action of a pair, and the side one. From the stock call sites: Discard /
-- Save, Turn Wi-Fi off / Connect, Open / Another, Yes / No, Choose folder /
-- Download.
M.PRIMARY = { "Save", "Connect", "Open", "Yes", "Download", "OK", "Apply" }
M.SECONDARY = { "Discard", "No", "Turn Wi-Fi off", "Another", "Choose folder" }

M.CIRCLED = { A = "Ⓐ", B = "Ⓑ", X = "Ⓧ", Y = "Ⓨ" }
M.CODEPOINTS = { 0x24B6, 0x24B7, 0x24CD, 0x24CE }
M.circled = nil -- nil = not checked yet (use_circled)

function M.use_circled()
    if M.circled == nil then
        local ok, res = pcall(M.glyph_check)
        M.circled = ok and res == true
    end
    return M.circled
end

function M.prefix(letter)
    if M.use_circled() then return M.CIRCLED[letter] .. " " end
    return letter .. " · "
end

function M.label(letter, text)
    return M.prefix(letter) .. text
end

local function has_label(text, letter)
    local p = M.prefix(letter)
    return type(text) == "string" and text:sub(1, #p) == p
end

-- The letter map of a MultiConfirmBox from its two choice texts.
function M.multi_spec(dlg, tr)
    tr = tr or function(s) return s end
    local function set(list)
        local t = {}
        for _, s in ipairs(list) do t[tr(s)] = true end
        return t
    end
    local primary, secondary = set(M.PRIMARY), set(M.SECONDARY)
    local function kind(i)
        local text = dlg["choice" .. i .. "_text"]
        local fn = dlg["choice" .. i .. "_text_func"]
        if type(fn) == "function" then
            local ok, t = pcall(fn)
            if ok then text = t end
        end
        if primary[text] then return "primary" end
        if secondary[text] then return "secondary" end
        return nil
    end
    local k1, k2 = kind(1), kind(2)
    local main
    if (k1 == "primary") ~= (k2 == "primary") then
        main = k1 == "primary" and 1 or 2
    elseif (k1 == "secondary") ~= (k2 == "secondary") then
        main = k1 == "secondary" and 2 or 1
    end
    if not main then
        return { X = "choice1_text", Y = "choice2_text", B = "cancel_text" }
    end
    return { A = "choice" .. main .. "_text", X = "choice" .. (3 - main) .. "_text", B = "cancel_text" }
end

-- Fields a spec must leave alone: no OK button, a disabled choice keeps its
-- text (its button is greyed out, a letter on it would promise an action).
local function skip(dlg, letter, field)
    if letter == "A" and field == "ok_text" and dlg.no_ok_button then return true end
    if field == "choice1_text" and dlg.choice1_enabled == false then return true end
    if field == "choice2_text" and dlg.choice2_enabled == false then return true end
    return false
end

-- Prefix the spec's texts on the instance (class defaults are read through
-- the metatable, written to the instance). A `<field>_func` (MultiConfirmBox
-- choice*_text_func) is wrapped instead. Once per dialog: a reinit
-- (ConfirmBox shrinking its font, addWidget) must not prefix twice.
function M.apply(dlg, spec)
    if type(dlg) ~= "table" or rawget(dlg, "_kopad_confirm") then return false end
    local keys = {}
    for _, letter in ipairs(M.LETTERS) do
        local field = spec[letter]
        if field and not skip(dlg, letter, field) then
            local fn = dlg[field .. "_func"]
            local text = dlg[field]
            if type(fn) == "function" then
                dlg[field .. "_func"] = function(...) return M.label(letter, tostring(fn(...))) end
                keys[letter] = true
            elseif type(text) == "string" and text ~= "" then
                dlg[field] = M.label(letter, text)
                keys[letter] = true
            end
        end
    end
    dlg._kopad_confirm = keys
    return next(keys) ~= nil
end

-- InputDialog: copy the caller's button rows, then label the default button
-- (A) and the first Cancel / Close (B). `cancel_texts` = the translated
-- texts that count as cancel.
function M.apply_input(dlg, cancel_texts)
    if type(dlg) ~= "table" or rawget(dlg, "_kopad_confirm") then return false end
    local keys = {}
    if type(dlg.buttons) == "table" then
        local rows = {}
        for r, row in ipairs(dlg.buttons) do
            local copy = {}
            for i, b in ipairs(type(row) == "table" and row or {}) do
                local nb = b
                if type(b) == "table" and type(b.text) == "string" then
                    local letter
                    if b.is_enter_default and not keys.A then
                        letter = "A"
                    elseif not keys.B and cancel_texts[b.text] then
                        letter = "B"
                    end
                    if letter then
                        nb = {}
                        for k, v in pairs(b) do nb[k] = v end
                        nb.text = M.label(letter, b.text)
                        keys[letter] = true
                    end
                end
                copy[i] = nb
            end
            rows[r] = copy
        end
        if next(keys) then dlg.buttons = rows end
    end
    dlg._kopad_confirm = keys
    return next(keys) ~= nil
end

-- Depth-first walk over the widget tree (array children only: the named
-- fields like show_parent point back up).
local MAX_DEPTH = 16
local function walk(w, fn, depth)
    if type(w) ~= "table" or depth > MAX_DEPTH then return nil end
    local r = fn(w)
    if r ~= nil then return r end
    for _, child in ipairs(w) do
        r = walk(child, fn, depth + 1)
        if r ~= nil then return r end
    end
    return nil
end

-- The Button carrying `letter`'s label, else nil.
function M.find_button(dlg, letter)
    return walk(dlg, function(w)
        if has_label(rawget(w, "text"), letter) and type(w.callback) == "function" then return w end
        return nil
    end, 0)
end

-- Is anything in the dialog painted as focused? Button / RadioButton /
-- IconButton invert their frame or image on Focus; on a touch device the
-- initial focus is set without that, so "shown" = the user moved it.
local function inverted(f) return type(f) == "table" and f.invert == true end
function M.focus_shown(dlg)
    return walk(dlg, function(w)
        if inverted(rawget(w, "frame")) or inverted(rawget(w, "_frame")) or inverted(rawget(w, "image")) then
            return true
        end
        return nil
    end, 0) or false
end

function M.letters(dlg)
    return type(dlg) == "table" and rawget(dlg, "_kopad_confirm") or nil
end

-- Run the button with `letter`. Returns true when the dialog has that letter
-- (the press is consumed, a disabled button -- SpinWidget's Apply before any
-- change -- does nothing), false otherwise (stock goes on).
function M.press(dlg, letter)
    local keys = M.letters(dlg)
    if not (keys and keys[letter]) then return false end
    local b = M.find_button(dlg, letter)
    if not b then return false end
    if b.enabled == false then return true end
    b.callback()
    return true
end

-- KOReader side -------------------------------------------------------------

-- Do the button font (cfont) or KOReader's fallback fonts have all four
-- circled letters? Same lookup as RenderText:getGlyph.
function M.glyph_check()
    local Font = require("ui/font")
    local face = Font:getFace("cfont")
    for _, cp in ipairs(M.CODEPOINTS) do
        local found = face.ftsize:hasGlyph(cp)
        if not found then
            for _, name in pairs(Font.fallbacks or {}) do
                local fb = Font:getFace(name, face.orig_size)
                if fb and fb.ftsize:hasGlyph(cp) then
                    found = true
                    break
                end
            end
        end
        if not found then return false end
    end
    return true
end

function M.wanted()
    if not (M._state_fn and M._state_fn()) then return false end
    local ok, Vkb = pcall(require, "vkb")
    return ok and type(Vkb) == "table" and Vkb.pad_connected() or false
end

local function wrap(Class, label_fn)
    if type(Class) ~= "table" or type(Class.init) ~= "function" then return false end
    if rawget(Class, "_kopad_confirm_init") then return true end
    local stock_init = Class.init
    Class._kopad_confirm_init = stock_init
    Class.init = function(self, ...)
        if not rawget(self, "_kopad_confirm") then
            local ok, want = pcall(M.wanted)
            if ok and want then
                local ok2, err = pcall(label_fn, self)
                if not ok2 and M._warn then M._warn("kopad: confirm labels failed: " .. tostring(err)) end
            end
        end
        return stock_init(self, ...)
    end
    return true
end

function M.install(state_fn, warn)
    M._state_fn = state_fn
    M._warn = warn
    if M._installed then return true end
    local okg, gettext = pcall(require, "gettext")
    local tr = okg and gettext or function(s) return s end
    local any = false
    for mod, spec in pairs(M.SPECS) do
        local ok, Class = pcall(require, mod)
        if ok and wrap(Class, function(dlg)
            M.apply(dlg, type(spec) == "function" and spec(dlg, tr) or spec)
        end) then any = true end
    end
    local ok, ID = pcall(require, M.INPUT_DIALOG)
    if ok and wrap(ID, function(dlg)
        M.apply_input(dlg, { [tr("Cancel")] = true, [tr("Close")] = true })
    end) then any = true end
    M._installed = any
    return any
end

return M
