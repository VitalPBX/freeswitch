--[[
    test_vars.lua
    Usage:
        Run from FreeSWITCH CLI with:
            fs_cli -x "luarun /usr/share/freeswitch/scripts/test_vars.lua your.domain.com"

    Description:
        This script simulates a vars.xml XML request in Lua by manually injecting the
        XML_REQUEST environment using a domain passed as an argument.

        It loads and renders global variables for the corresponding tenant from the
        PostgreSQL database via ODBC.

        Useful for testing the dynamic generation of vars.xml from the database per domain.
--]]

-- Get domain from argument (argv[1])
local domain = argv and argv[1] or "localhost"

-- Simulate the XML_REQUEST environment if it does not exist
if not XML_REQUEST then
    XML_REQUEST = {}
end
XML_REQUEST["domain"] = domain

-- Load the global_vars handler module
local global_vars = require("main.xml_handlers.global_vars")

-- Generate vars.xml using the domain from XML_REQUEST
local xml = global_vars.handle_from_request()

-- Output the generated XML to the FreeSWITCH console
freeswitch.consoleLog("INFO", "\n\n===== 🌐 vars.xml generated from Lua for domain: " .. domain .. " =====\n" .. xml .. "\n===========================================\n")
