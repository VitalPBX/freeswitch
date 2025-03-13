--[[
    sip_profiles.lua
    Generates Sofia SIP configuration for FreeSWITCH dynamically using database-driven profiles.
    Resolves variables prefixed with $$ using FreeSWITCH global variables. If a variable is not found,
    it is replaced with an empty string instead of a default value.

    This script connects to a database, retrieves SIP profile data, constructs an XML configuration,
    and optionally starts the profiles automatically after generation.

    Author: [Your Name]
    Date: March 13, 2025
    Version: 1.0
--]]

-- Main function executed by FreeSWITCH to generate the SIP configuration
-- @param settings Table containing configuration settings (e.g., debug flag)
-- @return None (sets XML_STRING global variable for FreeSWITCH)
return function(settings)
    -- Logging utility function to output messages to the FreeSWITCH console
    -- @param level string Log level ("info", "debug", "warning", etc.)
    -- @param message string Message to log
    local function log(level, message)
        -- Only log debug messages if debug mode is enabled in settings
        if level == "debug" and not settings.debug then return end
        freeswitch.consoleLog(level, "[Sofia Profiles] " .. message .. "\n")
    end

    log("info", "Initializing SIP profile configuration generation")

    -- Establish a connection to the database using ODBC
    -- Throws an error if the connection fails
    local dbh = assert(freeswitch.Dbh("odbc://ring2all"), "Failed to connect to database")

    -- Create an instance of the FreeSWITCH API for executing commands
    local api = freeswitch.API()

    -- Retrieve all global variables from FreeSWITCH
    -- Returns an empty string if the command fails
    local vars = api:execute("global_getvar", "") or ""
    log("debug", "Retrieved global variables:\n" .. vars)

    -- Parse global variables into a key-value table for quick lookup
    -- Each line is expected in the format "name=value"
    local global_vars = {}
    for line in vars:gmatch("[^\n]+") do
        local name, value = line:match("^([^=]+)=(.+)$")
        if name and value then
            global_vars[name] = value
            log("debug", "Parsed global variable: " .. name .. " = " .. value)
        end
    end

    -- Function to replace $$ variables in a string with their resolved values
    -- @param str string Input string containing variables (e.g., "$${var_name}")
    -- @return string String with variables replaced, or original string with unresolved variables removed
    local function replace_vars(str)
        log("debug", "Processing string: " .. str)
        -- Replace all occurrences of $${var_name} with the corresponding value from global_vars
        local resolved = str:gsub("%$%${([^}]+)}", function(var_name)
            local value = global_vars[var_name] or ""
            if value == "" then
                log("warning", "Variable $$" .. var_name .. " not found, replacing with empty string")
            else
                log("debug", "Resolved $$" .. var_name .. " to: " .. value)
            end
            return value
        end)
        log("debug", "Resolved string: " .. resolved)
        return resolved
    end

    -- Initialize the XML structure as a table of lines
    -- This structure defines the base configuration for Sofia SIP
    local xml = {
        '<?xml version="1.0" encoding="utf-8"?>',
        '<document type="freeswitch/xml">',
        '  <section name="configuration">',
        '    <configuration name="sofia.conf" description="Sofia SIP Endpoint">',
        '      <global_settings>',
        '        <param name="log-level" value="0"/>',       -- Default log level
        '        <param name="debug-presence" value="0"/>',  -- Disable presence debugging
        '      </global_settings>',
        '      <profiles>'
    }

    -- SQL query to fetch SIP profiles from the database
    local profile_query = "SELECT profile_uuid, profile_name FROM public.sip_profiles"
    log("debug", "Executing profile query: " .. profile_query)

    -- Counter for the number of profiles processed
    local profile_count = 0

    -- Execute the profile query and build the XML for each profile
    dbh:query(profile_query, function(row)
        profile_count = profile_count + 1
        local uuid = row.profile_uuid
        local name = row.profile_name
        log("info", "Processing profile: " .. name .. " (UUID: " .. uuid .. ")")

        -- Add profile opening tags to the XML
        table.insert(xml, '        <profile name="' .. name .. '">')
        table.insert(xml, '          <aliases>')
        table.insert(xml, '          </aliases>')
        table.insert(xml, '          <gateways>')

        -- Query to fetch gateways associated with this profile
        local gw_query = "SELECT gateway_uuid, gateway_name FROM public.sip_profile_gateways WHERE profile_uuid = '" .. uuid .. "'"
        log("debug", "Executing gateway query: " .. gw_query)
        dbh:query(gw_query, function(gw_row)
            local gw_uuid = gw_row.gateway_uuid
            local gw_name = gw_row.gateway_name
            log("debug", "Adding gateway: " .. gw_name)

            -- Add gateway opening tag
            table.insert(xml, '            <gateway name="' .. gw_name .. '">')

            -- Query to fetch settings for this gateway
            local gw_settings_query = "SELECT name, value FROM public.sip_profile_gateway_settings WHERE gateway_uuid = '" .. gw_uuid .. "'"
            log("debug", "Executing gateway settings query: " .. gw_settings_query)
            dbh:query(gw_settings_query, function(setting)
                local value = replace_vars(setting.value)
                table.insert(xml, '              <param name="' .. setting.name .. '" value="' .. value .. '"/>')
            end)

            -- Close gateway tag
            table.insert(xml, '            </gateway>')
        end)

        -- Add domains and settings sections
        table.insert(xml, '          </gateways>')
        table.insert(xml, '          <domains>')
        table.insert(xml, '            <domain name="all" alias="false" parse="false"/>')
        table.insert(xml, '          </domains>')
        table.insert(xml, '          <settings>')

        -- Query to fetch settings for this profile
        local settings_query = "SELECT name, value FROM public.sip_profile_settings WHERE profile_uuid = '" .. uuid .. "'"
        log("debug", "Executing settings query: " .. settings_query)
        dbh:query(settings_query, function(setting)
            local value = replace_vars(setting.value)
            table.insert(xml, '            <param name="' .. setting.name .. '" value="' .. value .. '"/>')
        end)

        -- Close profile tags
        table.insert(xml, '          </settings>')
        table.insert(xml, '        </profile>')
    end)

    -- Log the total number of profiles processed
    log("info", "Total profiles processed: " .. profile_count)
    if profile_count == 0 then
        log("warning", "No profiles found in the database")
    end

    -- Complete the XML structure
    table.insert(xml, '      </profiles>')
    table.insert(xml, '    </configuration>')
    table.insert(xml, '  </section>')
    table.insert(xml, '</document>')

    -- Convert the XML table to a single string and set it as the FreeSWITCH response
    XML_STRING = table.concat(xml, "\n")
    log("debug", "Generated XML configuration:\n" .. XML_STRING)

    -- Save the generated XML to a temporary file for debugging purposes
    local file = io.open("/tmp/sofia_profiles.xml", "w")
    if file then
        file:write(XML_STRING)
        file:close()
        log("info", "XML configuration saved to /tmp/sofia_profiles.xml")
    else
        log("warning", "Failed to save XML configuration to /tmp/sofia_profiles.xml")
    end

    -- Automatically start all defined profiles if any were found
    if profile_count > 0 then
        local profiles = {"internal", "external", "internal-ipv6", "external-ipv6"}
        for _, profile in ipairs(profiles) do
            api:execute("sofia", "profile " .. profile .. " start")
            log("info", "Automatically started profile '" .. profile .. "'")
        end
    end

    -- Release the database connection
    dbh:release()
end
