-- keyhints.lua: hiding the shortcut letters on file browser items, in the two
-- modes (stock: shortcuts off; keyreader's menupage: only the letters).
package.path = "./?.lua;" .. package.path

local function fresh(with_menupage)
    package.loaded["keyhints"] = nil
    local Menu = { is_enable_shortcut = true }
    if with_menupage then Menu.shortcut_box_manicule = true end
    Menu.__index = Menu
    local BookList = setmetatable({}, Menu)
    BookList.__index = BookList
    package.loaded["ui/widget/menu"] = Menu
    package.loaded["ui/widget/booklist"] = BookList

    local redraws = 0
    local fc = setmetatable({ perpage = 10, page = 1, itemnumber = 3 }, BookList)
    function fc:updateItems() redraws = redraws + 1 end
    package.loaded["apps/filemanager/filemanager"] = { instance = { file_chooser = fc } }
    return require("keyhints"), Menu, BookList, fc, function() return redraws end
end

-- 1. stock KOReader: shortcuts off, put back exactly
do
    local KH, Menu, BookList, fc, redraws = fresh(false)
    assert(not KH.is_applied())
    assert(KH.apply() == true and KH.is_applied())
    assert(rawget(BookList, "is_enable_shortcut") == false)
    assert(fc.is_enable_shortcut == false and not fc.hide_shortcut_letters)
    assert(redraws() == 1)
    assert(KH.apply() == false, "second apply is a no-op")
    assert(redraws() == 1)
    assert(KH.restore() == true and not KH.is_applied())
    assert(rawget(BookList, "is_enable_shortcut") == nil, "inherited again")
    assert(fc.is_enable_shortcut == true)
    assert(redraws() == 2)
    assert(KH.restore() == false)
end

-- 2. menupage installed: letters hidden, shortcuts stay (the hand lives in the box)
do
    local KH, Menu, BookList, fc, redraws = fresh(true)
    assert(KH.apply() == true)
    assert(rawget(BookList, "hide_shortcut_letters") == true)
    assert(rawget(BookList, "is_enable_shortcut") == nil, "shortcuts untouched")
    assert(fc.is_enable_shortcut == true and fc.hide_shortcut_letters == true)
    assert(redraws() == 1)
    assert(KH.apply() == false and redraws() == 1)
    assert(KH.restore() == true)
    assert(rawget(BookList, "hide_shortcut_letters") == nil)
    assert(not fc.hide_shortcut_letters and redraws() == 2)
end

-- 3. menupage appears after kopad applied: the next apply switches the mode
do
    local KH, Menu, BookList, fc = fresh(false)
    assert(KH.apply())
    assert(rawget(BookList, "is_enable_shortcut") == false)
    Menu.shortcut_box_manicule = true
    assert(KH.apply() == true, "mode switched")
    assert(rawget(BookList, "is_enable_shortcut") == nil, "stock mode undone")
    assert(rawget(BookList, "hide_shortcut_letters") == true)
    assert(fc.is_enable_shortcut == true)
    assert(KH.restore())
    assert(rawget(BookList, "hide_shortcut_letters") == nil)
end

-- 4. an own value of the class is put back verbatim
do
    local KH, Menu, BookList = fresh(false)
    rawset(BookList, "is_enable_shortcut", true)
    assert(KH.apply() and rawget(BookList, "is_enable_shortcut") == false)
    assert(KH.restore() and rawget(BookList, "is_enable_shortcut") == true)
end

print("keyhints_test: OK")
