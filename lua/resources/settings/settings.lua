--[[
  settings.lua
  Common settings and utility functions for FreeSWITCH scripts.

  This module provides shared utilities used throughout the Ring2All project,
  including XML formatting, database lookups for multi-tenant logic,
  and retrieval of domain information.

  Author: Rodrigo Cuadra
  Project: Ring2All
--]]

-- Global configuration table with shared functions
local settings = {
  -- Enable or disable debug-level logging globally
  debug = true
}

--[[
  settings.format_xml(section_name, content, options)
  -----------------------------------------------------
  Generates a properly indented FreeSWITCH XML response.

  Parameters:
    section_name (string): The name of the XML section (e.g., "directory", "dialplan", "configuration").
    content (string): The inner XML content (can include multiple lines).
    options (table, optional):
      - indent (string): Custom indentation (default: 3 spaces).
      - domain_name (string): If present, wraps content inside <domain name="...">.
      - alias (boolean): Whether to add alias="true" to the domain tag.
      - extra_attrs (table): Additional attributes for the section (not used currently).

  Returns:
    string: A full FreeSWITCH XML document.
--]]
function settings.format_xml(section_name, content, options)
  local opts = options or {}
  local indent = opts.indent or "   "
  local domain_name = opts.domain_name or ""
  local alias = opts.alias or false
  local extra_attrs = opts.extra_attrs or {}

  -- Define indentation levels
  local level0 = ""
  local level1 = indent
  local level2 = indent .. indent
  local level3 = indent .. indent .. indent
  local level4 = indent .. indent .. indent .. indent

  -- Start building XML response
  local xml = {
    level0 .. '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
    level0 .. '<document type="freeswitch/xml">',
    level1 .. '<section name="' .. section_name .. '">'
  }

  -- If domain is provided, wrap content inside a <domain> block
  if domain_name and domain_name ~= "" then
    local domain_line = level2 .. '<domain name="' .. domain_name .. '"'
    if alias then
      domain_line = domain_line .. ' alias="true"'
    end
    domain_line = domain_line .. '>'
    table.insert(xml, domain_line)

    for line in content:gmatch("[^\n]+") do
      table.insert(xml, level3 .. line)
    end

    table.insert(xml, level2 .. '</domain>')
  else
    -- Otherwise, insert content directly under section
    for line in content:gmatch("[^\n]+") do
      table.insert(xml, level2 .. line)
    end
  end

  -- Close section and document
  table.insert(xml, level1 .. '</section>')
  table.insert(xml, level0 .. '</document>')

  return table.concat(xml, "\n")
end

--[[
  settings.get_tenant_id_by_domain(domain)
  ----------------------------------------
  Retrieves the UUID of the tenant matching the given domain.

  Parameters:
    domain (string): The domain name (must match core.tenants.domain).

  Returns:
    string: The tenant_id UUID as a string. Returns a fallback "0000..." if not found.
--]]
function settings.get_tenant_id_by_domain(domain)
  local luasql = require "luasql.postgres"
  local env = luasql.postgres()

  local dbh = env:connect("ring2all", "ring2all", "r2a2025", "127.0.0.1", 5432)
  if not dbh then
    freeswitch.consoleLog("ERR", "? Could not connect to DB to resolve tenant_id\n")
    return nil
  end

  local tenant_id = nil
  local sql = string.format("SELECT id FROM core.tenants WHERE domain = '%s' LIMIT 1", domain)

  local cursor = dbh:execute(sql)
  if cursor then
    local row = cursor:fetch({}, "a")
    if row then
      tenant_id = row.id
    end
    cursor:close()
  end

  dbh:close()
  env:close()

  return tenant_id or "00000000-0000-0000-0000-000000000000"
end

--[[
  settings.get_domain()
  ---------------------
  Retrieves the domain name from one of several sources,
  in priority order:
    1. XML_REQUEST (used in XML handlers)
    2. FreeSWITCH global variables
    3. session (active call context)

  Returns:
    string or nil: The domain name.
--]]
function settings.get_domain()
  local domain = nil

  -- 1. Check XML_REQUEST (common in config requests)
  if XML_REQUEST then
    domain = XML_REQUEST["domain"] or XML_REQUEST["hostname"]
  end

  -- 2. Fallback to global FreeSWITCH variable
  if not domain or domain == "" then
    domain = freeswitch.getGlobalVariable("domain")
  end

  -- 3. Fallback to session variable (if call context exists)
  if not domain or domain == "" then
    if session and session:ready() then
      domain = session:getVariable("domain_name") or session:getVariable("sip_to_host")
    end
  end

  return domain
end

-- Export the settings module
return settings
