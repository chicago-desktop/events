-- Event Properties — one event in a window of its own.
--
-- Opened by the Event Viewer list with {thread_id, seq, log} as JSON. The
-- window reads the event itself — the threads contract's list_events bounded
-- to that one sequence number — so a payload of any size never travels
-- through a window argument, and the window shows what the contract lets
-- the logged-on person read, the same as the list does.
local app = require("app")
local model = require("model")
local format = require("format")
local threads = require("threads")
local time = require("time")
local json = require("json")

local definition: any = {title = model.EVENT_TITLE}

-- The runtime's libraries behind one table: a test swaps them.
definition.deps = {threads = threads, json = json, time = time}

local function deps(): any
    return definition.deps
end

-- load(state) — the event the args name, or the reason there is none.
local function load(state: any)
    state.event, state.failure = nil, nil
    if state.thread_id == nil or state.seq == nil then
        state.failure = "This window was not told which event to show."
        return
    end
    local d = deps()
    local result, err = d.threads.list_events(model.event_request(tostring(state.thread_id), state.seq))
    if err ~= nil or type(result) ~= "table" then
        state.failure = format.explain("event", err)
        return
    end
    local events, problem = model.events((result :: any).events)
    for _, event in ipairs(events) do
        if event.seq == state.seq then state.event = event end
    end
    if state.event == nil then
        state.failure = problem or ("Event " .. tostring(state.seq) .. " is no longer in this log.")
    end
end

function definition.init(args: any, context: any): any
    local d = deps()
    local wanted = model.read_args(args, d.json.decode)
    local state: any = {thread_id = wanted.thread_id, seq = wanted.seq, log = wanted.log,
        offset = format.parse_offset(d.time.now():format("-07:00")), event = nil, failure = nil}
    load(state)
    return state
end

-- The caption names the event: two windows of the same kind side by side
-- are told apart on the taskbar.
function definition.title(state: any): string
    if state.event then return model.EVENT_TITLE .. " — " .. tostring(state.event.name) end
    return model.EVENT_TITLE
end

function definition.view(state: any, context: any): any
    if state.event then
        return model.details_tree(state.event, state.log, tonumber(state.offset) or 0)
    end
    return model.missing_tree(state.failure)
end

function definition.update(state: any, action: any, context: any): boolean
    if action.type == "activate" and action.id == "close" then
        context.close()
        return true
    end
    if action.type == "key" and (action.key_type == "f5" or action.key == "F5") then
        load(state)
        return true
    end
    return false
end

definition.close_on_escape = true

return {main = app.main(definition), definition = definition}
