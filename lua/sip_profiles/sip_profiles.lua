--[[ 
    sip_profiles.lua
    Dynamically generates Sofia SIP configuration for FreeSWITCH using database-driven profiles.
    Resolves variables prefixed with $$ using FreeSWITCH global variables or predefined fallbacks.
    Author: [Your Name]
    Date: March 13, 2025
--]]

-- Main function executed by FreeSWITCH
return function(settings)
    -- Logging utility function
    -- @param level Log level (e.g., "info", "debug", "warning")
    -- @param message Message to log
    local function log(level, message)
        if level == "debug" and not settings.debug then return end
        freeswitch.consoleLog(level, "[Sofia Profiles] " .. message .. "\n")
    end

    log("info", "Initializing SIP profile generation")

    -- Database connection using ODBC
    local dbh = assert(freeswitch.Dbh("odbc://ring2all"), "Failed to connect to database")

    -- FreeSWITCH API instance
    local api = freeswitch.API()

    -- Fetch global variables from FreeSWITCH
    local vars = api:execute("global_getvar", "") or ""
    log("debug", "Global variables loaded:\n" .. vars)

    -- Parse global variables into a lookup table
    local global_vars = {}
    for line in vars:gmatch("[^\n]+") do
        local name, value = line:match("^([^=]+)=(.+)$")
        if name and value then
            global_vars[name] = value
            log("debug", "Loaded variable: " .. name .. " = " .. value)
        end
    end

    -- Fallback values for unresolved variables
    local fallback_vars = {
        local_ip_v4 = "192.168.10.22",
        external_sip_ip = "186.77.196.70",
        external_sip_port = "5080",
        external_tls_port = "5081",
        global_codec_prefs = "OPUS,G722,PCMU,PCMA,H264,VP8",
        hold_music = "local_stream://moh",
        sip_tls_version = "tlsv1,tlsv1.1,tlsv1.2",
        external_ssl_enable = "false",
        internal_sip_port = "5060",
        internal_tls_port = "5061",
        internal_ssl_enable = "false",
        internal_ssl_dir = "/etc/freeswitch/tls",
        sip_tls_ciphers = "ALL:!ADH:!LOW:!EXP:!MD5:@STRENGTH",
        domain = "192.168.10.22",
        recordings_dir = "/var/lib/freeswitch/recordings",
        internal_auth_calls = "true",
        external_rtp_ip = "186.77.196.70"
    }

    -- Resolve $$ variables in a string
    -- @param str Input string containing variables (e.g., "$${var_name}")
    -- @return String with variables replaced by their values or original string if unresolved
    local function replace_vars(str)
        log("debug", "Processing string: " .. str)
        local resolved = str:gsub("%$%${([^}]+)}", function(var_name)
            local value = global_vars[var_name] or fallback_vars[var_name]
            if value then
                log("debug", "Resolved $$" .. var_name .. " to: " .. value)
                return value
            end
            log("warning", "Variable $$" .. var_name .. " not found")
            return "" -- Return empty string if variable is unresolved
        end)
        log("debug", "Result: " .. resolved)
        return resolved
    end

    -- XML header and initial structure
    local xml = {
        '<?xml version="1.0" encoding="utf-8"?>',
        '<document type="freeswitch/xml">',
        '  <section name="configuration">',
        '    <configuration name="sofia.conf" description="sofia Endpoint">',
        '      <global_settings>',
        '        <param name="log-level" value="0"/>',
        '        <param name="debug-presence" value="0"/>',
        '      </global_settings>',
        '      <profiles>'
    }

    -- Fetch SIP profiles from database
    local profile_query = "SELECT profile_uuid, profile_name FROM public.sip_profiles"
    log("debug", "Running query: " .. profile_query)

    local profile_count = 0
    dbh:query(profile_query, function(row)
        profile_count = profile_count + 1
        local uuid, name = row.profile_uuid, row.profile_name
        log("info", "Processing profile: " .. name .. " (UUID: " .. uuid .. ")")

        -- Add profile opening tags
        table.insert(xml, '        <profile name="' .. name .. '">')
        table.insert(xml, '          <aliases>')
        table.insert(xml, '          </aliases>')
        table.insert(xml, '          <gateways>')

        -- Fetch and process gateways
        local gw_query = "SELECT gateway_uuid, gateway_name FROM public.sip_profile_gateways WHERE profile_uuid = '" .. uuid .. "'"
        log("debug", "Running gateway query: " .. gw_query)
        dbh:query(gw_query, function(gw_row)
            local gw_uuid, gw_name = gw_row.gateway_uuid, gw_row.gateway_name
            log("debug", "Adding gateway: " .. gw_name)
            table.insert(xml, '            <gateway name="' .. gw_name .. '">')

            -- Fetch gateway settings
            local gw_settings_query = "SELECT name, value FROM public.sip_profile_gateway_settings WHERE gateway_uuid = '" .. gw_uuid .. "'"
            log("debug", "Running gateway settings query: " .. gw_settings_query)
            dbh:query(gw_settings_query, function(setting)
                local value = replace_vars(setting.value)
                table.insert(xml, '              <param name="' .. setting.name .. '" value="' .. value .. '"/>')
            end)

            table.insert(xml, '            </gateway>')
        end)

        -- Add domains and settings
        table.insert(xml, '          </gateways>')
        table.insert(xml, '          <domains>')
        table.insert(xml, '            <domain name="all" alias="false" parse="false"/>')
        table.insert(xml, '          </domains>')
        table.insert(xml, '          <settings>')

        -- Fetch profile settings
        local settings_query = "SELECT name, value FROM public.sip_profile_settings WHERE profile_uuid = '" .. uuid .. "'"
        log("debug", "Running settings query: " .. settings_query)
        dbh:query(settings_query, function(setting)
            local value = replace_vars(setting.value)
            table.insert(xml, '            <param name="' .. setting.name .. '" value="' .. value .. '"/>')
        end)

        -- Close profile
        table.insert(xml, '          </settings>')
        table.insert(xml, '        </profile>')
    end)

    log("info", "Total profiles processed: " .. profile_count)
    if profile_count == 0 then
        log("warning", "No profiles found in database")
    end

    -- Complete XML structure
    table.insert(xml, '      </profiles>')
    table.insert(xml, '    </configuration>')
    table.insert(xml, '  </section>')
    table.insert(xml, '</document>')

    -- Join XML lines and set response
    XML_STRING = table.concat(xml, "\n")
    log("debug", "Generated XML:\n" .. XML_STRING)

    -- Clean up database connection
    dbh:release()
end
