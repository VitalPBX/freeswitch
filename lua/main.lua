--[[
    main.lua
    Main entry point for FreeSWITCH XML requests. Routes requests to specific handlers based on 
    the source argument and request type.
--]]

-- main.lua
local source = argv[1] or "unknown"
local section = XML_REQUEST["section"]

function log(level, message)
    freeswitch.consoleLog(level, "[Main] " .. message .. "\n")
end

log("INFO", "Processing XML request for section: " .. section)

if source == "xml_handlers" then
    if section == "directory" then
        dofile("/usr/share/freeswitch/scripts/xml_handlers/directory/sip_register.lua")
    elseif section == "dialplan" then
        dofile("/usr/share/freeswitch/scripts/xml_handlers/dialplan/dialplan.lua")
    else
        log("ERR", "Unknown section: " .. section)
    end
end
