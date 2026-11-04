-- keyhints.lua: hiding the shortcut letters on file browser items. The
-- shortcuts stay on (a slot for the hand of focushand.lua), the letter icon is
-- hidden by BookList's own factory; put back exactly on restore.
package.path = "./?.lua;" .. package.path

local function fresh(with_focushand)
    package.loaded["keyhints"] = nil
    package.loaded["focushand"] = nil
    local Menu = { is_enable_shortcut = true }
    Menu.getItemShortCutIcon = function() return { dimen = { w = 1, h = 1 }, paintTo = function() end } end
    Menu.__index = Menu
    local BookList = setmetatable({}, Menu)
    BookList.__index = BookList
    package.loaded["ui/widget/menu"] = Menu
    package.loaded["ui/widget/booklist"] = BookList
    if not with_focushand then
        package.preload["focushand"] = function() error("no focushand") end
    else
        package.preload["focushand"] = nil
    end

    local redraws = 0
    local fc = setmetatable({ perpage = 10, page = 1, itemnumber = 3 }, BookList)
    function fc:updateItems() redraws = redraws + 1 end
    package.loaded["apps/filemanager/filemanager"] = { instance = { file_chooser = fc } }
    return require("keyhints"), Menu, BookList, fc, function() return redraws end
end

-- 1. with focushand: shortcuts stay, the icon factory hides the letter
do
    local KH, Menu, BookList, fc, redraws = fresh(true)
    local stock = Menu.getItemShortCutIcon
    assert(not KH.is_applied())
    assert(KH.apply() == true and KH.is_applied())
    assert(rawget(BookList, "is_enable_shortcut") == true)
    assert(rawget(BookList, "getItemShortCutIcon") ~= nil and BookList.getItemShortCutIcon ~= stock)
    assert(redraws() == 1)
    local icon = fc:getItemShortCutIcon({}, nil, "A", "square")
    assert(icon._kopad_hidden and icon._kopad_hand, "letter hidden")
    assert(Menu.getItemShortCutIcon == stock, "Menu itself untouched")
    assert(KH.apply() == false and redraws() == 1, "second apply is a no-op")
    assert(KH.restore() == true and not KH.is_applied())
    assert(rawget(BookList, "is_enable_shortcut") == nil and rawget(BookList, "getItemShortCutIcon") == nil)
    assert(BookList.getItemShortCutIcon == stock and fc.is_enable_shortcut == true)
    assert(redraws() == 2)
    assert(KH.restore() == false)
end

-- 2. a menupage installed later (Menu's factory replaced) is still the one delegated to
do
    local KH, Menu, BookList, fc = fresh(true)
    KH.apply()
    local marker = { dimen = { w = 1, h = 1 }, paintTo = function() end, from_menupage = true }
    Menu.getItemShortCutIcon = function() return marker end
    local icon = fc:getItemShortCutIcon({}, nil, "A", "square")
    assert(icon.from_menupage and icon._kopad_hidden)
end

-- 3. without focushand: the old mechanism, shortcuts off
do
    local KH, Menu, BookList, fc = fresh(false)
    assert(KH.apply() == true)
    assert(rawget(BookList, "is_enable_shortcut") == false and rawget(BookList, "getItemShortCutIcon") == nil)
    assert(fc.is_enable_shortcut == false)
    assert(KH.restore() == true)
    assert(rawget(BookList, "is_enable_shortcut") == nil and fc.is_enable_shortcut == true)
end

-- 4. an own value of the class is put back verbatim
do
    local KH, Menu, BookList = fresh(true)
    rawset(BookList, "is_enable_shortcut", false)
    local own = function() end
    rawset(BookList, "getItemShortCutIcon", own)
    assert(KH.apply() and rawget(BookList, "is_enable_shortcut") == true)
    assert(KH.restore())
    assert(rawget(BookList, "is_enable_shortcut") == false and rawget(BookList, "getItemShortCutIcon") == own)
end

print("keyhints_test: OK")
