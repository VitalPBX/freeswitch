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
        XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="directory"><result status="not found"/></section></document>'
        dbh:release()
        return
    end

    -- SQL query to fetch authentication details
    local query = string.format([[
        SELECT se.extension, se.password, t.domain_name, se.enabled
        FROM public.sip_extensions se
        JOIN public.tenants t ON se.tenant_uuid = t.tenant_uuid
        WHERE se.extension = '%s' AND t.domain_name = '%s'
    ]], username, domain)

    log("debug", "Executing SQL query: " .. query)

    -- Variable to store query result
    local row = nil

    -- Execute query and store the result
    local success, err = pcall(function()
        dbh:query(query, function(result)
            row = {
                extension = result.extension,
                password = result.password,
                domain_name = result.domain_name,
                enabled = result.enabled
            }
        end)
    end)

    -- Handle SQL execution errors
    if not success then
        log("error", "Database query execution failed: " .. (err or "Unknown error"))
        XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="directory"><result status="not found"/></section></document>'
        dbh:release()
        return
    end

    -- Check if the extension exists and is enabled (valid values: "t" or "1")
    if row and (row.enabled == "t" or row.enabled == "1") then  
        log("info", string.format("Generating directory entry for extension %s in domain %s", row.extension, row.domain_name))
        XML_STRING = string.format([[
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
        ]], row.domain_name, row.extension, row.password)
    else
        log("warning", string.format("User %s not found or not enabled in domain %s", username, domain))
        XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="directory"><result status="not found"/></section></document>'
    end

    -- Log XML output only if debugging is enabled
    log("debug", "Generated XML: " .. XML_STRING)

    -- Release the database connection
    dbh:release()
end
