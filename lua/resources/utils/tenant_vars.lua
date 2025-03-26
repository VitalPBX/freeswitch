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
-- @param domain string - Domain name associated with the tenant (e.g., "company-a.com")
-- @return string|nil - Returns the tenant's UUID or nil if not found
local function resolve_tenant_id(domain)
    local dbh = freeswitch.Dbh("odbc://ring2all")
    local tenant_id

    local sql = string.format([[
        SELECT id FROM core.tenants
        WHERE domain_name = '%s' AND enabled = TRUE
        LIMIT 1
    ]], domain)

    -- Execute the query and extract the tenant ID
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

    -- Execute the query and store variables into the vars table
    dbh:query(sql, function(row)
        vars[row.name] = row.value
    end)

    dbh:release()
    return vars
end

-- Public function: Apply all variables for a specific tenant to the current session
-- @param session object - The FreeSWITCH session object (e.g., from dialplan or Lua app)
-- @param domain string - Domain name used to resolve the tenant
function M.apply(session, domain)
    log("INFO", "📡 Applying tenant vars for domain: " .. tostring(domain))

    -- Get the tenant ID based on domain
    local tenant_id = resolve_tenant_id(domain)

    if not tenant_id then
        log("WARNING", "⚠️ No tenant found for domain: " .. tostring(domain))
        return
    end

    -- Load the tenant-specific variables
    local vars = load_vars(tenant_id)
    local count = 0

    -- Apply each variable to the session
    for name, value in pairs(vars) do
        session:setVariable(name, value)
        count = count + 1
    end

    log("INFO", "✅ Applied " .. count .. " tenant variables for " .. domain)
end

return M  -- Return the module table
