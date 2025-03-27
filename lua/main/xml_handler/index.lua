--[[
  index.lua
  Main XML section dispatcher for FreeSWITCH (Ring2All Project)
  Routes XML handler requests like directory, dialplan, and configuration sections.

  Author: Rodrigo Cuadra
  Project: Ring2All
--]]

-- Get XML section requested by FreeSWITCH
local section = XML_REQUEST["section"]

-- Load settings and logging
local settings = require("resources.settings.settings")
local function log(level, message)
  if level == "debug" and not settings.debug then return end
  freeswitch.consoleLog(level, "[Main] " .. message .. "\n")
end

-- Entry point log
log("INFO", "Main.lua is handling XML request for section: " .. (section or "nil"))

-- Directory Handler (for SIP registration and authentication)
if section == "directory" then
  local handler = dofile("/usr/share/freeswitch/scripts/main/xml_handlers/directory/sip_register.lua")
  if type(handler) == "function" then
    handler(params)  -- `params` is automatically passed by FreeSWITCH
  else
    log("ERR", "sip_register.lua did not return a function")
  end

-- Dialplan Handler (for call routing logic)
elseif section == "dialplan" then
  local handler = dofile("/usr/share/freeswitch/scripts/main/xml_handlers/dialplan/dialplan.lua")
  if type(handler) == "function" then
    handler(params)
  else
    log("ERR", "dialplan.lua did not return a function")
  end

-- Configuration Handler (for vars.xml, sofia.conf, etc.)
elseif section == "configuration" then
  local config_name = XML_REQUEST["key_value"]
  log("DEBUG", "Configuration name: " .. (config_name or "unknown"))

  if config_name == "vars.xml" then
    log("INFO", "Handling vars.xml")
    local domain = XML_REQUEST["domain"] or XML_REQUEST["hostname"]
    local tenant_id = settings.get_tenant_id_by_domain(domain)
    local global_vars = require("main.xml_handlers.global_vars")
    XML_STRING = global_vars.handle(tenant_id)

  elseif config_name == "sofia.conf" then
    local handler = dofile("/usr/share/freeswitch/scripts/main/xml_handlers/sip_profiles/sip_profiles.lua")
    if type(handler) == "function" then
      handler(settings)
    else
      log("ERR", "sofia_profiles.lua did not return a function")
    end

  elseif config_name == "ivr.conf" then
    local ivr = require("main.xml_handlers.ivr.ivr")
    local domain = XML_REQUEST["domain"] or XML_REQUEST["hostname"]
    XML_STRING = ivr.handle(domain)

  else
    -- Placeholder response for unhandled config files
    log("WARNING", "No handler implemented for config: " .. config_name)
    XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="configuration"></section></document>'
  end

-- Unknown section fallback
else
  log("ERR", "Unknown section: " .. section)
  XML_STRING = '<?xml version="1.0" encoding="utf-8"?><document type="freeswitch/xml"><section name="' .. section .. '"></section></document>'
end
