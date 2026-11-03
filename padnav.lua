--[[
PadNav — gamepad reading controls for KOReader (active when kopad is enabled).
The on<Key> handlers below are the source of truth; keep this block, the
header of main.lua, README.md and CHEAT_READING/CHEAT_SELECTION in sync with them.

Reading:
  RT / LT (triggers)     Next / previous page (in the selection: paragraph)
  RB / LB                Next / previous page (X+RB = bookmarks, X+LB = TOC)
  L4 / R4 (back paddles) Same as LB / RB -- ONLY on old builds with
                         sdl3_gamepad.patch (key_events ScrollLock/Pause).
                         Not handled on KOReader >= 2026.07: SDL paddle ids
                         16+ have no stock mapping (Steam Input usually does
                         not expose them), so nothing arrives.
  Select                 Top menu          Start   Bottom menu (font,
                         margins, contrast, ...: ShowConfigMenu)
  B                      Back to the previous location (TOC entry, link, ...);
                         never KOReader's "Exit KOReader?" (Gamepad* path)
  A                      Select sentences (from the first one of the page)
  D-pad                  Select words: ↓/→ from the first word of the page,
                         ↑/← from the last one
  Y                      The page's saved highlights (D-pad steps between
                         them); none on the page = a message
  L-stick / R-stick      Nothing (consumed; TASK-12 / TASK-15)
  X (held)               Modifier: X + D-pad = ↑menu ↓footer ←history →files,
                         X + LB / RB = TOC / bookmarks. Gamepad* path: only
                         while X is held (TASK-16); legacy key path and a
                         trigger acting as X: a latch, spent by one combo.
                         Documents only; dropped as soon as the pad is used
                         anywhere but plain reading.

Context (PadNav:_context; Gamepad* path = KOReader >= 2026.07): what the pad
drives depends on the topmost non-toast window of the UIManager stack. The
reading / selection controls apply ONLY while that window is the reader
itself or kopad's selection overlay. Menus, dialogs, the dictionary popup and
the FileManager get the pad as stock KOReader keys plus the few additions
below -- nothing moves the document under them.

Top menu open (TouchMenu, reader AND FileManager):
  RB / LB                Next / previous CATEGORY (tab with icon), wrapping at
                         the ends. Consumed here, so the stock RPgFwd/RPgBack
                         key (= menu page turn) is NOT sent. Tabs that are
                         actions, not categories (remember == false or a tab
                         callback, e.g. the reader's "file browser" tab that
                         closes the book) are skipped.
  RT / LT                Next / previous PAGE of the menu (TouchMenu:onNextPage
                         / onPrevPage), one press = one page
  Select                 Close the menu (TouchMenu:closeMenu)
  D-pad / L-stick ←/→    On the tab bar: previous / next category at once
                         (stock only moves the focus and wants A)
  D-pad / L-stick / A / B / Start / R-stick
                         Otherwise stock: navigate / Press / Back / close
                         (stock "Menu" key) / menu page
  A category switch keeps the focus level: on the bar -> the new icon, in
  the items -> the first item of the new category. The current tab's icon is
  never inverted for the focus (its open-tab frame marks it already); another
  icon focused on the bar is (quiet_current_tab_focus, bottom menu too).
  Sticks in menus, lists, the dictionary popup and the FileManager drop
  release bounces (MENU_STICK_LOCK_S), which would move the focus back.

Other windows (TOC, bookmarks, history, config dialog, dialogs, book map, ...):
  RT / LT                Next / previous page of the list (Menu:onNextPage /
                         onPrevPage), when the window has pages
  Bottom menu (ConfigDialog: font, margins, contrast, ...):
    LB / RB              Previous / next tab (wrapping)
    D-pad / L-stick ←/→  On its tab bar (the bottom row): previous / next tab
                         at once; the focus level is kept as in the top menu
    Start                Close it (Start opened it)
  Start elsewhere        Swallowed
  Select / Guide / L3 / R3   Swallowed
  Everything else        Stock (the window navigates as without kopad)

Wheel (a ButtonDialog that wheel.lua drew as a radial menu, context "wheel",
checked before "foreign"):
  L-stick / R-stick      Point at a sector (8 directions, nearest sector;
                         wheel.lua polls the held axis directions)
  D-pad ←/↑ , →/↓        Previous / next sector
  A / X                  Run the selected button / its long-press action
  B                      Close (dlg:onClose, like stock Back)
  LB / RB, LT / RT       Previous / next page
  Everything else        Swallowed (the dialog's hidden button table must not
                         get stock keys)

FileManager (nothing on top of the file list):
  D-pad / A / sticks     Stock list navigation
  B                      Parent folder (stock asks "Exit KOReader?")
  LB / RB                Stock RPgBack / RPgFwd = previous / next list page
  RT / LT                Next / previous list page (file_chooser)
  Select                 Top menu

Selection (kopad's overlay; two levels, sentences "struct" and words "walk",
plus the saved highlights "hl" opened by Y):
  D-pad / L-stick ←/→    Words: word          Sentences: sentence
  D-pad / L-stick ↑/↓    Words: line          Sentences: paragraph
                         Highlights: previous / next one (all four)
                         Past the page edge: the next / previous page, both
                         directions (TASK-18). Held D-pad repeats (TASK-16)
                         and speeds up after a few steps (TASK-25).
  RT / LT                Next / previous paragraph (TASK-25): words = its first
                         word, sentences = as ↓/↑, highlights = next / previous;
                         back = start of this paragraph first. Over the page
                         edge; held, it keeps jumping; with A held = range.
  A held + arrows        Range from where A was pressed, both directions
                         (moving back over the anchor shrinks it); never
                         leaves the page (Gamepad* path, TASK-16)
  A tapped               Action menu (dict, AI, copy, note) -- on the release;
                         the A press that opened the selection does not
                         count. Legacy key path: on the press.
  R-stick ↓              Sentence -> its first word (walk)    (TASK-17)
  R-stick ↑              Word -> the sentence containing it (struct)
  R-stick ←/→            Nothing
  Y                      Vortuyo lookup
  X                      Toggle highlight (highlights: remove; the last one
                         removed closes the overlay)
  B                      Close
  RB / LB                Close and turn the page. Legacy key path: RB / LB
                         grow / shrink the range at its moving end instead
                         (no button release there, so no A hold)
  Select / Start         Close and open top / bottom menu

Dictionary popup:
  LB / RB                Cycle dictionaries (the popup's own RPgBack/RPgFwd)
  Y                      AI explain of kopad's selection (closes the popup;
                         passes when the popup was not opened from kopad)
  B / A / D-pad / sticks Stock (B closes the popup); RT / LT swallowed

Visel overlay (opt-in via pluginaro: visel.ext.kopad.gamepad_select):
  D-pad / L-stick ←/→   Move visel selection (as keyboard ←/→)
  RB / LB               Extend / trim selection (as Shift+→ / Shift+←)
  B                     Close visel

Scope: the selector (words / sentences / highlights) only exists for
crengine (rolling) documents. In paged documents (PDF/DjVu) no reader keys
are suppressed and the selector-dependent handlers return false
(pass-through); paged documents get their own view controls instead
(PAGED_* tables, _paged_idle; Gamepad* path only). Only LB/RB and LT/RT
change the page, always by a whole page:
  D-pad                  Pan the page slowly (never turns it)
  L-stick                Pan the page fast (never turns it)
  R-stick ↑ / ↓          Zoom in / out in small steps (ZOOM_STEP)
  R-stick ← / →          Fit whole page / fit text width (margins cropped)
  LB / RB, LT / RT       Previous / next page (GotoPage, view from the top)

Input paths (two, both end in the same on<Key> handlers):

1. KOReader >= 2026.07 (stock, NO patch / userpatch needed):
   frontend/device/sdl/device.lua broadcasts GamepadButtonDown {button} and
   GamepadAxisMotion {axis,value,time}; if a handler returns true the stock
   default key press (gamepad.lua button_key_names / axis_key_names) is NOT
   sent. onGamepadButtonDown / onGamepadAxisMotion below map SDL ids to the
   handlers; false = pass through to the stock default (kopad disabled, a
   menu / dialog / dictionary popup on top -- see Context above -- or a
   foreign overlay owning the screen).
   main.lua relays the broadcast here (PadNav lives in ui.active_widgets,
   which UIManager:broadcastEvent does not visit).
     Buttons (SDL ids): A=0 B=1 X=2 Y=3 Select=4 Start=6 LB=9 RB=10;
       D-pad 11..14: in an EPUB (reading / selection) kopad calls the KPUp2..
       handlers itself and repeats a held D-pad (stock buttons do not
       auto-repeat; DPAD_REPEAT_*); elsewhere it is passed through (stock
       sends Up/Down/Left/Right). Guide=5, L3=7, R3=8 are swallowed while
       kopad is active: stock maps them to RPgFwd / Menu / Menu, i.e.
       accidental page turns or menus from a stick click.
     Releases: GamepadButtonUp {button} is broadcast too (no stock key
       follows it); onGamepadButtonUp remaps it like the press and ends the
       A hold (range / tap = menu), the X hold and a D-pad repeat (TASK-16).
     Triggers: axis 4 = LT, axis 5 = RT. Stock has no mapping for them. One
       press = one page (in the top menu: one menu page): the stock
       auto-repeat (first repeat after 0.5 s, then every 0.2 s while held) is
       filtered out, see _trigger_is_new_press.
     Context first: _button_down / _trigger_event / onGamepadAxisMotion ask
       _context() before anything else and hand menus, other windows, the
       dictionary popup and the FileManager to _menu_button / _menu_trigger /
       _dict_button / _filemanager_button. _is_enabled() is true only in the
       reading contexts (PAD_CONTEXTS), so the on<Key> handlers -- also on the
       legacy key path -- stand down everywhere else.
     L-stick = axes 0 (x) / 1 (y), R-stick = axes 2 (x) / 3 (y); negative =
       left/up. The stock auto-repeat is kept on the sticks (handy for
       navigation). Stock maps R-stick Y to RPgBack/RPgFwd, which with the
       auto-repeat flips pages endlessly, so while kopad drives reading or a
       selection axes 2/3 are always consumed (axis 2 has no stock mapping);
       in an EPUB without a selection the L-stick is consumed as well (it
       does nothing there). In the selection both sticks drop release bounces
       (MENU_STICK_LOCK_S). In menus, dialogs, the dictionary popup and the
       FileManager both sticks are stock.

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
     applies only in the idle reading context -- context "reading" / "paged",
     no selection overlay and no X-combo (menus, dialogs, the dictionary
     popup and the FileManager never reach it, see Context). Anywhere
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
local BTN_DPAD_UP, BTN_DPAD_DOWN, BTN_DPAD_LEFT, BTN_DPAD_RIGHT = 11, 12, 13, 14
local AXIS_LX, AXIS_LY, AXIS_RX, AXIS_RY = 0, 1, 2, 3
local AXIS_LT, AXIS_RT = 4, 5

-- button id -> on<Key> handler (return value true = consumed).
local BUTTON_HANDLERS = {
    [BTN_A]      = "_press_a", -- a hold control (TASK-16); legacy Press = onKPConfirm
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

-- Contexts (PadNav:_context) in which PadNav's own handlers drive the pad.
-- In the others ("top_menu", "window", "dict", "foreign", "off") the pad
-- belongs to KOReader, apart from the few controls _menu_button /
-- _menu_trigger / _dict_button take. "wheel" (a ButtonDialog drawn as a
-- radial menu, wheel.lua) is driven entirely by _wheel_button / _wheel_*.
local PAD_CONTEXTS = {
    reading = true, paged = true, selection = true, filemanager = true,
}

-- D-pad on the Gamepad* path in an EPUB (see _button_down): handler per
-- button, and the repeat of a held D-pad in the selection (stock buttons do
-- not auto-repeat): first step after DPAD_REPEAT_DELAY_S, then every
-- DPAD_REPEAT_EVERY_S until the release, a context change or
-- DPAD_REPEAT_MAX steps (a lost release must not run forever). After
-- DPAD_ACCEL_AFTER repeats it speeds up (TASK-25): each interval is
-- DPAD_ACCEL times the previous one, down to DPAD_REPEAT_MIN_S.
local DPAD_HANDLERS = {
    [BTN_DPAD_UP] = "onKPUp2", [BTN_DPAD_DOWN] = "onKPDown2",
    [BTN_DPAD_LEFT] = "onKPLeft2", [BTN_DPAD_RIGHT] = "onKPRight2",
}
local DPAD_REPEAT_DELAY_S = 0.45
local DPAD_REPEAT_EVERY_S = 0.15
local DPAD_REPEAT_MAX     = 200
local DPAD_ACCEL_AFTER    = 5
local DPAD_ACCEL          = 0.8
local DPAD_REPEAT_MIN_S   = 0.05

-- Interval after repeat number `steps` (1 = the first repeat).
local function dpad_interval(steps)
    if steps < DPAD_ACCEL_AFTER then return DPAD_REPEAT_EVERY_S end
    return math.max(DPAD_REPEAT_MIN_S,
        DPAD_REPEAT_EVERY_S * DPAD_ACCEL ^ (steps - DPAD_ACCEL_AFTER + 1))
end

-- Paged documents (PDF/DjVu) have no selector, so there kopad steers the view
-- itself (see PadNav:_paged_idle). Only the bumpers and the triggers change
-- the page, always by a whole page (GotoPage, view from the top); every other
-- control stays on the current page, so nothing turns pages by surprise:
--   D-pad            pan slowly (PAGED_DPAD_PAN_STEP of the stock step)
--   L-stick          pan fast (stock ReaderPanning step = half a screen; the
--                    stick keeps moving while held); both bounded by the page
--   R-stick ↑ / ↓    zoom in / out in small steps (ZOOM_STEP; held, it keeps
--                    zooming);  ← / →  whole page / text width
-- ReaderPanning:onPanning moves dx/dy × half the visible area, so 0.2 = a
-- tenth of the screen per D-pad press.
local PAGED_DPAD_PAN_STEP = 0.2
local PAGED_PAN_DPAD = {
    [11] = { 0, -PAGED_DPAD_PAN_STEP }, [12] = { 0, PAGED_DPAD_PAN_STEP },
    [13] = { -PAGED_DPAD_PAN_STEP, 0 }, [14] = { PAGED_DPAD_PAN_STEP, 0 },
}
local PAGED_PAGE_BUTTONS = { [BTN_LB] = -1, [BTN_RB] = 1 }
-- R-stick X: { negative direction, positive direction } as event + arg
-- (R-stick Y zooms, see PadNav:_zoom_step)
local PAGED_RSTICK_X = { { "SetZoomMode", "page" }, { "SetZoomMode", "contentwidth" } }
-- One zoom step of the pad: KOReader's own Zoom event jumps ×1.33 / ×0.75.
local ZOOM_STEP = 1.03
-- Stick release bounce: SDL reports an axis only when it crosses the dead zone
-- (stock repeats carry ±5001), and a stick snapping back to centre often
-- crosses it once more on the far side or on the other axis (trace
-- 2026-11-03: zoom in, 8 ms later zoom out, then "whole page"). Each stick
-- keeps the direction of its last accepted event; a different direction
-- within STICK_LOCK_S of it is that bounce. 0.6 s covers the first stock
-- auto-repeat (0.5 s) plus the snap back.
local STICK_LOCK_S = 0.6
-- The same filter in menus, lists, the dictionary popup and the FileManager,
-- where the sticks otherwise stay stock: there a bounce would move the focus
-- back by one item or off the tab bar. Also in kopad's selection, where it
-- would undo a step or switch the level back. Shorter, so that a quick deliberate
-- reversal still works (bounces seen at 8-110 ms).
local MENU_STICK_LOCK_S = 0.2

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
        -- Select / Start: top menu / bottom menu (key names are an ASSUMPTION,
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

-- True when PadNav's own handlers may act: the current context (see
-- PadNav:_context) is reading, a paged document, kopad's selection overlay or
-- the FileManager. With a menu, the dictionary popup or any other window on
-- top (or kopad off / a foreign overlay) they stand down and return false.
function PadNav:_is_enabled()
    return PAD_CONTEXTS[self:_context()] or false
end

-- Why _is_enabled() is false. Trace output only; call it only when
-- Trace.active().
function PadNav:_why_disabled()
    return "context " .. self:_context()
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

-- Integration B (pluginaro): dictation into the focused text field through
-- diktonoti (`diktonoti.ext.kopad.gamepad_dictate`). Context "window" only
-- (the note InputDialog, any dialog with a text field): R3 starts / stops a
-- recording, B cancels a running one. With the toggle off, diktonoti absent,
-- or no focused text field (is_active nil/false) nothing is routed: R3 stays
-- swallowed and B stays the stock Back, as before.
function PadNav:_diktonoti_route(btn)
    if btn ~= BTN_R3 and btn ~= BTN_B then return false end
    local recording = Pluginaro.call_provided("diktonoti", "kopad", "gamepad_dictate", "is_recording")
    if btn == BTN_B then
        if not recording then return false end
        Pluginaro.call_provided("diktonoti", "kopad", "gamepad_dictate", "cancel")
        return true
    end
    if not (recording or Pluginaro.call_provided("diktonoti", "kopad", "gamepad_dictate", "is_active")) then
        return false
    end
    Pluginaro.call_provided("diktonoti", "kopad", "gamepad_dictate", "toggle")
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


-- Arrows in the selection overlay (D-pad, L-stick): dx / dy are screen
-- directions, dx flipped for RTL here; the overlay moves word / sentence /
-- highlight (step) or line / paragraph (line). While A is held (Gamepad*
-- path, TASK-16) the move extends a range from the anchor.
function PadNav:_sel_move(dx, dy)
    local selector = self:_selector()
    local ov = selector and selector.overlay
    if not ov then return end
    local range = self._a_down or false
    if range then self._a_moved = true end
    if self:_is_rtl() then dx = -dx end
    if dx ~= 0 then ov:step(dx, range) else ov:line(dy, range) end
end

-- L-stick: in the selection the same as the D-pad. While reading it does
-- nothing (TASK-12, TASK-15) but is consumed, so that the stock
-- Up/Down/Left/Right key it would become cannot open a word walk. Without a
-- selector (paged documents, FileManager) the key passes.
function PadNav:_lstick(dx, dy)
    if not self:_is_enabled() then return false end
    local selector = self:_selector()
    if not selector then return false end
    if selector.overlay then self:_sel_move(dx, dy) end
    return true
end

function PadNav:onKPUp()   return self:_lstick(0, -1) end
function PadNav:onKPDown() return self:_lstick(0, 1) end
function PadNav:onKPLeft()
    if self:_visel_route("move", -1) then return true end
    return self:_lstick(-1, 0)
end
function PadNav:onKPRight()
    if self:_visel_route("move", 1) then return true end
    return self:_lstick(1, 0)
end

-- A combo of the X modifier. While X is held (Gamepad* path, _x_hold) it
-- stays armed for the next combo; the latch (legacy key path, a trigger
-- acting as X) is spent by one combo.
function PadNav:_x_combo(action_fn)
    if not self._x_hold then self._x_mode = false end
    action_fn()
end

-- D-pad: arrows in the selection, else open the word level: ↓/→ on the first
-- word of the page, ↑/← on the last one.
function PadNav:_dpad(dx, dy)
    local selector = self:_selector()
    if selector.overlay then
        self:_sel_move(dx, dy); return
    end
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

-- The sentence level, from the first sentence of the page (A while reading,
-- the `sentence_select` action).
function PadNav:_open_sentence_select()
    local selector = self:_selector()
    if selector and not selector.overlay then selector:_open() end
end

-- R-stick: switches the selection level (TASK-17): ↓ sentence -> its first
-- word, ↑ word -> the sentence containing it; ←/→ nothing. While reading it
-- does nothing (TASK-15). Consumed whenever a selector exists.
function PadNav:_rstick(dy)
    if not self:_is_enabled() then return false end
    local selector = self:_selector()
    if not selector then return false end
    local ov = selector.overlay
    if ov then
        if dy > 0 then ov:to_words() elseif dy < 0 then ov:to_sentences() end
    end
    return true
end

function PadNav:onKPRStickUp()    return self:_rstick(-1) end
function PadNav:onKPRStickDown()  return self:_rstick(1) end
function PadNav:onKPRStickLeft()  return self:_rstick(0) end
function PadNav:onKPRStickRight() return self:_rstick(0) end

-- X: highlight toggle (overlay) or combo modifier (reading)
function PadNav:onKPExtend()
    if not self:_is_enabled() then return false end
    local selector = self:_selector()
    local ov = selector and selector.overlay
    if ov then
        local sel = ov:_get_selection()
        if sel then ov:_do_toggle_highlight(sel) end
        -- browsing highlights and the page's last one removed: done
        if ov.mode == "hl" and ov.hl_cur == 0 then selector:_close() end
        return true
    end
    -- The modifier only exists in a document: in the FileManager the stock
    -- list navigation eats the arrows, so X + D-pad could never fire there.
    if not (self.ui and self.ui.document) then return false end
    self._x_mode = not self._x_mode
    return true
end

-- RB: X+RB = bookmarks, next page (reading). In the selection only the legacy
-- key path gets here (the Gamepad* path turns the page in _button_down): it
-- has no button release, so no A hold -- RB grows the range at its moving end
-- instead (LB shrinks it), in document order.
function PadNav:onKPPgFwd()
    if self:_visel_route("extend", 1) then return true end
    if not self:_is_enabled() then return false end
    if self._x_mode then
        self:_x_combo(function() self.ui:handleEvent(Event:new("ShowBookmark")) end)
        return true
    end
    local selector = self:_selector()
    if selector and selector.overlay then
        selector.overlay:step(1, true); return true
    end
    self.ui:handleEvent(Event:new("GotoViewRel", 1)); return true
end

-- LB: X+LB = TOC, previous page (reading); legacy range step (see onKPPgFwd).
function PadNav:onKPPgBk()
    if self:_visel_route("extend", -1) then return true end
    if not self:_is_enabled() then return false end
    if self._x_mode then
        self:_x_combo(function() self.ui:handleEvent(Event:new("ShowToc")) end)
        return true
    end
    local selector = self:_selector()
    if selector and selector.overlay then
        selector.overlay:step(-1, true); return true
    end
    self.ui:handleEvent(Event:new("GotoViewRel", -1)); return true
end

-- LT/RT while reading (and LB/RB in the selection on the Gamepad* path): page
-- turn, closing the selection. GotoViewRel +1 = next page (KOReader
-- semantics, same in RTL books: "next" is reading order, so no _is_rtl() flip
-- here -- triggers are semantic, not spatial).
function PadNav:_turn_page(dir)
    local selector = self:_selector()
    if selector and selector.overlay then selector:_close() end
    self._x_mode = false
    self.ui:handleEvent(Event:new("GotoViewRel", dir)); return true
end
-- LT/RT in the selection (TASK-25): one paragraph back / forward at every
-- level (Selector:para); with A held the range grows by paragraphs. Also
-- reading order, no RTL flip.
function PadNav:_trigger_page(dir)
    local selector = self:_selector()
    local ov = selector and selector.overlay
    if not ov then return self:_turn_page(dir) end
    local range = self._a_down or false
    if range then self._a_moved = true end
    ov:para(dir, range)
    return true
end
function PadNav:onKPPgBk2()
    if not self:_is_enabled() then return false end
    return self:_trigger_page(-1)
end
function PadNav:onKPPgFwd2()
    if not self:_is_enabled() then return false end
    return self:_trigger_page(1)
end

-- Select: top menu. Start: bottom menu (ReaderConfig's ConfigDialog: font,
-- margins, contrast, ...). No X modifier needed; the footer mode toggle
-- stays on X + D-pad ↓.
function PadNav:_menu_action(fn)
    local selector = self:_selector()
    if selector and selector.overlay then selector:_close() end
    self._x_mode = false
    fn()
    return true
end
function PadNav:onKPSelect()
    if not self:_is_enabled() then return false end
    return self:_menu_action(function()
        self.ui:handleEvent(Event:new("ShowMenu"))
    end)
end
function PadNav:onKPStart()
    if not self:_is_enabled() then return false end
    return self:_menu_action(function()
        self.ui:handleEvent(Event:new("ShowConfigMenu"))
    end)
end
function PadNav:onKPPgBk3()  return self:onKPPgBk()  end
function PadNav:onKPPgFwd3() return self:onKPPgFwd() end

-- A on the LEGACY key path (Press): sentence selection (reading), action menu
-- at once (overlay). On the Gamepad* path A is _press_a / _release_a.
function PadNav:onKPConfirm()
    if not self:_is_enabled() then return false end

    local selector = self:_selector()
    if selector and selector.overlay then
        selector.overlay:action_menu()
        return true
    end
    -- No selector (paged doc / FileManager): Press bindings are not
    -- suppressed there — pass through so e.g. FileManager item selection works.
    if not selector then return false end
    self:_open_sentence_select()
    return true
end

-- A pressed (Gamepad* path, TASK-16). Reading: open the sentence level; its
-- release opens nothing. Selection: while held, the arrows select a range
-- (_sel_move); released without an arrow = a tap = the action menu, see
-- _release_a.
function PadNav:_press_a()
    if not self:_is_enabled() then return false end
    local selector = self:_selector()
    if not selector then return false end
    self._a_down, self._a_moved = true, false
    self._a_opened = not selector.overlay
    if self._a_opened then self:_open_sentence_select() end
    return true
end

-- A released (Gamepad* path): a tap in the selection opens the action menu.
-- A range selected while A was held stays the selection.
function PadNav:_release_a()
    if not self._a_down then return end
    local tap = not self._a_moved and not self._a_opened
    self._a_down, self._a_moved, self._a_opened = false, false, false
    local selector = self:_selector()
    local ov = selector and selector.overlay
    if tap and ov and self:_context() == "selection" then ov:action_menu() end
end

-- B: close the overlay
function PadNav:onKPBack()
    if self:_visel_route("close") then return true end
    if not self:_is_enabled() then return false end

    local selector = self:_selector()
    if selector and selector.overlay then
        selector:_close()
        return true
    end
    -- Stock Back in the reader ends in "Exit KOReader?" once the location
    -- history is empty (ReaderBack); a few B presses must not quit. B goes
    -- back to the previous location only (TOC entry, link, skim ...);
    -- ReaderLink shows "Location history is empty" when there is none.
    if self.ui and self.ui.document then
        local link = self.ui.link
        if link and type(link.onGoBackLink) == "function" then
            link:onGoBackLink(true)
        end
        return true
    end
    return false
end

-- Y: Vortuyo (overlay) or the page's highlights (reading)
-- When dict is open, Y→AI is handled by _hook_dict_widget on the dict widget itself.
function PadNav:onKPMenu()
    if not self:_is_enabled() then return false end

    local selector = self:_selector()
    -- No selector (paged doc / FileManager): pass through, don't eat the key.
    if not selector then return false end
    local ov = selector.overlay
    if ov then
        local sel = ov:_get_selection()
        if sel then ov:_do_vortuyo(sel) end
        return true
    end
    self:_open_highlights(selector)
    return true
end

-- The page's saved highlights (TASK-15): the overlay in mode "hl" on the
-- first one, the D-pad steps between them; none on the page = a short
-- message. Y in reading, and the `highlights` action (ACTION_RUNNERS).
function PadNav:_open_highlights(selector)
    if selector:_open_highlights() == false then
        self:_show_text(_("No highlights on this page"), 2)
    end
end

-- Held D-pad in the selection (Gamepad* path): repeat the step of button
-- `btn` until its release (onGamepadButtonUp), a context change (menu,
-- dialog, overlay closed) or DPAD_REPEAT_MAX steps.
function PadNav:_dpad_start(btn)
    self:_dpad_stop()
    if type(UIManager.scheduleIn) ~= "function" then return end
    local steps = 0
    local tick
    tick = function()
        if self._dpad_tick ~= tick then return end
        steps = steps + 1
        if steps > DPAD_REPEAT_MAX or self:_context() ~= "selection" then
            self:_dpad_stop(); return
        end
        self[DPAD_HANDLERS[btn]](self)
        UIManager:scheduleIn(dpad_interval(steps), tick)
    end
    self._dpad_held, self._dpad_tick = btn, tick
    UIManager:scheduleIn(DPAD_REPEAT_DELAY_S, tick)
end

function PadNav:_dpad_stop()
    if self._dpad_tick and type(UIManager.unschedule) == "function" then
        UIManager:unschedule(self._dpad_tick)
    end
    self._dpad_held, self._dpad_tick = nil, nil
end

-- KOReader >= 2026.07 broadcasts the release too (device.lua; no stock key
-- follows it, so the return value does not matter). Remapped like the
-- press, so the role that was pressed is the role released (TASK-16): ends
-- a D-pad repeat, the X hold (the modifier drops) and the A hold (a tap
-- opens the action menu).
function PadNav:onGamepadButtonUp(ev)
    if type(ev) ~= "table" or ev.button == nil then return false end
    local kind, btn = self:_resolve("button", ev.button)
    if kind ~= "button" then return false end
    if Trace.active() then
        Trace.log("padnav btn=%s up: role=%s", tostring(ev.button), tostring(btn))
    end
    if self._dpad_held == btn then self:_dpad_stop() end
    if self._x_hold == btn then
        self._x_hold, self._x_mode = nil, false
    end
    if btn == BTN_A then self:_release_a() end
    return false
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
    sentence_select   = with_selector(function(self) self:_open_sentence_select() end),
    highlights        = with_selector(function(self, selector) self:_open_highlights(selector) end),
    word_walk         = with_selector(function(self, selector) selector:_open_walk(false) end),
    -- The crosshair is gone (TASK-15); the id stays in the vocabulary (the
    -- koligilo contract) and opens the word level.
    crosshair         = with_selector(function(self, selector) selector:_open_walk(false) end),
    dict_lookup       = ui_event("ShowDictionaryLookup"),
    -- display
    font_bigger       = ui_event("IncreaseFontSize", 1),
    font_smaller      = ui_event("DecreaseFontSize", 1),
    zoom_in           = function(self) self:_zoom_step(1) end,
    zoom_out          = function(self) self:_zoom_step(-1) end,
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
-- stay on the built-in handlers; only the modifier may be pressed again) and
-- no selection overlay. (Menus, other windows and the dictionary popup never
-- reach it, see PadNav:_context.)
function PadNav:_override_action(role)
    local act = role and self._actions and self._actions[role]
    if not act then return nil end
    if not (self.ui and self.ui.document) then return nil end
    if self._x_mode and act ~= "x_modifier" then return nil end
    local selector = self:_selector()
    if selector and selector.overlay then return nil end
    return act
end

-- True when the pad should steer a paged document's view (PAGED_* tables):
-- context "paged" (a PDF/DjVu with nothing on top of it: no menu, dialog or
-- dictionary popup) and no X-combo pending (X + D-pad keeps its menus).
function PadNav:_paged_idle()
    if self:_context() ~= "paged" then return false end
    if self._x_mode then return false end
    return true
end

-- Whole page back/forward in a paged document (GotoViewRel would walk the
-- views of a zoomed page first); _gotoPage clamps to the document.
function PadNav:_paged_page(dir)
    local cur = self.ui.paging.current_page
    if type(cur) ~= "number" then return end
    self.ui:handleEvent(Event:new("GotoPage", cur + dir))
end

-- Panning shifts view.visible_area, which continuous view (KOReader's default
-- for PDF) ignores, and scrolling there would run into the next page anyway.
-- So the first pan switches the document to page view; KOReader saves that
-- with the document (kopt_page_scroll).
function PadNav:_paged_pan(dx, dy)
    if self.ui.view and self.ui.view.page_scroll then
        self.ui:handleEvent(Event:new("SetScrollMode", false))
    end
    self.ui:handleEvent(Event:new("Panning", { dx, dy }))
end

-- True for a release bounce of a stick: a different direction within
-- `lock_s` (default STICK_LOCK_S, paged documents) of the last accepted one.
function PadNav:_stick_bounce(axis, neg, lock_s)
    local stick = (axis == AXIS_LX or axis == AXIS_LY) and "l" or "r"
    local dir = axis * 2 + (neg and 1 or 0)
    local now = time.to_s(time.now())
    self._stick_dir = self._stick_dir or {}
    local st = self._stick_dir[stick]
    if st and st.dir ~= dir and now - st.t < (lock_s or STICK_LOCK_S) then return true end
    self._stick_dir[stick] = { dir = dir, t = now }
    return false
end

-- Zoom by ZOOM_STEP (dir 1 = in, -1 = out) instead of KOReader's Zoom event,
-- so the stick zooms gradually. Same steps as ReaderZooming:onZoom; nothing
-- happens without a paged document (EPUB, FileManager).
function PadNav:_zoom_step(dir)
    local z = self.ui.paging and self.ui.zooming
    if not (z and type(z.zoom) == "number" and self.ui.view) then return end
    z.zoom = z.zoom * (dir > 0 and ZOOM_STEP or 1 / ZOOM_STEP)
    z:onSetZoomMode("free")
    self.ui.view:onZoomUpdate(z.zoom)
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

-- LOGICAL button down (after remapping). A press that arms the X modifier
-- (X, or a role whose action is x_modifier) makes it a hold: the release of
-- that role ends it (onGamepadButtonUp, TASK-16). latch = true for a trigger
-- acting as a button, which never reports a release: the modifier stays a
-- latch then.
function PadNav:_button_down(ev, latch)
    local x_before = self._x_mode
    local res = self:_button_dispatch(ev)
    if self._x_mode and not x_before then
        self._x_hold = (not latch) and type(ev) == "table" and ev.button or nil
    end
    return res
end

function PadNav:_button_dispatch(ev)
    local tr = Trace.active()
    local btn = type(ev) == "table" and ev.button or nil
    local ctx = self:_context()
    self:_drop_x_mode(ctx)
    -- A menu or another window on top: the pad belongs to it (_menu_button
    -- takes LB/RB and Select in the top menu, the rest is stock).
    if ctx == "top_menu" or ctx == "window" then
        local res = self:_menu_button(btn, ctx)
        if tr then Trace.log("padnav btn=%s: context %s -> result=%s", tostring(btn), ctx, tostring(res)) end
        return res
    end
    if ctx == "filemanager" then
        local res = self:_filemanager_button(btn)
        if tr then Trace.log("padnav btn=%s: context filemanager -> result=%s", tostring(btn), tostring(res)) end
        return res
    end
    if ctx == "dict" then
        local res = self:_dict_button(btn)
        if tr then Trace.log("padnav btn=%s: context dict -> result=%s", tostring(btn), tostring(res)) end
        return res
    end
    if ctx == "wheel" then
        self:_wheel_button(btn)
        if tr then Trace.log("padnav btn=%s: context wheel -> result=true", tostring(btn)) end
        return true
    end
    if not PAD_CONTEXTS[ctx] then
        if tr then Trace.log("padnav btn=%s: passthrough, context %s -> result=false", tostring(btn), ctx) end
        return false
    end
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
    local pan, page = PAGED_PAN_DPAD[btn], PAGED_PAGE_BUTTONS[btn]
    if (pan or page) and self:_paged_idle() then
        if tr then Trace.log("padnav btn=%s: paged %s", tostring(btn), pan and "pan" or "page") end
        if pan then self:_paged_pan(pan[1], pan[2]) else self:_paged_page(page) end
        return true
    end
    -- In the selection LB / RB close it and turn the page (TASK-16); the
    -- range steps of onKPPgBk / onKPPgFwd belong to the legacy key path.
    if (btn == BTN_LB or btn == BTN_RB) and ctx == "selection" then
        if tr then Trace.log("padnav btn=%s: selection, close and turn the page", tostring(btn)) end
        return self:_turn_page(btn == BTN_RB and 1 or -1)
    end
    -- D-pad in an EPUB: kopad's own handlers, and a held D-pad repeats its
    -- step in the selection (stock buttons do not auto-repeat). Not after an
    -- X combo (it must fire once). Without a selector the stock key passes.
    local dpad = DPAD_HANDLERS[btn]
    if dpad and (ctx == "reading" or ctx == "selection") and self:_selector() then
        local combo = self._x_mode
        local handled = self[dpad](self) or false
        local selector = self:_selector()
        if handled and not combo and selector and selector.overlay then self:_dpad_start(btn) end
        if tr then Trace.log("padnav btn=%s: dpad %s -> result=%s", tostring(btn), dpad, tostring(handled)) end
        return handled
    end
    local method = BUTTON_HANDLERS[btn]
    local handled = method and self[method](self) or false
    -- D-pad (11..14) without a selector and the rest: false -> stock key.
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

-- Context of the pad = the topmost window on the UIManager stack that is not a
-- toast (Notification). Positive rule: kopad steers the document only when
-- that window is the reader / FileManager itself (self.ui) or kopad's own
-- selection overlay. Pluginaro.is_modal_active() is not enough: it only
-- looks at the class of the top window, and KOReader wraps the top menu
-- (ReaderMenu / FileManagerMenu), the TOC and the bookmark list in a
-- CenterContainer, while ConfigDialog and many full-screen widgets are no
-- modal class at all -- the pad would then drive the page under the menu.
--   "off"          kopad switched off
--   "foreign"      a FOREIGN family overlay (visel / hilite) owns the screen
--                  (kopad's own claim does not count, see selector._open*)
--   "reading"      a reflowable document (EPUB, ...), nothing on top
--   "paged"        a paged document (PDF / DjVu), nothing on top
--   "filemanager"  the file browser, nothing on top
--   "selection"    kopad's selection overlay on top
--   "dict"         the dictionary popup (DictQuickLookup) on top
--   "top_menu"     the top menu (TouchMenu) on top, reader or FileManager
--   "window"       anything else: TOC, bookmarks, history, config dialog,
--                  dialogs, book map, ... -- the pad belongs to it
--   "wheel"        a ButtonDialog that wheel.lua turned into a radial menu
--                  (dlg._kopad_wheel). Checked before "foreign": the wheel
--                  has no stock key navigation left, so it is always ours.
local MENU_SEARCH_DEPTH = 3

-- Depth-limited search of a window's widget tree (children = array part)
-- for the first widget `pred` accepts; `seen` guards against cycles.
local function find_in(w, pred, depth, seen)
    if type(w) ~= "table" or seen[w] then return nil end
    seen[w] = true
    if pred(w) then return w end
    if depth <= 0 then return nil end
    for i = 1, #w do
        local m = find_in(w[i], pred, depth - 1, seen)
        if m then return m end
    end
    return nil
end

-- TouchMenu, duck-typed (FileManager's `ui` has no ui.menu like the reader's).
local function is_touch_menu(w)
    return type(w.tab_item_table) == "table" and type(w.switchMenuTab) == "function"
end

-- Anything with pages to turn: Menu (TOC, bookmarks, history, ...), TouchMenu.
local function is_pager(w)
    return type(w.onNextPage) == "function" and type(w.onPrevPage) == "function"
end

-- The dictionary popup. DictQuickLookup has no `name` field; every open one
-- is listed in the class-level DictQuickLookup.window_list. (`name` is kept
-- as a fallback for builds / tests that set it.)
local function is_dict_window(w)
    if type(w) ~= "table" then return false end
    if w.name == "DictQuickLookup" then return true end
    local ok, DQL = pcall(require, "ui/widget/dictquicklookup")
    if ok and type(DQL) == "table" and type(DQL.window_list) == "table" then
        for _, d in ipairs(DQL.window_list) do
            if d == w then return true end
        end
    end
    return false
end

local function top_window()
    local stack = UIManager._window_stack
    if type(stack) ~= "table" then return nil end
    for i = #stack, 1, -1 do
        local w = stack[i] and stack[i].widget
        if type(w) == "table" and not w.toast then return w end
    end
    return nil
end

-- ReaderConfig's bottom menu, duck-typed (a FocusManager, not a modal class).
local function is_config_dialog(w)
    return type(w.config_options) == "table" and type(w.closeDialog) == "function"
end

local function find_touch_menu()
    local top = top_window()
    return top and find_in(top, is_touch_menu, MENU_SEARCH_DEPTH, {}) or nil
end

local function find_config_dialog()
    local top = top_window()
    return top and find_in(top, is_config_dialog, MENU_SEARCH_DEPTH, {}) or nil
end

-- The wheel controller of a ButtonDialog converted by wheel.lua, else nil.
local function wheel_of(w)
    local c = type(w) == "table" and rawget(w, "_kopad_wheel")
    return type(c) == "table" and c or nil
end

function PadNav:_context()
    if not (self.enabled_ref and self.enabled_ref.enabled) then return "off" end
    local top = top_window()
    if wheel_of(top) then return "wheel" end
    if Pluginaro.overlay_active(self.ui, "kopad") then return "foreign" end
    -- No stack (bare Lua tests) counts as the reader / FileManager itself.
    if top == nil or top == self.ui then
        local ui = self.ui
        if not (ui and ui.document) then return "filemanager" end
        if ui.paging and not ui.rolling then return "paged" end
        return "reading"
    end
    local selector = self:_selector()
    if selector and selector.overlay and top == selector.overlay then return "selection" end
    if is_dict_window(top) then return "dict" end
    if find_in(top, is_touch_menu, MENU_SEARCH_DEPTH, {}) then return "top_menu" end
    return "window"
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

-- Switch the TouchMenu `dir` categories (menu_tab_step) and keep the focus on
-- the same level, visibly: on the tab bar -> the new tab's icon, in the items
-- -> the first item of the new tab. (Stock resets it, invisibly, to the bar:
-- the next A would re-open the tab and the next D-pad press lands elsewhere.)
-- True when the TouchMenu focus is on its tab bar (FocusManager layout row 1;
-- the items are the rows below).
local function menu_focus_on_bar(menu)
    local sel = type(menu.selected) == "table" and menu.selected or nil
    return not (sel and type(sel.y) == "number" and sel.y > 1)
end

-- The bottom menu (ConfigDialog): its tab bar (MenuBar icons) is the LAST
-- FocusManager layout row, the option rows are above it.
local function config_focus_on_bar(dlg)
    local sel = type(dlg.selected) == "table" and dlg.selected or nil
    local rows = type(dlg.layout) == "table" and #dlg.layout or 0
    return not (sel and type(sel.y) == "number" and sel.y < rows)
end

-- Switch the bottom menu `dir` tabs (wrapping; ShowConfigPanel, like a tap on
-- the icon) and keep the focus level, visibly: on the bar -> the new icon, in
-- the options -> the first option row. (Stock update() parks the focus,
-- invisibly, on the bar.)
local function config_switch_tab(dlg, dir)
    local n = type(dlg.config_options) == "table" and #dlg.config_options or 0
    if n < 2 or type(dlg.onShowConfigPanel) ~= "function" then return false end
    local on_bar = config_focus_on_bar(dlg)
    local k = ((tonumber(dlg.panel_index) or 1) - 1 + dir) % n + 1
    dlg:onShowConfigPanel(k)
    if type(dlg.moveFocusTo) == "function" and type(dlg.layout) == "table" and #dlg.layout > 0 then
        if on_bar or #dlg.layout < 2 then dlg:moveFocusTo(k, #dlg.layout) else dlg:moveFocusTo(1, 1) end
    end
    return true
end

-- Tab bars (top and bottom menu): the current tab is already drawn as an
-- open tab (frame around its icon); the stock focus invert on top of that
-- clashes. Wrap each bar icon's onFocus once so the CURRENT tab's icon is not
-- inverted -- any other icon focused by stock navigation still is, so the
-- cursor stays visible where it is not on the current tab.
local function quiet_current_tab_focus(icons, is_current, parent)
    if type(icons) ~= "table" then return end
    local cleared = false
    for k, ib in ipairs(icons) do
        if type(ib) == "table" and not rawget(ib, "_kopad_quiet_focus") and type(ib.onFocus) == "function" then
            local stock = ib.onFocus
            ib._kopad_quiet_focus = true
            ib.onFocus = function(self, ...)
                if is_current(k) then
                    if type(self.image) == "table" then self.image.invert = false end
                    return true
                end
                return stock(self, ...)
            end
            -- already inverted by an earlier focus: undo it on the current tab
            if is_current(k) and type(ib.image) == "table" and ib.image.invert then
                ib.image.invert = false; cleared = true
            end
        end
    end
    if cleared and parent then UIManager:setDirty(parent, "ui") end
end

local function menu_switch_tab(menu, dir)
    local on_bar = menu_focus_on_bar(menu)
    if not menu_tab_step(menu, dir) then return false end
    if type(menu.moveFocusTo) == "function" and type(menu.layout) == "table" then
        local row = (not on_bar and menu.layout[2]) and 2 or 1
        menu:moveFocusTo(menu.cur_tab, row)
    end
    return true
end

-- The top menu (TouchMenu) when kopad should drive it, else nil: kopad
-- switched on, no FOREIGN family overlay, a TouchMenu in the top window.
function PadNav:_top_menu()
    if not (self.enabled_ref and self.enabled_ref.enabled) then return nil end
    if Pluginaro.overlay_active(self.ui, "kopad") then return nil end
    local ok, menu = pcall(find_touch_menu)
    return ok and menu or nil
end

-- No focus invert on the current tab's icon (quiet_current_tab_focus) in the
-- top menu (ctx "top_menu") and the bottom menu (ConfigDialog, ctx "window").
-- Installed lazily on the first pad event in the menu, before stock moves the
-- focus.
function PadNav:_quiet_tab_focus(ctx)
    local ok, err = pcall(function()
        if ctx == "top_menu" then
            local menu = self:_top_menu()
            local bar = menu and menu.bar
            if type(bar) == "table" then
                quiet_current_tab_focus(bar.icon_widgets, function(k) return menu.cur_tab == k end, menu)
            end
        elseif ctx == "window" then
            local dlg = find_config_dialog()
            local bar = dlg and dlg.config_menubar
            if type(bar) == "table" then
                quiet_current_tab_focus(bar.menu_items, function(k) return dlg.panel_index == k end, dlg)
            end
        end
    end)
    if not ok then logger.warn("kopad: tab focus wrap failed: " .. tostring(err)) end
end

-- Buttons (logical role id) while a menu or another window is on top
-- (ctx "top_menu" / "window"). Returns true = consumed, false = the stock key
-- goes to the menu. Rule: in menus the pad is KOReader's (D-pad / A / B /
-- L-stick navigate as stock); kopad only adds
--   top menu: LB / RB = previous / next category (buttons do not
--             auto-repeat, so no filter; the stock RPgBack/RPgFwd = menu page
--             turn is not sent), Select = close the menu (Select opened it).
--             Start passes: its stock key "Menu" closes a TouchMenu too.
--   window:   bottom menu (ConfigDialog): LB / RB = previous / next tab, D-pad
--             ←/→ on its tab bar too (config_switch_tab, focus level kept);
--             Start closes it (Start opened it; stock closes only on Back).
--   both:     BUTTON_SWALLOW (stick clicks, Guide, Select / Start elsewhere)
--             would send surprising stock keys, so they are eaten.
function PadNav:_menu_button(btn, ctx)
    self:_quiet_tab_focus(ctx)
    if ctx == "top_menu" then
        if btn == BTN_LB or btn == BTN_RB then
            local menu = self:_top_menu()
            if menu then
                local ok, err = pcall(menu_switch_tab, menu, btn == BTN_RB and 1 or -1)
                if not ok then logger.warn("kopad: menu tab switch failed: " .. tostring(err)) end
                Trace.log("padnav btn=%s: menu tab step ok=%s err=%s", tostring(btn), tostring(ok), tostring(err))
            end
            return true
        end
        -- D-pad ←/→ on the tab bar switches the tab at once (stock only moves
        -- the focus between the icons and wants A to open one). In the items
        -- they stay stock.
        if btn == BTN_DPAD_LEFT or btn == BTN_DPAD_RIGHT then
            local menu = self:_top_menu()
            if not (menu and menu_focus_on_bar(menu)) then return false end
            local ok, err = pcall(menu_switch_tab, menu, btn == BTN_DPAD_RIGHT and 1 or -1)
            if not ok then logger.warn("kopad: menu tab switch failed: " .. tostring(err)) end
            Trace.log("padnav btn=%s: menu tab step (bar) ok=%s err=%s", tostring(btn), tostring(ok), tostring(err))
            return true
        end
        if btn == BTN_SELECT then
            local menu = self:_top_menu()
            if menu and type(menu.closeMenu) == "function" then
                local ok, err = pcall(menu.closeMenu, menu)
                if not ok then logger.warn("kopad: menu close failed: " .. tostring(err)) end
            end
            return true
        end
        if btn == BTN_START then return false end
    elseif ctx == "window" then
        if self:_diktonoti_route(btn) then return true end
        local dlg = find_config_dialog()
        if not dlg then return BUTTON_SWALLOW[btn] or false end
        if btn == BTN_START then
            local ok, err = pcall(dlg.closeDialog, dlg)
            if not ok then logger.warn("kopad: config menu close failed: " .. tostring(err)) end
            return true
        end
        local dir
        if btn == BTN_LB or btn == BTN_RB then
            dir = btn == BTN_RB and 1 or -1
        elseif (btn == BTN_DPAD_LEFT or btn == BTN_DPAD_RIGHT) and config_focus_on_bar(dlg) then
            dir = btn == BTN_DPAD_RIGHT and 1 or -1
        end
        if dir then
            local ok, err = pcall(config_switch_tab, dlg, dir)
            if not ok then logger.warn("kopad: config tab switch failed: " .. tostring(err)) end
            Trace.log("padnav btn=%s: config tab step ok=%s err=%s", tostring(btn), tostring(ok), tostring(err))
            return true
        end
    end
    return BUTTON_SWALLOW[btn] or false
end

-- LT / RT while a menu or another window is on top, or in the FileManager:
-- previous / next page of the top menu, of the file list (file_chooser), or
-- of the first pager (Menu: TOC, bookmarks, ...) in the top window. One press = one page (_trigger_is_new_press); auto-repeats and
-- windows without pages are consumed without action (stock has no trigger
-- mapping anyway).
function PadNav:_menu_trigger(axis, value, from_button, ctx)
    local target
    if ctx == "top_menu" then
        target = self:_top_menu()
    elseif ctx == "filemanager" then
        target = self.ui and self.ui.file_chooser
        if not (type(target) == "table" and is_pager(target)) then
            target = self.ui and find_in(self.ui, is_pager, MENU_SEARCH_DEPTH, {}) or nil
        end
    else
        local top = top_window()
        target = top and find_in(top, is_pager, MENU_SEARCH_DEPTH, {}) or nil
    end
    if value > 0 and (from_button or self:_trigger_is_new_press(axis)) and target then
        local method = axis == AXIS_RT and "onNextPage" or "onPrevPage"
        if type(target[method]) == "function" then
            local ok, err = pcall(target[method], target)
            if not ok then
                logger.warn("kopad: menu page turn failed: " .. tostring(err))
            end
        end
    end
end

-- The X modifier belongs to plain reading: anywhere else (menu, dialog,
-- dictionary, selection overlay, FileManager) a pending X is dropped, so it
-- cannot fire as a surprise combo after the user comes back.
function PadNav:_drop_x_mode(ctx)
    if ctx ~= "reading" and ctx ~= "paged" then self._x_mode = false end
end

-- Buttons (logical role id) in the FileManager (ctx "filemanager"): the list
-- keeps the stock navigation -- D-pad / A, LB / RB (RPgBack / RPgFwd = list
-- page). kopad adds Select = top menu and B = parent folder; LT / RT (list
-- page) are in _menu_trigger. Returns true = consumed.
function PadNav:_filemanager_button(btn)
    if btn == BTN_SELECT then return self:onKPSelect() end
    -- B = parent folder. Stock Back in the file browser asks "Exit KOReader?"
    -- (FileChooser:onBack, back_to_exit = prompt); quitting stays in the menu.
    if btn == BTN_B then
        local fc = self.ui and self.ui.file_chooser
        if type(fc) == "table" and type(fc.onFolderUp) == "function" then
            local ok, err = pcall(fc.onFolderUp, fc)
            if not ok then logger.warn("kopad: folder up failed: " .. tostring(err)) end
        end
        return true
    end
    return BUTTON_SWALLOW[btn] or false
end

-- Buttons (logical role id) while the dictionary popup is on top (ctx
-- "dict"). The popup handles the stock keys itself: LB / RB (RPgBack /
-- RPgFwd) = previous / next dictionary, B (Back) closes it, A / D-pad /
-- L-stick as stock. kopad adds Y = AI explanation of the current selection
-- when the popup was opened from kopad's selector (the overlay stays under
-- it); otherwise Y passes. BUTTON_SWALLOW as in menus. Returns true = consumed.
function PadNav:_dict_button(btn)
    if btn == BTN_Y then
        local selector = self:_selector()
        local ov = selector and selector.overlay
        local sel = ov and ov:_get_selection()
        if not sel then return false end
        local top = top_window()
        if top then UIManager:close(top) end
        ov:_do_ai(sel)
        return true
    end
    return BUTTON_SWALLOW[btn] or false
