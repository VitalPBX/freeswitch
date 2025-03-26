--[[
  dialplan.lua
  Dynamic multi-tenant dialplan handler using view_dialplan_expanded
  Author: Rodrigo Cuadra
  Project: Ring2All

  Description:
  This script dynamically generates the FreeSWITCH dialplan XML based on tenant-specific
  configurations stored in PostgreSQL, using the `view_dialplan_expanded` view.

  Features:
  - Supports multi-tenant architecture based on domain name
  - Generates contexts, extensions, conditions, and actions dynamically
  - Supports both actions and anti-actions
--]]

return function()
  local settings = require("resources.settings.settings")

  -- Logging helper with debug toggle
  local function log(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[Dialplan] " .. message .. "\n")
  end

  -- Connect to the PostgreSQL database via ODBC
  local dbh = freeswitch.Dbh("odbc://ring2all")
  if not dbh:connected() then
    log("ERR", "Failed to connect to database")
    return
  end

  -- Extract necessary request parameters
  local context    = XML_REQUEST["context"] or "default"
  local destination = XML_REQUEST["destination-number"] or ""
  local domain     = freeswitch.getGlobalVariable("domain") or "default"

  log("DEBUG", "Context: " .. context .. ", Destination: " .. destination .. ", Domain: " .. domain)

  if domain == "" then
    log("ERR", "Missing domain in dialplan request")
    return
  end

  -- Resolve tenant_id from domain
  local tenant_id = nil
  local sql = "SELECT id FROM core.tenants WHERE domain_name = '" .. domain .. "'"
  dbh:query(sql, function(row)
    tenant_id = row.id
  end)

  if not tenant_id then
    log("ERR", "No tenant found for domain: " .. domain)
    return
  end

  -- Build the query to load dialplan structure for this tenant
  local dialplan_sql = [[
    SELECT * FROM view_dialplan_expanded
    WHERE tenant_id = ']] .. tenant_id .. [['
    ORDER BY context_name, extension_priority, extension_name, condition_id, action_sequence
  ]]

  log("debug", "Dialplan SQL: " .. dialplan_sql)

  -- Prepare XML output structure
  local xml = {}
  table.insert(xml, '<?xml version="1.0" encoding="UTF-8"?>')
  table.insert(xml, '<document type="freeswitch/xml">')
  table.insert(xml, '  <section name="dialplan">')

  -- State tracking
  local current_context, current_extension, current_condition
  local context_open, extension_open, condition_open = false, false, false

  -- Process each row from the view and build the XML structure
  dbh:query(dialplan_sql, function(row)
    -- New context
    if row.context_name ~= current_context then
      if context_open then
        if condition_open then
          table.insert(xml, "            </condition>")
          condition_open = false
        end
        if extension_open then
          table.insert(xml, "        </extension>")
          extension_open = false
        end
        table.insert(xml, "      </context>")
        context_open = false
      end
      table.insert(xml, '    <context name="' .. row.context_name .. '">')
      current_context = row.context_name
      context_open = true
    end

    -- New extension
    if row.extension_name ~= current_extension then
      if condition_open then
        table.insert(xml, "            </condition>")
        condition_open = false
      end
      if extension_open then
        table.insert(xml, "        </extension>")
        extension_open = false
      end

      local continue_attr = ""
      if row.continue and row.continue:lower() == "true" then
        continue_attr = ' continue="true"'
      end
      table.insert(xml, '      <extension name="' .. row.extension_name .. '"' .. continue_attr .. '>')

      current_extension = row.extension_name
      extension_open = true
    end

    -- New condition
    if row.condition_id ~= current_condition then
      if condition_open then
        table.insert(xml, "            </condition>")
        condition_open = false
      end
      table.insert(xml, '        <condition field="' .. row.condition_field .. '" expression="' .. row.condition_expr .. '">')
      current_condition = row.condition_id
      condition_open = true
    end

    -- Add action or anti-action
    local tag = row.action_type == "anti-action" and "anti-action" or "action"
    local line = '          <' .. tag .. ' application="' .. row.app_name .. '"'
    if row.app_data and row.app_data ~= "" then
      line = line .. ' data="' .. row.app_data .. '"'
    end
    line = line .. '/>'
    table.insert(xml, line)
  end)

  -- Close any remaining open tags
  if condition_open then table.insert(xml, "            </condition>") end
  if extension_open then table.insert(xml, "        </extension>") end
  if context_open then table.insert(xml, "      </context>") end

  -- Finalize XML
  table.insert(xml, '  </section>')
  table.insert(xml, '</document>')

  -- Join and return XML string
  local XML_STRING = table.concat(xml, "\n")
  log("info", "Generated Dialplan XML for domain " .. domain .. ":\n" .. XML_STRING)
  _G.XML_STRING = XML_STRING
end
