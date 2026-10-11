--[[
kopad_trace — optional on-device diagnostic trace.

Appends timestamped lines to <settings dir>/kopad-trace.log, but ONLY while the
flag file <settings dir>/kopad-trace exists:

    touch  <settings dir>/kopad-trace     -- start tracing (no restart needed)
    rm     <settings dir>/kopad-trace     -- stop tracing

<settings dir> is DataStorage:getSettingsDir() (Flatpak:
~/.var/app/rocks.koreader.KOReader/config/koreader/settings/).

Guarantees:
  * without the flag: nothing is written; the cost per call is one cached
    boolean test (the flag is re-checked at most every FLAG_CACHE_S seconds);
  * every public function runs under pcall and never raises;
  * the log is capped (> MAX_BYTES -> only the last KEEP_BYTES survive);
  * at most MAX_LINES_PER_S lines per second; the excess is folded into one
    "(N lines dropped)" line;
  * a repeated axis event (same key within AXIS_DEDUP_S) is collapsed, see
    begin_event / end_event.

Module name is kopad_trace (not "trace") so it cannot collide with another
module in package.loaded. Only optional dependencies: datastorage, socket
(sub-second clock). Callers fall back to a no-op stub when this file is
missing, so the plugin works without it.
]]

local M = {}

M.FLAG_NAME        = "kopad-trace"
M.LOG_NAME         = "kopad-trace.log"
M.MAX_BYTES        = 256 * 1024
M.KEEP_BYTES       = 64 * 1024
M.FLAG_CACHE_S     = 2
M.MAX_LINES_PER_S  = 20
M.AXIS_DEDUP_S     = 0.3

-- Sub-second wall clock; replaceable (tests). Falls back to os.time().
local ok_socket, socket = pcall(require, "socket")
if ok_socket and type(socket) == "table" and type(socket.gettime) == "function" then
    M._clock = socket.gettime
else
    M._clock = os.time
end

local st = {}
local function reset_state()
    st.flag_t, st.flag_v = nil, false
    st.dir = nil
    st.win_t, st.win_n, st.dropped = nil, 0, 0
    st.ev_key, st.ev_t, st.ev_rep, st.suppress = nil, 0, 0, false
end
reset_state()

-- Test hook: forget all cached state.
function M._reset() reset_state() end

local function settings_dir()
    if st.dir then return st.dir end
    local ok, DataStorage = pcall(require, "datastorage")
    if not ok or type(DataStorage) ~= "table" then return nil end
    local ok2, dir = pcall(DataStorage.getSettingsDir, DataStorage)
    if ok2 and type(dir) == "string" and dir ~= "" then
        st.dir = dir
        return dir
    end
    return nil
end

local function file_exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function flag_active()
    local now = M._clock()
    if st.flag_t and (now - st.flag_t) < M.FLAG_CACHE_S and now >= st.flag_t then
        return st.flag_v
    end
    local dir = settings_dir()
    st.flag_v = dir ~= nil and file_exists(dir .. "/" .. M.FLAG_NAME)
    st.flag_t = now
    return st.flag_v
end

--- True while the flag file exists (cached ~2 s). Never raises.
function M.active()
    local ok, res = pcall(flag_active)
    return ok and res == true
end

local function stamp(now)
    local sec = math.floor(now)
    local ms = math.floor((now - sec) * 1000)
    return os.date("%Y-%m-%d %H:%M:%S", sec) .. string.format(".%03d", ms)
end

-- Keep only the last KEEP_BYTES of `path` (from a line boundary).
local function truncate(path)
    local f = io.open(path, "rb")
    if not f then return end
    local size = f:seek("end")
    f:seek("set", math.max(0, size - M.KEEP_BYTES))
    local tail = f:read("*a") or ""
    f:close()
    local nl = tail:find("\n", 1, true)
    if nl and size > M.KEEP_BYTES then tail = tail:sub(nl + 1) end
    local out = io.open(path, "wb")
    if not out then return end
    out:write("(log truncated: kept the last ", tostring(#tail), " bytes)\n", tail)
    out:close()
end

-- Append one finished line (no rate limiting here). Opens/closes the file per
-- line so the trace survives a crash.
local function append(now, text)
    local dir = settings_dir()
    if not dir then return end
    local path = dir .. "/" .. M.LOG_NAME
    local f = io.open(path, "ab")
    if not f then return end
    local size = f:seek("end") or 0
    f:write(stamp(now), " ", text, "\n")
    f:close()
    if size > M.MAX_BYTES then truncate(path) end
end

local function format_msg(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    if ok then return s end
    local parts = { tostring(fmt) }
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    return table.concat(parts, " ")
end

local function emit(now, text)
    -- 1-second window rate limit; the "dropped" notice is written lazily when
    -- the next window starts.
    if not st.win_t or (now - st.win_t) >= 1 or now < st.win_t then
        st.win_t, st.win_n = now, 0
        if st.dropped > 0 then
            local n = st.dropped
            st.dropped = 0
            append(now, string.format("(%d lines dropped)", n))
            st.win_n = 1
        end
    end
    if st.win_n >= M.MAX_LINES_PER_S then
        st.dropped = st.dropped + 1
        return
    end
    st.win_n = st.win_n + 1
    append(now, (text:gsub("\r?\n", "\\n")))
end

--- Trace.log(fmt, ...): string.format-style, appended only while the flag file
--- exists. Never raises.
function M.log(fmt, ...)
    pcall(function(...)
        if not flag_active() then return end
        if st.suppress then return end
        emit(M._clock(), format_msg(fmt, ...))
    end, ...)
end

--- Start of one input event. `key` (e.g. "axis:2:-1") makes a repeat of the
--- same key within AXIS_DEDUP_S collapse: Trace.log calls are dropped until
--- end_event, and one "(N repeats of <key> collapsed)" line is written when
--- a different event follows. key == nil never collapses (buttons).
function M.begin_event(key)
    pcall(function()
        if not flag_active() then st.suppress = false; return end
        local now = M._clock()
        if key ~= nil and key == st.ev_key and now >= st.ev_t
                and (now - st.ev_t) < M.AXIS_DEDUP_S then
            st.ev_t = now
            st.ev_rep = st.ev_rep + 1
            st.suppress = true
            return
        end
        st.suppress = false
        if st.ev_key ~= nil and st.ev_rep > 0 then
            emit(now, string.format("(%d repeats of %s collapsed)", st.ev_rep, st.ev_key))
        end
        st.ev_key, st.ev_t, st.ev_rep = key, now, 0
    end)
end

--- End of the event opened by begin_event (re-enables logging).
function M.end_event()
    st.suppress = false
end

--- "mtime=YYYY-MM-DD HH:MM:SS size=N" for a file, "missing" if unreadable.
--- Uses lfs when available, otherwise only the size. Never raises.
function M.file_stamp(path)
    local ok, res = pcall(function()
        for _, name in ipairs({ "libs/libkoreader-lfs", "lfs" }) do
            local okl, lfs = pcall(require, name)
            if okl and type(lfs) == "table" and lfs.attributes then
                local attr = lfs.attributes(path)
                if attr then
                    return string.format("mtime=%s size=%s",
                        os.date("%Y-%m-%d %H:%M:%S", attr.modification), tostring(attr.size))
                end
                return "missing"
            end
        end
        local f = io.open(path, "rb")
        if not f then return "missing" end
        local size = f:seek("end")
        f:close()
        return string.format("mtime=? size=%s", tostring(size))
    end)
    return ok and res or "?"
end

return M
