--[[
PadNav — gamepad reading controls for KOReader (active when kopad is enabled).
The on<Key> handlers below are the source of truth; keep this block, the
header of main.lua, README.md and CHEAT_READING/CHEAT_SELECTION in sync with them.

Reading:
  RT / LT (triggers)     Next / previous page (always, also with overlay open)
  RB / LB                Next / previous page (X+RB = bookmarks, X+LB = TOC)
  L4 / R4 (back paddles) Same as LB / RB -- ONLY on old builds with
                         sdl3_gamepad.patch (key_events ScrollLock/Pause).
                         Not handled on KOReader >= 2026.07: SDL paddle ids
                         16+ have no stock mapping (Steam Input usually does
                         not expose them), so nothing arrives.
  Select                 Top menu          Start   Footer (bottom) menu
  D-pad                  Open word walk
  L-stick ↑/←            Page turn (↑/← = next page, legacy)
  L-stick ↓              Open crosshair   L-stick → Open word walk
  R-stick                Open crosshair (immediate)
  A                      Open sentence selector
  Y                      Open highlight mode (crosshair if none)
  X                      Modifier: X + D-pad = ↑menu ↓footer ←history →files

Top menu open (TouchMenu on top of the window stack, reader AND FileManager;
Gamepad* path = KOReader >= 2026.07 only):
  RB / LB                Next / previous CATEGORY (tab with icon), wrapping at
                         the ends. Consumed here, so the stock RPgFwd/RPgBack
                         key (= menu page turn) is NOT sent. Tabs that are
                         actions, not categories (remember == false or a tab
                         callback, e.g. the reader's "file browser" tab that
                         closes the book) are skipped.
  RT / LT                Next / previous PAGE of the menu (TouchMenu:onNextPage
                         / onPrevPage), one press = one page
  D-pad / A              Unchanged (stock navigation / Press)
  Outside a TouchMenu (other dialogs, plain Menu) LB/RB/LT/RT behave as before.

Selection (struct/walk/cross overlay):
  L-stick ←/→            Sentence move    ↑/↓  Paragraph jump
  D-pad / R-stick        Word navigation (R-stick ↑/↓ cycles highlights in struct)
  Y                      Vortuyo lookup
  X                      Toggle highlight
  A                      Action menu (dict, AI, copy, note)
  B                      Exit extend mode / close overlay
  RB                     Extend selection right (quick extend when active)
  LB                     Extend selection left (quick extend when active)
  RT / LT                Close overlay and turn page
  Select / Start         Close overlay and open top / footer menu

Dictionary popup:
  LB / RB                Cycle dictionaries
  Y                      AI explain

Visel overlay (opt-in via pluginaro: visel.ext.kopad.gamepad_select):
  D-pad / L-stick ←/→   Move visel selection (as keyboard ←/→)
  RB / LB               Extend / trim selection (as Shift+→ / Shift+←)
  B                     Close visel

Scope: the selector (word walk / struct / crosshair) only exists for
crengine (rolling) documents. In paged documents (PDF/DjVu) and in the
FileManager no reader keys are suppressed and the selector-dependent
handlers return false (pass-through) — only LB/RB page turns and X-combos
remain active there. Paged documents get their own view controls instead
(PAGED_DPAD, _paged_idle; Gamepad* path only):
  D-pad ↑ / ↓            Zoom in / out
  D-pad ← / →            Fit whole page / fit text width (margins cropped)
  R-stick                Pan the page
The FileManager keeps the stock list navigation.

Input paths (two, both end in the same on<Key> handlers):

1. KOReader >= 2026.07 (stock, NO patch / userpatch needed):
   frontend/device/sdl/device.lua broadcasts GamepadButtonDown {button} and
   GamepadAxisMotion {axis,value,time}; if a handler returns true the stock
   default key press (gamepad.lua button_key_names / axis_key_names) is NOT
   sent. onGamepadButtonDown / onGamepadAxisMotion below map SDL ids to the
   handlers; false = pass through to the stock default (kopad disabled, a
   modal Menu/dialog on top, or a foreign overlay owning the screen).
   main.lua relays the broadcast here (PadNav lives in ui.active_widgets,
   which UIManager:broadcastEvent does not visit).
     Buttons (SDL ids): A=0 B=1 X=2 Y=3 Select=4 Start=6 LB=9 RB=10;
       D-pad 11..14 is passed through (stock sends Up/Down/Left/Right ->
       KPUp2.. bindings). Guide=5, L3=7, R3=8 are swallowed while kopad is
       active: stock maps them to RPgFwd / Menu / Menu, i.e. accidental page
       turns or menus from a stick click.
     Triggers: axis 4 = LT, axis 5 = RT. Stock has no mapping for them. One
       press = one page (in the top menu: one menu page): the stock
       auto-repeat (first repeat after 0.5 s, then every 0.2 s while held) is
       filtered out, see _trigger_is_new_press.
     Top menu: the LB/RB (button) and LT/RT (axis) branches run BEFORE the
       _is_enabled() guard (a TouchMenu on top is a modal, which silences the
       rest of PadNav); they need kopad enabled, no foreign overlay and a
       TouchMenu on top of the window stack (_top_menu).
     L-stick = axes 0 (x) / 1 (y), R-stick = axes 2 (x) / 3 (y); negative =
       left/up. The stock auto-repeat is kept on the sticks (handy for
       navigation). Stock maps R-stick Y to RPgBack/RPgFwd, which with the
       auto-repeat flips pages endlessly, so while kopad is active axes 2/3
       are always consumed (axis 2 has no stock mapping).

   Remapping (padmap.lua, PC-011): onGamepadButtonDown / onGamepadAxisMotion
     first translate the PHYSICAL control into its logical ROLE (the ids
     above, Xbox labels) via the table main.lua passes to set_padmap(); all
     handlers below this point see roles only. Remappable: buttons 0-4, 6, 9,
     10 and trigger axes 4/5 (a button may become a trigger and vice versa:
     _trigger_event / _trigger_as_button). D-pad, sticks, Guide/L3/R3 and the
     legacy key_events path are never remapped. No table = identity. When an
     event is passed through (false), KOReader sees the physical control.

   Action overrides (padmap.lua `actions`, PC-014): after the role is known,
     _button_down / _trigger_event ask _override_action(role) whether the
     user gave that role another reading action (e.g. RB = top menu). It
     applies only in the idle reading context -- a document is open and no
     selection overlay, dictionary popup or X-combo is active (the top menu
     and modal dialogs are handled before, by their own branches). Anywhere
     else the role's built-in handler above runs unchanged, so the table of
     controls in this header stays true for selection, dictionary and menus.
     The override does not replace X + <button> combos (they stay on the
     built-in handlers). Actions are implemented in ACTION_RUNNERS.

2. Older builds with sdl3_gamepad.patch + 1-lstick-keys.lua userpatch: no
   Gamepad* broadcast, buttons/axes arrive as key names and hit the
   key_events table in PadNav:init (kept for compatibility):
     LT = LPgBack (F6), RT = LPgFwd (F7), LB = RPgBack (F9), RB = RPgFwd (F11)
     X = F10, R-stick = F3/F4/F5/F8, L-stick = LStickUp/Down/Left/Right.
     ASSUMPTION (unverifiable): the old patch emits no known key for
     Select/Start. We bind Select = F12 and Start = F2 (see
     SELECT_KEYS/START_KEYS; hunk for sdl3_gamepad.patch maps BACK ->
     1073741893 (F12), START -> 1073741883 (F2)). If those keys never arrive
     the bindings are simply inert; X + D-pad still reaches the menus.
]]

local Event          = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager      = require("ui/uimanager")
local time           = require("ui/time")
local logger         = require("logger")
local Pluginaro      = require("pluginaro")
local _              = require("gettext")

-- Optional on-device diagnostics (kopad_trace.lua, enabled by the flag file
-- <settings dir>/kopad-trace). A missing module degrades to a no-op stub.
local ok_trace, Trace = pcall(require, "kopad_trace")
if not ok_trace or type(Trace) ~= "table" then
    Trace = { log = function() end, active = function() return false end }
end

-- Optional button remapping (padmap.lua, PC-011). PadNav only calls
-- Padmap.resolve on the table main.lua hands over via set_padmap(); a missing
-- module or no table = identity mapping (behaviour before remapping existed).
local ok_padmap, Padmap = pcall(require, "padmap")
if not ok_padmap or type(Padmap) ~= "table" then Padmap = nil end

