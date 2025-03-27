--[[
  sip_profiles.lua
  Dynamic multi-tenant SIP Profile and Gateway handler using view_sip_profiles and view_gateways
  Author: Rodrigo Cuadra
  Project: Ring2All

  Description:
  Generates FreeSWITCH Sofia SIP Profiles configuration XML using PostgreSQL data.
--]]

local settings = require("resources.settings.settings")

local log = function(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[SIPProfiles] " .. message .. "\n")
end

local api = freeswitch.API()
local global_vars = {}

do
    local vars = api:execute("global_getvar", "") or ""
    for line in vars:gmatch("[^\n]+") do
        local name, value = line:match("^([^=]+)=(.+)$")
        if name and value then global_vars[name] = value end
    end
end

local function replace_vars(str)
    if not str then return "" end
    str = str:gsub("%$%${([^}]+)}", function(var) return global_vars[var] or "" end)
    str = str:gsub("%${([^}]+)}", function(var) return global_vars[var] or "" end)
    return str
end

local dbh = freeswitch.Dbh("odbc://ring2all")
assert(dbh:connected(), "Database connection failed!")

local xml = {
  '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
  '<document type="freeswitch/xml">',
  '  <section name="configuration">',
  '    <configuration name="sofia.conf" description="Sofia Endpoint">',
  '      <profiles>'
}

-- Fetch aliases per profile
local aliases_by_profile = {}
dbh:query("SELECT sip_profile_id, alias FROM core.sip_profile_aliases", function(row)
    aliases_by_profile[row.sip_profile_id] = aliases_by_profile[row.sip_profile_id] or {}
    table.insert(aliases_by_profile[row.sip_profile_id], row.alias)
end)

-- Fetch gateways per tenant
local gateways_by_tenant = {}
dbh:query([[SELECT * FROM view_gateways]], function(row)
    local t_id, gw_name = row.tenant_id, row.gateway_name
    gateways_by_tenant[t_id] = gateways_by_tenant[t_id] or {}
    gateways_by_tenant[t_id][gw_name] = gateways_by_tenant[t_id][gw_name] or { row = row, settings = {} }
    table.insert(gateways_by_tenant[t_id][gw_name].settings, {name=row.setting_name, value=row.setting_value})
end)

-- Fetch SIP profiles and settings
local profiles = {}
dbh:query([[SELECT * FROM view_sip_profiles ORDER BY sip_profile_id, setting_order]], function(row)
    local pid = row.sip_profile_id
    profiles[pid] = profiles[pid] or {
        name = row.profile_name,
        tenant_id = row.tenant_id,
        settings = {}
    }
    table.insert(profiles[pid].settings, {name=row.setting_name, value=row.setting_value})
end)

-- Generate XML for each profile
for pid, pdata in pairs(profiles) do
    table.insert(xml, '        <profile name="' .. replace_vars(pdata.name) .. '">')

    -- Aliases
    table.insert(xml, '          <aliases>')
    for _, alias in ipairs(aliases_by_profile[pid] or {}) do
        table.insert(xml, '            <alias name="' .. replace_vars(alias) .. '"/>')
    end
    table.insert(xml, '          </aliases>')

    -- Gateways
    table.insert(xml, '          <gateways>')
    for gw_name, gw_data in pairs(gateways_by_tenant[pdata.tenant_id] or {}) do
        table.insert(xml, '            <gateway name="' .. replace_vars(gw_name) .. '">')
        for attr, val in pairs(gw_data.row or {}) do
            if val and attr ~= "gateway_name" and attr ~= "tenant_id" and attr ~= "gateway_id" then
                table.insert(xml, '              <param name="' .. attr .. '" value="' .. replace_vars(val) .. '"/>')
            end
        end
        for _, setting in ipairs(gw_data.settings) do
            table.insert(xml, '              <param name="' .. replace_vars(setting.name) .. '" value="' .. replace_vars(setting.value) .. '"/>')
        end
        table.insert(xml, '            </gateway>')
    end
    table.insert(xml, '          </gateways>')

    -- Domains
    table.insert(xml, '          <domains>')
    table.insert(xml, '            <domain name="all" alias="false" parse="false"/>')
    table.insert(xml, '          </domains>')

    -- Settings
    table.insert(xml, '          <settings>')
    for _, setting in ipairs(pdata.settings) do
        table.insert(xml, '            <param name="' .. replace_vars(setting.name) .. '" value="' .. replace_vars(setting.value) .. '"/>')
    end
    table.insert(xml, '          </settings>')
    table.insert(xml, '        </profile>')
end

table.insert(xml, '      </profiles>')
table.insert(xml, '    </configuration>')
table.insert(xml, '  </section>')
table.insert(xml, '</document>')

XML_STRING = table.concat(xml, "\n")
log("info", "Generated XML:\n" .. XML_STRING)
log("info", "SIP Profiles XML generated successfully.")

dbh:release()
