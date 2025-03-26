--[[
  ivr.lua
  Multi-tenant IVR XML handler for FreeSWITCH using view_ivr_menu_options
  Author: Rodrigo Cuadra
  Project: Ring2All
--]]

return function()
  local settings = require("resources.settings.settings")

  -- Logging helper
  local function log(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[IVR] " .. message .. "\n")
  end

  -- Connect to the database
  local dbh = freeswitch.Dbh("odbc://ring2all")
  if not dbh:connected() then
    log("ERR", "Failed to connect to database")
    return
  end

  -- Extract domain from environment
  local domain = freeswitch.getGlobalVariable("domain") or "default"
  if domain == "" then
    log("ERR", "Missing domain from request")
    return
  end

  -- Resolve tenant_id from domain
  local tenant_id
  local sql = "SELECT id FROM core.tenants WHERE domain_name = '" .. domain .. "'"
  dbh:query(sql, function(row)
    tenant_id = row.id
  end)

  if not tenant_id then
    log("ERR", "No tenant found for domain: " .. domain)
    return
  end

  -- Build the query to get IVR menu structure
  local ivr_sql = [[
    SELECT * FROM view_ivr_menu_options
    WHERE tenant_id = ']] .. tenant_id .. [['
    ORDER BY ivr_name, priority
  ]]
  log("debug", "IVR SQL: " .. ivr_sql)

  -- Prepare XML
  local xml = {}
  table.insert(xml, '<?xml version="1.0" encoding="UTF-8"?>')
  table.insert(xml, '<document type="freeswitch/xml">')
  table.insert(xml, '  <section name="configuration">')
  table.insert(xml, '    <menus>')

  local current_menu = nil
  local menu_open = false

  dbh:query(ivr_sql, function(row)
    if row.ivr_name ~= current_menu then
      if menu_open then
        table.insert(xml, "      </menu>")
      end

      table.insert(xml, '      <menu name="' .. row.ivr_name .. '"')
      table.insert(xml, '            greet-long="' .. (row.greet_long or '') .. '"')
      table.insert(xml, '            greet-short="' .. (row.greet_short or '') .. '"')
      table.insert(xml, '            invalid-sound="' .. (row.invalid_sound or '') .. '"')
      table.insert(xml, '            exit-sound="' .. (row.exit_sound or '') .. '"')
      table.insert(xml, '            timeout="' .. (row.timeout or '5') .. '"')
      table.insert(xml, '            max-failures="' .. (row.max_failures or '3') .. '"')
      table.insert(xml, '            max-timeouts="' .. (row.max_timeouts or '3') .. '"')
      table.insert(xml, '            direct-dial="' .. tostring(row.direct_dial == 't') .. '">')

      current_menu = row.ivr_name
      menu_open = true
    end

    local entry = '        <entry action="' .. row.action .. '" digits="' .. row.digits .. '"'
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
    table.insert(xml, "      </menu>")
  end

  table.insert(xml, '    </menus>')
  table.insert(xml, '  </section>')
  table.insert(xml, '</document>')

  local XML_STRING = table.concat(xml, "\n")
  log("info", "Generated IVR XML for domain " .. domain .. ":\n" .. XML_STRING)
  _G.XML_STRING = XML_STRING
end
