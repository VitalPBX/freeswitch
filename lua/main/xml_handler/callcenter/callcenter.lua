--[[
    callcenter.lua
    Generates dynamic configuration for FreeSWITCH's callcenter.conf
    using PostgreSQL view_call_center_agents_by_queue.
--]]

-- Dependencies
local pg = require("luasql.postgres")
local env = pg.postgres()

-- Settings module
local settings = require("resources.settings.settings")
local log = function(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[CallCenter] " .. message .. "\n")
end

-- Connect to database
local dbh = env:connect("ring2all")
if not dbh then
    log("ERR", "Failed to connect to PostgreSQL database")
    return
end

-- Query agents and queues
local sql = [[
SELECT * FROM view_call_center_agents_by_queue ORDER BY queue_name, tier_level, tier_position
]]

local result = {}
for row in dbh:rows(sql) do
    table.insert(result, row)
end

if #result == 0 then
    log("WARNING", "No call center data found in view_call_center_agents_by_queue")
    XML_STRING = settings.format_xml("configuration", "")
    return
end

-- Group data by queue
local queues = {}
for _, row in ipairs(result) do
    local qname = row.queue_name
    queues[qname] = queues[qname] or { agents = {} }
    table.insert(queues[qname].agents, row)
end

-- Build XML
local lines = {
    '<configuration name="callcenter.conf" description="CallCenter Queues">',
    '  <queues>'
}

for queue_name, qdata in pairs(queues) do
    table.insert(lines, string.format('    <queue name="%s">', queue_name))
    for _, agent in ipairs(qdata.agents) do
        table.insert(lines, string.format(
            '      <member uuid="%s" contact="user/%s" status="%s" ready="%s" level="%d" position="%d"/>',
            agent.agent_id, agent.agent_contact, agent.agent_status,
            tostring(agent.agent_ready), agent.tier_level, agent.tier_position
        ))
    end
    table.insert(lines, '    </queue>')
end

table.insert(lines, '  </queues>')
table.insert(lines, '</configuration>')

-- Return XML
XML_STRING = settings.format_xml("configuration", table.concat(lines, "\n"))
log("INFO", "CallCenter XML configuration generated")

-- Close DB
dbh:close()
