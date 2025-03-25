-- ===================================================
-- File: global_vars.lua
-- Description:
--   Generates vars.xml dynamically from the database.
--   Supports tenant-specific variables with fallback to global values.
--   Returns XML string in the format expected by mod_xml_curl.
-- ===================================================

local M = {}

local function log(level, msg)
    freeswitch.consoleLog(level, "[global_vars] " .. msg .. "\n")
end

function M.handle(tenant_id)
    -- Connect via ODBC DSN
    local dbh = assert(freeswitch.Dbh("odbc://ring2all"), "❌ Failed to connect to database")

    local vars = {}

    -- Prepare and execute tenant-specific query
    local sql_tenant = string.format([[
        SELECT name, value FROM core.global_vars
        WHERE enabled = TRUE AND tenant_id = '%s'
    ]], tenant_id)

    local has_data = dbh:query(sql_tenant, function(row)
        vars[row.name] = row.value
    end)

    -- Fallback to global variables (tenant_id IS NULL)
    local sql_global = [[
        SELECT name, value FROM core.global_vars
        WHERE enabled = TRUE AND tenant_id IS NULL
    ]]
    dbh:query(sql_global, function(row)
        if not vars[row.name] then
            vars[row.name] = row.value
        end
    end)

    -- DEBUG log
    local count = 0
    for name, value in pairs(vars) do
        log("INFO", string.format("   ➕ %s = %s", name, value))
        count = count + 1
    end

    -- Build XML
    local xml_parts = {
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<document type="freeswitch/xml">',
        '  <section name="configuration">',
        '    <configuration name="vars.xml" description="Global Variables">',
        '      <settings>'
    }

    for name, value in pairs(vars) do
        table.insert(xml_parts, string.format(
            '        <variable name="%s" value="%s" global="true"/>',
            tostring(name), tostring(value)
        ))
    end

    table.insert(xml_parts, '      </settings>')
    table.insert(xml_parts, '    </configuration>')
    table.insert(xml_parts, '  </section>')
    table.insert(xml_parts, '</document>')

    log("INFO", "✅ vars.xml generated with " .. count .. " variables")
    return table.concat(xml_parts, "\n")
end

return M
