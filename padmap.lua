--[[
padmap — pure button-remapping layer for kopad (no KOReader dependencies).

Translates a PHYSICAL gamepad control (an SDL button or trigger axis, as
delivered by KOReader >= 2026.07 in GamepadButtonDown / GamepadAxisMotion)
into the LOGICAL kopad role (A/B/X/Y/LB/RB/LT/RT/Select/Start) that padnav.lua
then routes to its on<Key> handlers. Format decision: PC-011 in
~/utensili/libraro/decyzje (koligilo TASK-25 edits the same data); the layout
vocabulary was extended with `valve` in PC-013 (koligilo TASK-26).

Physical control names (SDL3 positional ids, the same on every pad):
  south=btn 0  east=btn 1  west=btn 2  north=btn 3  back=btn 4  start=btn 6
  lshoulder=btn 9  rshoulder=btn 10  ltrigger=axis 4  rtrigger=axis 5
Role names (what kopad's handlers mean; kopad's docs use Xbox labels):
  a b x y select start lb rb lt rt

Shared, synced data (settings/kopad.lua, top-level key `padmap`):
  padmap = {
      version = 1,
      layouts = {
          nintendo = { east = "a", south = "b", north = "x", west = "y" },
          xbox     = { ltrigger = "rt", rtrigger = "lt" },
      },
      actions = { rb = "top_menu", select = "next_page" },
  }
  A layout table holds overrides on top of that layout's built-in default;
  physical controls it does not mention keep the built-in default.

  `actions` (PC-014, optional, additive within version 1) is a second stage
  AFTER the layout: role -> action performed while plainly reading. It is keyed
  by ROLE, not by physical control, so it is shared by every layout (switching
  from a Switch pad to a Deck keeps "RB opens the menu"). Roles it does not
  mention keep their built-in behaviour (DEFAULT_ACTIONS). The override only
  applies in the idle reading context (a document is open; no selection
  overlay, dictionary popup, top menu or X-combo is active) -- everywhere else
  the role keeps what its handler does today, so RB still extends a selection
  and still switches menu categories. An old kopad without this stage ignores
  the key and reads `layouts` as before.

Device-local data (settings/kopad_device.lua, NOT synced by koligilo):
  padmap_layout = "nintendo"   -- which layout this device's pad uses

Not covered: D-pad (stock passthrough), sticks, Guide/L3/R3, the legacy
key_events path (old patched builds), and action remapping inside the
selection overlay / dictionary popup / menus. The
Steam Deck back paddles L4/L5/R4/R5 (SDL ids 16+) are not remappable either:
KOReader >= 2026.07 does not deliver them (see the header of padnav.lua), so
they have no entry in PHYSICAL.

Robustness: anything malformed (unknown version, unknown layout/physical/
role names, wrong types) is skipped with a warning; it never raises. With no
data at all every physical control maps to its identity role, i.e. exactly
kopad's behaviour before this module existed.
]]

local M = {}

M.SCHEMA_VERSION = 1
M.DEFAULT_LAYOUT = "xbox"

-- Physical control name -> { kind, SDL id }.
M.PHYSICAL = {
    south     = { kind = "button", id = 0 },
    east      = { kind = "button", id = 1 },
    west      = { kind = "button", id = 2 },
    north     = { kind = "button", id = 3 },
    back      = { kind = "button", id = 4 },
    start     = { kind = "button", id = 6 },
    lshoulder = { kind = "button", id = 9 },
    rshoulder = { kind = "button", id = 10 },
    ltrigger  = { kind = "axis",   id = 4 },
    rtrigger  = { kind = "axis",   id = 5 },
}

-- Role name -> { kind, logical SDL id the handlers expect }.
M.ROLES = {
    a      = { kind = "button", id = 0 },
    b      = { kind = "button", id = 1 },
    x      = { kind = "button", id = 2 },
    y      = { kind = "button", id = 3 },
    select = { kind = "button", id = 4 },
    start  = { kind = "button", id = 6 },
    lb     = { kind = "button", id = 9 },
    rb     = { kind = "button", id = 10 },
    lt     = { kind = "axis",   id = 4 },
    rt     = { kind = "axis",   id = 5 },
}