end

-- Call method `name` of the wheel on top (wheel.lua controller), guarded.
function PadNav:_wheel_call(name, arg)
    local c = wheel_of(top_window())
    if not c then return false end
    local ok, res = pcall(c[name], c, arg)
    if not ok then logger.warn("kopad: wheel " .. name .. " failed: " .. tostring(res)) end
    Trace.log("padnav wheel %s(%s) ok=%s res=%s", name, tostring(arg), tostring(ok), tostring(res))
    return ok and res
end

-- Buttons (logical role id) while a wheel dialog is on top (ctx "wheel",
-- wheel.lua). Every button is consumed: the dialog's stock focus navigation
-- would move an invisible button table.
--   A = run the selection, X = its long-press action, B = close,
--   D-pad ←/↑ = previous sector, →/↓ = next sector, LB / RB = previous / next page.
local WHEEL_BUTTONS = {
    [BTN_A] = { "activate", false }, [BTN_X] = { "activate", true },
    [BTN_B] = { "close" },
    [BTN_DPAD_LEFT] = { "rotate", -1 }, [BTN_DPAD_UP] = { "rotate", -1 },
    [BTN_DPAD_RIGHT] = { "rotate", 1 }, [BTN_DPAD_DOWN] = { "rotate", 1 },
    [BTN_LB] = { "page_step", -1 }, [BTN_RB] = { "page_step", 1 },
}
function PadNav:_wheel_button(btn)
    local w = WHEEL_BUTTONS[btn]
    if w then self:_wheel_call(w[1], w[2]) end
    return true
