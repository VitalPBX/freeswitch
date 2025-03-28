--[[
  index.lua
  Main XML section dispatcher for FreeSWITCH (Ring2All Project)

  This script is the main entry point for handling dynamic XML responses in FreeSWITCH.
  It determines which section of the XML configuration is being requested
  (e.g., directory, dialplan, or configuration), and then delegates processing
  to the appropriate Lua handler.

  Author: Rodrigo Cuadra
  Project: Ring2All
--]]

-- Get the section requested by FreeSWITCH (e.g., "directory", "dialplan", "configuration")
local section = XML_REQUEST["section"]

-- Load settings and logging helper
local settings = require("resources.settings.settings")

-- Logging function with debug level filtering
local function log(level, message)
  if level == "debug" and not settings.debug then return end
  freeswitch.consoleLog(level, "[Main] " .. message .. "\n")
end

-- Log the entry point with the section being processed
log("INFO", "Main.lua is handling XML request for section: " .. (section or "nil"))

-- Handle the "directory" section (typically used for SIP user authentication and registration)
if section == "directory" then
  local handler = dofile("/usr/share/freeswitch/scripts/main/xml_handlers/directory/sip_register.lua")
  if type(handler) == "function" then
    handler(params)  -- FreeSWITCH automatically passes request parameters as `params`
  else
    log("ERR", "sip_register.lua did not return a function")
  end

-- Handle the "dialplan" section (used for inbound and outbound call routing logic)
elseif section == "dialplan" then
  local handler = dofile("/usr/share/freeswitch/scripts/main/xml_handlers/dialplan/dialplan.lua")
  if type(handler) == "function" then
    handler(params)
  else
    log("ERR", "dialplan.lua did not return a function")
  end

-- Handle the "configuration" section (used for core FreeSWITCH configuration files)
elseif section == "configuration" then
  -- Get the specific config being requested (e.g., vars.xml, ivr.conf, sofia.conf)
  local config_name = XML_REQUEST["key_value"]
  log("DEBUG", "Configuration name: " .. (config_name or "unknown"))

  -- Handle vars.xml (usually for global FreeSWITCH variables)
  if config_name == "vars.xml" then
    log("INFO", "Handling vars.xml")
    local domain = XML_REQUEST["domain"] or XML_REQUEST["hostname"]
    local tenant_id = settings.get_tenant_id_by_domain(domain)
    local global_vars = require("main.xml_handlers.global_vars")
    XML_STRING = global_vars.handle(tenant_id)

  -- Handle sofia.conf (used to configure SIP profiles)
  elseif config_name == "sofia.conf" then
    dofile("/usr/share/freeswitch/scripts/main/xml_handlers/sip_profiles/sip_profiles.lua")

  -- Handle ivr.conf (used to define IVR menus)
  elseif config_name == "ivr.conf" then
    local domain = settings.get_domain()
    if not domain or domain == "" then
      log("ERR", "Domain not found in XML_REQUEST for IVR")
      return
    end

    local ivr = require("main.xml_handlers.ivr.ivr")
    ivr(domain)  -- This generates XML_STRING internally for ivr

  -- Handle the "ivr_menus" section (used when the IVR is actually executed)
  elseif section == "ivr_menus" then
    local domain = settings.get_domain()
    if not domain or domain == "" then
      log("ERR", "Domain not found in XML_REQUEST for IVR menu")
      return
    end

    local ivr = require("main.xml_handlers.ivr.ivr")
    ivr(domain) -- This generates XML_STRING internally for ivr_menus
    
  -- Fallback for unhandled configuration files
  else
    log("WARNING", "No handler implemented for config: " .. config_name)
    XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="configuration"></section></document>'
  end

-- Fallback if an unknown or unsupported XML section is requested
else
  log("ERR", "Unknown section: " .. section)
  XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="' .. section .. '"></section></document>'
end
