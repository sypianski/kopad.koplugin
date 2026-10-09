--[[
PadNav — gamepad reading controls for KOReader (active when kopad is enabled).
The on<Key> handlers below are the source of truth; keep this block, the
header of main.lua, README.md and CHEAT_READING/CHEAT_SELECTION in sync with them.

Reading:
  RT / LT (triggers)     Next / previous page (always, also with overlay open)
  RB / LB                Next / previous page (X+RB = bookmarks, X+LB = TOC)
  L4 / R4 (back paddles) Same as LB / RB
  Select                 Top menu          Start   Footer (bottom) menu
  D-pad                  Open word walk
  L-stick ↑/←            Page turn (↑/← = next page, legacy)
  L-stick ↓              Open crosshair   L-stick → Open word walk
  R-stick                Open crosshair (immediate)
  A                      Open sentence selector
  Y                      Open highlight mode (crosshair if none)
  X                      Modifier: X + D-pad = ↑menu ↓footer ←history →files

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
remain active there.

Key names (from SDL3 patch + userpatch):
  LT = LPgBack (F6), RT = LPgFwd (F7), LB = RPgBack (F9), RB = RPgFwd (F11)
  X = F10, R-stick = F3/F4/F5/F8.
  ASSUMPTION (unverifiable, KOReader SDL3.lua not available): the stock
  patch emits no known key for Select/Start. We bind Select = F12 and
  Start = F2 (see SELECT_KEYS/START_KEYS; proposed hunk for
  sdl3_gamepad.patch maps BACK -> 1073741893 (F12), START -> 1073741883 (F2)).
  If those keys never arrive, the bindings are simply inert; nothing else
  breaks and X + D-pad still reaches the menus.
]]

local Event          = require("ui/event")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager      = require("ui/uimanager")
local logger         = require("logger")
local Pluginaro      = require("pluginaro")
local _              = require("gettext")

local RTL_LANGS = { ar=true, he=true, fa=true, ur=true }

local PadNav = InputContainer:extend{
    name        = "kopad_padnav",
    enabled_ref = nil,
}

-- Select/Start key names: unverifiable without KOReader's SDL3.lua. These are
-- unused F-keys; the matching hunk must be added to sdl3_gamepad.patch
-- (BACK -> 1073741893 "F12", START -> 1073741883 "F2"). Unknown/absent keys
-- just never fire, so a wrong guess is harmless.
local SELECT_KEYS = { "F12" }
local START_KEYS  = { "F2" }

local SUPPRESS_KEYS = {
    "MoveUp", "MoveDown",
    "GotoNextView", "GotoPrevView",
    "Press",
}

function PadNav:init()
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
        KPPgBk3   = { { "ScrollLock" } }, -- L4 back paddle
        KPPgFwd3  = { { "Pause" } },      -- R4 back paddle
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
    selector:_open()
    if not selector.overlay then return true end
    if #selector.overlay.hl_items > 0 then
        selector.overlay.mode = "struct"
        selector.overlay.sel_sent = 1
        selector.overlay.sel_tail = 1
        selector.overlay.sel_word = nil
        selector.overlay.hl_cur = 1
        selector.overlay:_refresh()
    end
    return true
end


local CHEAT_READING = _("Reading mode")
    .. "\nRT / LT: next / previous page"
    .. "\nRB / LB: next / previous page (also L4/R4)"
    .. "\nSelect: top menu    Start: footer menu"
    .. "\nA: sentence selector    Y: highlights"
    .. "\nD-pad: word walk    R-stick: crosshair"
    .. "\nX + D-pad: \xE2\x86\x91 menu  \xE2\x86\x93 footer  \xE2\x86\x90 history  \xE2\x86\x92 files"
    .. "\nX + LB: TOC    X + RB: bookmarks"

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

function PadNav:getMenuItems()
    return {
        {
            text = _("Button cheat sheet: reading"),
            keep_menu_open = true,
            callback = function() self:_show_text(CHEAT_READING) end,
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
                    .. CHEAT_READING .. "\n\n" .. CHEAT_SELECTION)
            end,
        },
    }
end

return PadNav
