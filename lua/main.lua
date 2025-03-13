--[[
    main.lua
    Main entry point for FreeSWITCH XML requests. Routes requests to specific handlers based on 
    the source argument and request type. Loads settings globally and passes them to secondary scripts.
--]]

-- Get the source argument passed to the script, default to "unknown" if not provided
local source = argv[1] or "unknown"

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
log("INFO", "Main.lua is handling XML request for section: " .. section .. ", source: " .. source)

--for loop through arguments
	arguments = "";
	for key,value in pairs(argv) do
		if (key > 1) then
			arguments = arguments .. " '" .. value .. "'";
			--freeswitch.consoleLog("notice", "[app.lua] argv["..key.."]: "..argv[key].."\n");
		end
	end

--route the request to the application
	--freeswitch.consoleLog("notice", "["..app_name.."]".. scripts_dir .. "/main/" .. app_name .. "/index.lua\n");
	loadfile(scripts_dir .. "/main/" .. app_name .. "/index.lua")(argv);
