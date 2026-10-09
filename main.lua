--[[
kopad — gamepad control for KOReader.

When enabled, replaces KOReader's default key bindings with gamepad-optimized ones.
The authoritative control map (and the exact key names) lives in the header of
padnav.lua; this is a summary. Use menu > kopad > "Button cheat sheet" on-device.

  Reading:
    RT / LT                  Next / previous page (always)
    RB / LB                  Next / previous page (X+RB bookmarks, X+LB TOC)
    Select / Start           Top menu / footer menu
    D-pad                    Open word walk
    R-stick                  Open crosshair
    L-stick ↑/←              Page turn; ↓ crosshair selector; → word walk
    A                        Sentence selector
    Y                        Highlight mode
    X + D-pad                Combo: ↑menu ↓footer ←history →files

  Selection (struct/walk/cross):
    L-stick ←/→              Sentence move    ↑/↓  Paragraph jump
    D-pad / R-stick          Word navigation (R-stick ↑/↓ cycles highlights)
    Y                        Vortuyo lookup
    X                        Toggle highlight
    A                        Action menu (dict, AI, copy, note)
    B                        Exit extend / close overlay
    RB / LB                  Extend selection right / left
    RT / LT                  Close overlay and turn page
    Select / Start           Close overlay and open top / footer menu

  Dictionary popup:
    LB / RB                  Cycle dictionaries
    Y                        AI explain

Gamepad buttons arrive from SDL3 as standard key names:
  L-stick          →  LStickUp/Down/Left/Right (via userpatch)
  D-pad            →  Up, Down, Left, Right
  R-stick          →  F3, F4, F5, F8
  A (South)        →  Press
  B (East)         →  Back
  X (West)         →  F10
  Y (North)        →  ContextMenu
  LB / RB          →  RPgBack (F9) / RPgFwd (F11)
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

local kopad = WidgetContainer:extend{
    name        = "kopad",
    is_doc_only = false,
}

local function safe_require(modname)
    local ok, mod = pcall(require, modname)
    if not ok then
        logger.warn("kopad: failed to load " .. modname .. ": " .. tostring(mod))
        return nil
    end
    return mod
end

function kopad:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/kopad.lua")
    self.enabled  = self.settings:isTrue("enabled")
    self.subs     = {}

    self:_load_subs()

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
        label           = "Steruj także z gamepada (kopad)",
        default_enabled = false,
    })

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function kopad:_load_subs()
    if self.subs.nav then return end

    local Nav = safe_require("padnav")
    if Nav then
        self.subs.nav = Nav:new{ ui = self.ui, enabled_ref = self }
    end

    self:_ensure_selector()
end

function kopad:_ensure_selector()
    if self.subs.selector then return end
    if not self.ui or not self.ui.rolling then return end
    local Selector = safe_require("selector")
    if Selector then
        self.subs.selector = Selector:new{ ui = self.ui, enabled_ref = self }
    end
end

function kopad:onReaderReady()
    self:_ensure_selector()
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
                self.settings:saveSetting("enabled", self.enabled)
                self.settings:flush()
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
            text = _("Rozszerzenia"),
            sub_item_table = ext_rows,
        })
    end

    menu_items.kopad = {
        text = _("kopad"),
        sorting_hint = "more_tools",
        sub_item_table = sub_items,
    }
end

function kopad:onFlushSettings()
    self.settings:flush()
end

return kopad
