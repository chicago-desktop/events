-- Event Viewer's window: the registry entry the Start menu reads, the
-- module's own picture, the window's policy, and the process's definition
-- run against the harness's stand-in for kickside.core.threads:contract
-- (test/stubs/core) — three logs in two classes, 130 events in the first, a
-- log whose events are refused.
local test = require("test")
local registry = require("registry")
local app = require("app")
local images = require("images")
local window = require("window")
local event_window = require("event_window")
local json = require("json")

local definition = window.definition
local REAL = definition.deps
local event_definition = event_window.definition

local STARTED = "acme.bridge.events:run.started"

local function walk(node: any, visit: any)
    if type(node) ~= "table" then return end
    visit(node)
    for _, child in ipairs(type(node.children) == "table" and node.children or {}) do walk(child, visit) end
end

-- find(tree, wanted) — the first node the predicate accepts. The hit is kept
-- in a table, not in a local the closure shares.
local function find(tree: any, wanted: any): any
    local hit: any = {}
    walk(tree, function(node: any)
        if hit.node == nil and wanted(node) then hit.node = node end
    end)
    return hit.node
end

local function by_id(tree: any, id: string): any
    return find(tree, function(node: any): boolean return node.id == id end)
end

local function status(state: any, context: any): string
    local bar = find(definition.view(state, context), function(node: any): boolean return node.kind == "statusbar" end)
    if bar == nil then return "" end
    return tostring(bar.fields[1].text)
end

