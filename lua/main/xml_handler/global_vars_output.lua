--[[
    Script: global_vars_output.lua
    Purpose: Generate vars.xml from database per tenant using domain or fallback to 'Default'
    Usage:   luarun /usr/share/freeswitch/scripts/main/xml_handlers/global_vars_output.lua [domain]
--]]

local domain = argv and argv[1] or (XML_REQUEST and XML_REQUEST["domain"]) or "localhost"

local log = function(level, msg)
    freeswitch.consoleLog(level, "[global_vars] " .. msg .. "\n")
end

local dbh = freeswitch.Dbh("odbc://ring2all")
assert(dbh:connected(), "❌ Failed to connect to PostgreSQL via ODBC")

log("INFO", "🌐 Resolving tenant from domain: " .. domain)

local tenant_id = nil

-- Step 1: Try by domain_name
local sql_domain = string.format([[
    SELECT id FROM core.tenants 
    WHERE domain_name = '%s'
    LIMIT 1
]], domain)

dbh:query(sql_domain, function(row)
    tenant_id = row.id
end)

-- Step 2: Fallback to 'Default' tenant name
if not tenant_id then
    log("WARNING", "⚠️ Domain not found, trying fallback tenant: 'Default'")
    dbh:query("SELECT id FROM core.tenants WHERE name = 'Default' LIMIT 1", function(row)
        tenant_id = row.id
    end)
end

-- Step 3: If still not found, proceed without tenant_id (load global vars only)
if tenant_id then
    log("INFO", "✅ Loaded tenant-specific vars for tenant_id: " .. string.upper(tenant_id))
else
    log("WARNING", "⚠️ No tenant found. Loading only global vars (tenant_id IS NULL)")
end

-- Load vars
local vars = {}

-- Tenant vars
if tenant_id then
    local q = string.format([[
        SELECT name, value FROM core.global_vars
        WHERE enabled = TRUE AND tenant_id = '%s'
    ]], tenant_id)
    dbh:query(q, function(row)
        vars[row.name] = row.value
    end)
end

-- Global fallback vars
dbh:query("SELECT name, value FROM core.global_vars WHERE enabled = TRUE AND tenant_id IS NULL", function(row)
    if not vars[row.name] then
        vars[row.name] = row.value
    end
end)

-- Generate XML
local xml_parts = {
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<document type="freeswitch/xml">',
    '  <section name="configuration">',
    '    <configuration name="vars.xml" description="Global Variables">',
    '      <settings>'
}

local count = 0
for name, value in pairs(vars) do
    table.insert(xml_parts, string.format('        <variable name="%s" value="%s" global="true"/>', name, value))
    count = count + 1
end

table.insert(xml_parts, '      </settings>')
table.insert(xml_parts, '    </configuration>')
table.insert(xml_parts, '  </section>')
table.insert(xml_parts, '</document>')

log("INFO", string.format("📦 vars.xml generated with %d variables", count))
log("INFO", "\n===== 🌐 vars.xml generated from Lua for domain: " .. domain .. " =====\n" ..
    table.concat(xml_parts, "\n") ..
    "\n===========================================\n"
)
