--[[
kopad — gamepad control for KOReader.

When enabled, replaces KOReader's default key bindings with gamepad-optimized ones.
The authoritative control map (and the exact key names) lives in the header of
padnav.lua; this is a summary. Use menu > kopad > "Button cheat sheet" on-device.

  Reading:
    RT / LT                  Next / previous page
    RB / LB                  Next / previous page (X+RB bookmarks, X+LB TOC)
    Select / Start           Top menu / bottom menu
    D-pad                    Next / previous page (TASK-28)
    A held + D-pad           Select words (→/↓ from the first, ←/↑ the last)
    Y held + D-pad           Select sentences (the same)
    A tapped                 Select sentences
    Y tapped                 The page's highlights (none = a message)
    B held + D-pad           ↑/↓ font size, ←/→ margins (PDF: zoom / fit)
    B tapped                 Back to the previous location
    L-stick                  Nothing
    R-stick                  Quick-action wheel (also PDF; library set in
                             the file browser; padmap `quick`, TASK-26)
    X held + D-pad           Combo: ↑menu ↓footer ←history →files

  Menus versus reading (KOReader >= 2026.07, PadNav:_context): the reading
  and selection controls apply only while the book (or kopad's selection) is
  the top window; menus, lists, dialogs, the dictionary popup and the file
  browser get stock KOReader keys plus:
    Top menu                 RB / LB category, RT / LT menu page, Select close
    Lists / dialogs          RT / LT list page (TOC, bookmarks, history, ...)
    File browser             LB / RB, LT / RT list page, Select top menu,
                             R-stick quick-action wheel

  Selection (sentences / words; highlights after Y):
    D-pad / L-stick          ←/→ word or sentence, ↑/↓ line or paragraph,
                             across page edges; held D-pad repeats, faster
    RT / LT                  Next / previous paragraph (held: keeps jumping)
    A held + arrows          Range from where A was pressed (not the A hold
                             that opened the words: that one moves the cursor)
    A tapped                 Action menu (dict, AI, copy, note)
    R-stick ↓ / ↑            Sentence -> its first word / word -> its sentence
    Y                        Vortuyo lookup
    X                        Toggle highlight
    B                        Close
    RB / LB                  Close and turn the page
    Select / Start           Close and open top / bottom menu

  Dictionary popup:
    LB / RB                  Cycle dictionaries (the popup's own keys)
    Y                        AI explain (selection from kopad)
    B                        Close the popup

  Dialogs with a grid of buttons (ButtonDialog) as a wheel (wheel.lua;
  menu > kopad > "Dialogs as a wheel", this device, default on):
    L-stick / R-stick        Point at a sector (8 directions, nearest sector)
    D-pad                    Previous / next sector
    A / X                    Run the button / its long-press action
    B                        Close
    LB / RB, LT / RT         Previous / next page (more than 8 buttons)

Input paths:
  KOReader >= 2026.07 (stock, no patch): the device broadcasts
  GamepadButtonDown / GamepadButtonUp / GamepadAxisMotion events;
  kopad:onGamepadButtonDown / :onGamepadButtonUp / :onGamepadAxisMotion below
  relay them to PadNav (see padnav.lua header for
  the SDL button/axis ids). LT/RT/Select/Start work without any patch.

  Button remapping (KOReader >= 2026.07 path only, padmap.lua / PC-011):
  the shared `padmap` table in settings/kopad.lua (synced by koligilo) holds
  per-layout overrides; the layout of THIS device's pad (menu > kopad >
  "Gamepad layout") lives in settings/kopad_device.lua, which koligilo does
  not sync. No data = identity = the map above.
  Its optional `actions` (PC-014) gives a ROLE another action while plainly
  reading (e.g. RB = top menu); selection, dictionary and menus keep the map
  above. See padnav.lua (_override_action) and padmap.lua (ACTION_ORDER).

  Older builds (sdl3_gamepad.patch + 1-lstick-keys.lua userpatch): buttons
  arrive from SDL3 as standard key names:
  L-stick          →  LStickUp/Down/Left/Right (via userpatch)
  D-pad            →  Up, Down, Left, Right
  R-stick          →  F3, F4, F5, F8
  A (South)        →  Press
  B (East)         →  Back
  X (West)         →  F10
  Y (North)        →  ContextMenu
  LB / RB          →  RPgBack (F9) / RPgFwd (F11)
  L4 / R4 (paddles)→  ScrollLock / Pause = aliases of LB / RB (patched builds
                      only; not handled on KOReader >= 2026.07)
  LT / RT          →  LPgBack (F6) / LPgFwd (F7)
  Select / Start   →  F12 / F2 (ASSUMED; needs a hunk in sdl3_gamepad.patch,
                      see padnav.lua header — inert if the keys never arrive)
]]

local DataStorage    = require("datastorage")
local LuaSettings    = require("luasettings")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger          = require("logger")
local _               = require("gettext")
local Pluginaro       = require("pluginaro")

-- Optional on-device diagnostics (kopad_trace.lua, enabled by the flag file
-- <settings dir>/kopad-trace). A missing module degrades to a no-op stub.
local ok_trace, Trace = pcall(require, "kopad_trace")
if not ok_trace or type(Trace) ~= "table" then
    local nop = function() end
    Trace = { log = nop, begin_event = nop, end_event = nop,
              active = function() return false end,
              file_stamp = function() return "" end }
end

-- padmap.lua (pure remapping layer), loaded lazily via safe_require.
local Padmap

local kopad = WidgetContainer:extend{
    name        = "kopad",
    is_doc_only = false,
}

local function safe_require(modname)
    local ok, mod = pcall(require, modname)
    if not ok then
        logger.warn("kopad: failed to load " .. modname .. ": " .. tostring(mod))
        Trace.log("load %s: FAILED: %s", modname, tostring(mod))
        return nil
    end
    Trace.log("load %s: ok (%s)", modname, type(mod))
    return mod
end

-- Directory this main.lua was loaded from ("@/path/main.lua" in the chunk's
-- debug source), or nil.
local function plugin_dir()
    local ok, src = pcall(function() return debug.getinfo(1, "S").source end)
    return ok and type(src) == "string" and src:match("^@(.*)/[^/]*$") or nil
end

-- Startup marker: which code is on disk (mtimes) and the initial state.
function kopad:_trace_start()
    local dir = plugin_dir()
    Trace.log("=== kopad init: ui=%s rolling=%s enabled=%s dir=%s",
        tostring(self.ui and self.ui.name), tostring(self.ui and self.ui.rolling ~= nil),
        tostring(self.enabled), tostring(dir))
    if dir then
        for _, f in ipairs({ "main.lua", "padnav.lua", "keyhints.lua" }) do
            Trace.log("file %s: %s", f, Trace.file_stamp(dir .. "/" .. f))
        end
    end
end

function kopad:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/kopad.lua")
    -- Device-local settings: never listed in koligilo's catalog, so they do
    -- not travel between devices (the pad layout differs per device).
    self.device_settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/kopad_device.lua")
    self.enabled  = self.settings:isTrue("enabled")
    self.subs     = {}

    if Trace.active() then self:_trace_start() end
    self:_default_page_view()
    self:_load_subs()
    self:_apply_padmap()
    self:_install_wheel()
    self:_install_vkb()
    Trace.log("subs: nav=%s keyhints=%s selector=%s",
        tostring(self.subs.nav ~= nil), tostring(self.subs.keyhints ~= nil),
        tostring(self.subs.selector ~= nil))

    -- FileManager instantiates plugins BEFORE it builds its FileChooser, so
    -- applying here is enough for the file browser created right after.
    self:_sync_key_hints()

    -- Integration A (pluginaro): kopad can steer visel's selection with the
    -- gamepad. The toggle lives in visel's menu (menu_location = "host");
    -- kopad's menu shows the auto-generated signpost annotation. Routing
    -- checks is_enabled per event through Pluginaro.call_provided, so no
    -- on_enable/on_disable hooks are needed. Registering when visel
    -- (keyreader) is absent is harmless: nothing provides the impl, so
    -- call_provided keeps returning nil and behaviour stays as today.
    Pluginaro.register("visel", {
        id              = "gamepad_select",
        provider        = "kopad",
        section         = "extensions",
        menu_location   = "host",
        label           = _("Steer also with gamepad (kopad)"),
        default_enabled = false,
    })

    -- Integration B (pluginaro): RT held in a text field dictates through
    -- diktonoti (B cancels). Same shape as above: toggle in diktonoti's menu,
    -- harmless without diktonoti.
    Pluginaro.register("diktonoti", {
        id              = "gamepad_dictate",
        provider        = "kopad",
        section         = "extensions",
        menu_location   = "host",
        label           = _("Dictate holding RT, B cancels (kopad)"),
        default_enabled = false,
    })

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

-- On the pad, only LB/RB and LT/RT turn the page of a PDF/DjVu, so new
-- documents should open in page view: continuous view (KOReader's default,
-- kopt_page_scroll = 1) scrolls into the next page and ignores panning.
-- Done once per device, the first time kopad runs enabled; switching
-- continuous view back on in KOReader's settings afterwards sticks.
-- Documents that already remember continuous view switch on the first pan
-- (PadNav:_paged_pan).
function kopad:_default_page_view()
    if not self.enabled or self.device_settings:isTrue("page_view_default_set") then return end
    local grs = rawget(_G, "G_reader_settings")
    if not grs then return end
    grs:saveSetting("kopt_page_scroll", 0)
    grs:flush()
    self.device_settings:saveSetting("page_view_default_set", true)
    self.device_settings:flush()
    Trace.log("default page view set (kopt_page_scroll = 0)")
end

function kopad:_load_subs()
    if self.subs.nav then return end

    local Nav = safe_require("padnav")
    if Nav then
        self.subs.nav = Nav:new{ ui = self.ui, enabled_ref = self }
    end

    -- File browser letter labels (q w e r t y…): plain module with global state.
    self.subs.keyhints = safe_require("keyhints")

    self:_ensure_selector()
end

-- Hide KOReader's keyboard-shortcut letter labels on file browser items while
-- kopad is enabled; restore them when it is off (see keyhints.lua). Idempotent.
function kopad:_sync_key_hints()
    local kh = self.subs.keyhints
    if not kh then return end
    local ok, err = pcall(self.enabled and kh.apply or kh.restore)
    if not ok then
        logger.warn("kopad: key hints sync failed: " .. tostring(err))
    end
end

-- ButtonDialogs as a radial menu (wheel.lua). The patch of ButtonDialog.init
-- is installed once per KOReader run; the state function is replaced by every
-- kopad instance, so it follows the current reader / file browser. Not
-- available without KOReader's Gamepad* events (wheel.install -> false).
function kopad:_install_wheel()
    local Wheel = safe_require("wheel")
    if not Wheel then return end
    local ok, res = pcall(Wheel.install, function()
        return self.enabled and self.device_settings:nilOrTrue("wheel_dialogs")
    end)
    if not ok then logger.warn("kopad: wheel install failed: " .. tostring(res)) end
    self.wheel_available = ok and res or false
    Trace.log("wheel: available=%s", tostring(self.wheel_available))
end

-- No on-screen keyboard popping up in text-input dialogs while kopad is
-- enabled and a pad is connected (vkb.lua). Same once-per-run patch with a
-- per-instance state function as the wheel.
function kopad:_install_vkb()
    local Vkb = safe_require("vkb")
    if not Vkb then return end
    local ok, res = pcall(Vkb.install, function() return self.enabled end)
    if not ok then logger.warn("kopad: vkb install failed: " .. tostring(res)) end
    Trace.log("vkb: installed=%s", tostring(ok and res))
end

function kopad:_ensure_selector()
    if self.subs.selector then return end
    if not self.ui or not self.ui.rolling then
        Trace.log("selector: skipped (no ui.rolling)")
        return
    end
    local Selector = safe_require("selector")
    if Selector then
        self.subs.selector = Selector:new{ ui = self.ui, enabled_ref = self }
    end
end

-- (Re)build the button remapping and hand it to PadNav. Called on init, on
-- onReaderReady / onResume (koligilo may have rewritten `padmap` in place in
-- self.settings) and after a layout change in the menu. Any failure leaves
-- PadNav on the identity mapping.
function kopad:_apply_padmap()
    local nav = self.subs and self.subs.nav
    if not nav or not nav.set_padmap then return end
    Padmap = Padmap or safe_require("padmap")
    if not Padmap then nav:set_padmap(nil); return end
    local ok, res = pcall(Padmap.build,
        self.settings:readSetting("padmap"),
        self.device_settings and self.device_settings:readSetting("padmap_layout"),
        function(msg) logger.warn("kopad: " .. msg) end)
    if not ok then
        logger.warn("kopad: padmap build failed: " .. tostring(res))
        res = nil
    end
    Trace.log("padmap: layout=%s ok=%s", tostring(ok and res and res.layout), tostring(ok))
    nav:set_padmap(res)
end

function kopad:_layout_menu()
    local P = Padmap or safe_require("padmap")
    if not P then return nil end
    Padmap = P
    local labels = {
        xbox        = _("Xbox / generic"),
        playstation = _("PlayStation (DualShock / DualSense)"),
        nintendo    = _("Nintendo (A/B and X/Y swapped)"),
        valve       = _("Valve (Steam Deck / Steam Controller)"),
    }
    local function current()
        local l = self.device_settings and self.device_settings:readSetting("padmap_layout")
        return P.LAYOUTS[l] and l or P.DEFAULT_LAYOUT
    end
    local items = {}
    for _i, name in ipairs(P.LAYOUT_ORDER) do
        table.insert(items, {
            text = labels[name] or name,
            radio = true,
            checked_func = function() return current() == name end,
            callback = function()
                self.device_settings:saveSetting("padmap_layout", name)
                self.device_settings:flush()
                self:_apply_padmap()
            end,
        })
    end
    return {
        text_func = function()
            return _("Gamepad layout (this device)") .. ": " .. (labels[current()] or current())
        end,
        sub_item_table = items,
    }
end

function kopad:onResume()
    self:_apply_padmap()
end

function kopad:onReaderReady()
    self:_apply_padmap()
    self:_ensure_selector()
    Trace.log("onReaderReady: enabled=%s nav=%s selector=%s", tostring(self.enabled),
        tostring(self.subs.nav ~= nil), tostring(self.subs.selector ~= nil))
    if self.enabled and self.subs.nav then
        -- Re-apply suppression now that all reader modules have their key_events set
        self.subs.nav:restore_reader_keys()
        self.subs.nav:_suppress_reader_keys()
    end
end

function kopad:onCloseDocument()
    -- The selector overlay is a UIManager window bound to this document's
    -- ReaderUI. When the document is torn down (e.g. end of book -> next book)
    -- while the overlay is open, it would otherwise linger on the window stack
    -- with dead references and the fresh ReaderUI's PadNav (a brand-new
    -- selector) could never close it. Close it here; _close also releases the
    -- pluginaro overlay claim.
    if self.subs.selector and self.subs.selector.overlay then
        self.subs.selector:_close()
    end
