-- tenant_vars_test.lua
-- Test script to load and display tenant-specific variables (without a session)

-- Usage:
--   luarun /usr/share/freeswitch/scripts/tests/tenant_vars_test.lua [domain]
--   Example: luarun /usr/share/freeswitch/scripts/tests/tenant_vars_test.lua empresa-a.com

local domain = argv[1] or "localhost"

local tenant_vars = require("resources.utils.tenant_vars")

-- Mock object to simulate session:setVariable()
local fake_session = {
    vars = {},
    setVariable = function(self, name, value)
        self.vars[name] = value
    end
}

-- Apply and display tenant vars
tenant_vars.apply(fake_session, domain)

freeswitch.consoleLog("INFO", "\n🌐 Dump of variables for domain: " .. domain .. "\n")
for name, value in pairs(fake_session.vars) do
    freeswitch.consoleLog("INFO", string.format("  ➕ %s = %s\n", name, value))
end
