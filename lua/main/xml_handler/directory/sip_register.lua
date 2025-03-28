--[[
  sip_register.lua
  Enhanced FreeSWITCH XML Directory handler with SIP Profile inheritance
  Author: Rodrigo Cuadra
  Project: Ring2All

  This script generates XML for SIP registrations dynamically from a PostgreSQL database,
  using user-specific settings and settings inherited from a related SIP profile.
--]]

return function(params)
    local settings = require("resources.settings.settings")
    local log = function(level, message)
        if level == "debug" and not settings.debug then return end
        freeswitch.consoleLog(level, "[SIPRegister] " .. message .. "\n")
    end

    local dbh = freeswitch.Dbh("odbc://ring2all")
    assert(dbh:connected(), "Database connection failed!")

    local api = freeswitch.API()
    local domain = params:getHeader("domain") or params:getHeader("sip_host") or ""
    local username = params:getHeader("user") or params:getHeader("sip_user") or ""

    if domain == "" or username == "" then
        log("error", "Missing domain or username")
        return
    end

    -- Resolve tenant ID
    local tenant_id
    dbh:query("SELECT id FROM core.tenants WHERE domain_name = '" .. domain .. "'", function(row)
        tenant_id = row.id
    end)

    if not tenant_id then
        log("error", "No tenant found for domain: " .. domain)
        return
    end

    -- Fetch user info
    local sip_profile_id
    local user_enabled = false
    local user_params, user_vars = {}, {}
    local found_user = false

    local user_row
    dbh:query(string.format([[SELECT DISTINCT ON (username) username, sip_profile_id, enabled
        FROM view_sip_users WHERE tenant_id = '%s' AND username = '%s']], tenant_id, username), function(row)
        user_row = row
        found_user = true
    end)

    if not found_user then
        log("error", "User not found: " .. username)
        return
    end

    sip_profile_id = user_row.sip_profile_id
    user_enabled = tostring(user_row.enabled):lower() == "t" or tostring(user_row.enabled):lower() == "true" or tostring(user_row.enabled) == "1"

    if not user_enabled then
        log("error", "User is not enabled: " .. username)
        return
    end

    -- Load user settings
    dbh:query(string.format([[SELECT name, type, value FROM core.sip_user_settings
        WHERE sip_user_id = (SELECT id FROM core.sip_users WHERE username = '%s' AND tenant_id = '%s')
        AND enabled = true]], username, tenant_id), function(row)
        if row.type == "param" then
            user_params[row.name] = row.value
        elseif row.type == "variable" then
            user_vars[row.name] = row.value
        end
    end)

    -- Load SIP profile inheritance if valid
    if sip_profile_id then
        local valid_profile = false
        dbh:query(string.format([[SELECT id FROM core.sip_profiles WHERE id = '%s' AND category = 'sip_user']], sip_profile_id), function(_)
            valid_profile = true
        end)

        if valid_profile then
            log("info", "Herencia activada desde perfil: " .. tostring(sip_profile_id))
            dbh:query(string.format([[SELECT type, name, value FROM core.sip_profile_settings
                WHERE sip_profile_id = '%s' AND category = 'sip_user' AND enabled = TRUE ORDER BY setting_order]], sip_profile_id), function(row)
                log("debug", string.format("?? Heredando %s: %s = %s", row.type, row.name, row.value))
                if row.type == "param" and not user_params[row.name] then
                    user_params[row.name] = row.value
                elseif row.type == "variable" and not user_vars[row.name] then
                    user_vars[row.name] = row.value
                end
            end)
        else
            log("debug", "Associated profile is not of category 'sip_user', skipping inheritance")
        end
    end

    -- Load global variables
    local global_vars = {}
    local vars = api:execute("global_getvar", "") or ""
    for line in vars:gmatch("[^\n]+") do
        local name, value = line:match("^([^=]+)=(.+)$")
        if name and value then global_vars[name] = value end
    end

    local function replace_vars(str)
        if not str then return "" end
        str = str:gsub("%$%${([^}]+)}", function(var) return global_vars[var] or "" end)
        str = str:gsub("%${([^}]+)}", function(var) return global_vars[var] or "" end)
        return str
    end

    -- Start generating XML
    local xml = {'<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
        '<document type="freeswitch/xml">',
        '        <section name="directory">',
        '                <domain name="' .. domain .. '">',
        '                        <groups>',
        '                                <group name="default">',
        '                                        <users>',
        '                                                <user id="' .. username .. '">',
        '                                                        <params>'}

    for k, v in pairs(user_params) do
        table.insert(xml, '                                                                <param name="' .. k .. '" value="' .. replace_vars(v) .. '"/>')
    end

    table.insert(xml, '                                                        </params>')
    table.insert(xml, '                                                        <variables>')

    for k, v in pairs(user_vars) do
        table.insert(xml, '                                                                <variable name="' .. k .. '" value="' .. replace_vars(v) .. '"/>')
    end

    table.insert(xml, '                                                        </variables>')
    table.insert(xml, '                                                </user>')
    table.insert(xml, '                                        </users>')
    table.insert(xml, '                                </group>')
    table.insert(xml, '                        </groups>')
    table.insert(xml, '                </domain>')
    table.insert(xml, '        </section>')
    table.insert(xml, '</document>')

    _G.XML_STRING = table.concat(xml, "\n")
    log("info", "Generated XML:\n" .. _G.XML_STRING)
end
