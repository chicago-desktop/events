-- Event Viewer — the platform's threads and their events in the Chicago
-- shell, with the look of the classic Event Viewer.
--
-- A window on the shell SDK. IO lives here and does what the HTTP handlers of
-- kickside/core do, without HTTP: the log tree is kickside.core.threads:contract
-- list (list_threads.lua), a log's events are its list_events (list_events.lua),
-- a page of model.PAGE at a time, newest first. Nothing loads a whole log: the
-- next page is asked for when the table says `end` — the wheel or the keys
-- pushed past its last loaded row.
--
-- The contract lists only threads whose component the caller may read, so the
-- window shows what the web UI shows the logged-in user. Threads without a
-- component (the lifecycle logs, most of the events in the database) are not
-- in that listing, and the window does not go around it to the table.
--
-- A double click (or Enter) on an event opens it in a window of its own,
-- chicago.events:event — one window per event: the list asks the compositor
-- what is open (`desktop.list`, answered on the reply channel) and raises the
-- window already showing that event, or opens one. The event window is told
-- only which event and reads it itself.
local app = require("app")
local model = require("model")
local format = require("format")
local threads = require("threads")
local time = require("time")
local desktop = require("desktop")
local json = require("json")

local definition: any = {title = "Event Viewer"}

-- The compositor's API and the encoder behind one table: a test swaps them
-- and checks what the list asked for.
definition.deps = {desktop = desktop, json = json}

local function deps(): any
    return definition.deps
end

local TREE_WIDTH = 32

local COLUMNS = {
    {title = "Time", width = 17},
    {title = "Source", weight = 2},
    {title = "Type", weight = 2},
    {title = "Message", weight = 5},
}

-- ─── IO ─────────────────────────────────────────────────────────────────

local function load_logs(state: any)
    state.log_failure = nil
    state.offset = format.parse_offset(time.now():format("-07:00"))
    local result, err = threads.list({limit = model.THREAD_LIMIT})
    if err ~= nil or type(result) ~= "table" then
        state.logs, state.log_failure = {}, format.explain("logs", err)
        return
    end
    local logs, problem = model.logs((result :: any).threads)
    state.logs, state.log_failure = logs, problem
    if state.log_id ~= nil and model.find_log(logs, state.log_id) == nil then
        state.log_id, state.events, state.more = nil, {}, false
    end
end

-- load_events(state, more) — the first page of the chosen log, or with
-- `more` the page below the loaded ones.
local function load_events(state: any, more: boolean)
    state.failure = nil
    if state.log_id == nil then
        state.events, state.more = {}, false
        return
    end
    local before = nil
    if more then before = model.next_before(state.events) end
    local result, err = threads.list_events(model.page_request(tostring(state.log_id), before, state.type))
    if err ~= nil or type(result) ~= "table" then
        state.failure, state.more = format.explain("events", err), false
        if not more then state.events = {} end
        return
    end
    local page, problem = model.events((result :: any).events)
    if more then state.events = model.merge(state.events, page) else state.events = page end
    state.more, state.failure = model.has_more(page), problem
end

-- ─── state ──────────────────────────────────────────────────────────────

local function open_log(state: any, id: any)
    state.log_id, state.tree_id = id, model.log_id(tostring(id))
    state.event_id, state.type = nil, model.ALL_TYPES
    load_events(state, false)
end

function definition.init(args: any, context: any): any
    local state: any = {logs = {}, collapsed = {}, log_id = nil, tree_id = nil,
        events = {}, more = false, event_id = nil, type = model.ALL_TYPES, find = "",
        offset = 0, failure = nil, log_failure = nil, notice = nil, opening = nil, replies = nil}
    local replies = deps().desktop.replies()
    if replies then
        state.replies = replies
        context.watch(replies)
    end
    load_logs(state)
    local first = model.first_log(state.logs)
    if first then open_log(state, first.id) end
    return state
end

local function current_log(state: any): any
    return model.find_log(state.logs, state.log_id)
end

-- ─── view ───────────────────────────────────────────────────────────────

local function events_body(state: any, visible: any): any
    if state.log_id == nil then return {kind = "label", text = model.PICK} end
    if #visible > 0 then
        return {kind = "table", id = "events", columns = COLUMNS,
            rows = model.table_rows(visible, tonumber(state.offset) or 0), selected = state.event_id}
    end
    if state.failure then return {kind = "label", text = "The events could not be read.", alert = true} end
    if #state.events > 0 then return {kind = "label", text = model.NO_MATCH} end
    return {kind = "label", text = model.EMPTY_EVENTS}
end

local function list_view(state: any): any
    local visible = model.visible(state.events, state.find)
    local rows = model.tree_rows(state.logs, state.collapsed)
    local left: any
    if #rows == 0 then
        left = {kind = "label", size = TREE_WIDTH, alert = state.log_failure ~= nil,
            text = state.log_failure and "The logs could not be read." or model.EMPTY_LOGS}
    else
        left = {kind = "tree", id = "logs", size = TREE_WIDTH, rows = rows, selected = state.tree_id}
    end
    local filtered = state.type ~= model.ALL_TYPES or state.find ~= ""
    local right: any = {kind = "column", gap = 0, children = {
        {kind = "row", size = 2, gap = 1, children = {
            {kind = "label", size = 5, text = "Type:"},
            {kind = "select", id = "type", size = 34, value = state.type,
                options = model.type_options(state.events, state.type), disabled = state.log_id == nil},
            {kind = "label", size = 5, text = "Find:"},
            {kind = "input", id = "find", text = state.find, placeholder = "text in the loaded events"},
        }},
        events_body(state, visible),
        {kind = "row", size = 2, gap = 1, align = "right", children = {
            {kind = "button", id = "refresh", size = 11, text = "Refresh"},
            {kind = "button", id = "clear", size = 14, text = "Clear filter", disabled = not filtered},
            {kind = "button", id = "close", size = 9, text = "Close", default = true},
        }},
    }}
    return {kind = "row", padding = 1, padding_bottom = 0, gap = 1, children = {left, right}}
