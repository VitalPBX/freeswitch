--[[ 
    sip_register.lua (directory) 
    Handles FreeSWITCH directory requests for user authentication.
    Uses ODBC via FreeSWITCH Dbh and logs based on debug settings.
    Generates XML using the generic format_xml function from settings.lua.
    Retrieves user and domain from XML_REQUEST.
--]]

-- Cargar el módulo settings
local settings = require("resources.settings.settings")

return function()
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

    -- SQL query to fetch authentication details from `sip_users`
    local query = string.format([[
        SELECT su.username, su.password, su.xml_data, t.domain_name, su.enabled
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
                xml_data = result.xml_data,
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
        log("info", string.format("Generating directory entry for user %s in domain %s", row.username, row.domain_name))
        
        -- Construir el contenido del directorio con <params> y <groups>
        local indent = "    "  -- Indentación base
        local user_indent = indent .. indent .. indent  -- Tres niveles de indentación para <user> (12 espacios)
        -- Ajustar la indentación de row.xml_data para que esté al nivel correcto
        local indented_user_xml = ""
        for line in row.xml_data:gmatch("[^\n]+") do
            indented_user_xml = indented_user_xml .. user_indent .. line .. "\n"
        end
        indented_user_xml = indented_user_xml:gsub("\n$", "")  -- Eliminar el último salto de línea

        local directory_content = table.concat({
            '<params>',
            indent .. '<param name="jsonrpc-allowed-methods" value="verto"/>',
            indent .. '<param name="jsonrpc-allowed-event-channels" value="demo,conference,presence"/>',
            '</params>',
            '<groups>',
            indent .. '<group name="default">',
            indent .. indent .. '<users>',
            indented_user_xml,  -- XML del usuario con indentación ajustada
            indent .. indent .. '</users>',
            indent .. '</group>',
            '</groups>'
        }, "\n")

        -- Usar format_xml para construir el XML completo
        XML_STRING = settings.format_xml("directory", directory_content, {
            domain_name = row.domain_name,
            alias = true
        })
    else
        log("warning", string.format("User %s not found or not enabled in domain %s", username, domain))
        XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="directory"><result status="not found"/></section></document>'
    end

    -- Log XML output only if debugging is enabled
    log("debug", "Generated XML: " .. XML_STRING)

    -- Release the database connection
    dbh:release()
end
