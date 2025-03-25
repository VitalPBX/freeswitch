-- ===================================================
-- File: global_vars.lua
-- Description:
--   Generates vars.xml dynamically from the database.
--   Supports tenant-specific variables with fallback to global values.
--   Returns XML string in the format expected by mod_xml_curl.
-- ===================================================

-- main/xml_handlers/global_vars.lua
local M = {}

-- Logging helper
local function log(level, msg)
    freeswitch.consoleLog(level, "[global_vars] " .. msg .. "\n")
end

-- Get tenant_id from domain
local function resolve_tenant_id(domain)
    local dbh = freeswitch.Dbh("odbc://ring2all")
    local tenant_id = nil

    if dbh then
        local sql = string.format(
            "SELECT id FROM core.tenants WHERE domain = '%s' LIMIT 1", domain
        )

        dbh:query(sql, function(row)
            tenant_id = row.id
        end)
        dbh:release()
    else
        log("ERR", "❌ Cannot connect to database to resolve tenant_id")
    end

    return tenant_id
end

-- Main function
function M.handle_from_request()
    local dbh = freeswitch.Dbh("odbc://ring2all")
    if not dbh then
        log("ERR", "❌ Failed to connect to database")
        return ""
    end

    local vars = {}

    -- 1. Get domain from XML_REQUEST
    local domain = XML_REQUEST["domain"] or XML_REQUEST["hostname"]
    log("INFO", "Resolving tenant for domain: " .. tostring(domain))
    local tenant_id = resolve_tenant_id(domain)

    -- 2. Load global variables (tenant_id IS NULL)
    dbh:query([[
        SELECT name, value FROM core.global_vars
        WHERE enabled = TRUE AND tenant_id IS NULL
    ]], function(row)
        vars[row.name] = row.value
    end)

    -- 3. Load tenant-specific variables (if found)
    if tenant_id then
        local sql = string.format([[
            SELECT name, value FROM core.global_vars
            WHERE enabled = TRUE AND tenant_id = '%s'
        ]], tenant_id)

        dbh:query(sql, function(row)
            vars[row.name] = row.value
        end)

        log("INFO", "✅ Loaded variables for tenant_id: " .. tenant_id)
    else
        log("WARNING", "⚠️ No tenant found for domain: " .. tostring(domain))
    end

    dbh:release()

    -- 4. Generate XML
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
