--[[
    dialplan.lua
    Handles dynamic dialplan lookups from PostgreSQL using view_dialplan_expanded.
    Groups conditions and actions by context and extension, then builds XML.
--]]

-- Dependencies
local pg = require("luasql.postgres")
local env = pg.postgres()

-- Settings module
local settings = require("resources.settings.settings")
local log = function(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[Dialplan] " .. message .. "\n")
end

-- Input context (from FreeSWITCH)
local context = XML_REQUEST["context"] or "default"
log("INFO", "Dialplan lookup for context: " .. context)

-- Connect to database
local dbh = env:connect("ring2all")
if not dbh then
    log("ERR", "Failed to connect to PostgreSQL database")
    return
end

-- Query all dialplan rules for this context
local sql = [[
SELECT * FROM view_dialplan_expanded
WHERE context_name = '%s'
ORDER BY extension_priority, action_sequence
]]
sql = string.format(sql, dbh:escape(context))

local result = {}
for row in dbh:rows(sql) do
    table.insert(result, row)
end

if #result == 0 then
    log("WARNING", "No dialplan found for context: " .. context)
    XML_STRING = settings.format_xml("dialplan", "")
    return
end

-- Group data by extension and condition
local dialplan = {}
for _, row in ipairs(result) do
    local ext = row.extension_name
    local cond = row.condition_field .. "=" .. row.condition_expr

    dialplan[ext] = dialplan[ext] or {}
    dialplan[ext][cond] = dialplan[ext][cond] or { actions = {}, anti_actions = {}, priority = row.extension_priority }

    local action = {
        app = row.app_name,
        data = row.app_data or ""
    }

    if row.action_type == "action" then
        table.insert(dialplan[ext][cond].actions, action)
    else
        table.insert(dialplan[ext][cond].anti_actions, action)
    end
end

-- Construct XML
local lines = {}
for ext, conditions in pairs(dialplan) do
    table.insert(lines, string.format('<extension name="%s">', ext))
    for cond_key, data in pairs(conditions) do
        local field, expression = cond_key:match("(.-)=(.*)")
        table.insert(lines, string.format('  <condition field="%s" expression="%s">', field, expression))

        for _, action in ipairs(data.actions) do
            table.insert(lines, string.format('    <action application="%s" data="%s"/>', action.app, action.data))
        end

        for _, action in ipairs(data.anti_actions) do
            table.insert(lines, string.format('    <anti-action application="%s" data="%s"/>', action.app, action.data))
        end

        table.insert(lines, '  </condition>')
    end
    table.insert(lines, '</extension>')
end

-- Return XML
XML_STRING = settings.format_xml("dialplan", table.concat(lines, "\n"))
log("INFO", "Dialplan XML returned for context: " .. context)

-- Close DB
dbh:close()
