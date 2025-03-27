--[[
  sip_profiles.lua
  Dynamic multi-tenant SIP Profile and Gateway handler using optimized sip_profiles and sip_profile_settings tables
  Author: Rodrigo Cuadra
  Project: Ring2All

  Description:
  Generates FreeSWITCH Sofia SIP Profile configuration dynamically from PostgreSQL (core.sip_profiles and core.sip_profile_settings)

  Features:
  - Multi-tenant support
  - Dynamic profile and gateway loading
  - Variable substitution using FreeSWITCH globals
--]]

local settings = require("resources.settings.settings")
local log = function(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[SIPProfiles] " .. message .. "\n")
end

local api = freeswitch.API()

-- Load FreeSWITCH global variables
local global_vars = {}
local vars = api:execute("global_getvar", "") or ""
for line in vars:gmatch("[^\n]+") do
    local name, value = line:match("^([^=]+)=(.+)$")
    if name and value then
        global_vars[name] = value
    end
end

local function replace_vars(str)
    if not str then return "" end
    str = str:gsub("%$%${([^}]+)}", global_vars)
    str = str:gsub("%${([^}]+)}", global_vars)
    return str
end

local dbh = freeswitch.Dbh("odbc://ring2all")
assert(dbh:connected(), "Database connection failed!")

local aliases_by_profile = {}
dbh:query("SELECT sip_profile_id, alias FROM core.sip_profile_aliases", function(row)
    aliases_by_profile[row.sip_profile_id] = aliases_by_profile[row.sip_profile_id] or {}
    table.insert(aliases_by_profile[row.sip_profile_id], row.alias)
end)

local gateways_by_tenant = {}
dbh:query([[SELECT * FROM view_gateways ORDER BY gateway_id, setting_name]], function(row)
    gateways_by_tenant[row.tenant_id] = gateways_by_tenant[row.tenant_id] or {}
    gateways_by_tenant[row.tenant_id][row.gateway_name] = gateways_by_tenant[row.tenant_id][row.gateway_name] or { row = row, settings = {} }
    table.insert(gateways_by_tenant[row.tenant_id][row.gateway_name].settings, { name = row.setting_name, value = row.setting_value })
end)

local xml = {'<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
'<document type="freeswitch/xml">',
'  <section name="configuration">',
'    <configuration name="sofia.conf" description="Sofia Endpoint">',
'      <profiles>'}

local current_profile_id = nil
local current_profile = {}

-- Load profiles and settings
dbh:query([[SELECT p.id, p.name, p.tenant_id, s.name AS setting_name, s.value AS setting_value
FROM core.sip_profiles p
JOIN core.sip_profile_settings s ON s.sip_profile_id = p.id
WHERE p.enabled = TRUE AND s.enabled = TRUE
ORDER BY p.setting_order, s.setting_order]], function(row)
    if current_profile_id ~= row.id then
        if #current_profile > 0 then
            table.insert(current_profile, '        </settings>')
            table.insert(current_profile, '      </profile>')
            for _, line in ipairs(current_profile) do table.insert(xml, line) end
        end
        current_profile = {}
        current_profile_id = row.id

        table.insert(current_profile, string.format('      <profile name="%s">', replace_vars(row.name)))

        -- Aliases
        table.insert(current_profile, '        <aliases>')
        local aliases = aliases_by_profile[row.id] or {}
        for _, alias in ipairs(aliases) do
            table.insert(current_profile, string.format('          <alias name="%s"/>', replace_vars(alias)))
        end
        table.insert(current_profile, '        </aliases>')

        -- Gateways
        table.insert(current_profile, '        <gateways>')
        local gateways = gateways_by_tenant[row.tenant_id] or {}
        for gw_name, gw_data in pairs(gateways) do
            table.insert(current_profile, string.format('          <gateway name="%s">', replace_vars(gw_name)))
            for _, setting in ipairs(gw_data.settings) do
                table.insert(current_profile, string.format('            <param name="%s" value="%s"/>', replace_vars(setting.name), replace_vars(setting.value)))
            end
            table.insert(current_profile, '          </gateway>')
        end
        table.insert(current_profile, '        </gateways>')

        table.insert(current_profile, '        <domains>')
        table.insert(current_profile, '          <domain name="all" alias="false" parse="false"/>')
        table.insert(current_profile, '        </domains>')
        table.insert(current_profile, '        <settings>')
    end

    table.insert(current_profile, string.format('          <param name="%s" value="%s"/>', replace_vars(row.setting_name), replace_vars(row.setting_value)))
end)

if #current_profile > 0 then
    table.insert(current_profile, '        </settings>')
    table.insert(current_profile, '      </profile>')
    for _, line in ipairs(current_profile) do table.insert(xml, line) end
end

-- Finalize XML
table.insert(xml, '      </profiles>')
table.insert(xml, '    </configuration>')
table.insert(xml, '  </section>')
table.insert(xml, '</document>')

XML_STRING = table.concat(xml, "\n")
log("info", "SIP Profiles XML generated successfully.")

dbh:release()
