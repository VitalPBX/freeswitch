-- tenant_vars.lua
-- Utility module to load tenant-specific global variables from PostgreSQL (via ODBC)
-- and apply them to the current call session in FreeSWITCH.

-- Usage:
--   local tenant_vars = require("resources.utils.tenant_vars")
--   local domain = session:getVariable("domain_name")
--   tenant_vars.apply(session, domain)

local M = {}  -- Module table

-- Internal function to log messages with a standard prefix
-- @param level string - Logging level (e.g., "INFO", "ERR")
-- @param msg string - Message to log
local function log(level, msg)
    freeswitch.consoleLog(level, "[tenant_vars] " .. msg .. "\n")
end

-- Resolve the tenant UUID based on the given domain name
-- If domain is nil or "main", fallback to tenant with is_main = TRUE
-- @param domain string|nil - Domain name (or nil to use main tenant)
-- @return string|nil - Returns the tenant's UUID or nil if not found
local function resolve_tenant_id(domain)
    local dbh = freeswitch.Dbh("odbc://ring2all")
    local tenant_id = nil

    if not dbh then
        log("ERR", "❌ Cannot connect to database to resolve tenant_id")
        return nil
    end

    local sql
    if not domain or domain == "main" then
        sql = [[
            SELECT id FROM core.tenants
            WHERE is_main = TRUE AND enabled = TRUE
            LIMIT 1
        ]]
    else
        sql = string.format([[ 
            SELECT id FROM core.tenants
            WHERE domain_name = '%s' AND enabled = TRUE
            LIMIT 1
        ]], domain)
    end

    dbh:query(sql, function(row)
        tenant_id = row.id
    end)

    dbh:release()
    return tenant_id
end

-- Load all global variables associated with a specific tenant from the database
-- @param tenant_id string - The UUID of the tenant
-- @return table - A table of variable name-value pairs
local function load_vars(tenant_id)
    local dbh = freeswitch.Dbh("odbc://ring2all")
    local vars = {}

    if not tenant_id then
        return vars
    end

    local sql = string.format([[ 
        SELECT name, value FROM core.global_vars
        WHERE enabled = TRUE AND tenant_id = '%s'
    ]], tenant_id)

    dbh:query(sql, function(row)
        vars[row.name] = row.value
    end)

    dbh:release()
    return vars
end

-- Public function: Apply all variables for a specific tenant to the current session
-- @param session object - The FreeSWITCH session object (or a simulated session)
-- @param domain string - Domain name used to resolve the tenant
function M.apply(session, domain)
    log("INFO", "?? Applying tenant vars for domain: " .. tostring(domain))

    local tenant_id = resolve_tenant_id(domain)

    if not tenant_id then
        log("WARNING", "?? No tenant found for domain: " .. tostring(domain))
        return
    end

    local vars = load_vars(tenant_id)
    local count = 0

    for name, value in pairs(vars) do
        session:setVariable(name, value)
        count = count + 1
    end

    log("INFO", "? Applied " .. count .. " tenant variables for " .. tostring(domain))
end

return M