end

function kopad:addToMainMenu(menu_items)
    local sub_items = {
        {
            text = _("Enable kopad"),
            checked_func = function() return self.enabled end,
            keep_menu_open = true,
            callback = function()
                self.enabled = not self.enabled
                Trace.log("toggle: enabled -> %s", tostring(self.enabled))
                self.settings:saveSetting("enabled", self.enabled)
                self.settings:flush()
                self:_sync_key_hints()
                if self.enabled then
                    if self.subs.nav then
                        self.subs.nav:_suppress_reader_keys()
                    end
                else
                    if self.subs.selector then
                        self.subs.selector:_close()
                    end
                    if self.subs.nav then
                        self.subs.nav:restore_reader_keys()
                    end
                end
            end,
            separator = true,
        },
    }

    local layout_item = self:_layout_menu()
    if layout_item then table.insert(sub_items, layout_item) end

    if self.wheel_available then
        table.insert(sub_items, {
            text = _("Dialogs as a wheel (this device)"),
            checked_func = function() return self.device_settings:nilOrTrue("wheel_dialogs") end,
            callback = function()
                self.device_settings:flipNilOrTrue("wheel_dialogs")
                self.device_settings:flush()
            end,
        })
    end

    for _, sub in pairs(self.subs) do
        if sub.getMenuItems then
            local ok, items = pcall(sub.getMenuItems, sub)
            if ok and items then
                for _, item in ipairs(items) do
                    table.insert(sub_items, item)
                end
            end
        end
    end

    local ext_rows = Pluginaro.build_ext_menu("kopad")
    if #ext_rows > 0 then
        table.insert(sub_items, {
            text = _("Extensions"),
            sub_item_table = ext_rows,
        })
    end

    menu_items.kopad = {
        text = _("kopad"),
        sorting_hint = "more_tools",
        sub_item_table = sub_items,
    }