end

local function status_text(state: any): string
    if state.notice then return tostring(state.notice) end
    if state.log_failure then return tostring(state.log_failure) end
    if state.failure then return tostring(state.failure) end
    local log = current_log(state)
    if not log then return tostring(#state.logs) .. " logs" end
    local shown = #model.visible(state.events, state.find)
    return log.label .. ": " .. model.summary(#state.events, shown, state.more == true, state.find, state.type)
end

function definition.view(state: any, context: any): any
    return {kind = "column", gap = 0, children = {
        list_view(state),
        {kind = "statusbar", size = 1, fields = {{text = " " .. status_text(state)}}},
    }}
end

-- ─── update ─────────────────────────────────────────────────────────────

local function find_event(state: any, id: any): any
    for _, event in ipairs(state.events) do
        if event.id == id then return event end
    end
    return nil
end

-- launch(state, wanted) — open the event's window. A refusal goes to the
-- status bar.
local function launch(state: any, wanted: any)
    local d = deps()
    local encoded, eerr = d.json.encode(wanted)
    if not encoded then
        state.notice = format.explain("open the event", eerr)
        return
    end
    local ok, err = d.desktop.open({entry = model.EVENT_ENTRY, title = model.EVENT_TITLE, args = encoded})
    if not ok then state.notice = format.explain("open the event", err) end
end

-- open_event(state) — one window per event. The list asks what is open
-- first and decides on the answer (`reply`); without a reply channel it
-- opens a new window rather than doing nothing.
local function open_event(state: any)
    local event = find_event(state, state.event_id)
    if not event then return end
    local log = current_log(state)
    local wanted = model.event_args(event, state.log_id, log and log.label or "")
    state.notice = nil
    if state.replies ~= nil and deps().desktop.request("desktop.list", {}) then
        state.opening = wanted
        return
    end
    launch(state, wanted)
end

-- reply(state, action) — the compositor's answer: the window list an open is
-- waiting for (raise the event's window if it is there, open it if not), or
-- a refusal of a command sent earlier.
local function reply(state: any, action: any): boolean
    local kind, windows, why = model.take_reply(model.unwrap(action.value))
    if kind == "notice" then
        state.notice = tostring(windows)
        return true
    end
    if kind ~= "list" or state.opening == nil then return false end
    local wanted: any = state.opening
    state.opening = nil
    local d = deps()
    -- A refused list still opens the window: the list cannot see what is
    -- open, and a second copy beats doing nothing.
    local id = why == nil and model.open_target(windows, wanted, d.json.decode) or nil
    if id then
        local ok, err = d.desktop.focus(id)
        if not ok then state.notice = format.explain("raise the event", err) end
        return true
    end
    launch(state, wanted)
    return true
end

local function refresh(state: any)
    load_logs(state)
    load_events(state, false)
end

local function on_tree(state: any, action: any): boolean
    local row: any = action.value
    local id = type(row) == "table" and row.id or nil
    local class = model.group_of(id)
    if action.type == "toggle" or (action.type == "activate" and class) then
        if class then state.collapsed[class] = not (state.collapsed[class] == true) end
        return true
    end
    if action.type ~= "select" then return false end
    local log_id = model.log_of(id)
    if log_id then
        if log_id ~= state.log_id then open_log(state, log_id) end
    else
        state.tree_id = id
    end
    return true
end

local function on_events(state: any, action: any): boolean
    local value: any = action.value
    local id = type(value) == "table" and value.id or nil
    local again = id ~= nil and id == state.event_id and action.pointer == true
    state.event_id = id or state.event_id
    if action.type == "activate" or again then
        open_event(state)
        return true
    end
    return true
end

function definition.update(state: any, action: any, context: any)
    if action.type == "channel" then
        if not action.ok then return false end
        if state.replies ~= nil and action.channel == state.replies then return reply(state, action) end
        return false
    end
    if action.type == "resize" or action.type == "tick" or action.type == "timer" then return false end

    if action.type == "key" then
        if action.key_type == "f5" or action.key == "F5" then
            refresh(state)
            return true
        end
        return false
    end

    if model.loads_more(action, state.more == true) then
        load_events(state, true)
        return true
    end
    if action.id == "logs" then return on_tree(state, action) end
    if action.id == "events" and (action.type == "select" or action.type == "activate") then
        return on_events(state, action)
    end

    if action.type == "change" then
        if action.id == "type" then
            state.type, state.event_id = tostring(action.value or ""), nil
            load_events(state, false)
            return true
        end
        if action.id == "find" then
            state.find = tostring(action.value or "")
            return true
        end
        return false
    end

    if action.type ~= "activate" then return false end
    if action.id == "close" then
        context.close()
    elseif action.id == "refresh" then
        refresh(state)
    elseif action.id == "clear" then
        state.type, state.find, state.event_id = model.ALL_TYPES, "", nil
        load_events(state, false)
    end
    return true
end

definition.close_on_escape = true

return {main = app.main(definition), definition = definition}
