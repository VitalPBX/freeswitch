--[[
    ivr.lua
    Generates IVR configuration XML dynamically from PostgreSQL using view_ivr_menu_options.
    Returns menus, greetings, and DTMF actions for FreeSWITCH ivr.conf.
--]]

-- Dependencies
local pg = require("luasql.postgres")
local env = pg.postgres()

-- Settings module
local settings = require("resources.settings.settings")
local log = function(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[IVR] " .. message .. "\n")
end

-- Connect to database
local dbh = env:connect("ring2all")
if not dbh then
    log("ERR", "Failed to connect to PostgreSQL database")
    return
end

-- Query IVR menu options
local sql = [[
SELECT * FROM view_ivr_menu_options ORDER BY ivr_name, priority
]]

local result = {}
for row in dbh:rows(sql) do
    table.insert(result, row)
end

if #result == 0 then
    log("WARNING", "No IVR menus found in view_ivr_menu_options")
    XML_STRING = settings.format_xml("configuration", "")
    return
end

-- Group by IVR name
local ivrs = {}
for _, row in ipairs(result) do
    local name = row.ivr_name
    ivrs[name] = ivrs[name] or {
        greet_long = row.greet_long,
        greet_short = row.greet_short,
        invalid_sound = row.invalid_sound,
        exit_sound = row.exit_sound,
        timeout = row.timeout,
        max_failures = row.max_failures,
        max_timeouts = row.max_timeouts,
        direct_dial = row.direct_dial,
        options = {}
    }
    table.insert(ivrs[name].options, row)
end

-- Build XML
local lines = {
    '<configuration name="ivr.conf" description="IVR menus">',
    '  <menus>'
}

for ivr_name, data in pairs(ivrs) do
    table.insert(lines, string.format('    <menu name="%s" greet-long="%s" greet-short="%s"',
        ivr_name, data.greet_long or "", data.greet_short or ""))
    table.insert(lines, string.format('          invalid-sound="%s" exit-sound="%s" timeout="%d" max-failures="%d" max-timeouts="%d" direct-dial="%s">',
        data.invalid_sound or "", data.exit_sound or "", data.timeout or 5,
        data.max_failures or 3, data.max_timeouts or 3, tostring(data.direct_dial)))

    for _, opt in ipairs(data.options) do
        local line = string.format('      <entry digits="%s" action="%s"', opt.digits, opt.action)
        if opt.destination then
            line = line .. string.format(' param="%s"', opt.destination)
        end
        if opt.condition then
            line = line .. string.format(' condition="%s"', opt.condition)
        end
        if opt.break_on_match then
            line = line .. ' break="true"'
        end
        line = line .. ' />'
        table.insert(lines, line)
    end

    table.insert(lines, '    </menu>')
end

table.insert(lines, '  </menus>')
table.insert(lines, '</configuration>')

-- Return XML
XML_STRING = settings.format_xml("configuration", table.concat(lines, "\n"))
log("INFO", "IVR menus XML configuration generated")

-- Close DB
dbh:close()
