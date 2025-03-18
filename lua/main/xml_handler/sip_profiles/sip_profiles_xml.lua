--[[ 
    sip_profiles.lua
    Generates Sofia SIP configuration for FreeSWITCH dynamically using database-driven profiles.
    Retrieves the full XML configuration directly from the database.
    Ensures that each profile includes a valid <gateways> section.
]]

return function(settings)
    -- Logging function
    local function log(level, message)
        if level == "debug" and not settings.debug then return end
        freeswitch.consoleLog(level, "[Sofia Profiles] " .. message .. "\n")
    end

    log("info", "Initializing SIP profile configuration generation")

    -- Establish database connection
    local dbh = assert(freeswitch.Dbh("odbc://ring2all"), "Failed to connect to database")

    -- Initialize XML structure
    local xml = {
        '<?xml version="1.0" encoding="utf-8"?>',
        '<document type="freeswitch/xml">',
        '  <section name="configuration">',
        '    <configuration name="sofia.conf" description="Sofia SIP Endpoint">',
        '      <profiles>'
    }

    -- Query SIP profiles from the database
    local profile_query = [[
        SELECT profile_name, xml_config FROM public.sip_profiles
    ]]

    log("debug", "Executing profile query: " .. profile_query)

    -- Counter for the number of profiles processed
    local profile_count = 0

    -- Execute the query and append XML from the database
    dbh:query(profile_query, function(row)
        profile_count = profile_count + 1
        local profile_name = row.profile_name
        local profile_xml = row.xml_config

        log("info", "Processing profile: " .. profile_name)

        -- Ensure <gateways> section exists in the XML
        if not profile_xml:find("<gateways>") then
            log("warning", "Profile " .. profile_name .. " is missing <gateways> section. Adding an empty one.")
            -- Insert <gateways></gateways> before </profile>
            profile_xml = profile_xml:gsub("</profile>", "  <gateways></gateways>\n</profile>")
        end

        -- Append profile XML to the main structure
        table.insert(xml, profile_xml)
    end)

    -- Log the total number of profiles processed
    log("info", "Total profiles processed: " .. profile_count)
    if profile_count == 0 then
        log("warning", "No profiles found in the database")
    end

    -- Complete XML structure
    table.insert(xml, '      </profiles>')
    table.insert(xml, '    </configuration>')
    table.insert(xml, '  </section>')
    table.insert(xml, '</document>')

    -- Convert table to string
    XML_STRING = table.concat(xml, "\n")

    -- Save XML for debugging
    local file = io.open("/tmp/sofia_profiles.xml", "w")
    if file then
        file:write(XML_STRING)
        file:close()
        log("info", "XML configuration saved to /tmp/sofia_profiles.xml")
    else
        log("warning", "Failed to save XML configuration to /tmp/sofia_profiles.xml")
    end

    -- Release DB connection
    dbh:release()
end
