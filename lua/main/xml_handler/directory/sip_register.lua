--[[
    sip_register.lua
    Handles SIP user registration and directory lookups from FreeSWITCH.
    Loads user information from PostgreSQL via view_sip_users.
--]]

-- Dependencies
local pg = require("luasql.postgres")
local env = pg.postgres()

-- Input data
local domain = XML_REQUEST["domain"] or ""
local user = XML_REQUEST["user"] or ""

-- Settings module
local settings = require("resources.settings.settings")
local log = function(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[Directory] " .. message .. "\n")
end

log("INFO", "Directory lookup for user: " .. user .. " @ " .. domain)

-- Connect to database
local dbh = env:connect("ring2all")
if not dbh then
    log("ERR", "Failed to connect to PostgreSQL database")
    return
end

-- Fetch SIP user and settings
local sql = [[
    SELECT * FROM view_sip_users
    WHERE username = %s AND tenant_id = (
        SELECT id FROM core.tenants WHERE name = 'Default'
    )
]]
sql = string.format(sql, dbh:escape(user))

local result = {}
for row in dbh:rows(sql) do
    table.insert(result, row)
end

if #result == 0 then
    log("WARNING", "No SIP user found for: " .. user)
    XML_STRING = settings.format_xml("directory", "")
    return
end

-- Build <user> XML
local user_id = result[1].username
local password = result[1].password
local variables = {}
local params = {
    { name = "password", value = password }
}

for _, row in ipairs(result) do
    if row.setting_type == "param" then
        table.insert(params, { name = row.setting_name, value = row.setting_value })
    elseif row.setting_type == "variable" then
        table.insert(variables, { name = row.setting_name, value = row.setting_value })
    end
end

-- XML content construction
local lines = {
    string.format('<user id="%s">', user_id),
    '  <params>'
}
for _, p in ipairs(params) do
    table.insert(lines, string.format('    <param name="%s" value="%s"/>', p.name, p.value))
end

table.insert(lines, '  </params>')
table.insert(lines, '  <variables>')
for _, v in ipairs(variables) do
    table.insert(lines, string.format('    <variable name="%s" value="%s"/>', v.name, v.value))
end

table.insert(lines, '  </variables>')
table.insert(lines, '</user>')

-- Return XML
XML_STRING = settings.format_xml("directory", table.concat(lines, "\n"), {
    domain_name = domain,
    alias = true
})

log("INFO", "User XML returned for " .. user .. "@" .. domain)

-- Close DB
dbh:close()
