--[[
    sofia_profiles.lua
    Dynamically generates Sofia SIP profiles from the ring2all database for FreeSWITCH.
--]]

-- Load ODBC library for database access
local dbh = assert(freeswitch.Dbh("odbc://ring2all"), "Failed to connect to ODBC database")

-- Load settings from a central configuration file
local settings = require("xml_handlers.settings")

-- Logging function respecting debug setting
local function log(level, message)
    if level == "debug" and not settings.debug then
        return
    end
    freeswitch.consoleLog(level, "[Sofia Profiles] " .. message .. "\n")
end

-- Start generating the XML response
local xml = '<?xml version="1.0" encoding="utf-8"?>\n' ..
            '<document type="freeswitch/xml">\n' ..
            '  <section name="sofia">\n' ..
            '    <profiles>\n'

-- Query to fetch all SIP profiles for the tenant
local tenant_uuid = "fbfb3edd-52b2-4309-af14-f63b2024810d"  -- Replace with your tenant_uuid
local profile_query = "SELECT profile_uuid, profile_name FROM public.sip_profiles WHERE tenant_uuid = ?"
local success, result = pcall(function()
    return dbh:query(profile_query, {tenant_uuid}, function(profile_row)
        local profile_uuid = profile_row.profile_uuid
        local profile_name = profile_row.profile_name

        log("info", "Generating profile: " .. profile_name)

        -- Start profile XML
        xml = xml .. '      <profile name="' .. profile_name .. '">\n'

        -- Fetch settings for this profile
        local settings_query = "SELECT name, value FROM public.sip_profile_settings WHERE profile_uuid = ?"
        dbh:query(settings_query, {profile_uuid}, function(setting_row)
            xml = xml .. '        <param name="' .. setting_row.name .. '" value="' .. setting_row.value .. '"/>\n'
        end)

        -- Fetch gateways for this profile
        local gateways_query = "SELECT gateway_uuid, gateway_name FROM public.sip_profile_gateways WHERE profile_uuid = ?"
        dbh:query(gateways_query, {profile_uuid}, function(gateway_row)
            local gateway_uuid = gateway_row.gateway_uuid
            local gateway_name = gateway_row.gateway_name

            xml = xml .. '        <gateway name="' .. gateway_name .. '">\n'

            -- Fetch gateway settings
            local gw_settings_query = "SELECT name, value FROM public.sip_profile_gateway_settings WHERE gateway_uuid = ?"
            dbh:query(gw_settings_query, {gateway_uuid}, function(gw_setting_row)
                xml = xml .. '          <param name="' .. gw_setting_row.name .. '" value="' .. gw_setting_row.value .. '"/>\n'
            end)

            xml = xml .. '        </gateway>\n'
        end)

        -- Close profile XML
        xml = xml .. '      </profile>\n'
    end)
end)

if not success then
    log("error", "Failed to query profiles: " .. result)
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
