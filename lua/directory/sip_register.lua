--[[
    handler.lua (directory)
    Handles FreeSWITCH directory requests (e.g., user registration authentication).
    Receives settings from main.lua to control debug logging.
--]]

-- Load PostgreSQL LuaSQL library
local luasql = require "luasql.postgres"

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

    -- Establish database connection
    local env = assert(luasql.postgres())
    local conn = assert(env:connect("ring2all", "ring2all", "ring2all", "localhost", 5432))

    -- Extract username and domain from request parameters
    local username = params:getHeader("User-Name") or ""
    local domain = params:getHeader("Domain-Name") or "192.168.10.21"

    -- Log the extracted username and domain for debugging
    log("DEBUG", "Username: " .. username)
    log("DEBUG", "Domain: " .. domain)

    -- Query to fetch user authentication data
    local query = string.format([[
        SELECT su.username, su.password, t.domain_name
        FROM public.sip_users su
        JOIN public.tenants t ON su.tenant_uuid = t.tenant_uuid
        WHERE su.username = '%s' AND t.domain_name = '%s'
    ]], username, domain)

    -- Execute the query and fetch the result
    local cur = assert(conn:execute(query))
    local row = cur:fetch({}, "a")

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

    -- Close database connections
    cur:close()
    conn:close()
    env:close()
end
