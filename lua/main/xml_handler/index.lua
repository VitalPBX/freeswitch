--[[
    main.lua
    Main entry point for FreeSWITCH XML requests. Routes requests to specific handlers based on 
    the source argument and request type. Loads settings globally and passes them to secondary scripts.
--]]

-- Extract the XML section from the XML_REQUEST table provided by FreeSWITCH
local section = XML_REQUEST["section"]

-- Load the settings.lua file using module notation relative to script-directory
local settings = require("resources.settings.settings")

-- Define a logging function to output messages to the FreeSWITCH console, respecting the debug setting
function log(level, message)
    -- Skip debug messages if debug is disabled in settings
    if level == "debug" and not settings.debug then
        return
    end
    freeswitch.consoleLog(level, "[Main] " .. message .. "\n")
end

-- Log an info message indicating the script is running
log("INFO", "Main.lua is handling XML request for section: " .. section)

    if section == "directory" then
        -- Load the SIP registration handler script and pass settings as an argument
        local sip_register = dofile("/usr/share/freeswitch/scripts/main/xml_handlers/directory/sip_register.lua")
        sip_register(settings)
    elseif section == "dialplan" then
        -- Load the dialplan handler script and pass settings as an argument
        local dialplan = dofile("/usr/share/freeswitch/scripts/main/xml_handlers/dialplan/dialplan.lua")
        dialplan(settings)
    elseif section == "configuration" then
        -- Check if the configuration request is for sofia.conf
        local config_name = XML_REQUEST["key_value"]
        log("DEBUG", "Configuration name: " .. (config_name or "unknown"))
        if config_name == "sofia.conf" then
            local sofia_profiles = dofile("/usr/share/freeswitch/scripts/main/xml_handlers/sip_profiles/sip_profiles.lua")
            if type(sofia_profiles) == "function" then
                sofia_profiles(settings)
            else
                log("ERR", "sip_profiles.lua did not return a function")
            end
        elseif config_name == "spandsp.conf" then
            -- Future handler for spandsp.conf
            log("INFO", "spandsp.conf handler not implemented yet")
            XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="configuration"></section></document>'
        elseif config_name == "loopback.conf" then
            -- Future handler for loopback.conf
            log("INFO", "loopback.conf handler not implemented yet")
            XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="configuration"></section></document>'
        elseif config_name == "enum.conf" then
            -- Future handler for enum.conf
            log("INFO", "enum.conf handler not implemented yet")
            XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="configuration"></section></document>'
        elseif config_name == "timezones.conf" then
            -- Future handler for timezones.conf
            log("INFO", "timezones.conf handler not implemented yet")
            XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="configuration"></section></document>'
        else
            -- Log an error if the section is not recognized
            log("WARNING", "No handler for configuration: " .. (config_name or "unknown"))
            XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="configuration"></section></document>'
        end
    else
        -- Log an error if the section is not recognized
        log("ERR", "Unknown section: " .. section)
        XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="' .. section .. '"></section></document>'
    end
