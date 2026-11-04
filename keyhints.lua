--[[
keyhints — hide KOReader's keyboard-shortcut letter labels (Q W E R T Y …)
on file browser items while kopad is enabled, and restore them exactly when it
is switched off.

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

Mechanism: `rawset(BookList, "is_enable_shortcut", false)`. Instances look the
field up through the metatable chain, so already-open and future instances
pick it up alike. The original *own* value of the class table (usually none,
i.e. inherited from Menu) is remembered and put back verbatim by restore().

Live FileManager: its FileChooser was built with the old value, so apply() /
restore() also re-sync the `SelectByShortCut` key binding that Menu:init only
registers when the flag is on, and redraw the page via updateItems() (only when
the effective value actually changed). A FileManager created later needs
nothing: kopad's init runs before FileManager builds its FileChooser.

Two modes. Stock KOReader: the flag above is switched off. With keyreader's
menupage installed (it sets `Menu.shortcut_box_manicule`) switching shortcuts
off would also take away the hand (☞) it paints on the focused item INSIDE the
shortcut box, so there only the letters are hidden: `hide_shortcut_letters`
on BookList, which menupage's `getItemShortCutIcon` reads (a box with no letter
and no backdrop; the shortcuts and the box stay). The mode is chosen on every
apply(): when the keyreader loads after kopad, the next sync switches over.

State is module-level on purpose: the plugin is instantiated once per UI
(FileManager / ReaderUI), but the class patch is process-global; apply() and
restore() are idempotent so any instance may call them in any order.
Everything is pcall-guarded; a failure only logs a warning.
]]

local KeyHints = {}

local FIELD = "is_enable_shortcut"
local HIDE_FIELD = "hide_shortcut_letters"
-- Lowest class shared by every cover/list browser (see header).
local TARGET_MODULES = { "ui/widget/booklist" }

local ok_logger, logger = pcall(require, "logger")
if not ok_logger then
    logger = { warn = function() end, dbg = function() end }
end

-- nil while not applied; otherwise { field = <name>, list = { { cls = <class>,
-- had_own = bool, value = <raw value> }, ... } }
local saved = nil

-- The field to set: HIDE_FIELD when menupage keeps the hand in the shortcut
-- box (see header), else FIELD.
local function wanted_field()
    local Menu = package.loaded["ui/widget/menu"]
    if type(Menu) == "table" and rawget(Menu, "shortcut_box_manicule") then
        return HIDE_FIELD
    end
    return FIELD
end

-- What the live browser shows, to redraw only when it changes.
local function effective(fc)
    if not fc then return nil end
    return (fc[FIELD] and "s" or "-") .. (fc[HIDE_FIELD] and "h" or "-")
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

-- Hide the letter labels. Idempotent: a second call never re-saves (which
-- would capture our own `false` as the "original"); it only switches the mode
-- when the keyreader's menupage appeared since the last call.
function KeyHints.apply()
    local field = wanted_field()
    if saved then
        if saved.field == field then return false end
        KeyHints.restore()
    end

    local fc = live_file_chooser()
    local before = effective(fc)

    local list = {}
    for _, modname in ipairs(TARGET_MODULES) do
        local ok, cls = pcall(require, modname)
        if ok and type(cls) == "table" then
            local own = rawget(cls, field)
            list[#list + 1] = { cls = cls, had_own = own ~= nil, value = own }
            rawset(cls, field, field == HIDE_FIELD)
        else
            logger.warn("kopad keyhints: cannot load " .. modname .. ": " .. tostring(cls))
        end
    end
    if #list == 0 then return false end

    saved = { field = field, list = list }
    refresh_live(fc, before)
    return true
end

-- Put the class tables back exactly as they were. Idempotent.
function KeyHints.restore()
    if not saved then return false end

    local current = saved
    saved = nil

    local fc = live_file_chooser()
    local before = effective(fc)

    for _, entry in ipairs(current.list) do
        if entry.had_own then
            rawset(entry.cls, current.field, entry.value)
        else
            rawset(entry.cls, current.field, nil) -- fall back to the inherited value
        end
    end

    refresh_live(fc, before)
    return true
end

return KeyHints
