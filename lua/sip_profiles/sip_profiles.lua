--[[ 
    sip_profiles.lua
    Dynamically generates Sofia SIP configuration for FreeSWITCH, mimicking FusionPBX format.
--]]

return function(settings)
    -- Logging function with respect to debug settings
    local function log(level, message)
        if level == "debug" and not settings.debug then return end
        freeswitch.consoleLog(level, "[Sofia Profiles] " .. message .. "\n")
    end

    log("info", "Starting sofia_profiles.lua")

    -- Establish ODBC database connection using FreeSWITCH Dbh
    local dbh = assert(freeswitch.Dbh("odbc://ring2all"), "Failed to connect to ODBC database")

    -- Start generating the XML response in FusionPBX format
    local xml = '<?xml version="1.0" encoding="utf-8"?>\n' ..
                '<document type="freeswitch/xml">\n' ..
                '  <section name="configuration">\n' ..
                '    <configuration name="sofia.conf" description="sofia Endpoint">\n' ..
                '      <global_settings>\n' ..
                '        <param name="log-level" value="0"/>\n' ..
                '        <param name="debug-presence" value="0"/>\n' ..
                '      </global_settings>\n' ..
                '      <profiles>\n'

    -- Query to fetch all SIP profiles
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
        xml = xml .. '        <profile name="' .. profile_name .. '">\n' ..
                    '          <aliases>\n' ..
                    '          </aliases>\n' ..
                    '          <gateways>\n'

        -- Fetch gateways for this profile
        local gateways_query = "SELECT gateway_uuid, gateway_name FROM public.sip_profile_gateways WHERE profile_uuid = '" .. profile_uuid .. "'"
        log("debug", "Executing gateways query: " .. gateways_query)
        dbh:query(gateways_query, function(gateway_row)
            local gateway_uuid = gateway_row.gateway_uuid
            local gateway_name = gateway_row.gateway_name

            log("debug", "Generating gateway: " .. gateway_name .. " for profile: " .. profile_name)
            xml = xml .. '            <gateway name="' .. gateway_name .. '">\n'

            -- Fetch gateway settings
            local gw_settings_query = "SELECT name, value FROM public.sip_profile_gateway_settings WHERE gateway_uuid = '" .. gateway_uuid .. "'"
            log("debug", "Executing gateway settings query: " .. gw_settings_query)
            dbh:query(gw_settings_query, function(gw_setting_row)
                xml = xml .. '              <param name="' .. gw_setting_row.name .. '" value="' .. gw_setting_row.value .. '"/>\n'
            end)

            xml = xml .. '            </gateway>\n'
        end)

        xml = xml .. '          </gateways>\n' ..
                    '          <domains>\n' ..
                    '            <domain name="all" alias="false" parse="false"/>\n' ..
                    '          </domains>\n' ..
                    '          <settings>\n'

        -- Fetch settings for this profile
        local settings_query = "SELECT name, value FROM public.sip_profile_settings WHERE profile_uuid = '" .. profile_uuid .. "'"
        log("debug", "Executing settings query: " .. settings_query)
        dbh:query(settings_query, function(setting_row)
            xml = xml .. '            <param name="' .. setting_row.name .. '" value="' .. setting_row.value .. '"/>\n'
        end)

        -- Close profile XML
        xml = xml .. '          </settings>\n' ..
                    '        </profile>\n'
    end)

    log("info", "Total profiles found: " .. row_count)

    if not profiles_found then
        log("warning", "No profiles found in sip_profiles table")
    end

    -- Complete the XML document
    xml = xml .. '      </profiles>\n' ..
                '    </configuration>\n' ..
                '  </section>\n' ..
                '</document>'

    -- Set the XML response to FreeSWITCH
    XML_STRING = xml
    log("debug", "Generated XML:\n" .. xml)

    -- Release the database connection
    dbh:release()
end
