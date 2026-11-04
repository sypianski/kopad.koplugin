--[[
keyhints — hide KOReader's keyboard-shortcut letter labels (Q W E R T Y …)
on file browser items while kopad is enabled (the hand of focushand.lua takes
their place on the focused item), and restore them exactly when it is switched
off.

How KOReader draws them (verified against KOReader 2026.07.1 sources):
  * Menu:updateItems and the coverbrowser plugin's MosaicMenu/ListMenu
    `_updateItemsBuildUI` hand each item a `shortcut` letter only when
    `self.is_enable_shortcut` is truthy. The letter is painted as an
    ItemShortCutIcon over the cover (mosaic) or beside the row (list).
  * `is_enable_shortcut` is a plain *class* field of Menu, initialised to
    `Device:hasKeyboard()` (always true on the SDL/Steam Deck device). There is
    no user-facing setting for it — nothing is stored in G_reader_settings, so
    nothing can be permanently overwritten.
  * FileChooser, History, Collections and search results are all BookList
    (extends Menu) instances, so BookList is the lowest class covering every
    cover/list browser without touching TOC, bookmark or other Menus.

Mechanism (since 0.1.22): the shortcuts stay ON and BookList gets its own
`getItemShortCutIcon` (focushand.wrap_factory, hidden): the icon it returns
paints nothing, except the hand (☞) on the item the pad has focused. The slot
the letter used to take is thus where the hand goes (see focushand.lua), and it
needs nothing from keyreader's menupage. (Before: `is_enable_shortcut` was
switched off, which left no slot for a hand; for a while 0.1.21 asked
menupage to hide the letters instead.) Instances look the fields up through the
metatable chain, so already-open and future instances pick them up alike. The
original *own* values of the class table (usually none, i.e. inherited from
Menu) are remembered and put back verbatim by restore(). Without focushand.lua
the old mechanism (`is_enable_shortcut` off) is used.

Live FileManager: its FileChooser was built with the old value, so apply() /
restore() also re-sync the `SelectByShortCut` key binding that Menu:init only
registers when the flag is on, and redraw the page via updateItems() (only when
the effective value actually changed). A FileManager created later needs
nothing: kopad's init runs before FileManager builds its FileChooser.

State is module-level on purpose: the plugin is instantiated once per UI
(FileManager / ReaderUI), but the class patch is process-global; apply() and
restore() are idempotent so any instance may call them in any order.
Everything is pcall-guarded; a failure only logs a warning.
]]

local KeyHints = {}

local FIELD = "is_enable_shortcut"
local FACTORY = "getItemShortCutIcon"
-- Lowest class shared by every cover/list browser (see header).
local TARGET_MODULES = { "ui/widget/booklist" }

local ok_logger, logger = pcall(require, "logger")
if not ok_logger then
    logger = { warn = function() end, dbg = function() end }
end

-- nil while not applied; otherwise { { cls = <class>, was = { [field] = { own = bool, value = <raw> } } }, ... }
local saved = nil

-- What the live browser shows, to redraw only when it changes.
local function effective(fc)
    if not fc then return nil end
    return (fc[FIELD] and "s" or "-") .. tostring(rawget(fc, FACTORY) or fc[FACTORY])
end

-- The live FileManager file browser, or nil. Never forces a module load:
-- when the FileManager module was not loaded no instance can exist.
local function live_file_chooser()
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    if type(FileManager) ~= "table" then return nil end
    local fm = FileManager.instance
    return fm and fm.file_chooser or nil
end

-- Mirror what Menu:init does for the letter-key binding: it exists iff the
-- device has a D-pad and the flag is on at construction time.
local function sync_shortcut_keys(fc)
    local Device = package.loaded["device"]
    if type(fc.key_events) ~= "table" or not Device or not Device:hasDPad() then
        return
    end
    if fc[FIELD] then
        if not fc.key_events.SelectByShortCut and fc.item_shortcuts then
            fc.key_events.SelectByShortCut = { { fc.item_shortcuts } }
        end
    else
        fc.key_events.SelectByShortCut = nil
    end
end

-- Redraw the live file browser if the effective flag changed. Keeps the
-- focused item (FileChooser:updateItems records select_number in path_items).
local function refresh_live(fc, before)
    if not fc then return end
    local ok, err = pcall(function()
        sync_shortcut_keys(fc)
        if effective(fc) == before then
            return
        end
        local select_number
        local perpage, page, item = fc.perpage, fc.page, fc.itemnumber
        if type(perpage) == "number" and type(page) == "number" and type(item) == "number"
           and perpage > 0 and item > (page - 1) * perpage and item <= page * perpage then
            select_number = item - (page - 1) * perpage
        end
        fc:updateItems(select_number)
    end)
    if not ok then
        logger.warn("kopad keyhints: refresh failed: " .. tostring(err))
    end
end

function KeyHints.is_applied()
    return saved ~= nil
end

local function set_field(cls, was, field, value)
    local own = rawget(cls, field)
    was[field] = { own = own ~= nil, value = own }
    rawset(cls, field, value)
end

-- Hide the letter labels. Idempotent: a second call never re-saves (which
-- would capture our own values as the "original").
function KeyHints.apply()
    if saved then return false end

    local fc = live_file_chooser()
    local before = effective(fc)

    local ok_fh, FocusHand = pcall(require, "focushand")

    local list = {}
    for _, modname in ipairs(TARGET_MODULES) do
        local ok, cls = pcall(require, modname)
        if ok and type(cls) == "table" then
            local was = {}
            if ok_fh and type(FocusHand) == "table" then
                local Menu = package.loaded["ui/widget/menu"]
                set_field(cls, was, FIELD, true)
                set_field(cls, was, FACTORY, FocusHand.wrap_factory(function()
                    return Menu.getItemShortCutIcon
                end, true))
            else
                set_field(cls, was, FIELD, false)
            end
            list[#list + 1] = { cls = cls, was = was }
        else
            logger.warn("kopad keyhints: cannot load " .. modname .. ": " .. tostring(cls))
        end
    end
    if #list == 0 then return false end

    saved = list
    refresh_live(fc, before)
    return true
end

-- Put the class tables back exactly as they were. Idempotent.
function KeyHints.restore()
    if not saved then return false end

    local list = saved
    saved = nil

    local fc = live_file_chooser()
    local before = effective(fc)

    for _, entry in ipairs(list) do
        for field, w in pairs(entry.was) do
            if w.own then
                rawset(entry.cls, field, w.value)
            else
                rawset(entry.cls, field, nil) -- fall back to the inherited value
            end
        end
    end

    refresh_live(fc, before)
    return true
end

return KeyHints