-- A stand-in compositor: what the list asked it, and its reply channel.
-- `given.no_replies` is a list with no reply channel.
local function opened(given: any?): (any, any, any, any)
    local opts: any = given or {}
    local log: any = {calls = {}}
    local replies: any = {name = "replies"}
    definition.deps = {json = REAL.json, desktop = {
        replies = function(): any
            if opts.no_replies then return nil end
            return replies
        end,
        request = function(topic: any): (any, any)
            log.calls[#log.calls + 1] = {topic = topic}
            return true, nil
        end,
        open = function(spec: any): (any, any)
            log.calls[#log.calls + 1] = {topic = "desktop.open", spec = spec}
            return true, nil
        end,
        focus = function(id: any): (any, any)
            log.calls[#log.calls + 1] = {topic = "desktop.focus", id = id}
            return true, nil
        end,
    }}
    local context = app.context({width = 100, height = 26})
    local state = definition.init("", context)
    return state, context, log, replies
end

local function last(log: any): any return log.calls[#log.calls] or {} end

local function listed(replies: any, windows: any): any
    return {type = "channel", ok = true, channel = replies,
        value = {command = "desktop.list", ok = true, windows = windows}}
end

local function define_tests()
    test.describe("Event Viewer window entry", function()
        test.it("is Event Viewer in Settings with the module's own event_viewer picture", function()
            local entry, err = registry.get("chicago.events:window")
            test.is_nil(err, tostring(err))
            local record: any = entry
            local meta: any = record and type(record.meta) == "table" and record.meta or {}
            test.eq(table.concat({tostring(meta.type), tostring(meta.title), tostring(meta.group), tostring(meta.image),
                tostring(meta.pixel_render), tostring(meta.pixel_state)}, "|"),
                "tui_desktop.window|Event Viewer|Settings|chicago.events:images/event_viewer|chicago.shell.sdk:render|chicago.events:window")
            for _, size in ipairs({32, 16}) do
                local picture, why = images.get("chicago.events:images/event_viewer", size)
                test.not_nil(picture, "event_viewer@" .. tostring(size) .. ": " .. tostring(why))
            end
        end)

        test.it("declares the event window outside the menu, with the same picture and policy", function()
            local record: any = assert(registry.get("chicago.events:event"))
            local meta: any = record.meta or {}
            test.eq(table.concat({tostring(meta.type), tostring(meta.title), tostring(meta.in_menu),
                tostring(meta.image), tostring(meta.pixel_state)}, "|"),
                "tui_desktop.window|Event Properties|false|chicago.events:images/event_viewer|chicago.events:event")
            local policies = (record.data and record.data.security and record.data.security.policies) or {}
            test.eq(table.concat(policies, ","), "chicago.events:window_scope")
        end)

        test.it("runs under its own policy, which only talks to the compositor", function()
            local record: any = assert(registry.get("chicago.events:window"))
            local policies = (record.data and record.data.security and record.data.security.policies) or {}
            test.eq(table.concat(policies, ","), "chicago.events:window_scope")
            local scope: any = assert(registry.get("chicago.events:window_scope"))
            local policy: any = scope.data and scope.data.policy or {}
            test.eq(table.concat(policy.actions or {}, ","), "process.context,process.registry,process.send")
        end)
    end)

    test.describe("Event Viewer window over the threads contract", function()
        test.it("opens the first log in tree order with its newest page", function()
            local state, context = opened()
            test.is_nil(state.log_failure, tostring(state.log_failure))
            test.eq(#state.logs, 3)
            test.eq(state.log_id, "t-runs", "the first log of the first class")
            test.eq(#state.events, 100, "one page, not the whole log")
            test.eq(state.events[1].seq, 130, "newest first")
            test.eq(state.more, true)
            local tree = definition.view(state, context)
            test.eq(#by_id(tree, "logs").rows, 5, "two folders and three logs")
            test.eq(#by_id(tree, "events").rows, 100)
            test.eq(status(state, context), " Runs: 100 events loaded, more below")
        end)

        test.it("loads the next page when the table says end, and stops at the end of the log", function()
            local state, context = opened()
            test.is_true(definition.update(state, {type = "end", id = "events"}, context))
            test.eq(#state.events, 130)
            test.eq(state.events[130].seq, 1)
            test.eq(state.more, false, "a short page is the end of the log")
            test.is_false(definition.update(state, {type = "end", id = "events"}, context), "nothing below the last page")
            test.eq(#state.events, 130)
            test.eq(status(state, context), " Runs: 130 events loaded")
        end)

        test.it("asks the contract for one type, and Clear filter asks for all again", function()
            local state, context = opened()
            test.is_true(definition.update(state, {type = "change", id = "type", value = STARTED}, context))
            test.eq(#state.events, 65)
            for _, event in ipairs(state.events) do test.eq(event.type, STARTED) end
            test.eq(state.more, false)
            test.eq(status(state, context), " Runs: 65 events loaded · type " .. STARTED)
            test.is_true(definition.update(state, {type = "activate", id = "clear"}, context))
            test.eq(state.type, "")
            test.eq(#state.events, 100)
        end)

        test.it("opens an event in a window of its own, after asking what is open", function()
            local state, context, log, replies = opened()
            local first = state.events[1]
            test.is_true(definition.update(state, {type = "activate", id = "events", value = {id = first.id}}, context))
            test.eq(last(log).topic, "desktop.list", "first it asks what is open")
            test.not_nil(by_id(definition.view(state, context), "events"), "the list stays a list")
            test.is_true(definition.update(state, listed(replies, {
                {id = "w5", entry = "chicago.events:event", args = json.encode({thread_id = "t-runs", seq = 129})},
            }), context))
            local opened_call = last(log)
            test.eq(opened_call.topic, "desktop.open", "another event's window is not this one")
            test.eq(opened_call.spec.entry, "chicago.events:event")
            local args: any = json.decode(tostring(opened_call.spec.args))
            test.eq(tostring(args.thread_id) .. "|" .. tostring(args.seq) .. "|" .. tostring(args.log), "t-runs|130|Runs",
                "the window is told which event, not given it")
        end)

        test.it("raises the window already showing the event instead of opening a second", function()
            local state, context, log, replies = opened()
            local first = state.events[1]
            definition.update(state, {type = "activate", id = "events", value = {id = first.id}}, context)
            definition.update(state, listed(replies, {
                {id = "w7", entry = "chicago.events:event", args = json.encode({thread_id = "t-runs", seq = 130, log = "Runs"})},
            }), context)
            test.eq(last(log).topic, "desktop.focus")
            test.eq(last(log).id, "w7")
        end)

        test.it("opens straight away without a reply channel, and says a refusal on the channel", function()
            local state, context, log = opened({no_replies = true})
            local first = state.events[1]
            definition.update(state, {type = "activate", id = "events", value = {id = first.id}}, context)
            test.eq(last(log).topic, "desktop.open", "without a reply channel it opens at once")
            local listing, lcontext, _, replies = opened()
            test.is_true(definition.update(listing, {type = "channel", ok = true, channel = replies,
                value = {command = "desktop.open", ok = false, error = "no room"}}, lcontext))
            test.eq(status(listing, lcontext), " desktop.open refused: no room")
        end)

        test.it("names a refused log in the status bar instead of showing it empty", function()
            local state, context = opened()
            test.is_true(definition.update(state, {type = "select", id = "logs", value = {id = "log:t-locked"}}, context))
            test.eq(state.log_id, "t-locked")
            test.eq(#state.events, 0)
            local failure = tostring(state.failure)
            test.eq(failure:sub(1, #"events: permission denied"), "events: permission denied",
                "the refusal's kind decides the wording: " .. failure)
            local tree = definition.view(state, context)
            test.not_nil(find(tree, function(node: any): boolean return node.text == "The events could not be read." end))
            test.eq(status(state, context), " " .. failure)
        end)
    end)

    test.describe("Event Properties window", function()
        local function event_opened(args: any): (any, any)
            local context = app.context({width = 76, height = 26})
            local state = event_definition.init(args, context)
            return state, context
        end

        test.it("reads the event it is told of and shows its properties and payload", function()
            local state, context = event_opened(json.encode({thread_id = "t-runs", seq = 130, log = "Runs"}))
            test.is_nil(state.failure, tostring(state.failure))
            test.eq(state.event.seq, 130)
            local sheet = event_definition.view(state, context)
            test.eq(by_id(sheet, "payload").text, "{\n  \"run_id\": \"r130\",\n  \"status\": \"started\"\n}")
            test.eq(event_definition.title(state), "Event Properties — run.started", "the caption names the event")
            local pairs_table = find(sheet, function(node: any): boolean return node.kind == "table" end)
            local log_value: any = nil
            for _, row in ipairs(pairs_table and pairs_table.rows or {}) do
                if row.cells[1] == "Log" then log_value = row.cells[2] end
            end
            test.eq(log_value, "Runs", "the log the list named")
        end)

        test.it("reads one event by its sequence, not the first of the log", function()
            local state = event_opened(json.encode({thread_id = "t-runs", seq = 7, log = "Runs"}))
            test.eq(state.event and state.event.seq, 7)
        end)

        test.it("says why there is nothing to show, and Close closes", function()
            local cases = {
                {args = "", want = "not told which event"},
                {args = json.encode({thread_id = "t-runs", seq = 9999}), want = "no longer in this log"},
                {args = json.encode({thread_id = "t-locked", seq = 1}), want = "permission denied"},
            }
            for _, case in ipairs(cases) do
                local state, context = event_opened(case.args)
                test.is_nil(state.event)
                local sheet = event_definition.view(state, context)
                local missing = by_id(sheet, "missing")
                test.not_nil(missing, case.want)
                test.is_true(tostring(missing.text):find(case.want, 1, true) ~= nil, tostring(missing.text))
            end
            local state, context = event_opened("")
            local closed: any = {}
            context.close = function() closed.yes = true end
            test.is_true(event_definition.update(state, {type = "activate", id = "close"}, context))
            test.is_true(closed.yes, "Close closes the window")
        end)
    end)
end

local run_cases = test.run_cases(define_tests)
return {run = function(options) return run_cases(options) end}
