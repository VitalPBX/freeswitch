--[[
    File: main/xml_handlers/global_vars.lua
    Description: Dynamically generate `vars.xml` from a PostgreSQL database with multi-tenant support.
    Usage: Called from `index.lua`, or manually for testing:
           fs_cli -x "luarun /usr/share/freeswitch/scripts/main/xml_handlers/global_vars_output.lua"

    Requirements:
    - ODBC DSN: ring2all
    - Table: core.global_vars (fields: name, value, enabled, tenant_id)
    - Table: core.tenants (fields: id, domain_name, enabled)
--]]

local M = {}

-- Wrapper for logging to the FreeSWITCH console
local function log(level, msg)
    freeswitch.consoleLog(level, "[global_vars] " .. msg .. "\n")
end

-- Resolve tenant_id from the domain name (used for multi-tenant isolation)
local function resolve_tenant_id(domain)
    local dbh = freeswitch.Dbh("odbc://ring2all")
    local tenant_id = nil

    if dbh then
        local sql = string.format([[
            SELECT id FROM core.tenants
            WHERE domain_name = '%s' AND enabled = TRUE
            LIMIT 1
        ]], domain)

        dbh:query(sql, function(row)
            tenant_id = row.id
        end)

        dbh:release()
    else
        log("ERR", "❌ Cannot connect to database to resolve tenant_id")
    end

    return tenant_id
end

-- Main handler that generates vars.xml dynamically
function M.handle_from_request()
    local dbh = freeswitch.Dbh("odbc://ring2all")
    if not dbh then
        log("ERR", "❌ Failed to connect to database")
        return ""
    end

    local vars = {}

    -- Extract the requested domain from FreeSWITCH's XML_REQUEST environment
    local domain = XML_REQUEST["domain"] or XML_REQUEST["hostname"]
    log("INFO", "🔍 Resolving tenant from domain: " .. tostring(domain))

    local tenant_id = resolve_tenant_id(domain)

    -- Step 1: Load default (global) variables where tenant_id IS NULL
    dbh:query([[
        SELECT name, value FROM core.global_vars
        WHERE enabled = TRUE AND tenant_id IS NULL
    ]], function(row)
        vars[row.name] = row.value
    end)

    -- Step 2: Load tenant-specific variables if a tenant was resolved
    if tenant_id then
        local sql = string.format([[
            SELECT name, value FROM core.global_vars
            WHERE enabled = TRUE AND tenant_id = '%s'
        ]], tenant_id)

        dbh:query(sql, function(row)
            vars[row.name] = row.value
        end)

        log("INFO", "✅ Loaded tenant-specific vars for tenant_id: " .. tenant_id)
    else
        log("WARNING", "⚠️ No tenant found for domain: " .. tostring(domain))
    end

    dbh:release()

    -- Step 3: Construct XML output for vars.xml
    local xml_parts = {
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<document type="freeswitch/xml">',
        '  <section name="configuration">',
        '    <configuration name="vars.xml" description="Global Variables">',
        '      <settings>'
    }

    local count = 0
    for name, value in pairs(vars) do
        table.insert(xml_parts, string.format(
            '        <variable name="%s" value="%s" global="true"/>',
            tostring(name), tostring(value)
        ))
        count = count + 1
    end

    table.insert(xml_parts, '      </settings>')
    table.insert(xml_parts, '    </configuration>')
    table.insert(xml_parts, '  </section>')
    table.insert(xml_parts, '</document>')

    log("INFO", "✅ vars.xml generated with " .. count .. " variables")
    return table.concat(xml_parts, "\n")
end

return M
