--[[
    xml_handlers/index.lua
    Main XML section router for FreeSWITCH.
    Dispatches to specific handler scripts based on the requested XML section.
--]]

-- Extract the XML section from the XML_REQUEST table provided by FreeSWITCH
local section = XML_REQUEST["section"]

-- Load global settings and utility functions
local settings = require("resources.settings.settings")

-- Logging helper with debug filter
function log(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[Main] " .. message .. "\n")
end

-- Log the entry point
log("INFO", "Main.lua is handling XML request for section: " .. section)

-- Handle the XML section
if section == "directory" then
    -- Handle SIP directory (user registration, auth, etc.)
    local sip_register = dofile("/usr/share/freeswitch/scripts/main/xml_handlers/directory/sip_register.lua")
    sip_register(settings)

elseif section == "dialplan" then
    -- Handle dynamic dialplan generation
    local dialplan = dofile("/usr/share/freeswitch/scripts/main/xml_handlers/dialplan/dialplan.lua")
    dialplan(settings)

elseif section == "configuration" then
    -- Handle configuration files like vars.xml, sofia.conf, etc.
    local config_name = XML_REQUEST["key_value"]
    log("DEBUG", "Configuration name: " .. (config_name or "unknown"))

    if config_name == "vars.xml" then
        -- Handle dynamic vars.xml loading
        log("INFO", "Handling configuration vars.xml")

        -- Extract domain from XML request
        local domain = XML_REQUEST["domain"] or XML_REQUEST["hostname"]
        log("DEBUG", "Domain received: " .. (domain or "unknown"))

        -- Resolve tenant_id from domain using helper in settings
        local tenant_id = settings.get_tenant_id_by_domain(domain)
        log("DEBUG", "Resolved tenant_id: " .. tenant_id)

        -- Load and return XML from global_vars handler
        local global_vars = require("main.xml_handlers.global_vars")
        XML_STRING = global_vars.handle(tenant_id)

    elseif config_name == "sofia.conf" then
        -- Handle SIP profiles (sofia module)
        local sofia_profiles = dofile("/usr/share/freeswitch/scripts/main/xml_handlers/sip_profiles/sip_profiles.lua")
        if type(sofia_profiles) == "function" then
            sofia_profiles(settings)
        else
            log("ERR", "sip_profiles.lua did not return a function")
        end

    elseif config_name == "ivr.conf" then
        -- Handle IVR configuration
        log("INFO", "Handling configuration ivr.conf")
        local ivr = dofile("/usr/share/freeswitch/scripts/main/xml_handlers/ivr/ivr.lua")
        ivr(settings)

    -- Placeholder blocks for future configurations
    elseif config_name == "spandsp.conf" then
        log("INFO", "spandsp.conf handler not implemented yet")
        XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="configuration"></section></document>'

    elseif config_name == "loopback.conf" then
        log("INFO", "loopback.conf handler not implemented yet")
        XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="configuration"></section></document>'

    elseif config_name == "enum.conf" then
        log("INFO", "enum.conf handler not implemented yet")
        XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="configuration"></section></document>'

    elseif config_name == "timezones.conf" then
        log("INFO", "timezones.conf handler not implemented yet")
        XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="configuration"></section></document>'

    else
        -- No handler found for requested config
        log("WARNING", "No handler for configuration: " .. (config_name or "unknown"))
        XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="configuration"></section></document>'
    end

else
    -- Unknown or unsupported XML section
    log("ERR", "Unknown section: " .. section)
    XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="' .. section .. '"></section></document>'
end
