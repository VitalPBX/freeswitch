-- main/xml_handlers/global_vars.lua
-- Generate vars.xml dynamically from the database (multi-tenant support)
-- ✅ Now supports a proper fallback using is_main column in core.tenants

local M = {}

-- Simple logging wrapper
local function log(level, msg)
    freeswitch.consoleLog(level, "[global_vars] " .. msg .. "\n")
end

-- Resolve tenant_id from domain_name field
-- Falls back to the main tenant where is_main = TRUE
local function resolve_tenant_id(domain)
    local dbh = freeswitch.Dbh("odbc://ring2all")
    local tenant_id = nil

    if dbh then
        -- Try to find tenant by domain_name
        local sql_domain = string.format([[
            SELECT id FROM core.tenants
            WHERE domain_name = '%s' AND enabled = TRUE
            LIMIT 1
        ]], domain)

        dbh:query(sql_domain, function(row)
            tenant_id = row.id
        end)

        -- Fallback: try main tenant where is_main = TRUE
        if not tenant_id then
            log("WARNING", "⚠️ Domain not found, trying fallback tenant with is_main = TRUE")
            local sql_main = [[
                SELECT id FROM core.tenants
                WHERE is_main = TRUE AND enabled = TRUE
                LIMIT 1
            ]]
            dbh:query(sql_main, function(row)
                tenant_id = row.id
            end)
        end

        dbh:release()
    else
        log("ERR", "❌ Cannot connect to database to resolve tenant_id")
    end

    return tenant_id
end

-- Main entry point to generate vars.xml
-- This is called by index.lua via handle_from_request()
function M.handle_from_request()
    local dbh = freeswitch.Dbh("odbc://ring2all")
    if not dbh then
        log("ERR", "❌ Failed to connect to database")
        return ""
    end

    local vars = {}

    -- Extract domain from XML_REQUEST
    local domain = XML_REQUEST["domain"] or XML_REQUEST["hostname"]
    log("INFO", "🔍 Resolving tenant from domain: " .. tostring(domain))
    local tenant_id = resolve_tenant_id(domain)

    -- Step 1: Load global vars (those not linked to a tenant)
    dbh:query([[
        SELECT name, value FROM core.global_vars
        WHERE enabled = TRUE AND tenant_id IS NULL
    ]], function(row)
        vars[row.name] = row.value
    end)

    -- Step 2: Load tenant-specific vars (if resolved)
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

    -- Step 3: Render XML output
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
