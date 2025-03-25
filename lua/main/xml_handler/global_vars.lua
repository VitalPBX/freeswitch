-- ===================================================
-- File: global_vars.lua
-- Description:
--   Generates vars.xml dynamically from the database.
--   Supports tenant-specific variables with fallback to global values.
--   Returns XML string in the format expected by mod_xml_curl.
-- ===================================================

local xml = require("xml")
local M = {}

-- Logger
local function log(level, msg)
    freeswitch.consoleLog(level, "[global_vars] " .. msg .. "\n")
end

function M.handle(tenant_id)
    local dbh = env:connect("ring2all")
    if not dbh then
        log("ERR", "Failed to connect to PostgreSQL database")
        return ""
    end

    local vars = {}

    -- Load tenant-specific vars
    local query_tenant = string.format([[
        SELECT name, value FROM core.v_global_vars
        WHERE tenant_id = '%s' AND scope = 'tenant'
    ]], tenant_id)

    dbh:query(query_tenant, function(row)
        vars[row.name] = row.value
    end)

    -- Load global vars (fallback)
    local query_global = [[
        SELECT name, value FROM core.v_global_vars
        WHERE scope = 'global'
    ]]
    dbh:query(query_global, function(row)
        if not vars[row.name] then
            vars[row.name] = row.value
        end
    end)

    -- Build XML
    local xml_parts = {
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<document type="freeswitch/xml">',
        '  <section name="configuration">',
        '    <configuration name="vars.xml" description="Global Variables">',
        '      <settings>'
    }

    for name, value in pairs(vars) do
        table.insert(xml_parts, string.format('        <variable name="%s" value="%s"/>', name, value))
    end

    table.insert(xml_parts, '      </settings>')
    table.insert(xml_parts, '    </configuration>')
    table.insert(xml_parts, '  </section>')
    table.insert(xml_parts, '</document>')

    local XML_STRING = table.concat(xml_parts, "\n")
    return XML_STRING
end

return M
