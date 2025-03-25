--[[
    sip_profiles.lua
    Generates XML configuration for FreeSWITCH's sofia.conf profiles
    using the PostgreSQL view: view_sip_profiles.
--]]

-- Dependencies
local pg = require("luasql.postgres")
local env = pg.postgres()

-- Settings module
local settings = require("resources.settings.settings")
local log = function(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[SIP Profiles] " .. message .. "\n")
end

-- Connect to database
local dbh = env:connect("ring2all")
if not dbh then
    log("ERR", "Failed to connect to PostgreSQL database")
    return
end

-- Query all SIP profiles and settings
local sql = [[
SELECT * FROM view_sip_profiles ORDER BY profile_name, setting_name
]]

local result = {}
for row in dbh:rows(sql) do
    table.insert(result, row)
end

if #result == 0 then
    log("WARNING", "No SIP profiles found in view_sip_profiles")
    XML_STRING = settings.format_xml("configuration", "")
    return
end

-- Group by profile
local profiles = {}
for _, row in ipairs(result) do
    local name = row.profile_name
    profiles[name] = profiles[name] or { settings = {}, bind_address = row.bind_address }
    table.insert(profiles[name].settings, { name = row.setting_name, value = row.setting_value })
end

-- Build XML for sofia.conf
local lines = {
    '<configuration name="sofia.conf" description="Sofia SIP">'
}

table.insert(lines, '  <profiles>')

for profile_name, data in pairs(profiles) do
    table.insert(lines, string.format('    <profile name="%s">', profile_name))
    table.insert(lines, '      <settings>')
    for _, setting in ipairs(data.settings) do
        table.insert(lines, string.format('        <param name="%s" value="%s"/>', setting.name, setting.value))
    end
    table.insert(lines, '      </settings>')
    table.insert(lines, '    </profile>')
end

table.insert(lines, '  </profiles>')
table.insert(lines, '</configuration>')

-- Return XML
XML_STRING = settings.format_xml("configuration", table.concat(lines, "\n"))
log("INFO", "SIP profiles XML configuration generated")

-- Close DB
dbh:close()
