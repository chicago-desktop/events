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

local definition = window.definition

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

local function opened(): (any, any)
    local context = app.context({width = 100, height = 26})
    local state = definition.init("", context)
    return state, context
end

local function define_tests()
    test.describe("Event Viewer window entry", function()
        test.it("is Event Viewer in Settings with the module's own text_document picture", function()
            local entry, err = registry.get("chicago.events:window")
            test.is_nil(err, tostring(err))
            local record: any = entry
            local meta: any = record and type(record.meta) == "table" and record.meta or {}
            test.eq(table.concat({tostring(meta.type), tostring(meta.title), tostring(meta.group), tostring(meta.image),
                tostring(meta.pixel_render), tostring(meta.pixel_state)}, "|"),
                "tui_desktop.window|Event Viewer|Settings|chicago.events:images/text_document|chicago.shell.sdk:render|chicago.events:window")
            for _, size in ipairs({32, 16}) do
                local picture, why = images.get("chicago.events:images/text_document", size)
                test.not_nil(picture, "text_document@" .. tostring(size) .. ": " .. tostring(why))
            end
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

        test.it("opens an event's properties, and Esc goes back to the list", function()
            local state, context = opened()
            local first = state.events[1]
            test.is_true(definition.update(state, {type = "activate", id = "events", value = {id = first.id}}, context))
            test.eq(state.mode, "details")
            local sheet = definition.view(state, context)
            test.eq(by_id(sheet, "payload").text, "{\n  \"run_id\": \"r130\",\n  \"status\": \"started\"\n}")
            test.is_nil(by_id(sheet, "events"), "the sheet replaces the list")
            test.is_true(definition.update(state, {type = "key", key_type = "esc"}, context))
            test.eq(state.mode, "list")
            test.not_nil(by_id(definition.view(state, context), "events"))
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
end

local run_cases = test.run_cases(define_tests)
return {run = function(options) return run_cases(options) end}