-- Identity map: physical -> role at the same position.
M.IDENTITY = {
    south = "a", east = "b", west = "x", north = "y", back = "select",
    start = "start", lshoulder = "lb", rshoulder = "rb",
    ltrigger = "lt", rtrigger = "rt",
}

-- Known layouts (closed vocabulary shared with koligilo's panel editor; add
-- new ids to LAYOUTS, LAYOUT_ORDER, the menu labels in main.lua and the panel
-- together). `default` = built-in overrides on top of IDENTITY.
--   xbox        Xbox / generic XInput: labels match positions.
--   playstation DualShock / DualSense: positions as Xbox (cross = south =
--               role A); only the printed symbols differ.
--   nintendo    Switch Pro / Joy-Con / 8BitDo in Switch mode: printed A is
--               EAST, B south, X north, Y west. Default follows the printed
--               labels, so "press A" in kopad's docs means the A-labelled key.
--   valve       Steam Deck / Steam Controller: positions as Xbox (A/B/X/Y =
--               south/east/west/north), so the built-in default is identity;
--               only the printed labels differ (back = "View", start =
--               "Menu"; bumpers L1/R1, triggers L2/R2). Back paddles are not
--               available (see above).
M.LAYOUTS = {
    xbox        = { default = {} },
    playstation = { default = {} },
    nintendo    = { default = { east = "a", south = "b", north = "x", west = "y" } },
    valve       = { default = {} },
}
M.LAYOUT_ORDER = { "xbox", "playstation", "nintendo", "valve" }

-- Role-level actions (PC-014): what a role does while plainly reading. Closed
-- vocabulary shared with koligilo (padmap.go / web/padmap.js); padnav.lua
-- implements each id in PadNav:_run_action. Order = order in the panel.
--   next_page / prev_page   GotoViewRel +1 / -1
--   top_menu / footer_menu  the reader's top menu (where its settings live) /
--                           the footer (bottom) menu toggle
--   toc / bookmarks / history / file_browser
--                           the same targets X + LB / X + RB / X + D-pad
--                           left / X + D-pad right reach
--   sentence_select         open the sentence selector (A today)
--   highlights              open highlight mode, crosshair if none (Y today)
--   word_walk / crosshair   open the word walk / the crosshair
--   x_modifier              toggle the X modifier (X today)
--   none                    swallow the press; do nothing
M.ACTION_ORDER = {
    "next_page", "prev_page", "top_menu", "footer_menu",
    "toc", "bookmarks", "history", "file_browser",
    "sentence_select", "highlights", "word_walk", "crosshair",
    "x_modifier", "none",
}
M.ACTIONS = {}
for _, id in ipairs(M.ACTION_ORDER) do M.ACTIONS[id] = true end

-- What each role does in the idle reading context without an override. B is
-- absent on purpose: kopad does nothing there and KOReader's own Back runs, so
-- no action id describes it. An override equal to the default is dropped
-- (build_actions), which keeps the built-in handler -- and its pass-through in
-- paged documents -- exactly as it was.
M.DEFAULT_ACTIONS = {
    a = "sentence_select", x = "x_modifier", y = "highlights",
    lb = "prev_page", rb = "next_page", lt = "prev_page", rt = "next_page",
    select = "top_menu", start = "footer_menu",
}

-- Logical (kind, id) -> role name; nil for controls outside the vocabulary.
local ROLE_BY_CONTROL = { button = {}, axis = {} }
for name, r in pairs(M.ROLES) do ROLE_BY_CONTROL[r.kind][r.id] = name end
function M.role_of(kind, id)
    local t = ROLE_BY_CONTROL[kind]
    return t and t[id] or nil
end

local function noop() end

