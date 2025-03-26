-- tenant_vars_xml_test.lua
-- This script loads tenant-specific global variables from the database
-- and prints them as a FreeSWITCH-compatible vars.xml structure.

-- Usage:
--   luarun /usr/share/freeswitch/scripts/tests/tenant_vars_xml_test.lua [domain]
--   Example: luarun /usr/share/freeswitch/scripts/tests/tenant_vars_xml_test.lua company-a.com
--   To test the main tenant: luarun /usr/share/freeswitch/scripts/tests/tenant_vars_xml_test.lua main

local input = argv[1] or "localhost"
local domain = (input == "main") and nil or input
local tenant_vars = require("resources.utils.tenant_vars")

-- Fake session object for simulation purposes (captures variables)
local fake_session = {
    vars = {},
    setVariable = function(self, name, value)
        self.vars[name] = value
    end
}

-- Apply tenant variables
if domain == nil then
    freeswitch.consoleLog("INFO", "\n[tenant_vars] 🔍 Looking up main tenant (is_main = TRUE)\n")
end

tenant_vars.apply(fake_session, domain)

-- Output XML headers
freeswitch.consoleLog("INFO", "\n===== ?? Simulated vars.xml for domain: " .. input .. " =====\n")
freeswitch.consoleLog("INFO", '<?xml version="1.0" encoding="UTF-8"?>\n')
freeswitch.consoleLog("INFO", '<document type="freeswitch/xml">\n')
freeswitch.consoleLog("INFO", '  <section name="configuration">\n')
freeswitch.consoleLog("INFO", '    <configuration name="vars.xml" description="Global Variables">\n')
freeswitch.consoleLog("INFO", '      <settings>\n')

local count = 0
for name, value in pairs(fake_session.vars) do
    freeswitch.consoleLog("INFO", string.format(
        '        <variable name="%s" value="%s" global="true"/>\n',
        tostring(name), tostring(value)
    ))
    count = count + 1
end

freeswitch.consoleLog("INFO", '      </settings>\n')
freeswitch.consoleLog("INFO", '    </configuration>\n')
freeswitch.consoleLog("INFO", '  </section>\n')
freeswitch.consoleLog("INFO", '</document>\n')
freeswitch.consoleLog("INFO", "===== ? Loaded " .. count .. " variables from domain: " .. input .. " =====\n")
