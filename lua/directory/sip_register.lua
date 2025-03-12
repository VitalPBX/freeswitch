--[[
    handler.lua (directory)
    Handles FreeSWITCH directory requests (e.g., user registration authentication).
    Uses ODBC connection via FreeSWITCH Dbh and receives settings from main.lua to control debug logging.
--]]

return function(settings)
    --- Logs messages based on the debug setting.
    -- @param level The log level (e.g., "DEBUG", "NOTICE", "ERROR").
    -- @param message The message to log.
    local function log(level, message)
        if level == "debug" and not settings.debug then
            return  -- Skip debug messages if debug is disabled
        end
        freeswitch.consoleLog(level, "[Directory] " .. message .. "\n")
    end

    -- Log script execution
    log("NOTICE", "xml_handlers/directory/handler.lua called")

    -- Establish ODBC database connection
    local dbh = assert(freeswitch.Dbh("odbc://ring2all"), "Failed to connect to ODBC database")

    -- Retrieve user and domain from SIP request headers
    local username = params:getHeader("user")
    local domain = params:getHeader("domain")

    -- Log extracted values for debugging
    log("DEBUG", "Username: " .. (username or "nil"))
    log("DEBUG", "Domain: " .. (domain or "nil"))

    -- Construct SQL query
    local query = string.format(
        "SELECT su.username, su.password, t.domain_name " ..
        "FROM public.sip_users su " ..
        "JOIN public.tenants t ON su.tenant_uuid = t.tenant_uuid " ..
        "WHERE su.username = '%s' AND t.domain_name = '%s'",
        username, domain
    )
    log("DEBUG", "Executing query: " .. query)

    -- Variable to store query result
    local row = nil

    -- Execute query and fetch result
    local success, err = pcall(function()
        dbh:query(query, function(result)
            row = {
                username = result.username,
                password = result.password,
                domain_name = result.domain_name
            }
        end)
    end)

    -- Log error if query fails
    if not success then
        log("ERROR", "SQL query execution error: " .. (err or "Unknown error"))
    end

    -- Verify if user was found
    if row then
        log("DEBUG", "User authenticated successfully: " .. row.username)
    else
        log("WARNING", "User not found in the database")
    end

    -- Generate XML response
    local xml
    if row then
        xml = string.format(
            [[<?xml version="1.0" encoding="utf-8"?>
<document type="freeswitch/xml">
  <section name="directory">
    <domain name="%s">
      <user id="%s">
        <params>
          <param name="password" value="%s"/>
        </params>
      </user>
    </domain>
  </section>
</document>]],
            row.domain_name, row.username, row.password
        )
    else
        xml = [[<?xml version="1.0" encoding="utf-8"?>
<document type="freeswitch/xml">
  <section name="directory">
    <result status="not found"/>
  </section>
</document>]]
    end

    -- Log generated XML
    log("DEBUG", "Generated XML: " .. xml)

    -- Set the XML response for FreeSWITCH
    XML_STRING = xml

    -- Release database handle
    dbh:release()
end