-- Role -> action overrides from the shared `padmap` value (already known to be
-- a table of the right version). Returns { [role] = action } holding only what
-- differs from DEFAULT_ACTIONS. Bad entries are skipped with a warning.
function M.build_actions(padmap, warn)
    warn = warn or noop
    local out = {}
    local raw = type(padmap) == "table" and padmap.actions or nil
    if raw == nil then return out end
    if type(raw) ~= "table" then
        warn("padmap: actions is not a table, ignored")
        return out
    end
    for role, action in pairs(raw) do
        if type(role) ~= "string" or not M.ROLES[role] then
            warn("padmap: unknown role " .. tostring(role) .. " in actions, ignored")
        elseif type(action) ~= "string" or not M.ACTIONS[action] then
            warn("padmap: unknown action " .. tostring(action) .. " for " .. role .. ", ignored")
        elseif action ~= M.DEFAULT_ACTIONS[role] then
            out[role] = action
        end
    end
    return out
end

-- Build the resolution tables for `layout` from the shared `padmap` value.
-- `warn` (optional) receives one string per skipped entry.
-- Returns { buttons = {[phys_id] = {kind,id}}, axes = {[phys_id] = {kind,id}},
--           layout = <name>, actions = {[role] = action} }.
function M.build(padmap, layout, warn)
    warn = warn or noop
    local map = {}
    for phys, role in pairs(M.IDENTITY) do map[phys] = role end

    if layout ~= nil and (type(layout) ~= "string" or not M.LAYOUTS[layout]) then
        warn("padmap: unknown layout " .. tostring(layout) .. ", using " .. M.DEFAULT_LAYOUT)
        layout = nil
    end
    layout = layout or M.DEFAULT_LAYOUT
    for phys, role in pairs(M.LAYOUTS[layout].default) do map[phys] = role end

    local user
    local actions = {}
    if padmap ~= nil then
        if type(padmap) ~= "table" then
            warn("padmap: not a table, ignored")
        elseif padmap.version ~= M.SCHEMA_VERSION then
            warn("padmap: unsupported version " .. tostring(padmap.version) .. ", ignored")
        else
            -- the two stages are independent: a broken `layouts` does not
            -- discard valid `actions` and vice versa
            actions = M.build_actions(padmap, warn)
            if padmap.layouts ~= nil and type(padmap.layouts) ~= "table" then
                warn("padmap: layouts is not a table, ignored")
            elseif padmap.layouts then
                for name in pairs(padmap.layouts) do
                    if not M.LAYOUTS[name] then
                        warn("padmap: unknown layout " .. tostring(name) .. " in data, ignored")
                    end
                end
                user = padmap.layouts[layout]
                if user ~= nil and type(user) ~= "table" then
                    warn("padmap: layout " .. layout .. " is not a table, ignored")
                    user = nil
                end
            end
        end
    end
    if user then
        for phys, role in pairs(user) do
            if not M.PHYSICAL[phys] then
                warn("padmap: unknown physical control " .. tostring(phys) .. ", ignored")
            elseif type(role) ~= "string" or not M.ROLES[role] then
                warn("padmap: unknown role " .. tostring(role) .. " for " .. phys .. ", ignored")
            else
                map[phys] = role
            end
        end
    end

    local res = { buttons = {}, axes = {}, layout = layout, actions = actions }
    for phys, role in pairs(map) do
        local p = M.PHYSICAL[phys]
        local r = M.ROLES[role]
        local t = p.kind == "button" and res.buttons or res.axes
        t[p.id] = { kind = r.kind, id = r.id }
    end
    return res
end

-- Resolve a physical SDL control to its logical role.
-- kind = "button" | "axis"; id = SDL id. Returns role_kind, role_id.
-- Controls outside the remappable set (D-pad, sticks, Guide, L3, R3, unknown)
-- and a nil/broken `resolved` come back unchanged.
function M.resolve(resolved, kind, id)
    local t = type(resolved) == "table"
        and (kind == "button" and resolved.buttons or kind == "axis" and resolved.axes) or nil
    local r = type(t) == "table" and t[id] or nil
    if r then return r.kind, r.id end
    return kind, id
end

return M