local RTL_LANGS = { ar=true, he=true, fa=true, ur=true }

-- Stock KOReader >= 2026.07 gamepad ids (frontend/device/sdl/gamepad.lua).
-- GamepadButtonDown carries {button = <id>}; GamepadAxisMotion {axis = <id>}.
local BTN_A, BTN_B, BTN_X, BTN_Y = 0, 1, 2, 3
local BTN_SELECT, BTN_GUIDE, BTN_START = 4, 5, 6
local BTN_L3, BTN_R3, BTN_LB, BTN_RB = 7, 8, 9, 10
local AXIS_LX, AXIS_LY, AXIS_RX, AXIS_RY = 0, 1, 2, 3
local AXIS_LT, AXIS_RT = 4, 5

-- button id -> on<Key> handler (return value true = consumed).
local BUTTON_HANDLERS = {
    [BTN_A]      = "onKPConfirm",
    [BTN_B]      = "onKPBack",
    [BTN_X]      = "onKPExtend",
    [BTN_Y]      = "onKPMenu",
    [BTN_SELECT] = "onKPSelect",
    [BTN_START]  = "onKPStart",
    [BTN_LB]     = "onKPPgBk",
    [BTN_RB]     = "onKPPgFwd",
}
-- Buttons consumed even when their handler declines: the stock default key of
-- each would be wrong here (Select -> RPgBack, Guide -> RPgFwd, Start/L3 ->
-- Menu). R3 has no stock key; swallowed so a future default cannot leak in.
local BUTTON_SWALLOW = {
    [BTN_SELECT] = true, [BTN_GUIDE] = true, [BTN_START] = true,
    [BTN_L3] = true, [BTN_R3] = true,
}

-- Paged documents (PDF/DjVu) have no selector, so there the D-pad and the
-- R-stick steer the view instead (see PadNav:_paged_idle): D-pad up/down =
-- zoom in/out, left = whole page, right = text width (margins cropped);
-- R-stick = pan the page (stock ReaderPanning, half a screen per step, the
-- stock axis auto-repeat keeps it moving while held).
local PAGED_DPAD = {
    [11] = { "Zoom", "in" },
    [12] = { "Zoom", "out" },
    [13] = { "SetZoomMode", "page" },
    [14] = { "SetZoomMode", "contentwidth" },
}

-- Trigger auto-repeat filter (see PadNav:_trigger_is_new_press). Stock
-- device.lua fires the first repeat 0.5 s after the press (delay) and then
-- every 0.2 s; it never reports the release of an axis to plugins.
local TRIGGER_FIRST_REPEAT_MIN_S = 0.45 -- first repeat cannot come earlier than 0.5 s
local TRIGGER_FIRST_REPEAT_MAX_S = 0.9  -- ...allow slack for a slow page render
local TRIGGER_NEXT_REPEAT_MAX_S  = 0.6  -- later repeats: 0.2 s + slack

local PadNav = InputContainer:extend{
    name        = "kopad_padnav",
    enabled_ref = nil,
}

-- LEGACY (builds with sdl3_gamepad.patch only). On KOReader >= 2026.07
-- Select/Start arrive via onGamepadButtonDown and these keys never fire.
-- Select/Start key names: unverifiable without the old KOReader SDL3.lua.
-- These are unused F-keys; the matching hunk must be added to
-- sdl3_gamepad.patch (BACK -> 1073741893 "F12", START -> 1073741883 "F2").
-- Unknown/absent keys just never fire, so a wrong guess is harmless.
local SELECT_KEYS = { "F12" }
local START_KEYS  = { "F2" }

local SUPPRESS_KEYS = {
    "MoveUp", "MoveDown",
    "GotoNextView", "GotoPrevView",
    "Press",
}

function PadNav:init()
    -- key_events: LEGACY input path for builds with sdl3_gamepad.patch. On
    -- KOReader >= 2026.07 the same handlers are driven by onGamepadButtonDown /
    -- onGamepadAxisMotion (bottom of this file); the keys below are then only
    -- hit by the stock default keys (D-pad Up/Down/Left/Right, and the
    -- Press/Back/ContextMenu/RPgBack/RPgFwd fall-through when a handler passes).
    self.key_events = {
        -- L-stick: separate key names injected by 1-lstick-keys.lua userpatch
        -- Falls back to Up/Down/Left/Right if patch not applied (also covers D-pad until patch confirmed)
        KPUp      = { { "LStickUp" } },
        KPDown    = { { "LStickDown" } },
        KPLeft    = { { "LStickLeft" } },
        KPRight   = { { "LStickRight" } },
        KPUp2     = { { "Up" } },
        KPDown2   = { { "Down" } },
        KPLeft2   = { { "Left" } },
        KPRight2  = { { "Right" } },
        -- D-pad: Up/Down/Left/Right pass through to KOReader (menu nav etc.)

        -- R-stick: word navigation / extend-trim (toggled by R3 click)
        KPRStickUp    = { { "F3" } },
        KPRStickDown  = { { "F4" } },
        KPRStickLeft  = { { "F5" } },
        KPRStickRight = { { "F8" } },
        -- face buttons (accent actions)
        KPExtend  = { { "F10" } },        -- X: toggle extend mode
        -- shoulder buttons: page turn
        KPPgBk    = { { "RPgBack" } },    -- LB
        KPPgFwd   = { { "RPgFwd" } },     -- RB
        KPPgBk2   = { { "LPgBack" } },    -- LT (F6): always previous page
        KPPgFwd2  = { { "LPgFwd" } },     -- RT (F7): always next page
        -- Select / Start: top menu / footer menu (key names are an ASSUMPTION,
        -- see header docstring and SELECT_KEYS/START_KEYS)
        KPSelect  = { SELECT_KEYS },
        KPStart   = { START_KEYS },
        KPPgBk3   = { { "ScrollLock" } }, -- L4 back paddle (LEGACY patched builds only)
        KPPgFwd3  = { { "Pause" } },      -- R4 back paddle (LEGACY patched builds only)
        -- face buttons
        KPConfirm = { { "Press" } },      -- A
        KPBack    = { { "Back" } },       -- B
        KPMenu    = { { "ContextMenu" } }, -- Y
    }

    self._saved_keys = nil

    if self.ui and self.ui.active_widgets then
        table.insert(self.ui.active_widgets, 1, self)
    end

    if self:_is_enabled() then
        self:_suppress_reader_keys()
    end
end

function PadNav:_is_enabled()
    -- A FOREIGN family overlay (visel / hilite) owns the screen — stand
    -- down. kopad's own selector overlay also claims ui._kokb_overlay
    -- (as "kopad", see selector._open*), and must NOT lock out the very
    -- gamepad that drives it — hence the `except` argument.
    if Pluginaro.overlay_active(self.ui, "kopad") then return false end
    -- Modal arbitration: while a KOReader Menu / dialog owns the top of the
    -- window stack, stand down from every reader-context gamepad handler
    -- (crosshair / selector openers, shoulder-button page turns, face
    -- buttons). Menu D-pad navigation is unaffected: the Menu sits on top of
    -- the window stack and consumes Up/Down/Left/Right/Press before padnav
    -- (in active_widgets) is ever consulted. kopad's own overlay is a Widget,
    -- not in MODAL_CLASSES, so selection handling inside it still works.
    if Pluginaro.is_modal_active() then return false end
    return self.enabled_ref and self.enabled_ref.enabled
end

-- Why _is_enabled() is false (same checks, same order). Trace output only;
-- call it only when Trace.active().
function PadNav:_why_disabled()
    if Pluginaro.overlay_active(self.ui, "kopad") then return "foreign overlay" end
    if Pluginaro.is_modal_active() then return "modal active" end
    if not self.enabled_ref then return "no enabled_ref" end
    if not self.enabled_ref.enabled then return "not enabled" end
    return "enabled"
end

