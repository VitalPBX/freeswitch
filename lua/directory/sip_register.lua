--[[ 
    sip_register.lua (directory) 
    Handles FreeSWITCH directory requests for user authentication.
    Uses ODBC via FreeSWITCH Dbh and logs based on debug settings.
--]]

return function(settings)
    -- Logging function with respect to debug settings
    local function log(level, message)
        if level == "debug" and not settings.debug then
            return  -- Skip debug messages if debug is false
        end
        freeswitch.consoleLog(level, "[Directory] " .. message .. "\n")
    end

    -- Establish ODBC database connection using FreeSWITCH Dbh
    local dbh = assert(freeswitch.Dbh("odbc://ring2all"), "Failed to connect to ODBC database")

    -- Retrieve user and domain from SIP request headers
    local username = params:getHeader("user") or ""
    local domain = params:getHeader("domain") or ""

    -- Debugging logs (only if debug is enabled)
    log("debug", "Received username: " .. username)
    log("debug", "Received domain: " .. domain)

    -- Validate input to avoid SQL errors
    if username == "" or domain == "" then
        log("warning", "Invalid request: Missing username or domain.")
        return
    end

    -- SQL query to fetch authentication details
    local query = string.format([[
        SELECT su.username, su.password, t.domain_name 
        FROM public.sip_users su 
        JOIN public.tenants t ON su.tenant_uuid = t.tenant_uuid 
        WHERE su.username = '%s' AND t.domain_name = '%s'
    ]], username, domain)

    log("debug", "Executing SQL query: " .. query)

    -- Variable to store query result
    local row = nil

    -- Execute query and store the result
    local success, err = pcall(function()
        dbh:query(query, function(result)
            row = {
                username = result.username,
                password = result.password,
                domain_name = result.domain_name
            }
        end)
    end)

    -- Handle SQL execution errors
    if not success then
        log("error", "Database query execution failed: " .. (err or "Unknown error"))
        return
    end

    -- Check if the user was found
    if row then
        if not row.logged then
            log("info", string.format("Extension %s registered successfully for domain %s", row.username, row.domain_name))
            row.logged = true -- Prevent duplicate log messages
        end
    else
        log("warning", "Authentication failed: User not found in the database")
    end
    
    -- Generate XML response for FreeSWITCH
    local xml
    if row then
        xml = string.format([[
            <?xml version="1.0" encoding="utf-8"?>
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
            </document>
        ]], row.domain_name, row.username, row.password)
    else
        xml = [[
            <?xml version="1.0" encoding="utf-8"?>
            <document type="freeswitch/xml">
              <section name="directory">
                <result status="not found"/>
              </section>
            </document>
        ]]
    end

    -- Log XML output only if debugging is enabled
    log("debug", "Generated XML: " .. xml)

    -- Return XML response to FreeSWITCH
    XML_STRING = xml

    -- Release the database connection
    dbh:release()
end
