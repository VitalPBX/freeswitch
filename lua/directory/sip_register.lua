--[[
    handler.lua (directory)
    Handles FreeSWITCH directory requests (e.g., user registration authentication).
    Uses ODBC connection via FreeSWITCH Dbh and receives settings from main.lua to control debug logging.
--]]

-- Return a function that accepts settings as a parameter
return function(settings)
    -- Define a logging function that respects the debug setting from settings
    local function log(level, message)
        if level == "debug" and not settings.debug then
            return  -- Skip debug messages if debug is false
        end
        freeswitch.consoleLog(level, "[Directory] " .. message .. "\n")
    end

    -- Log that the script has been called
    log("NOTICE", "xml_handlers/directory/handler.lua called")

    -- Establish ODBC database connection using FreeSWITCH Dbh
    local dbh = assert(freeswitch.Dbh("odbc://ring2all"), "Failed to connect to ODBC database")

    -- Extract username and domain from request parameters
    local username = params:getHeader("User-Name") or ""
    local domain = params:getHeader("Domain-Name") or "192.168.10.21"

    -- Log the extracted username and domain for debugging
    log("DEBUG", "Username: " .. username)
    log("DEBUG", "Domain: " .. domain)

    -- Query to fetch user authentication data (using placeholders to prevent SQL injection)
    local query = "SELECT su.username, su.password, t.domain_name " ..
                  "FROM public.sip_users su " ..
                  "JOIN public.tenants t ON su.tenant_uuid = t.tenant_uuid " ..
                  "WHERE su.username = ? AND t.domain_name = ?"

    -- Execute the query with parameters and fetch the result
    local success, result = pcall(function()
        assert(dbh:query(query, {username, domain}, function(row)
            -- Store the first row (assuming single result)
            return row
        end))
    end)

    -- Check if query was successful and a row was returned
    local row
    if success and result then
        row = result  -- Dbh:query returns the row directly when a callback is used
    else
        log("DEBUG", "No result or query failed")
    end

    -- Generate XML response based on query result
    local xml
    if row then
        xml = [[<?xml version="1.0" encoding="utf-8"?>
<document type="freeswitch/xml">
  <section name="directory">
    <domain name="]] .. row.domain_name .. [[">
      <user id="]] .. row.username .. [[">
        <params>
          <param name="password" value="]] .. row.password .. [["/>
        </params>
      </user>
    </domain>
  </section>
</document>]]
    else
        xml = [[<?xml version="1.0" encoding="utf-8"?>
<document type="freeswitch/xml">
  <section name="directory">
    <result status="not found"/>
  </section>
</document>]]
    end

    -- Log the generated XML for debugging
    log("DEBUG", "Generated XML: " .. xml)

    -- Set the XML response for FreeSWITCH
    XML_STRING = xml

    -- Release the database handle (Dbh automatically closes when out of scope, but explicit release is good practice)
    dbh:release()
end
