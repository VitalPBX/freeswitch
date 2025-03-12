--[[
    sofia_profiles.lua
    Dynamically generates all Sofia SIP profiles from the ring2all database for FreeSWITCH.
--]]

-- Load ODBC library for database access
local dbh = freeswitch.Dbh("odbc://ring2all")

-- Load settings from the correct path
local settings = require("resources.settings.settings")

-- Logging function respecting debug setting
local function log(level, message)
    if level == "debug" and not settings.debug then
        return
    end
    freeswitch.consoleLog(level, "[Sofia Profiles] " .. message .. "\n")
end

-- Log script start
log("info", "Starting sofia_profiles.lua")

-- Check settings loading
if not settings then
    log("error", "Failed to load settings.lua from resources/settings/settings.lua")
else
    log("info", "Settings loaded successfully, debug = " .. tostring(settings.debug))
end

-- Check database connection
if not dbh then
    log("error", "Failed to connect to ODBC database 'ring2all'")
    XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="sofia"><profiles></profiles></section></document>'
    return
end

-- Start generating the XML response
local xml = '<?xml version="1.0" encoding="utf-8"?>\n' ..
            '<document type="freeswitch/xml">\n' ..
            '  <section name="sofia">\n' ..
            '    <profiles>\n'

-- Query to fetch all SIP profiles (no tenant_uuid filter)
local profile_query = "SELECT profile_uuid, profile_name FROM public.sip_profiles"
log("debug", "Executing query: " .. profile_query)

local profiles_found = false
local row_count = 0

-- Execute the profile query and log results
dbh:query(profile_query, function(profile_row)
    row_count = row_count + 1
    profiles_found = true
    local profile_uuid = profile_row.profile_uuid
    local profile_name = profile_row.profile_name

    log("info", "Found profile: " .. profile_name .. " with UUID: " .. profile_uuid)

    -- Start profile XML
    xml = xml .. '      <profile name="' .. profile_name .. '">\n'

    -- Fetch settings for this profile
    local settings_query = "SELECT name, value FROM public.sip_profile_settings WHERE profile_uuid = '" .. profile_uuid .. "'"
    log("debug", "Executing settings query: " .. settings_query)
    dbh:query(settings_query, function(setting_row)
        xml = xml .. '        <param name="' .. setting_row.name .. '" value="' .. setting_row.value .. '"/>\n'
    end)

    -- Fetch gateways for this profile
    local gateways_query = "SELECT gateway_uuid, gateway_name FROM public.sip_profile_gateways WHERE profile_uuid = '" .. profile_uuid .. "'"
    log("debug", "Executing gateways query: " .. gateways_query)
    dbh:query(gateways_query, function(gateway_row)
        local gateway_uuid = gateway_row.gateway_uuid
        local gateway_name = gateway_row.gateway_name

        log("debug", "Generating gateway: " .. gateway_name .. " for profile: " .. profile_name)
        xml = xml .. '        <gateway name="' .. gateway_name .. '">\n'

        -- Fetch gateway settings
        local gw_settings_query = "SELECT name, value FROM public.sip_profile_gateway_settings WHERE gateway_uuid = '" .. gateway_uuid .. "'"
        log("debug", "Executing gateway settings query: " .. gw_settings_query)
        dbh:query(gw_settings_query, function(gw_setting_row)
            xml = xml .. '          <param name="' .. gw_setting_row.name .. '" value="' .. gw_setting_row.value .. '"/>\n'
        end)

        xml = xml .. '        </gateway>\n'
    end)

    -- Close profile XML
    xml = xml .. '      </profile>\n'
end)

log("info", "Total profiles found: " .. row_count)

if not profiles_found then
    log("warning", "No profiles found in sip_profiles table")
end

-- Complete the XML document
xml = xml .. '    </profiles>\n' ..
            '  </section>\n' ..
            '</document>'

-- Set the XML response for FreeSWITCH
XML_STRING = xml
log("debug", "Generated XML:\n" .. xml)

-- Release the database handle
dbh:release()
