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
local settings = require("/usr/share/freeswitch/scripts/xml_handlers/settings")

-- Define a logging function to output messages to the FreeSWITCH console, respecting the debug setting
function log(level, message)
    -- Skip debug messages if debug is disabled in settings
    if level == "debug" and not settings.debug then
        return
    end
    freeswitch.consoleLog(level, "[Main] " .. message .. "\n")
end

-- Log an info message indicating the section being processed
log("INFO", "Processing XML request for section: " .. section)

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
    else
        -- Log an error if the section is not recognized
        log("ERR", "Unknown section: " .. section)
    end
end
