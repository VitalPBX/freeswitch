--[[
  sip_profiles.lua
  Dynamic multi-tenant SIP Profile and Gateway handler using view_sip_profiles and view_gateways
  Author: Rodrigo Cuadra
  Project: Ring2All

  Description:
  This script dynamically generates the FreeSWITCH Sofia SIP Profiles configuration XML,
  including associated Gateways, using tenant-specific data from PostgreSQL.

  Features:
  - Multi-tenant support based on tenant_id
  - Dynamic profile and gateway generation
  - Supports $${var} and ${var} substitution with FreeSWITCH global variables
--]]

-- Load global settings and logging function
-- sip_profiles.lua (optimizado con método de reemplazo robusto y adaptado para cargar aliases correctamente)
local settings = require("resources.settings.settings")

local log = function(level, message)
    if level == "debug" and not settings.debug then return end
    freeswitch.consoleLog(level, "[SIPProfiles] " .. message .. "\n")
end

local api = freeswitch.API()

-- Retrieve all global variables from FreeSWITCH and store in a key-value table
local global_vars = {}
do
    local vars = api:execute("global_getvar", "") or ""
    for line in vars:gmatch("[^\n]+") do
        local name, value = line:match("^([^=]+)=(.+)$")
        if name and value then
            global_vars[name] = value
            log("debug", "Parsed global variable: " .. name .. " = " .. value)
        end
    end
end

-- Replace $${var} and ${var} with their corresponding values from global_vars
local function replace_vars(str)
    if not str then return "" end
    str = str:gsub("%$%${([^}]+)}", function(var_name)
        local value = global_vars[var_name] or ""
        if value == "" then
            log("warning", "Variable $$" .. var_name .. " not found, replacing with empty string")
        else
            log("debug", "Resolved $$" .. var_name .. " to: " .. value)
        end
        return value
    end)
    str = str:gsub("%${([^}]+)}", function(var_name)
        local value = global_vars[var_name] or ""
        if value == "" then
            log("warning", "Variable ${" .. var_name .. "} not found, replacing with empty string")
        else
            log("debug", "Resolved ${" .. var_name .. "} to: " .. value)
        end
        return value
    end)
    return str
end

local dbh = freeswitch.Dbh("odbc://ring2all")
assert(dbh:connected(), "Database connection failed!")

local aliases_by_profile = {}
dbh:query("SELECT sip_profile_id, alias FROM core.sip_profile_aliases", function(row)
    aliases_by_profile[row.sip_profile_id] = aliases_by_profile[row.sip_profile_id] or {}
    table.insert(aliases_by_profile[row.sip_profile_id], row.alias)
end)

local xml = {'<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
'<document type="freeswitch/xml">',
'  <section name="configuration">',
'    <configuration name="sofia.conf" description="Sofia Endpoint">',
'      <profiles>'}

local gateways_by_tenant = {}
dbh:query([[SELECT * FROM view_gateways ORDER BY gateway_id, setting_name]], function(row)
    local t_id = row.tenant_id
    gateways_by_tenant[t_id] = gateways_by_tenant[t_id] or {}
    local gw_name = row.gateway_name
    gateways_by_tenant[t_id][gw_name] = gateways_by_tenant[t_id][gw_name] or { row = row, settings = {} }
    table.insert(gateways_by_tenant[t_id][gw_name].settings, { name = row.setting_name, value = row.setting_value })
end)

local last_profile_id = nil
local current_profile = {}
dbh:query([[SELECT * FROM view_sip_profiles ORDER BY tenant_id, sip_profile_id, setting_name]], function(row)
    if last_profile_id ~= row.sip_profile_id then
        if #current_profile > 0 then
            table.insert(current_profile, '        </settings>')
            table.insert(current_profile, '      </profile>')
            for _, line in ipairs(current_profile) do table.insert(xml, line) end
        end
        current_profile = {}
        last_profile_id = row.sip_profile_id

        table.insert(current_profile, string.format('      <profile name="%s">', replace_vars(row.profile_name)))

        -- Aliases
        table.insert(current_profile, '        <aliases>')
        local aliases = aliases_by_profile[row.sip_profile_id] or {}
        for _, alias in ipairs(aliases) do
            table.insert(current_profile, string.format('          <alias name="%s"/>', replace_vars(alias)))
       end
       table.insert(current_profile, '        </aliases>')

        -- Gateways
        table.insert(current_profile, '        <gateways>')
        local gateways = gateways_by_tenant[row.tenant_id] or {}
        for gw_name, gw_data in pairs(gateways) do
            table.insert(current_profile, string.format('          <gateway name="%s">', replace_vars(gw_name)))
            local attrs = { "username", "password", "from-user", "from-domain", "proxy", "expire-seconds", "register", "register-transport", "contact-params", "retry-seconds", "context" }
            for _, attr in ipairs(attrs) do
                local val = gw_data.row[attr]
                if val and val ~= "" then
                    table.insert(current_profile, string.format('            <param name="%s" value="%s"/>', attr, replace_vars(val)))
                end
            end
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
    if row.setting_name and row.setting_value then
        table.insert(current_profile, string.format('          <param name="%s" value="%s"/>', replace_vars(row.setting_name), replace_vars(row.setting_value)))
    end
end)

if #current_profile > 0 then
    table.insert(current_profile, '        </settings>')
    table.insert(current_profile, '      </profile>')
    for _, line in ipairs(current_profile) do table.insert(xml, line) end
end

table.insert(xml, '      </profiles>')
table.insert(xml, '    </configuration>')
table.insert(xml, '  </section>')
table.insert(xml, '</document>')

XML_STRING = table.concat(xml, "\n")
log("info", "Generated XML:\n" .. XML_STRING)
log("info", "SIP Profiles and Gateways XML generated successfully.")

dbh:release()
