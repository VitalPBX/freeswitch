-- sip_profiles.lua
-- Generate SIP Profiles and Gateways XML for FreeSWITCH in correct format
-- Supports variable substitution of $${var} and ${var} from global variables.

-- Load global settings and logging function
local settings = require("resources.settings.settings")
local log = function(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[SIPProfiles] " .. message .. "\n")
end

-- Create a FreeSWITCH API instance
local api = freeswitch.API()

-- Retrieve all global variables from FreeSWITCH and store in a key-value table
global_vars = {}
do
    local vars = api:execute("global_getvar", "") or ""
    for line in vars:gmatch("[^\n]+") do
        local name, value = line:match("^([^=]+)=(.+)$")
        if name and value then
            global_vars[name] = value
            log("debug", "Parsed global variable: " .. name .. " = " .. value)
        end
    end
end

-- Replace $${var} and ${var} with their corresponding values from global_vars
local function replace_vars(str)
    -- Replace $${var_name}
    str = str:gsub("%$%${([^}]+)}", function(var_name)
        local value = global_vars[var_name] or ""
        if value == "" then
            log("warning", "Variable $$" .. var_name .. " not found, replacing with empty string")
        else
            log("debug", "Resolved $$" .. var_name .. " to: " .. value)
        end
        return value
    end)

    -- Replace ${var_name}
    str = str:gsub("%${([^}]+)}", function(var_name)
        local value = global_vars[var_name] or ""
        if value == "" then
            log("warning", "Variable ${" .. var_name .. "} not found, replacing with empty string")
        else
            log("debug", "Resolved ${" .. var_name .. "} to: " .. value)
        end
        return value
    end)

    return str
end

-- Connect to PostgreSQL using ODBC
dbh = freeswitch.Dbh("odbc://ring2all")
if not dbh:connected() then
    freeswitch.consoleLog("ERR", "Failed to connect to database\n")
    return
end
log("info", "ODBC connection established")

-- Load all gateways grouped by tenant and gateway name
gateways_by_tenant = {}
dbh:query([[SELECT * FROM view_gateways ORDER BY gateway_id, setting_name]], function(row)
    local tenant_id = row.tenant_id
    gateways_by_tenant[tenant_id] = gateways_by_tenant[tenant_id] or {}
    local gw_name = row.gateway_name
    gateways_by_tenant[tenant_id][gw_name] = gateways_by_tenant[tenant_id][gw_name] or { row = row, settings = {} }
    table.insert(gateways_by_tenant[tenant_id][gw_name].settings, { name = row.setting_name, value = row.setting_value })
end)

-- Begin XML generation
local xml = {}
table.insert(xml, '<?xml version="1.0" encoding="UTF-8" standalone="no"?>')
table.insert(xml, '<document type="freeswitch/xml">')
table.insert(xml, '  <section name="configuration">')
table.insert(xml, '    <configuration name="sofia.conf" description="sofia Endpoint">')
table.insert(xml, '      <profiles>')

-- Generate SIP Profiles
local last_profile_id = nil
local current_profile = {}

dbh:query([[SELECT * FROM view_sip_profiles ORDER BY sip_profile_id, setting_name]], function(row)
    if last_profile_id ~= row.sip_profile_id then
        -- Close previous profile
        if #current_profile > 0 then
            table.insert(current_profile, '        </settings>')
            table.insert(current_profile, '      </profile>')
            for _, line in ipairs(current_profile) do table.insert(xml, line) end
        end

        -- Start new profile
        current_profile = {}
        last_profile_id = row.sip_profile_id

        table.insert(current_profile, string.format('      <profile name="%s">', replace_vars(row.profile_name)))
        table.insert(current_profile, '        <aliases></aliases>')

        -- Gateways section
        table.insert(current_profile, '        <gateways>')
        local gateways = gateways_by_tenant[row.tenant_id] or {}
        for gw_name, gw_data in pairs(gateways) do
            table.insert(current_profile, string.format('          <gateway name="%s">', replace_vars(gw_name)))
            local attrs = { "username", "password", "from-user", "from-domain", "proxy", "expire-seconds", "register", "register-transport", "contact-params", "retry-seconds", "context" }
            for _, attr in ipairs(attrs) do
                local val = gw_data.row[attr]
                if val and val ~= "" then
                    table.insert(current_profile, string.format('            <param name="%s" value="%s"/>', attr, replace_vars(val)))
                end
            end
            for _, setting in ipairs(gw_data.settings) do
                table.insert(current_profile, string.format('            <param name="%s" value="%s"/>', replace_vars(setting.name), replace_vars(setting.value)))
            end
            table.insert(current_profile, '            <variables></variables>')
            table.insert(current_profile, '          </gateway>')
        end
        table.insert(current_profile, '        </gateways>')

        -- Domains section (default stub)
        table.insert(current_profile, '        <domains>')
        table.insert(current_profile, '          <domain name="all" alias="false" parse="false"/>')
        table.insert(current_profile, '        </domains>')

        -- Settings section
        table.insert(current_profile, '        <settings>')
    end

    -- Add profile setting
    if row.setting_name and row.setting_value then
        table.insert(current_profile, string.format('          <param name="%s" value="%s"/>', replace_vars(row.setting_name), replace_vars(row.setting_value)))
    end
end)

-- Finalize last profile
if #current_profile > 0 then
    table.insert(current_profile, '        </settings>')
    table.insert(current_profile, '      </profile>')
    for _, line in ipairs(current_profile) do table.insert(xml, line) end
end

-- Close XML structure
table.insert(xml, '      </profiles>')
table.insert(xml, '    </configuration>')
table.insert(xml, '  </section>')
table.insert(xml, '</document>')

-- Output final XML
XML_STRING = table.concat(xml, "\n")
log("info", "Generated XML:\n" .. XML_STRING)
log("info", "SIP Profiles and Gateways XML generated successfully.")
