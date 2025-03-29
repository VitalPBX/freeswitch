--[[
  ivr.lua
  Dynamic IVR XML Generator for FreeSWITCH (Ring2All Project)

  This module builds a dynamic IVR configuration XML based on tenant-specific data
  stored in a PostgreSQL database accessed via ODBC.

  Author: Rodrigo Cuadra
  Project: Ring2All
--]]

return function(domain)
  local settings = require("resources.settings.settings")

  local function log(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[IVR] " .. message .. "\n")
  end

  if not domain then
    log("ERR", "Parameter 'domain' is nil")
    return
  end

  local dbh = freeswitch.Dbh("odbc://ring2all")
  if not dbh:connected() then
    log("ERR", "Failed to connect to database")
    return
  end

  local tenant_id
  local sql = "SELECT id FROM core.tenants WHERE domain_name = '" .. domain .. "'"
  dbh:query(sql, function(row)
    tenant_id = row.id
  end)

  if not tenant_id then
    log("ERR", "Tenant not found for domain " .. domain)
    return
  end

  local ivr_sql = [[
    SELECT * FROM view_ivr_menu_options
    WHERE tenant_id = ']] .. tenant_id .. [['
    ORDER BY ivr_name, priority
  ]]
  log("debug", "IVR SQL: " .. ivr_sql)

  local xml = {}
  table.insert(xml, '<?xml version="1.0" encoding="UTF-8"?>')
  table.insert(xml, '<document type="freeswitch/xml">')
  table.insert(xml, '  <section name="configuration">')
  table.insert(xml, '    <configuration name="ivr.conf" description="IVR menus">')
  table.insert(xml, '      <menus>')

  local current_menu = nil
  local menu_open = false

  dbh:query(ivr_sql, function(row)
    if row.ivr_name ~= current_menu then
      if menu_open then
        table.insert(xml, "        </menu>")
      end

      table.insert(xml, '        <menu name="' .. row.ivr_name .. '"'
        .. ' greet-long="' .. (row.greet_long or '') .. '"'
        .. ' greet-short="' .. (row.greet_short or '') .. '"'
        .. ' invalid-sound="' .. (row.invalid_sound or '') .. '"'
        .. ' exit-sound="' .. (row.exit_sound or '') .. '"'
        .. ' timeout="' .. (row.timeout or '5000') .. '"'
        .. ' max-failures="' .. (row.max_failures or '3') .. '"'
        .. ' max-timeouts="' .. (row.max_timeouts or '3') .. '"'
        .. ' direct-dial="' .. tostring(row.direct_dial == 't') .. '">')

      current_menu = row.ivr_name
      menu_open = true
    end

    local entry = '          <entry action="' .. row.action .. '" digits="' .. row.digits .. '"'
    if row.destination and row.destination ~= "" then
      entry = entry .. ' param="' .. row.destination .. '"'
    end
    if row.condition and row.condition ~= "" then
      entry = entry .. ' expression="' .. row.condition .. '"'
    end
    if row.break_on_match == "t" then
      entry = entry .. ' break="true"'
    end
    entry = entry .. '/>'
    table.insert(xml, entry)
  end)

  if menu_open then
    table.insert(xml, "        </menu>")
  end

  table.insert(xml, '      </menus>')
  table.insert(xml, '    </configuration>')
  table.insert(xml, '  </section>')
  table.insert(xml, '</document>')

  local XML_STRING = table.concat(xml, "\n")
  log("info", "Generated IVR XML for domain " .. domain .. ":\n" .. XML_STRING)
  _G.XML_STRING = XML_STRING
end
