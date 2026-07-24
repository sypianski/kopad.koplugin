--[[
llm.lua — thin, self-contained LLM transport for the plugin family.

Purpose: give keyreader/visel, kopad, wordsearch a way to run a one-shot chat
completion WITHOUT routing through assistant.koplugin's `querier` object. The
only thing we ever borrowed from assistant was a single POST to OpenRouter; this
module owns that POST outright, built purely on KOReader core modules
(socket.http / ssl.https / ltn12 / json). No assistant require, no fragile reach
into `self.ui.assistant.querier`.

Config lives in a vendored, gitignored `llm_config.lua` at each consumer plugin's
root (same pattern as assistant's own `configuration.lua`). See
`lib/llm_config.sample.lua`. When absent, `LLM.available()` returns false and
call sites fall back to the assistant path, so migration is non-breaking.

Vendored the same way as paginmapo.lua / pluginaro.lua: canonical source is
`lib/llm.lua`; `bin/sync-llm.fish` propagates verbatim copies into each consumer
plugin; the pre-commit hook fails on drift.

API:
  LLM.available()            -> bool     (true iff llm_config.lua has an api_key)
  LLM.config()               -> table|nil (resolved config, or nil)
  LLM.query(messages, opts)  -> text, err (blocking POST; run inside NetworkMgr)
  LLM.show_result(ui, title, text)        (rich viewer if assistant present, else core TextViewer)
]]

local http        = require("socket.http")
local https       = require("ssl.https")
local ltn12       = require("ltn12")
local socket      = require("socket")
local socketutil  = require("socketutil")
local json        = require("json")
local koutil      = require("util")
local logger      = require("logger")
local UIManager   = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _           = require("gettext")

local LLM = {}

-- Resolve config from the vendored, gitignored llm_config.lua. Returns nil when
-- the file is missing or carries no usable api_key (opt-in: absent = fall back).
function LLM.config()
    local ok, cfg = pcall(require, "llm_config")
    if not ok or type(cfg) ~= "table" then return nil end
    if type(cfg.api_key) ~= "string" or cfg.api_key == "" then return nil end
    return cfg
end

function LLM.available()
    return LLM.config() ~= nil
end

-- Blocking POST of an OpenAI/OpenRouter-shape chat completion. `messages` is the
-- standard {{role=, content=}, ...} list. Returns (text, nil) on success or
-- (nil, err_string) on failure. Must be called from inside
-- NetworkMgr:runWhenOnline (network may be down otherwise).
function LLM.query(messages, opts)
    opts = opts or {}
    local cfg = LLM.config()
    if not cfg then return nil, _("LLM not configured.") end

    local body = json.encode({
        model       = cfg.model,
        messages    = messages,
        max_tokens  = cfg.max_tokens or 4096,
        temperature = cfg.temperature or 0.7,
        stream      = false,
    })
    local headers = {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = "Bearer " .. cfg.api_key,
        ["HTTP-Referer"]  = "https://github.com/sypianski/koreader-konfig",
        ["X-Title"]       = "koreader-konfig",
    }

    local url = cfg.base_url or "https://openrouter.ai/api/v1/chat/completions"

    local sink = {}
    socketutil:set_timeout(opts.timeout or 20, opts.maxtime or 45)
    -- `https.cert_verify` is a module-level flag on the shared ssl.https module,
    -- so writing it leaks to every other plugin in the KOReader process. E-ink
    -- devices often lack a fresh CA bundle, so we still need verification off for
    -- THIS request — but scoped to it: save the previous value, override for the
    -- blocking call, and restore on every exit path. Lua is single-threaded and
    -- http.request blocks, so no other request runs in between; pcall guarantees
    -- the flag is restored even if the request raises.
    local is_https = url:sub(1, 8) == "https://"
    local prev_cert_verify
    if is_https then
        prev_cert_verify = https.cert_verify
        https.cert_verify = false
    end
    local ok_req, code = pcall(function()
        return socket.skip(1, http.request{
            url     = url,
            method  = "POST",
            headers = headers,
            source  = ltn12.source.string(body),
            sink    = ltn12.sink.table(sink),
        })
    end)
    if is_https then
        https.cert_verify = prev_cert_verify
    end
    socketutil:reset_timeout()
    if not ok_req then
        logger.warn("llm.query: request raised", code)
        return nil, _("Network error.")
    end
    local content = table.concat(sink)

    if code == socketutil.TIMEOUT_CODE or code == socketutil.SSL_HANDSHAKE_CODE
            or code == socketutil.SINK_TIMEOUT_CODE then
        return nil, _("Request timed out.")
    end
    if type(code) ~= "number" then
        return nil, _("Network error.")
    end

    local ok, data = pcall(json.decode, content)
    if ok and type(data) == "table" then
        local text = koutil.tableGetValue(data, "choices", 1, "message", "content")
        if text then return text end
        local api_err = koutil.tableGetValue(data, "error", "message")
        if api_err then return nil, api_err end
    end
    logger.warn("llm.query: bad response", code, content)
    return nil, _("Error: ") .. tostring(code)
end

-- Display an answer. When assistant.koplugin is installed we borrow its nicer
-- scrollable ChatGPTViewer (markdown + follow-up chat); otherwise fall back to
-- KOReader's core TextViewer. This is display-only reuse — no query/key coupling.
function LLM.show_result(ui, title, text)
    local assistant = ui and ui.assistant
    if assistant then
        local ok, ChatGPTViewer = pcall(require, "assistant_viewer")
        if ok then
            UIManager:show(ChatGPTViewer:new{
                assistant = assistant,
                ui        = ui,
                title     = title,
                text      = text or "",
            })
            return
        end
    end
    local TextViewer = require("ui/widget/textviewer")
    UIManager:show(TextViewer:new{
        title = title,
        text  = text or "",
    })
end

-- Query `messages`, showing the answer. Backend order:
--   1. our own transport (LLM.query) when llm_config.lua is present;
--   2. assistant.koplugin's querier as fallback — used both when our transport
--      is unconfigured AND when it fails at runtime (bad key, API down, …).
-- When neither is available, shows opts.err_msg (default "AI not available").
-- opts:
--   title      (string)      result + loading title (default "AI")
--   format(t)  -> string      transform applied to the answer before display
--   err_msg    (string)       message when no backend at all is available
--   err_timeout(number)       timeout for the no-backend InfoMessage
function LLM.ask(ui, messages, opts)
    opts = opts or {}
    local title  = opts.title or _("AI")
    local format = opts.format or function(t) return t end
    local NetworkMgr = require("ui/network/manager")

    -- Assistant fallback (streaming querier → needs Trapper:wrap). Returns false
    -- when assistant.koplugin is absent so the caller can report no-backend.
    local function assistant_fallback()
        local assistant = ui and ui.assistant
        if not assistant or not assistant.querier then return false end
        local ok_v, ChatGPTViewer = pcall(require, "assistant_viewer")
        if not ok_v then return false end
        local Trapper = require("ui/trapper")
        NetworkMgr:runWhenOnline(function()
            Trapper:wrap(function()
                local ret, err = assistant.querier:query(messages, _("Looking up…"))
                if err then assistant.querier:showError(err); return end
                UIManager:show(ChatGPTViewer:new{
                    assistant = assistant, ui = ui, title = title, text = format(ret or ""),
                })
            end)
        end)
        return true
    end

    local function no_backend()
        UIManager:show(InfoMessage:new{
            text = opts.err_msg or _("AI not available"), timeout = opts.err_timeout,
        })
    end

    if LLM.available() then
        NetworkMgr:runWhenOnline(function()
            -- Static "Looking up…" hint; force a repaint since LLM.query blocks.
            local info = InfoMessage:new{ text = _("Looking up…") }
            UIManager:show(info)
            UIManager:forceRePaint()
            local ret, err = LLM.query(messages, { title = title })
            UIManager:close(info)
            if err then
                -- Our transport failed → try assistant before giving up.
                logger.warn("llm.ask: own transport failed, trying assistant:", err)
                if not assistant_fallback() then no_backend() end
                return
            end
            LLM.show_result(ui, title, format(ret or ""))
        end)
        return
    end

    -- No own config → assistant is the primary path.
    if not assistant_fallback() then no_backend() end
end

return LLM