function PadNav:_suppress_reader_keys()
    -- Selector-driven navigation only exists for crengine (rolling) documents
    -- (main.lua:_ensure_selector requires ui.rolling). In paged documents
    -- (PDF/DjVu) and in the FileManager there is no ui.rolling, so we leave
    -- every original key binding untouched — the selector-dependent handlers
    -- below return false in that case, letting arrows/Press pass through to
    -- the reader's / file manager's own navigation. Only LB/RB page turns
    -- (which need no selector) stay active in paged documents.
    if not (self.ui and self.ui.rolling) then return end
    if self._saved_keys then return end
    self._saved_keys = {}

    local seen = {}
    local targets = {}
    local function add(mod)
        if mod and mod.key_events and not seen[mod] and mod ~= self then
            seen[mod] = true
            table.insert(targets, mod)
        end
    end

    add(self.ui)
    add(self.ui and self.ui.rolling)
    add(self.ui and self.ui.paging)
    add(self.ui and self.ui.view)
    add(self.ui and self.ui.view and self.ui.view.footer)
    add(self.ui and self.ui.footer)
    add(self.ui and self.ui.highlight)
    add(self.ui and self.ui.bookmark)
    -- scan all active_widgets so nothing slips through
    if self.ui and self.ui.active_widgets then
        for _, w in ipairs(self.ui.active_widgets) do
            add(w)
        end
    end

    for _, mod in ipairs(targets) do
        self._saved_keys[mod] = {}
        for _, name in ipairs(SUPPRESS_KEYS) do
            if mod.key_events[name] then
                self._saved_keys[mod][name] = mod.key_events[name]
                mod.key_events[name] = nil
            end
        end
        local to_remove = {}
        for name, binding in pairs(mod.key_events) do
            if type(binding) == "table" and type(binding[1]) == "table" then
                for _, k in ipairs(binding[1]) do
                    if k == "Press" then
                        table.insert(to_remove, name); break
                    end
                end
            end
        end
        for _, name in ipairs(to_remove) do
            self._saved_keys[mod][name] = mod.key_events[name]
            mod.key_events[name] = nil
        end
    end
end

function PadNav:restore_reader_keys()
    if not self._saved_keys then return end
    for mod, keys in pairs(self._saved_keys) do
        if mod and mod.key_events then
            for name, binding in pairs(keys) do
                mod.key_events[name] = binding
            end
        end
    end
    self._saved_keys = nil
end

function PadNav:_selector()
    return self.enabled_ref and self.enabled_ref.subs
        and self.enabled_ref.subs.selector
end

-- Integration A (pluginaro): route a gamepad event into visel's selection
-- while the visel overlay is open AND the user opted in
-- (`visel.ext.kopad.gamepad_select`). Returns true when the event was
-- routed (caller consumes it). call_provided returns nil when the toggle
-- is OFF, visel is absent (nothing provided) or the impl errors — in all
-- of those cases we return false and the handler falls through to today's
-- behaviour (which, with the visel overlay open, is `_is_enabled() ==
-- false` → stand down, exactly as before this integration).
-- Note this check runs BEFORE _is_enabled() in the handlers, because
-- _is_enabled() deliberately returns false while `ui._kokb_overlay` is
-- claimed by a foreign overlay (visel/hilite)
-- — the very state we are routing for. The kopad master switch and the
-- Task-2 modal guard are re-checked here so neither is bypassed.
function PadNav:_visel_route(method, arg)
    if not (self.enabled_ref and self.enabled_ref.enabled) then return false end
    if Pluginaro.is_modal_active() then return false end
    if not Pluginaro.call_provided("visel", "kopad", "gamepad_select", "is_active") then
        return false
    end
    Pluginaro.call_provided("visel", "kopad", "gamepad_select", method, arg)
    return true
end

function PadNav:_is_rtl()
    if not self.ui or not self.ui.document then return false end
    local ok, props = pcall(function() return self.ui.document:getProps() end)
    if not ok then return false end
    local lang_raw = (props and props.language) or ""
    local lang_base = lang_raw:lower():match("^([a-z]+)") or ""
    return RTL_LANGS[lang_base] or false
end

function PadNav:_find_dict_widget()
    local stack = UIManager._window_stack
    if not stack then return nil end
    for i = #stack, 1, -1 do
        local w = stack[i].widget
        if w and w.name == "DictQuickLookup" then return w end
    end
    return nil
end


function PadNav:_lstick_dir(dx, dy)
    if self:_is_rtl() then dx = -dx end
    local selector = self:_selector()
    if not selector then return end
    if not selector.overlay then
        self:_open_sentence_select(1)
        return
    end
    local ov = selector.overlay
    if ov.mode == "walk" then return end
    if ov.mode ~= "struct" then
        ov.mode = "struct"; ov.sel_sent = 1; ov.sel_tail = 1; ov.sel_word = nil
        ov:_refresh(); return
    end

    ov.hl_cur = 0
    if dy ~= 0 then
        -- ↑↓: paragraph jump
        local cur_para = ov.sentences[ov.sel_sent] and ov.sentences[ov.sel_sent].para
        if dy > 0 then
            for j = ov.sel_sent + 1, #ov.sentences do
                if ov.sentences[j].para ~= cur_para then
                    ov.sel_sent = j; ov.sel_tail = j; ov.sel_word = nil
                    ov:_refresh(); return
                end
            end
        else
            local j = ov.sel_sent - 1
            while j >= 1 and ov.sentences[j].para == cur_para do j = j - 1 end
            if j >= 1 then
                local prev_para = ov.sentences[j].para
                while j > 1 and ov.sentences[j - 1].para == prev_para do j = j - 1 end
                ov.sel_sent = j; ov.sel_tail = j; ov.sel_word = nil
                ov:_refresh()
            end
        end
    else
        -- ←→: move sentence
        local new = ov.sel_sent + dx
        if new >= 1 and new <= #ov.sentences then
            ov.sel_sent = new; ov.sel_tail = new; ov.sel_word = nil
            ov:_refresh()
        end
    end
end

-- Walk mode L-stick = page turn. After the page reflows we must recollect the
-- overlay's words so it re-anchors to the new page; GotoViewRel changes the
-- visible page synchronously (same pattern _ww_move uses after its own off-page
-- page turn), so reload() right after is safe. Without it the overlay keeps
-- drawing/selecting the previous page's stale word.
function PadNav:_walk_page(ov, dir)
    self.ui:handleEvent(Event:new("GotoViewRel", dir))
    ov:reload()
end

function PadNav:onKPUp()
    if not self:_is_enabled() then return false end
    local selector = self:_selector()
    if selector and selector.overlay then
        if selector.overlay.mode == "walk" then
            self:_walk_page(selector.overlay, 1); return true
        end
        if selector.overlay.mode == "cross" then
            selector.overlay:_cross_move(0, -1); return true
        end
        self:_lstick_dir(0, -1); return true
    end
    self.ui:handleEvent(Event:new("GotoViewRel", 1)); return true
end
function PadNav:onKPDown()
    if not self:_is_enabled() then return false end
    local selector = self:_selector()
    if selector and selector.overlay then
        if selector.overlay.mode == "walk" then
            self:_walk_page(selector.overlay, -1); return true
        end
        if selector.overlay.mode == "cross" then
            selector.overlay:_cross_move(0, 1); return true
        end
        self:_lstick_dir(0, 1); return true
    end
    -- No selector (paged doc / FileManager): pass the key through instead of
    -- consuming it as a no-op.
    if not selector then return false end
    selector:_open()
    return true
end
function PadNav:onKPLeft()
    if self:_visel_route("move", -1) then return true end
    if not self:_is_enabled() then return false end
    local selector = self:_selector()
    if selector and selector.overlay then
        if selector.overlay.mode == "walk" then
            self:_walk_page(selector.overlay, 1); return true
        end
        if selector.overlay.mode == "cross" then
            selector.overlay:_cross_move(-1, 0); return true
        end
        self:_lstick_dir(-1, 0); return true
    end
    self.ui:handleEvent(Event:new("GotoViewRel", 1)); return true
end
function PadNav:onKPRight()
    if self:_visel_route("move", 1) then return true end
    if not self:_is_enabled() then return false end
    local selector = self:_selector()
    if selector and selector.overlay then
        if selector.overlay.mode == "walk" then
            self:_walk_page(selector.overlay, -1); return true
        end
        if selector.overlay.mode == "cross" then
            selector.overlay:_cross_move(1, 0); return true
        end
        self:_lstick_dir(1, 0); return true
    end
    if not self:_selector() then return false end
    self:_rstick_dir(1, 0); return true
end

-- D-pad: X-mode combos (reading) or word walk (overlay / normal)
function PadNav:_x_combo(action_fn)
    self._x_mode = false
    action_fn()
end

