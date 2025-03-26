--[[
  sip_register.lua
  FreeSWITCH XML Directory handler for SIP registration (via ODBC + PostgreSQL)
  Author: Rodrigo Cuadra
  Project: Ring2All

  This script dynamically generates the XML directory response used by FreeSWITCH
  when processing SIP REGISTER requests. It integrates with a multi-tenant database
  and builds user parameters and variables from the `view_sip_users` view.
--]]

return function(params)
  -- Load settings and define logging helper
  local settings = require("resources.settings.settings")
  local log = function(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[SIPRegister] " .. message .. "\n")
  end

  -- Establish ODBC connection
  dbh = freeswitch.Dbh("odbc://ring2all")
  if not dbh:connected() then
    log("ERR", "Failed to connect to database")
    return
  end
  log("info", "ODBC connection established")

  -- Load FreeSWITCH global vars
  local api = freeswitch.API()
  local vars_raw = api:execute("global_getvar", "") or ""
  local global_vars = {}
  for line in vars_raw:gmatch("[^\n]+") do
    local name, value = line:match("^([^=]+)=(.+)$")
    if name and value then
      global_vars[name] = value
    end
  end

  -- Helper: Replace $${var} with global values
  local function replace_vars(str)
    return str:gsub("%$%${([^}]+)}", function(var_name)
      local value = global_vars[var_name] or ""
      if value == "" then
        log("warning", "Variable $$" .. var_name .. " not found, replacing with empty string")
      else
        log("debug", "Resolved $$" .. var_name .. " to: " .. value)
      end
      return value
    end)
  end

  -- Extract SIP headers
  local username, domain = "", ""
  if type(params) == "userdata" then
    username = params:getHeader("user") or params:getHeader("sip_user") or ""
    domain   = params:getHeader("domain") or params:getHeader("sip_host") or ""
  else
    log("error", "params is not a valid freeswitch XML handler object")
    return
  end

  log("debug", "Parsed SIP headers - username: " .. username .. ", domain: " .. domain)

  if domain == "" then
    log("error", "Missing domain in registration request")
    return
  end

  -- Resolve tenant ID
  local tenant_id = nil
  local tenant_sql = "SELECT id FROM core.tenants WHERE domain_name = '" .. domain .. "'"
  log("debug", "Looking up tenant ID with SQL: " .. tenant_sql)
  dbh:query(tenant_sql, function(row)
    tenant_id = row.id
  end)

  if not tenant_id then
    log("error", "No tenant found for domain: " .. domain)
    return
  end

  -- Prepare XML structure
  local xml = {}
  table.insert(xml, '<?xml version="1.0" encoding="UTF-8" standalone="no"?>')
  table.insert(xml, '<document type="freeswitch/xml">')
  table.insert(xml, '  <section name="directory">')
  table.insert(xml, '    <domain name="' .. domain .. '">')
  table.insert(xml, '      <users>')

  -- Check if user exists
  local user_exists_sql = "SELECT COUNT(*) AS count FROM view_sip_users WHERE tenant_id = '" .. tenant_id .. "' AND username = '" .. username .. "'"
  local user_exists = false
  dbh:query(user_exists_sql, function(row)
    user_exists = tonumber(row.count or 0) > 0
  end)

  if not user_exists then
    log("warning", "No SIP users found for tenant_id: " .. tenant_id .. " and username: " .. username)
  end

  -- If exists, load full data
  if user_exists then
    local user_sql = [[
      SELECT * FROM view_sip_users
      WHERE tenant_id = ']] .. tenant_id .. [[' AND username = ']] .. username .. [['
      ORDER BY username
    ]]

    log("debug", "Executing user query: " .. user_sql)

    local current_user = nil
    local last_username = nil

    dbh:query(user_sql, function(row)
      local row_username = row.username

      if row_username ~= last_username then
        if current_user then
          table.insert(current_user, '          </variables>')
          table.insert(current_user, '        </user>')
          for _, line in ipairs(current_user) do table.insert(xml, line) end
        end

        current_user = {}
        table.insert(current_user, '        <user id="' .. row_username .. '">')
        table.insert(current_user, '          <params>')
        table.insert(current_user, '            <param name="password" value="' .. row.password .. '"/>')
        table.insert(current_user, '          </params>')
        table.insert(current_user, '          <variables>')
        last_username = row_username
      end

      if row.setting_type == 'param' then
        table.insert(current_user, '            <param name="' .. row.setting_name .. '" value="' .. replace_vars(row.setting_value) .. '"/>')
      elseif row.setting_type == 'variable' then
        table.insert(current_user, '            <variable name="' .. row.setting_name .. '" value="' .. replace_vars(row.setting_value) .. '"/>')
      end
    end)

    -- Final user close
    if current_user then
      table.insert(current_user, '          </variables>')
      table.insert(current_user, '        </user>')
      for _, line in ipairs(current_user) do table.insert(xml, line) end
    end
  end

  -- Close XML
  table.insert(xml, '      </users>')
  table.insert(xml, '    </domain>')
  table.insert(xml, '  </section>')
  table.insert(xml, '</document>')

  -- Output to FreeSWITCH
  local XML_STRING = table.concat(xml, "\n")
  log("info", "Generated XML:\n" .. XML_STRING)
  _G.XML_STRING = XML_STRING
end