end

-- KOReader >= 2026.07 broadcasts raw gamepad events (UIManager:broadcastEvent
-- in frontend/device/sdl/device.lua). The broadcast reaches the window-level
-- widgets and their children, i.e. this plugin widget, but NOT PadNav, which
-- is only in ui.active_widgets — so relay to it. Returning true makes the
-- device skip the stock default key press; false keeps stock behaviour.
function kopad:onGamepadButtonDown(ev)
    local nav = self.subs and self.subs.nav
    local tr = Trace.active()
    if tr then
        Trace.begin_event(nil)
        Trace.log("relay btn: button=%s nav=%s enabled=%s",
            tostring(type(ev) == "table" and ev.button), tostring(nav ~= nil),
            tostring(self.enabled))
    end
    local res = nav and nav:onGamepadButtonDown(ev) or false
    if tr then
        Trace.log("relay btn: returned %s", tostring(res))
        Trace.end_event()
    end
    return res
end

-- The release (TASK-16): ends the A hold, the X hold and a D-pad repeat.
function kopad:onGamepadButtonUp(ev)
    local nav = self.subs and self.subs.nav
    if not nav then return false end
    if Trace.active() then
        Trace.begin_event(nil)
        Trace.log("relay btn up: button=%s", tostring(type(ev) == "table" and ev.button))
    end
    nav:onGamepadButtonUp(ev)
    if Trace.active() then Trace.end_event() end
    return false
end

function kopad:onGamepadAxisMotion(ax)
    local nav = self.subs and self.subs.nav
    local tr = Trace.active()
    if tr then
        local axis = type(ax) == "table" and ax.axis
        local value = type(ax) == "table" and ax.value
        -- Repeats of the same axis+direction within 0.3 s are collapsed.
        local dir = type(value) ~= "number" and "?"
            or (value < 0 and "-" or (value > 0 and "+" or "0"))
        Trace.begin_event("axis:" .. tostring(axis) .. ":" .. dir)
        Trace.log("relay axis: axis=%s value=%s nav=%s enabled=%s",
            tostring(axis), tostring(value), tostring(nav ~= nil), tostring(self.enabled))
    end
    local res = nav and nav:onGamepadAxisMotion(ax) or false
    if tr then
        Trace.log("relay axis: returned %s", tostring(res))
        Trace.end_event()
    end
    return res
end

function kopad:onFlushSettings()
    self.settings:flush()
    if self.device_settings then self.device_settings:flush() end
end

return kopad
