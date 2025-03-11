--[[
    handler.lua (directory)
    Handles FreeSWITCH directory requests (e.g., user registration authentication).
--]]

-- Load PostgreSQL LuaSQL library
local luasql = require "luasql.postgres"

-- Log script execution
freeswitch.consoleLog("NOTICE", "xml_handlers/directory/handler.lua called\n")

-- Database connection
local env = assert(luasql.postgres())
local conn = assert(env:connect("ring2all", "ring2all", "ring2all", "localhost", 5432))

-- Extract username and domain from request parameters
local username = params:getHeader("User-Name") or ""
local domain = params:getHeader("Domain-Name") or "192.168.10.21"

freeswitch.consoleLog("DEBUG", "Username: " .. username .. "\n")
freeswitch.consoleLog("DEBUG", "Domain: " .. domain .. "\n")

-- Query to fetch user authentication data
local query = string.format([[
    SELECT su.username, su.password, t.domain_name
    FROM public.sip_users su
    JOIN public.tenants t ON su.tenant_uuid = t.tenant_uuid
    WHERE su.username = '%s' AND t.domain_name = '%s'
]], username, domain)

local cur = assert(conn:execute(query))
local row = cur:fetch({}, "a")

-- Generate XML response
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

freeswitch.consoleLog("DEBUG", "Generated XML: " .. xml .. "\n")
XML_STRING = xml

-- Close database connections
cur:close()
conn:close()
env:close()
