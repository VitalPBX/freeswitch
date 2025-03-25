--[[
    conference.lua
    Generates dynamic configuration for FreeSWITCH's conference.conf
    using PostgreSQL data from core.conference_rooms and core.conference_room_settings.
--]]

-- Dependencies
local pg = require("luasql.postgres")
local env = pg.postgres()

-- Settings module
local settings = require("resources.settings.settings")
local log = function(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[Conference] " .. message .. "\n")
end

-- Connect to database
local dbh = env:connect("ring2all")
if not dbh then
    log("ERR", "Failed to connect to PostgreSQL database")
    return
end

-- Query conference profiles and settings
local sql = [[
SELECT r.id AS room_id, r.name AS profile_name, s.name AS setting_name, s.value AS setting_value
FROM core.conference_rooms r
LEFT JOIN core.conference_room_settings s ON s.conference_room_id = r.id
WHERE r.enabled = TRUE AND s.enabled = TRUE
ORDER BY r.name, s.name;
]]

local result = {}
for row in dbh:rows(sql) do
    table.insert(result, row)
end

if #result == 0 then
    log("WARNING", "No conference profiles found in the database")
    XML_STRING = settings.format_xml("configuration", "")
    return
end

-- Group by profile
local profiles = {}
for _, row in ipairs(result) do
    local name = row.profile_name
    profiles[name] = profiles[name] or {}
    table.insert(profiles[name], { name = row.setting_name, value = row.setting_value })
end

-- Build XML
local lines = {
    '<configuration name="conference.conf" description="Audio Conference">',
    '  <profiles>'
}

for profile_name, settings_list in pairs(profiles) do
    table.insert(lines, string.format('    <profile name="%s">', profile_name))
    for _, setting in ipairs(settings_list) do
        table.insert(lines, string.format('      <param name="%s" value="%s"/>', setting.name, setting.value))
    end
    table.insert(lines, '    </profile>')
end

table.insert(lines, '  </profiles>')
table.insert(lines, '</configuration>')

-- Return XML
XML_STRING = settings.format_xml("configuration", table.concat(lines, "\n"))
log("INFO", "Conference profiles XML configuration generated")

-- Close DB
dbh:close()