function PadNav:_dpad(dx, dy)
    local selector = self:_selector()
    if selector and selector.overlay then
        if selector.overlay.extend_side then
            if self:_is_rtl() then dx = -dx end
            selector.overlay:extend_dpad(dx, dy); return
        end
        if selector.overlay.mode == "walk" then
            self:_rstick_dir(dx, dy); return
        end
        if selector.overlay.mode == "struct" and not selector.overlay.sel_word then
            self:_lstick_dir(dx, dy); return
        end
        self:_rstick_dir(dx, dy); return
    end
    if not selector then return end
    selector:_open_walk(dy < 0 or dx < 0)
end

function PadNav:onKPUp2()
    if not self:_is_enabled() then return false end
    if self._x_mode then
        self:_x_combo(function() self.ui:handleEvent(Event:new("ShowMenu")) end)
        return true
    end
    -- No selector (paged doc / FileManager): keys are not suppressed there,
    -- so return false to let the original arrow bindings handle navigation.
    if not self:_selector() then return false end
    self:_dpad(0, -1); return true
end
function PadNav:onKPDown2()
    if not self:_is_enabled() then return false end
    if self._x_mode then
        self:_x_combo(function()
            local footer = self.ui.view and self.ui.view.footer
            if footer then footer:onToggleFooterMode() end
        end)
        return true
    end
    if not self:_selector() then return false end
    self:_dpad(0, 1); return true
end
function PadNav:onKPLeft2()
    if self:_visel_route("move", -1) then return true end
    if not self:_is_enabled() then return false end
    if self._x_mode then
        self:_x_combo(function() self.ui:handleEvent(Event:new("ShowHist")) end)
        return true
    end
    if not self:_selector() then return false end
    self:_dpad(-1, 0); return true
end
function PadNav:onKPRight2()
    if self:_visel_route("move", 1) then return true end
    if not self:_is_enabled() then return false end
    if self._x_mode then
        self:_x_combo(function() self.ui:handleEvent(Event:new("Home")) end)
        return true
    end
    if not self:_selector() then return false end
    self:_dpad(1, 0); return true
end

-- Sentence selection: open overlay, navigate, extend/trim
function PadNav:_open_sentence_select(start_idx)
    local selector = self:_selector()
    if not selector then return end
    if not selector.overlay then
        selector:_open()
        if not selector.overlay then return end
        selector.overlay.mode = "struct"
        selector.overlay.sel_sent = start_idx or 1
        selector.overlay.sel_tail = selector.overlay.sel_sent
        selector.overlay.sel_word = nil
        selector.overlay:_refresh()
    end
end

