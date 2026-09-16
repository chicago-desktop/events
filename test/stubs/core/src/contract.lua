-- Harness stand-in for kickside.core.threads:contract: the two reads Event
-- Viewer makes, written from the contract's behaviour.
--
--   list(args)        -> {threads = rows}; `limit` 1..1000, `thread_class`
--   list_events(args) -> {events = rows}; `thread_id` required, newest first
--                        unless `ascending`, only seqs below `before`, at
--                        most `limit` (1..1000), only `event_type` when given
--
-- A refusal is an error with a kind, as the real contract returns one. Three
-- threads in two classes: t-runs with 130 events (run.started on even seqs,
-- run.finished on odd), t-journal with three, and t-locked whose events are
-- refused as a thread the caller may not read.
local errors = require("errors")

local contract = {}

local STARTED = "acme.bridge.events:run.started"
local FINISHED = "acme.bridge.events:run.finished"
local APPENDED = "chestor.journal.events:entry.appended"

local THREADS: {any} = {
    {id = "t-runs", thread_class = "agent.run", component_id = "c-runs", component_title = "Runs",
        attrs = "{}", event_count = 130, last_event_ts = "2026-09-07 10:10:00"},
    {id = "t-journal", thread_class = "workspace.journal", component_id = "c-journal", component_title = "Journal",
        attrs = "{}", event_count = 3, last_event_ts = "2026-09-07 08:03:00"},
    {id = "t-locked", thread_class = "workspace.journal", component_id = "c-locked", component_title = "Locked",
        attrs = "{}", event_count = 1, last_event_ts = "2026-09-07 08:01:00"},
}

local function two(value: number): string
    local text = tostring(math.floor(value))
    if #text < 2 then return "0" .. text end
    return text
end

-- A SQLite UTC datetime, one minute per seq from 08:00.
local function stamp(seq: number): string
    return "2026-09-07 " .. two(8 + math.floor(seq / 60)) .. ":" .. two(seq % 60) .. ":00"
end

local function run_event(seq: number): any
    local started = seq % 2 == 0
    local id = tostring(math.floor(seq))
    return {id = "run-" .. id, thread_id = "t-runs", type = started and STARTED or FINISHED, role = "system",
        seq = seq, created_at = stamp(seq), content_mode = "inline",
        body = "{\"run_id\":\"r" .. id .. "\",\"status\":\"" .. (started and "started" or "finished") .. "\"}"}
end

local function journal_event(seq: number): any
    local id = tostring(math.floor(seq))
    return {id = "journal-" .. id, thread_id = "t-journal", type = APPENDED, role = "user",
        seq = seq, created_at = stamp(seq), content_mode = "inline",
        body = "{\"title\":\"Entry " .. id .. "\"}"}
end

-- Oldest first, as a log is written.
local EVENTS: {[string]: {any}} = {["t-runs"] = {}, ["t-journal"] = {}}
for seq = 1, 130 do EVENTS["t-runs"][seq] = run_event(seq) end
for seq = 1, 3 do EVENTS["t-journal"][seq] = journal_event(seq) end

local function invalid(message: string): any
    return errors.new({message = message, kind = errors.INVALID})
end

local function copy(row: any): any
    local out = {}
    for key, value in pairs(row) do out[key] = value end
    return out
end

-- limit_of(value) -> limit, err: absent is the default, otherwise a whole
-- number in 1..1000.
local function limit_of(value: any, default: number): (number?, any)
    if value == nil then return default, nil end
    if type(value) ~= "number" or value ~= math.floor(value) or value < 1 or value > 1000 then
        return nil, invalid("limit must be an integer between 1 and 1000")
    end
    return value, nil
end

function contract.list(args: any): (any, any)
    local request: any = type(args) == "table" and args or {}
    local _, err = limit_of(request.limit, 1000)
    if err ~= nil then return nil, err end
    local rows = {}
    for _, thread in ipairs(THREADS) do
        if request.thread_class == nil or thread.thread_class == request.thread_class then
            rows[#rows + 1] = copy(thread)
        end
    end
    return {threads = rows}, nil
end

function contract.list_events(args: any): (any, any)
    local request: any = type(args) == "table" and args or {}
    if type(request.thread_id) ~= "string" or request.thread_id == "" then
        return nil, invalid("thread_id is required")
    end
    if request.thread_id == "t-locked" then
        return nil, errors.new({message = "no read access to thread t-locked (harness stand-in)",
            kind = errors.PERMISSION_DENIED})
    end
    local limit, err = limit_of(request.limit, 100)
    if err ~= nil then return nil, err end
    local wanted = tonumber(limit) or 100
    local before = tonumber(request.before)
    -- The real contract's seq bounds, both inclusive.
    local from_seq = tonumber(request.from_seq)
    local to_seq = tonumber(request.to_seq)
    local event_type = request.event_type
    local rows = EVENTS[request.thread_id] or {}
    local first, last, step = #rows, 1, -1
    if request.ascending == true then first, last, step = 1, #rows, 1 end
    local out = {}
    for index = first, last, step do
        local row = rows[index]
        if (before == nil or row.seq < before) and (event_type == nil or row.type == event_type)
            and (from_seq == nil or row.seq >= from_seq) and (to_seq == nil or row.seq <= to_seq) then
            out[#out + 1] = copy(row)
            if #out >= wanted then break end
        end
    end
    return {events = out}, nil
end

return contract
