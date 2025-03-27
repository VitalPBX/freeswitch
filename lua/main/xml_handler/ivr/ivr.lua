--[[
  ivr.lua
  Dynamic IVR XML Generator for FreeSWITCH (Ring2All Project)

  This module builds a dynamic IVR configuration XML based on tenant-specific data
  stored in a PostgreSQL database accessed via ODBC.

  Author: Rodrigo Cuadra
  Project: Ring2All
--]]

return function(domain)
  -- Load global settings and helpers
  local settings = require("resources.settings.settings")

  -- Logging utility, respects the global debug flag
  local function log(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[IVR] " .. message .. "\n")
  end

  -- Validate input
  if not domain then
    log("ERR", "Parameter 'domain' is nil")
    return
  end

  -- Connect to the PostgreSQL database via ODBC
  local dbh = freeswitch.Dbh("odbc://ring2all")
  if not dbh:connected() then
    log("ERR", "Failed to connect to database")
    return
  end

  -- Look up tenant_id for the provided domain
  local tenant_id
  local sql = "SELECT id FROM core.tenants WHERE domain_name = '" .. domain .. "'"
  dbh:query(sql, function(row)
    tenant_id = row.id
  end)

  if not tenant_id then
    log("ERR", "Tenant not found for domain " .. domain)
    return
  end

  -- SQL query to fetch all IVR menu options for this tenant
  local ivr_sql = [[
    SELECT * FROM view_ivr_menu_options
    WHERE tenant_id = ']] .. tenant_id .. [['
    ORDER BY ivr_name, priority
  ]]
  log("debug", "IVR SQL: " .. ivr_sql)

  -- Start constructing the IVR XML response
  local xml = {}
  table.insert(xml, '<?xml version="1.0" encoding="UTF-8"?>')
  table.insert(xml, '<document type="freeswitch/xml">')
  table.insert(xml, '  <section name="configuration">')
  table.insert(xml, '    <configuration name="ivr.conf" description="IVR menus">')
  table.insert(xml, '      <menus>')

  local current_menu = nil
  local menu_open = false

  -- Loop through all IVR rows and build <menu> and <entry> elements
  dbh:query(ivr_sql, function(row)
    -- New menu block
    if row.ivr_name ~= current_menu then
      if menu_open then
        table.insert(xml, "        </menu>")
      end

      -- Open new <menu> block
      table.insert(xml, '        <menu name="' .. row.ivr_name .. '"')
      table.insert(xml, '              greet-long="' .. (row.greet_long or '') .. '"')
      table.insert(xml, '              greet-short="' .. (row.greet_short or '') .. '"')
      table.insert(xml, '              invalid-sound="' .. (row.invalid_sound or '') .. '"')
      table.insert(xml, '              exit-sound="' .. (row.exit_sound or '') .. '"')
      table.insert(xml, '              timeout="' .. (row.timeout or '5000') .. '"')
      table.insert(xml, '              max-failures="' .. (row.max_failures or '3') .. '"')
      table.insert(xml, '              max-timeouts="' .. (row.max_timeouts or '3') .. '"')
      table.insert(xml, '              direct-dial="' .. tostring(row.direct_dial == 't') .. '">')

      current_menu = row.ivr_name
      menu_open = true
    end

    -- Build an <entry> inside the current menu
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

  -- Close the last open menu
  if menu_open then
    table.insert(xml, "        </menu>")
  end

  -- Finish XML structure
  table.insert(xml, '      </menus>')
  table.insert(xml, '    </configuration>')
  table.insert(xml, '  </section>')
  table.insert(xml, '</document>')

  -- Generate final XML string
  local XML_STRING = table.concat(xml, "\n")
  log("info", "Generated IVR XML for domain " .. domain .. ":\n" .. XML_STRING)

  -- Return the XML to FreeSWITCH
  _G.XML_STRING = XML_STRING
end