-- R-stick: immediate crosshair — opens crosshair if needed, moves cursor in any mode
function PadNav:_cross_dir(dx, dy)
    if self:_is_rtl() then dx = -dx end
    local selector = self:_selector()
    if not selector then return end
    if not selector.overlay then
        selector:_open()
        if not selector.overlay then return end
    end
    local ov = selector.overlay
    if ov.extend_side then ov:exit_extend() end
    if ov.mode == "cross" then
        ov:_cross_move(dx, dy)
    elseif ov.mode == "walk" then
        if dx ~= 0 then ov:_ww_move(dx) end
        if dy ~= 0 then ov:_ww_line(dy) end
    elseif ov.mode == "struct" then
        -- in struct: HL cycling (↑↓ no word) or word nav
        if not ov.sel_word and #ov.hl_items > 0 and dy ~= 0 then
            if dy > 0 then
                ov.hl_cur = (ov.hl_cur < #ov.hl_items) and ov.hl_cur + 1 or 1
            else
                ov.hl_cur = (ov.hl_cur > 1) and ov.hl_cur - 1 or #ov.hl_items
            end
            ov:_refresh()
        else
            -- dx was already RTL-flipped at the top of _cross_dir; tell
            -- _rstick_dir not to flip again (M1).
            self:_rstick_dir(dx, dy, true)
        end
    end
end

-- D-pad word handling: walk mode (no overlay) or word-within-sentence (struct)
-- already_flipped: set by callers (e.g. _cross_dir) that have already applied
-- the RTL dx flip, so we don't flip a second time (M1: double-flip netting zero).
function PadNav:_rstick_dir(dx, dy, already_flipped)
    if not already_flipped and self:_is_rtl() then dx = -dx end
    local selector = self:_selector()
    if not selector then return end
    if not selector.overlay then
        selector:_open_walk()
        if not selector.overlay then return end
    end
    local ov = selector.overlay
    if ov.mode == "walk" then
        if dx ~= 0 then ov:_ww_move(dx) end
        if dy ~= 0 then ov:_ww_line(dy) end
        return
    end
    if ov.mode == "cross" then
        ov:_cross_move(dx, dy); return
    end
    if ov.mode ~= "struct" then return end
    local sent = ov.sentences[ov.sel_sent]
    if not sent or not sent.word_list or #sent.word_list == 0 then return end

    ov.hl_cur = 0
    if not ov.sel_word then
        ov.sel_word = 1
        ov.sel_word_tail = 1
        ov:_refresh()
        return
    end

    local delta
    if dx ~= 0 then
        delta = dx
    else
        local cur_w = sent.word_list[ov.sel_word]
        if cur_w and cur_w.sbox then
            local cx = cur_w.sbox.x + cur_w.sbox.w / 2
            local cy = cur_w.sbox.y + cur_w.sbox.h / 2
            local lh = cur_w.sbox.h
            local best, best_dist = ov.sel_word, math.huge
            for i, w in ipairs(sent.word_list) do
                if w.sbox then
                    local wy = w.sbox.y + w.sbox.h / 2
                    if (dy > 0 and wy > cy + lh * 0.5) or
                       (dy < 0 and wy < cy - lh * 0.5) then
                        local d = math.abs(wy - (cy + dy * lh)) * 2
                                + math.abs(w.sbox.x + w.sbox.w/2 - cx)
                        if d < best_dist then best = i; best_dist = d end
                    end
                end
            end
            ov.sel_word = best
            ov.sel_word_tail = best
            ov:_refresh()
            return
        end
        delta = dy
    end
    local new = ov.sel_word + delta
    if new >= 1 and new <= #sent.word_list then
        ov.sel_word = new
        ov.sel_word_tail = new
    end
    ov:_refresh()
end

function PadNav:onKPRStickUp()
    if not self:_is_enabled() then return false end
    if not self:_selector() then return false end
    self:_cross_dir(0, -1); return true
end
function PadNav:onKPRStickDown()
    if not self:_is_enabled() then return false end
    if not self:_selector() then return false end
    self:_cross_dir(0, 1); return true
end
function PadNav:onKPRStickLeft()
    if not self:_is_enabled() then return false end
    if not self:_selector() then return false end
    self:_cross_dir(-1, 0); return true
end
function PadNav:onKPRStickRight()
    if not self:_is_enabled() then return false end
    if not self:_selector() then return false end
    self:_cross_dir(1, 0); return true
end

-- X: highlight toggle (overlay) or combo modifier (reading)
function PadNav:onKPExtend()
    if not self:_is_enabled() then return false end
    local selector = self:_selector()
    if selector and selector.overlay then
        if selector.overlay.extend_side then selector.overlay:exit_extend() end
        local sel = selector.overlay:_get_selection()
        if sel then selector.overlay:_do_toggle_highlight(sel) end
        return true
    end
    self._x_mode = not self._x_mode
    return true
end

-- RB: X+RB=bm, enter/quick extend right (overlay), next page (reading)
function PadNav:onKPPgFwd()
    if self:_visel_route("extend", 1) then return true end
    if not self:_is_enabled() then return false end
    if self._x_mode then
        self:_x_combo(function() self.ui:handleEvent(Event:new("ShowBookmark")) end)
        return true
    end
    local dict_w = self:_find_dict_widget()
    if dict_w then
        dict_w:handleEvent(Event:new("Swipe", nil, {direction = "west"}))
        return true
    end
    local selector = self:_selector()
    if selector and selector.overlay
        and (selector.overlay.mode == "struct" or selector.overlay.mode == "walk") then
        local ov = selector.overlay
        if ov.extend_side == "right" then
            ov:quick_extend_right()
        elseif ov.extend_side == "left" then
            ov.extend_side = "right"; ov:_refresh()
        else
            ov:enter_extend("right")
        end
        return true
    end
    self.ui:handleEvent(Event:new("GotoViewRel", 1)); return true
end

-- LB: X+LB=TOC, enter/quick extend left (overlay), previous page (reading)
function PadNav:onKPPgBk()
    if self:_visel_route("extend", -1) then return true end
    if not self:_is_enabled() then return false end
    if self._x_mode then
        self:_x_combo(function() self.ui:handleEvent(Event:new("ShowToc")) end)
        return true
    end
    local dict_w = self:_find_dict_widget()
    if dict_w then
        dict_w:handleEvent(Event:new("Swipe", nil, {direction = "east"}))
        return true
    end
    local selector = self:_selector()
    if selector and selector.overlay
        and (selector.overlay.mode == "struct" or selector.overlay.mode == "walk") then
        local ov = selector.overlay
        if ov.extend_side == "left" then
            ov:quick_extend_left()
        elseif ov.extend_side == "right" then
            ov.extend_side = "left"; ov:_refresh()
        else
            ov:enter_extend("left")
        end
        return true
    end
    self.ui:handleEvent(Event:new("GotoViewRel", -1)); return true
end

-- LT/RT: page turn, independent of overlay state. GotoViewRel +1 = next page
-- (KOReader semantics, same in RTL books: "next" is reading order, so no
-- _is_rtl() flip here — triggers are semantic, not spatial).
function PadNav:_turn_page(dir)
    if self:_find_dict_widget() then return false end
    local selector = self:_selector()
    if selector and selector.overlay then selector:_close() end
    self._x_mode = false
    self.ui:handleEvent(Event:new("GotoViewRel", dir)); return true
end
function PadNav:onKPPgBk2()
    if not self:_is_enabled() then return false end
    return self:_turn_page(-1)
end
function PadNav:onKPPgFwd2()
    if not self:_is_enabled() then return false end
    return self:_turn_page(1)
end

-- Select: top menu. Start: footer (bottom) menu. No X modifier needed.
function PadNav:_menu_action(fn)
    local selector = self:_selector()
    if selector and selector.overlay then selector:_close() end
    self._x_mode = false
    fn()
    return true
end
function PadNav:onKPSelect()
    if not self:_is_enabled() then return false end
    if self:_find_dict_widget() then return false end
    return self:_menu_action(function()
        self.ui:handleEvent(Event:new("ShowMenu"))
    end)
end
function PadNav:onKPStart()
    if not self:_is_enabled() then return false end
    if self:_find_dict_widget() then return false end
    return self:_menu_action(function()
        local footer = self.ui.view and self.ui.view.footer
        if footer then footer:onToggleFooterMode() end
    end)
end
function PadNav:onKPPgBk3()  return self:onKPPgBk()  end
function PadNav:onKPPgFwd3() return self:onKPPgFwd() end

-- A: sentence selection (reading), confirm/action menu (overlay)
function PadNav:onKPConfirm()
    if not self:_is_enabled() then return false end

    local selector = self:_selector()
    if selector and selector.overlay then
        selector.overlay:confirm()
        return true
    end
    -- No selector (paged doc / FileManager): Press bindings are not
    -- suppressed there — pass through so e.g. FileManager item selection works.
    if not selector then return false end
    self:_open_sentence_select(1)
    return true
end

-- B: exit extend mode, or close overlay
function PadNav:onKPBack()
    if self:_visel_route("close") then return true end
    if not self:_is_enabled() then return false end

    local selector = self:_selector()
    if selector and selector.overlay then
        if selector.overlay.extend_side then
            selector.overlay:exit_extend()
            return true
        end
        selector:_close()
        return true
    end
    return false
end

-- Y: Vortuyo (overlay) or highlight mode / crosshair fallback (reading)
-- When dict is open, Y→AI is handled by _hook_dict_widget on the dict widget itself.
function PadNav:onKPMenu()
    if not self:_is_enabled() then return false end

    local selector = self:_selector()
    if selector and selector.overlay then
        if selector.overlay.extend_side then selector.overlay:exit_extend() end
        local sel = selector.overlay:_get_selection()
        if sel then
            selector.overlay:_do_vortuyo(sel)
            return true
        end
    end

    -- No selector (paged doc / FileManager): pass through, don't eat the key.
    if not selector then return false end
    self:_open_highlights(selector)
    return true
end

-- Highlight mode: open the selector (crosshair); when the page already has
-- highlights, start on the first one instead. Y in reading, and the
-- `highlights` action (ACTION_RUNNERS).
function PadNav:_open_highlights(selector)
    selector:_open()
    if not selector.overlay then return end
    if #selector.overlay.hl_items > 0 then
        selector.overlay.mode = "struct"
        selector.overlay.sel_sent = 1
        selector.overlay.sel_tail = 1
        selector.overlay.sel_word = nil
        selector.overlay.hl_cur = 1
        selector.overlay:_refresh()
    end
end

-- ---------------------------------------------------------------------------
-- KOReader >= 2026.07: raw gamepad events (no patch). Return true = handled,
-- stock default key press is suppressed; false = stock behaviour unchanged.
-- Called from kopad:onGamepadButtonDown / onGamepadAxisMotion in main.lua.
-- When _is_enabled() is false (kopad off, modal Menu/dialog on top, foreign
-- overlay) we return false before touching anything; the stock default key
-- then reaches the on<Key> bindings (e.g. visel routing in onKPBack/onKPLeft)
-- or the menu exactly as it would without kopad.
-- ---------------------------------------------------------------------------

-- Remapping (padmap.lua): main.lua builds the resolution table from
-- settings/kopad.lua (`padmap`, synced) + settings/kopad_device.lua
-- (`padmap_layout`, local) and passes it here; nil = identity.
function PadNav:set_padmap(resolved)
    self._padmap = resolved
    self._actions = type(resolved) == "table" and type(resolved.actions) == "table"
        and next(resolved.actions) ~= nil and resolved.actions or nil
end

-- Role-level actions (PC-014). What each action id does while reading; ids are
-- the closed vocabulary of padmap.lua (ACTION_ORDER). Each runner gets the
-- PadNav and is only called from the idle reading context (see
-- _override_action), where no overlay is open and `_x_mode` is off -- except
-- x_modifier, which is also how a role that holds the modifier switches it off.
local function toggle_footer(self)
    local footer = self.ui.view and self.ui.view.footer
    if footer then footer:onToggleFooterMode() end
end
local unpack = table.unpack or unpack -- LuaJIT (KOReader) has the global, Lua 5.4 (tests) the table field
local function ui_event(name, ...)
    local args = { ... }
    return function(self) self.ui:handleEvent(Event:new(name, unpack(args))) end
end
-- Openers that need the selector (rolling documents only); without one the
-- press is swallowed, see _run_action.
local function with_selector(fn)
    return function(self)
        local selector = self:_selector()
        if not selector then return false end
        fn(self, selector)
    end
end
local ACTION_RUNNERS = {
    -- pages
    next_page         = ui_event("GotoViewRel", 1),
    prev_page         = ui_event("GotoViewRel", -1),
    pages_forward_10  = ui_event("GotoViewRel", 10),
    pages_back_10     = ui_event("GotoViewRel", -10),
    next_chapter      = ui_event("GotoNextChapter"),
    prev_chapter      = ui_event("GotoPrevChapter"),
    first_page        = ui_event("GoToBeginning"),
    last_page         = ui_event("GoToEnd"),
    back_location     = ui_event("GoBackLink", true),
    forward_location  = ui_event("GoForwardLink"),
    goto_page         = ui_event("ShowGotoDialog"),
    skim              = ui_event("ShowSkimtoDialog"),
    -- menus
    top_menu          = ui_event("ShowMenu"),
    footer_menu       = toggle_footer,
    config_menu       = ui_event("ShowConfigMenu"),
    -- book
    toc               = ui_event("ShowToc"),
    bookmarks         = ui_event("ShowBookmark"),
    toggle_bookmark   = ui_event("ToggleBookmark"),
    next_bookmark     = ui_event("GotoNextBookmarkFromPage"),
    prev_bookmark     = ui_event("GotoPreviousBookmarkFromPage"),
    book_map          = ui_event("ShowBookMap"),
    page_browser      = ui_event("ShowPageBrowser"),
    fulltext_search   = ui_event("ShowFulltextSearchInput"),
    book_status       = ui_event("ShowBookStatus"),
    book_info         = ui_event("ShowBookInfo"),
    reading_progress  = ui_event("ShowReaderProgress"),
    -- library
    history           = ui_event("ShowHist"),
    file_browser      = ui_event("Home"),
    last_book         = ui_event("OpenLastDoc"),
    favorites         = ui_event("ShowColl"),
    collections       = ui_event("ShowCollList"),
    -- selection and dictionary
    sentence_select   = with_selector(function(self) self:_open_sentence_select(1) end),
    highlights        = with_selector(function(self, selector) self:_open_highlights(selector) end),
    word_walk         = with_selector(function(self, selector) selector:_open_walk(false) end),
    crosshair         = with_selector(function(self, selector) selector:_open() end),
    dict_lookup       = ui_event("ShowDictionaryLookup"),
    -- display
    font_bigger       = ui_event("IncreaseFontSize", 1),
    font_smaller      = ui_event("DecreaseFontSize", 1),
    zoom_in           = ui_event("Zoom", "in"),
    zoom_out          = ui_event("Zoom", "out"),
    zoom_fit_width    = ui_event("SetZoomMode", "contentwidth"),
    zoom_fit_page     = ui_event("SetZoomMode", "page"),
    night_mode        = ui_event("ToggleNightMode"),
    rotate            = ui_event("IterateRotation"),
    full_refresh      = ui_event("FullRefresh"),
    frontlight_toggle = ui_event("ToggleFrontlight"),
    frontlight_up     = ui_event("IncreaseFlIntensity", 1),
    frontlight_down   = ui_event("DecreaseFlIntensity", 1),
    -- other
    screenshot        = ui_event("Screenshot"),
    cheat_sheet       = function(self) self:_show_text(self:_cheat_reading()) end,
    x_modifier        = function(self) self._x_mode = not self._x_mode end,
    none              = function() end,
}

-- The action id `role` should perform NOW instead of its built-in handler, or
-- nil (built-in runs). Idle reading context only: a document is open (the
-- FileManager keeps the stock list navigation), no X-combo pending (combos
-- stay on the built-in handlers; only the modifier may be pressed again), no
-- dictionary popup and no selection overlay.
function PadNav:_override_action(role)
    local act = role and self._actions and self._actions[role]
    if not act then return nil end
    if not (self.ui and self.ui.document) then return nil end
    if self._x_mode and act ~= "x_modifier" then return nil end
    if self:_find_dict_widget() then return nil end
    local selector = self:_selector()
    if selector and selector.overlay then return nil end
    return act
end

-- True when the D-pad and the R-stick should steer a paged document's view
-- (PAGED_DPAD): a PDF/DjVu is open (the FileManager has no ui.paging, so its
-- list navigation stays stock), no X-combo pending (X + D-pad keeps its
-- menus) and no dictionary popup.
function PadNav:_paged_idle()
    if not (self.ui and self.ui.document and self.ui.paging) or self.ui.rolling then return false end
    if self._x_mode then return false end
    if self:_find_dict_widget() then return false end
    return true
end

-- Run an override. Always consumes the press (true): the user chose this
-- action for the button, so falling back to the stock key would be a surprise.
-- Selector openers silently do nothing where no selector exists (PDF/DjVu).
function PadNav:_run_action(action, role)
    local run = ACTION_RUNNERS[action]
    local ok, res = pcall(run, self)
    if not ok then
        logger.warn("kopad: action " .. tostring(action) .. " for " .. tostring(role) .. " failed: " .. tostring(res))
    end
    Trace.log("padnav role=%s: override action=%s ok=%s%s", tostring(role), tostring(action), tostring(ok),
        res == false and " (needs selector, no-op)" or "")
    return true
end

-- Physical control (kind "button"/"axis", SDL id) -> logical role kind, id.
function PadNav:_resolve(kind, id)
    if Padmap and self._padmap then
        local ok, rk, rid = pcall(Padmap.resolve, self._padmap, kind, id)
        if ok and rk ~= nil and rid ~= nil then return rk, rid end
    end
    return kind, id
end

-- Entry point for the physical button: remap, then handle the LOGICAL role.
-- A button remapped to a trigger role (lt/rt) acts as one trigger press.
function PadNav:onGamepadButtonDown(ev)
    if type(ev) == "table" and ev.button ~= nil then
        local kind, id = self:_resolve("button", ev.button)
        if kind == "axis" then
            Trace.log("padnav btn=%s: remapped to trigger axis=%s", tostring(ev.button), tostring(id))
            return self:_trigger_event(id, 32767, true)
        end
        if id ~= ev.button then
            Trace.log("padnav btn=%s: remapped to btn=%s", tostring(ev.button), tostring(id))
            ev = { button = id }
        end
    end
    return self:_button_down(ev)
end

-- LOGICAL button down (after remapping).
function PadNav:_button_down(ev)
    local tr = Trace.active()
    -- Top menu first (before the modal guard): LB/RB switch categories there.
    if type(ev) == "table" and self:_menu_button(ev.button) then
        if tr then Trace.log("padnav btn=%s: menu-branch handled -> result=true", tostring(ev.button)) end
        return true
    end
    if not self:_is_enabled() then
        if tr then
            Trace.log("padnav btn=%s: passthrough, %s -> result=false",
                tostring(type(ev) == "table" and ev.button), self:_why_disabled())
        end
        return false
    end
    local btn = type(ev) == "table" and ev.button or nil
    if btn == nil then
        if tr then Trace.log("padnav btn=nil: no button in event -> result=false") end
        return false
    end
    -- Role-level action override (PC-014); idle reading context only.
    local role = Padmap and Padmap.role_of("button", btn)
    local override = role and self:_override_action(role)
    if override then
        if tr then Trace.log("padnav btn=%s: role=%s override=%s", tostring(btn), role, override) end
        return self:_run_action(override, role)
    end
    local paged = PAGED_DPAD[btn]
    if paged and self:_paged_idle() then
        if tr then Trace.log("padnav btn=%s: paged view %s:%s", tostring(btn), paged[1], paged[2]) end
        self.ui:handleEvent(Event:new(paged[1], paged[2]))
        return true
    end
    local method = BUTTON_HANDLERS[btn]
    local handled = method and self[method](self) or false
    -- D-pad (11..14) and the rest: false -> stock Up/Down/Left/Right key.
    local result = handled or BUTTON_SWALLOW[btn] or false
    if tr then
        Trace.log("padnav btn=%s: handler=%s returned %s, %s -> result=%s", tostring(btn),
            tostring(method), tostring(handled),
            handled and "handled" or (BUTTON_SWALLOW[btn] and "swallowed"
                or ((type(btn) == "number" and btn >= 11 and btn <= 14) and "passthrough(dpad)" or "passthrough")),
            tostring(result))
    end
    return result
end

-- True when this trigger event is a NEW press, false when it is stock
-- auto-repeat of a trigger that is still held. The plugin never sees the
-- release, so a press is recognised by timing against the previous event on
-- the same axis: repeats arrive 0.5 s after the press, then every 0.2 s. We
-- use our own monotonic clock instead of ax.time: the first event carries
-- the SDL timestamp, repeats carry time.now() (different time bases).
-- Known trade-off: a deliberate second tap within ~0.9 s of a press that was
-- already held 0.5 s+ is indistinguishable from a repeat and is swallowed.
function PadNav:_trigger_is_new_press(axis)
    self._trigger_seen = self._trigger_seen or {}
    local now = time.to_s(time.now())
    local st = self._trigger_seen[axis]
    if st then
        local gap = now - st.t
        local is_repeat
        if st.n == 1 then
            is_repeat = gap >= TRIGGER_FIRST_REPEAT_MIN_S and gap < TRIGGER_FIRST_REPEAT_MAX_S
        else
            is_repeat = gap < TRIGGER_NEXT_REPEAT_MAX_S
        end
        if is_repeat then
            st.t = now; st.n = st.n + 1
            return false
        end
    end
    self._trigger_seen[axis] = { t = now, n = 1 }
    return true
end

-- axis id -> { negative-direction handler, positive-direction handler }
-- (SDL: x- = left, x+ = right, y- = up, y+ = down).
local STICK_HANDLERS = {
    [AXIS_LX] = { "onKPLeft",       "onKPRight" },
    [AXIS_LY] = { "onKPUp",         "onKPDown" },
    [AXIS_RX] = { "onKPRStickLeft", "onKPRStickRight" },
    [AXIS_RY] = { "onKPRStickUp",   "onKPRStickDown" },
}

-- Top menu (TouchMenu), reader and FileManager alike. The window on top of
-- the UIManager stack is a container (ReaderMenu / FileManagerMenu:
-- CenterContainer with the TouchMenu as child [1]); we do not assume
-- self.ui.menu (FileManager's `ui` differs) and duck-type instead: a table
-- with a `tab_item_table` list and a `switchMenuTab` function. Toast widgets
-- (Notification) on top of the menu are skipped; any other widget on top
-- (dialog, InfoMessage, keyboard) means "not the top menu" -> nil.
local MENU_SEARCH_DEPTH = 3

local function is_touch_menu(w)
    return type(w) == "table"
        and type(w.tab_item_table) == "table"
        and type(w.switchMenuTab) == "function"
end

local function find_touch_menu_in(w, depth, seen)
    if type(w) ~= "table" or seen[w] then return nil end
    seen[w] = true
    if is_touch_menu(w) then return w end
    if depth <= 0 then return nil end
    for i = 1, #w do
        local m = find_touch_menu_in(w[i], depth - 1, seen)
        if m then return m end
    end
    return nil
end

local function find_touch_menu()
    local stack = UIManager._window_stack
    if type(stack) ~= "table" then return nil end
    for i = #stack, 1, -1 do
        local w = stack[i] and stack[i].widget
        if type(w) == "table" and not w.toast then
            return find_touch_menu_in(w, MENU_SEARCH_DEPTH, {})
        end
    end
    return nil
end

-- Switch the TouchMenu `dir` (+1 / -1) categories, wrapping at the ends.
-- Same path as a tap on a tab icon: TouchMenuBar:switchToTab(k) runs the
-- icon's callback (highlight: bar_sep / icon_seps) and ends in
-- TouchMenu:switchMenuTab(k) (cur_tab, item_table, stack reset, updateItems
-- -> moveFocusTo(cur_tab, ...) + repaint). switchMenuTab alone would leave the
-- old icon highlighted. Falls back to switchMenuTab when there is no bar.
-- Action tabs (remember == false / tab callback) are skipped, see header.
-- Returns true when a switch was made.
local function menu_tab_step(menu, dir)
    local tabs = menu.tab_item_table
    local n = #tabs
    if n < 2 then return false end
    local cur = tonumber(menu.cur_tab) or 0
    if cur < 1 or cur > n then cur = dir > 0 and 0 or n + 1 end
    local k = cur
    for _ = 1, n do
        k = k + dir
        if k > n then k = 1 elseif k < 1 then k = n end
        if k == cur then return false end -- only one category to go to
        local t = tabs[k]
        if type(t) == "table" and t.remember ~= false and not t.callback then
            local bar = menu.bar
            if type(bar) == "table" and type(bar.switchToTab) == "function" then
                bar:switchToTab(k)
            else
                menu:switchMenuTab(k)
            end
            return true
        end
    end
    return false
end

-- The top menu (TouchMenu) when kopad should drive it, else nil. Used by the
-- menu branches that run BEFORE the _is_enabled() guard (a TouchMenu on top
-- counts as modal there): kopad must be switched on, and no FOREIGN family
-- overlay may own the screen (kopad's own claim does not count).
function PadNav:_top_menu()
    if not (self.enabled_ref and self.enabled_ref.enabled) then return nil end
    if Pluginaro.overlay_active(self.ui, "kopad") then return nil end
    local ok, menu = pcall(find_touch_menu)
    return ok and menu or nil
end

-- LB / RB with the top menu up: previous / next category. Buttons do not
-- auto-repeat (GamepadButtonDown fires once), so no filter is needed. Returns
-- true = consumed (the stock RPgBack/RPgFwd key, i.e. a menu page turn, is not
-- sent); false = no top menu / not our business, the caller continues as before.
function PadNav:_menu_button(btn)
    if btn ~= BTN_LB and btn ~= BTN_RB then return false end
    local menu = self:_top_menu()
    if not menu then
        if Trace.active() then
            Trace.log("padnav btn=%s: menu-branch no top menu (enabled=%s foreign_overlay=%s)",
                tostring(btn), tostring(self.enabled_ref and self.enabled_ref.enabled),
                tostring(Pluginaro.overlay_active(self.ui, "kopad")))
        end
        return false
    end
    local ok, err = pcall(menu_tab_step, menu, btn == BTN_RB and 1 or -1)
    if not ok then
        logger.warn("kopad: menu tab switch failed: " .. tostring(err))
    end
    Trace.log("padnav btn=%s: menu tab step ok=%s err=%s", tostring(btn), tostring(ok), tostring(err))
    return true
end

-- LT / RT with the top menu up: previous / next page of the menu. One press =
-- one page (_trigger_is_new_press); auto-repeats are consumed without action.
-- Returns true when the event belongs to the menu, false = caller continues.
function PadNav:_menu_trigger(axis, value, from_button)
    local menu = self:_top_menu()
    if not menu then return false end
    Trace.log("padnav axis=%s value=%s: menu page branch (new_press check next)",
        tostring(axis), tostring(value))
    if value > 0 and (from_button or self:_trigger_is_new_press(axis)) then
        local method = axis == AXIS_RT and "onNextPage" or "onPrevPage"
        if type(menu[method]) == "function" then
            local ok, err = pcall(menu[method], menu)
            if not ok then
                logger.warn("kopad: menu page turn failed: " .. tostring(err))
            end
        end
    end
    return true
end

-- LOGICAL trigger (axis AXIS_LT / AXIS_RT after remapping), numeric value.
-- from_button = true when a remapped BUTTON produced it: buttons fire once
-- per press, so the auto-repeat filter is skipped.
function PadNav:_trigger_event(axis, value, from_button)
    local tr = Trace.active()
    if self:_menu_trigger(axis, value, from_button) then
        if tr then
            Trace.log("padnav axis=%s value=%s: menu-branch handled -> result=true",
                tostring(axis), tostring(value))
        end
        return true
    end
    if not self:_is_enabled() then
        if tr then
            Trace.log("padnav axis=%s value=%s: passthrough, %s -> result=false",
                tostring(axis), tostring(value), self:_why_disabled())
        end
        return false
    end
    -- Triggers: 0..32767, only positive values are a press.
    local new_press = value > 0 and (from_button or self:_trigger_is_new_press(axis))
    local handler = "none"
    if new_press then
        -- Role-level action override (PC-014); idle reading context only.
        local role = axis == AXIS_LT and "lt" or "rt"
        local override = self:_override_action(role)
        if override then
            handler = "override:" .. override
            self:_run_action(override, role)
        elseif axis == AXIS_LT then
            handler = "onKPPgBk2"; self:onKPPgBk2()
        else
            handler = "onKPPgFwd2"; self:onKPPgFwd2()
        end
    end
    if tr then
        Trace.log("padnav axis=%s value=%s: trigger new_press=%s handler=%s swallowed -> result=true",
            tostring(axis), tostring(value), tostring(new_press), handler)
    end
    return true
end

-- Physical trigger remapped to a BUTTON role: one new press (auto-repeat
-- filtered on the physical axis) = one logical button down. Consumed while
-- kopad is switched on (stock has no mapping for axes 4/5 anyway).
function PadNav:_trigger_as_button(phys_axis, value, btn)
    if not (self.enabled_ref and self.enabled_ref.enabled) then return false end
    if value > 0 and self:_trigger_is_new_press(phys_axis) then
        Trace.log("padnav axis=%s: remapped to btn=%s", tostring(phys_axis), tostring(btn))
        self:_button_down({ button = btn })
    end
    return true
end

-- Entry point for the physical axis. Triggers (numeric value) are remapped
-- and handled above; sticks (and malformed events) continue below unchanged.
function PadNav:onGamepadAxisMotion(ax)
    local tr = Trace.active()
    if type(ax) == "table" and (ax.axis == AXIS_LT or ax.axis == AXIS_RT)
            and type(ax.value) == "number" then
        local kind, id = self:_resolve("axis", ax.axis)
        if kind == "button" then
            return self:_trigger_as_button(ax.axis, ax.value, id)
        end
        return self:_trigger_event(id, ax.value, false)
    end
    if not self:_is_enabled() then
        if tr then
            Trace.log("padnav axis=%s value=%s: passthrough, %s -> result=false",
                tostring(type(ax) == "table" and ax.axis), tostring(type(ax) == "table" and ax.value),
                self:_why_disabled())
        end
        return false
    end
    if type(ax) ~= "table" then return false end
    local axis, value = ax.axis, ax.value
    if axis == nil or value == nil then
        if tr then Trace.log("padnav axis=%s value=%s: incomplete event -> result=false",
            tostring(axis), tostring(value)) end
        return false
    end

    if axis == AXIS_LT or axis == AXIS_RT then
        -- Triggers: 0..32767, only positive values are a press.
        local new_press = value > 0 and self:_trigger_is_new_press(axis)
        if new_press then
            if axis == AXIS_LT then self:onKPPgBk2() else self:onKPPgFwd2() end
        end
        if tr then
            Trace.log("padnav axis=%s value=%s: trigger new_press=%s handler=%s swallowed -> result=true",
                tostring(axis), tostring(value), tostring(new_press),
                new_press and (axis == AXIS_LT and "onKPPgBk2" or "onKPPgFwd2") or "none")
        end
        return true
    end

    local pair = STICK_HANDLERS[axis]
    if not pair then
        if tr then Trace.log("padnav axis=%s value=%s: no stick mapping, passthrough -> result=false",
            tostring(axis), tostring(value)) end
        return false
    end
    local method = pair[value < 0 and 1 or 2]

    if (axis == AXIS_RX or axis == AXIS_RY) and self:_paged_idle() then
        local step = value < 0 and -1 or 1
        if tr then Trace.log("padnav axis=%s value=%s: paged pan", tostring(axis), tostring(value)) end
        self.ui:handleEvent(Event:new("Panning", axis == AXIS_RX and { step, 0 } or { 0, step }))
        return true
    end
    if axis == AXIS_RX or axis == AXIS_RY then
        -- Always consumed while kopad is active: stock maps R-stick Y to
        -- RPgBack/RPgFwd and auto-repeats it -> endless page turning. The
        -- handlers return false without a selector (FileManager / paged
        -- docs); we still swallow the event there.
        local handled = self[method](self)
        if tr then
            Trace.log("padnav axis=%s value=%s: handler=%s returned %s, swallowed -> result=true",
                tostring(axis), tostring(value), method, tostring(handled))
        end
        return true
    end

    -- L-stick. Without a selector (FileManager / paged docs) the L-stick
    -- handlers would eat the event as a no-op or a page turn, so let the stock
    -- Up/Down/Left/Right key through to the original list/page navigation.
    if not self:_selector() then
        if tr then
            Trace.log("padnav axis=%s value=%s: L-stick, no selector, passthrough -> result=false",
                tostring(axis), tostring(value))
        end
        return false
    end
    local result = self[method](self) or false
    if tr then
        Trace.log("padnav axis=%s value=%s: handler=%s -> result=%s",
            tostring(axis), tostring(value), method, tostring(result))
    end
    return result
end

local CHEAT_READING = _("Reading mode")
    .. "\nRT / LT: next / previous page"
    .. "\nRB / LB: next / previous page"
    .. "\nSelect: top menu    Start: footer menu"
    .. "\nA: sentence selector    Y: highlights"
    .. "\nD-pad: word walk    R-stick: crosshair"
    .. "\nX + D-pad: \xE2\x86\x91 menu  \xE2\x86\x93 footer  \xE2\x86\x90 history  \xE2\x86\x92 files"
    .. "\nX + LB: TOC    X + RB: bookmarks"
    .. "\n\n" .. _("PDF / DjVu")
    .. "\nD-pad \xE2\x86\x91/\xE2\x86\x93: zoom in / out"
    .. "\nD-pad \xE2\x86\x90/\xE2\x86\x92: whole page / text width"
    .. "\nR-stick: pan the page"
    .. "\n\n" .. _("Top menu open")
    .. "\nRB / LB: next / previous category"
    .. "\nRT / LT: next / previous page"

local CHEAT_SELECTION = _("Selection mode")
    .. "\nL-stick \xE2\x86\x90/\xE2\x86\x92: sentence    \xE2\x86\x91/\xE2\x86\x93: paragraph"
    .. "\nD-pad / R-stick: word navigation"
    .. "\nR-stick \xE2\x86\x91/\xE2\x86\x93: cycle highlights"
    .. "\nA: action menu    Y: Vortuyo"
    .. "\nX: toggle highlight    B: close / exit extend"
    .. "\nRB / LB: extend right / left"
    .. "\nRT / LT: close and turn page"
    .. "\nSelect / Start: close and open menu"
    .. "\n\n" .. _("Dictionary popup")
    .. "\nLB / RB: cycle dictionaries    Y: AI explain"

function PadNav:_show_text(text)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = text })
end

-- Role names as the docs write them, and the English action labels (the panel
-- in koligilo shows Polish ones); order = padmap.lua ROLES order.
local ROLE_LABELS = {
    "a", "b", "x", "y", "select", "start", "lb", "rb", "lt", "rt",
}
local ACTION_LABELS = {
    next_page         = _("next page"),
    prev_page         = _("previous page"),
    pages_forward_10  = _("10 pages forward"),
    pages_back_10     = _("10 pages back"),
    next_chapter      = _("next chapter"),
    prev_chapter      = _("previous chapter"),
    first_page        = _("first page"),
    last_page         = _("last page"),
    back_location     = _("back to previous location"),
    forward_location  = _("forward to next location"),
    goto_page         = _("go to page"),
    skim              = _("skim document"),
    top_menu          = _("top menu"),
    footer_menu       = _("footer menu"),
    config_menu       = _("bottom configuration menu"),
    toc               = _("table of contents"),
    bookmarks         = _("bookmarks"),
    toggle_bookmark   = _("toggle bookmark"),
    next_bookmark     = _("next bookmark"),
    prev_bookmark     = _("previous bookmark"),
    book_map          = _("book map"),
    page_browser      = _("page browser"),
    fulltext_search   = _("fulltext search"),
    book_status       = _("book status"),
    book_info         = _("book information"),
    reading_progress  = _("reading progress"),
    history           = _("history"),
    file_browser      = _("file browser"),
    last_book         = _("previous book"),
    favorites         = _("favorites"),
    collections       = _("collections"),
    sentence_select   = _("sentence selector"),
    highlights        = _("highlights"),
    word_walk         = _("word walk"),
    crosshair         = _("crosshair"),
    dict_lookup       = _("dictionary lookup"),
    font_bigger       = _("bigger font"),
    font_smaller      = _("smaller font"),
    zoom_in           = _("zoom in"),
    zoom_out          = _("zoom out"),
    zoom_fit_width    = _("fit text width"),
    zoom_fit_page     = _("fit whole page"),
    night_mode        = _("night mode"),
    rotate            = _("rotate screen"),
    full_refresh      = _("full screen refresh"),
    frontlight_toggle = _("frontlight on/off"),
    frontlight_up     = _("frontlight brighter"),
    frontlight_down   = _("frontlight dimmer"),
    screenshot        = _("screenshot"),
    cheat_sheet       = _("button cheat sheet"),
    x_modifier        = _("X modifier"),
    none              = _("nothing"),
}

-- The reading cheat sheet plus, when koligilo gave some roles other reading
-- actions (PC-014), one extra line per such role: the static text above
-- describes the defaults.
function PadNav:_cheat_reading()
    if not self._actions then return CHEAT_READING end
    local lines = {}
    for _i, role in ipairs(ROLE_LABELS) do
        local act = self._actions[role]
        if act then
            lines[#lines + 1] = "\n" .. role:upper() .. ": " .. (ACTION_LABELS[act] or act)
        end
    end
    if #lines == 0 then return CHEAT_READING end
    return CHEAT_READING .. "\n\n" .. _("Changed in koligilo (reading only)") .. table.concat(lines)
end

-- For tests/padmap_test.lua: every id of padmap.lua's ACTION_ORDER must have
-- a runner and a label.
PadNav._ACTION_RUNNERS = ACTION_RUNNERS
PadNav._ACTION_LABELS = ACTION_LABELS

function PadNav:getMenuItems()
    return {
        {
            text = _("Button cheat sheet: reading"),
            keep_menu_open = true,
            callback = function() self:_show_text(self:_cheat_reading()) end,
        },
        {
            text = _("Button cheat sheet: selection"),
            keep_menu_open = true,
            callback = function() self:_show_text(CHEAT_SELECTION) end,
        },
        {
            text = _("About kopad"),
            keep_menu_open = true,
            callback = function()
                self:_show_text(_("kopad: gamepad control for KOReader.\n\n")
                    .. self:_cheat_reading() .. "\n\n" .. CHEAT_SELECTION)
            end,
        },
    }
end

return PadNav