end

-- LOGICAL trigger (axis AXIS_LT / AXIS_RT after remapping), numeric value.
-- from_button = true when a remapped BUTTON produced it: buttons fire once
-- per press, so the auto-repeat filter is skipped.
function PadNav:_trigger_event(axis, value, from_button)
    local tr = Trace.active()
    local ctx = self:_context()
    self:_drop_x_mode(ctx)
    if ctx == "dict" then
        if tr then Trace.log("padnav axis=%s value=%s: context dict, swallowed -> result=true", tostring(axis), tostring(value)) end
        return true
    end
    if ctx == "wheel" then
        if value > 0 and (from_button or self:_trigger_is_new_press(axis)) then
            self:_wheel_call("page_step", axis == AXIS_RT and 1 or -1)
        end
        if tr then Trace.log("padnav axis=%s value=%s: context wheel, page -> result=true", tostring(axis), tostring(value)) end
        return true
    end
    if ctx == "top_menu" or ctx == "window" or ctx == "filemanager" then
        self:_menu_trigger(axis, value, from_button, ctx)
        if tr then
            Trace.log("padnav axis=%s value=%s: context %s, menu page -> result=true",
                tostring(axis), tostring(value), ctx)
        end
        return true
    end
    if not PAD_CONTEXTS[ctx] then
        if tr then
            Trace.log("padnav axis=%s value=%s: passthrough, context %s -> result=false",
                tostring(axis), tostring(value), ctx)
        end
        return false
    end
    -- Triggers: 0..32767, only positive values are a press.
    local new_press = value > 0 and (from_button or self:_trigger_is_new_press(axis))
    -- In the selection a held trigger keeps jumping by paragraph (TASK-25):
    -- the stock auto-repeat goes through there (and only there).
    local held = value > 0 and not new_press and ctx == "selection"
    local handler = "none"
    if new_press or held then
        -- Role-level action override (PC-014); idle reading context only.
        local role = axis == AXIS_LT and "lt" or "rt"
        local override = self:_override_action(role)
        if override then
            handler = "override:" .. override
            self:_run_action(override, role)
        elseif self:_paged_idle() then
            handler = "paged page"
            self:_paged_page(axis == AXIS_LT and -1 or 1)
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
        self:_button_down({ button = btn }, true)
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
    local ctx = self:_context()
    self:_drop_x_mode(ctx)
    -- A wheel dialog: either stick points at a sector; nothing reaches stock.
    if ctx == "wheel" then
        local axis = type(ax) == "table" and ax.axis
        if axis == AXIS_LX or axis == AXIS_LY then
            self:_wheel_call("stick", "left")
        elseif axis == AXIS_RX or axis == AXIS_RY then
            self:_wheel_call("stick", "right")
        end
        if tr then Trace.log("padnav axis=%s: context wheel -> result=true", tostring(axis)) end
        return true
    end
    -- Menus, lists, dialogs, the dictionary popup and the FileManager: the
    -- sticks stay stock (L-stick = navigation, R-stick Y = page), minus
    -- release bounces (MENU_STICK_LOCK_S); on the top menu's tab bar the
    -- L-stick ←/→ switches the tab like the D-pad.
    if (ctx == "top_menu" or ctx == "window" or ctx == "dict" or ctx == "filemanager")
            and type(ax) == "table" and STICK_HANDLERS[ax.axis] and type(ax.value) == "number" then
        local neg = ax.value < 0
        if self:_stick_bounce(ax.axis, neg, MENU_STICK_LOCK_S) then
            if tr then Trace.log("padnav axis=%s value=%s: context %s, stick bounce, ignored -> result=true",
                tostring(ax.axis), tostring(ax.value), ctx) end
            return true
        end
        self:_quiet_tab_focus(ctx)
        if ctx == "top_menu" and ax.axis == AXIS_LX then
            local menu = self:_top_menu()
            if menu and menu_focus_on_bar(menu) then
                local ok, err = pcall(menu_switch_tab, menu, neg and -1 or 1)
                if not ok then logger.warn("kopad: menu tab switch failed: " .. tostring(err)) end
                Trace.log("padnav axis=%s value=%s: menu tab step (bar) ok=%s", tostring(ax.axis), tostring(ax.value), tostring(ok))
                return true
            end
        elseif ctx == "window" and ax.axis == AXIS_LX then
            local dlg = find_config_dialog()
            if dlg and config_focus_on_bar(dlg) then
                local ok, err = pcall(config_switch_tab, dlg, neg and -1 or 1)
                if not ok then logger.warn("kopad: config tab switch failed: " .. tostring(err)) end
                Trace.log("padnav axis=%s value=%s: config tab step (bar) ok=%s", tostring(ax.axis), tostring(ax.value), tostring(ok))
                return true
            end
        end
    end
    if not PAD_CONTEXTS[ctx] or ctx == "filemanager" then
        if tr then
            Trace.log("padnav axis=%s value=%s: passthrough, context %s -> result=false",
                tostring(type(ax) == "table" and ax.axis), tostring(type(ax) == "table" and ax.value), ctx)
        end
        return false
    end
    if type(ax) ~= "table" then return false end
    local axis, value = ax.axis, ax.value
    -- Triggers with a numeric value were handled at the top; anything else
    -- that is not a numeric stick event passes (no comparison on a non-number).
    if axis == nil or type(value) ~= "number" or axis == AXIS_LT or axis == AXIS_RT then
        if tr then Trace.log("padnav axis=%s value=%s: incomplete event -> result=false",
            tostring(axis), tostring(value)) end
        return false
    end

    local pair = STICK_HANDLERS[axis]
    if not pair then
        if tr then Trace.log("padnav axis=%s value=%s: no stick mapping, passthrough -> result=false",
            tostring(axis), tostring(value)) end
        return false
    end
    local method = pair[value < 0 and 1 or 2]

    if STICK_HANDLERS[axis] and self:_paged_idle() then
        local neg = value < 0
        if self:_stick_bounce(axis, neg) then
            if tr then Trace.log("padnav axis=%s value=%s: paged stick bounce, ignored", tostring(axis), tostring(value)) end
            return true
        end
        if axis == AXIS_LX or axis == AXIS_LY then
            local step = neg and -1 or 1
            if tr then Trace.log("padnav axis=%s value=%s: paged pan", tostring(axis), tostring(value)) end
            if axis == AXIS_LX then self:_paged_pan(step, 0) else self:_paged_pan(0, step) end
        elseif axis == AXIS_RY then
            if tr then Trace.log("padnav axis=%s value=%s: paged zoom %s", tostring(axis), tostring(value), neg and "in" or "out") end
            self:_zoom_step(neg and 1 or -1)
        else
            local ev = PAGED_RSTICK_X[neg and 1 or 2]
            if tr then Trace.log("padnav axis=%s value=%s: paged %s:%s", tostring(axis), tostring(value), ev[1], ev[2]) end
            self.ui:handleEvent(Event:new(ev[1], ev[2]))
        end
        return true
    end
    -- kopad's selection: a stick snapping back to centre must not undo the
    -- step or switch the level back.
    if ctx == "selection" and self:_stick_bounce(axis, value < 0, MENU_STICK_LOCK_S) then
        if tr then Trace.log("padnav axis=%s value=%s: selection stick bounce, ignored", tostring(axis), tostring(value)) end
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

    -- L-stick. Without a selector (FileManager / paged docs) let the stock
    -- Up/Down/Left/Right key through to the original list/page navigation;
    -- with one the handlers consume it (in reading as a no-op).
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
    .. "\nRT / LT, RB / LB: next / previous page"
    .. "\nSelect: top menu    Start: bottom menu"
    .. "\nB: back to the previous location"
    .. "\nA: select sentences    D-pad: select words"
    .. "\nY: highlights on the page"
    .. "\nHold X + D-pad: \xE2\x86\x91 menu  \xE2\x86\x93 footer  \xE2\x86\x90 history  \xE2\x86\x92 files"
    .. "\nHold X + LB: TOC    X + RB: bookmarks"
    .. "\n\n" .. _("PDF / DjVu")
    .. "\nD-pad: move around the page slowly    L-stick: fast"
    .. "\nR-stick \xE2\x86\x91/\xE2\x86\x93: zoom in / out"
    .. "\nR-stick \xE2\x86\x90/\xE2\x86\x92: whole page / text width"
    .. "\nLB / RB, LT / RT: previous / next page"
    .. "\n\n" .. _("Top menu open")
    .. "\nRB / LB: next / previous category"
    .. "\nRT / LT: next / previous page    Select: close"
    .. "\nD-pad \xE2\x86\x90/\xE2\x86\x92 on the tabs: category"
    .. "\n\n" .. _("Lists (TOC, bookmarks, history, ...)")
    .. "\nRT / LT: next / previous page"
    .. "\n\n" .. _("Bottom menu open")
    .. "\nRB / LB: next / previous tab    Start: close"
    .. "\nD-pad \xE2\x86\x90/\xE2\x86\x92 on the tabs: tab"
    .. "\n\n" .. _("Dialog wheel")
    .. "\nSticks: point    D-pad: previous / next"
    .. "\nA: run    X: long press    B: close"
    .. "\nLB / RB, LT / RT: page"
    .. "\n\n" .. _("File browser")
    .. "\nLB / RB, LT / RT: previous / next page    Select: menu"
    .. "\nB: parent folder"

local CHEAT_SELECTION = _("Selection mode")
    .. "\nD-pad / L-stick \xE2\x86\x90/\xE2\x86\x92: word / sentence"
    .. "\nD-pad / L-stick \xE2\x86\x91/\xE2\x86\x93: line / paragraph"
    .. "\nRT / LT: next / previous paragraph"
    .. "\nHold A + arrows: select a range"
    .. "\nA: action menu    Y: Vortuyo"
    .. "\nR-stick \xE2\x86\x93: words    \xE2\x86\x91: sentences"
    .. "\nX: toggle highlight    B: close"
    .. "\nRB / LB: close and turn page"
    .. "\nSelect / Start: close and open menu"
    .. "\n\n" .. _("Highlights (Y)")
    .. "\nD-pad: previous / next    X: remove"
    .. "\n\n" .. _("Dictionary popup")
    .. "\nLB / RB: cycle dictionaries    Y: AI explain    B: close"

function PadNav:_show_text(text, timeout)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
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
    footer_menu       = _("footer mode toggle"),
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
    crosshair         = _("word walk"),
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
