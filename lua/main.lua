--[[
    main.lua
    Main entry point for FreeSWITCH XML requests. Routes requests to specific handlers based on 
    the source argument and request type. Loads settings globally and passes them to secondary scripts.
--]]

-- Get the source argument passed to the script, default to "unknown" if not provided
local source = argv[1] or "unknown"

-- Extract the XML section from the XML_REQUEST table provided by FreeSWITCH
local section = XML_REQUEST["section"]

-- Load the settings.lua file containing configuration variables (e.g., debug)
local settings = require("/usr/share/freeswitch/scripts/resources/settings/settings.lua")

-- Define a logging function to output messages to the FreeSWITCH console, respecting the debug setting
function log(level, message)
    -- Skip debug messages if debug is disabled in settings
    if level == "debug" and not settings.debug then
        return
    end
    freeswitch.consoleLog(level, "[Main] " .. message .. "\n")
end

-- Log an info message indicating the section being processed
log("INFO", "Processing XML request for section: " .. section .. ", source: " .. source)

-- Check if the source is "xml_handlers" to route to specific handler scripts
if source == "xml_handlers" then
    if section == "directory" then
        -- Load the SIP registration handler script and pass settings as an argument
        local sip_register = dofile("/usr/share/freeswitch/scripts/xml_handlers/directory/sip_register.lua")
        sip_register(settings)
    elseif section == "dialplan" then
        -- Load the dialplan handler script and pass settings as an argument
        local dialplan = dofile("/usr/share/freeswitch/scripts/xml_handlers/dialplan/dialplan.lua")
        dialplan(settings)
    elseif section == "configuration" then
        -- Check if the configuration request is for sofia.conf
        local config_name = XML_REQUEST["key_value"]
        log("DEBUG", "Configuration name: " .. (config_name or "unknown"))
        if config_name == "sofia.conf" then
            -- Load the SIP profiles handler script and pass settings as an argument
            local sofia_profiles = dofile("/usr/share/freeswitch/scripts/xml_handlers/sip_profiles/sip_profiles.lua")
            sofia_profiles(settings)
        else
            log("WARNING", "No handler for configuration: " .. (config_name or "unknown"))
            XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="configuration"></section></document>'
        end
    else
        -- Log an error if the section is not recognized
        log("ERR", "Unknown section: " .. section)
        XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="' .. section .. '"></section></document>'
    end
end
