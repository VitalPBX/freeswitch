--[[
  sip_register.lua
  Enhanced FreeSWITCH XML Directory handler
  Author: Rodrigo Cuadra
  Project: Ring2All

  This script generates XML for SIP registrations dynamically from a PostgreSQL database,
  supporting a structured format and improved readability with 8-space indentation.
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

        -- Fetch user settings
        local settings_sql = string.format([[SELECT * FROM view_sip_users
                WHERE tenant_id = '%s' AND username = '%s']], tenant_id, username)

        local user_params, user_vars = {}, {}

        dbh:query(settings_sql, function(row)
                if row.setting_type == "param" then
                        user_params[row.setting_name] = row.setting_value
                elseif row.setting_type == "variable" then
                        user_vars[row.setting_name] = row.setting_value
                end
        end)

        local xml = {'<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
                '<document type="freeswitch/xml">',
                '        <section name="directory">',
                '                <domain name="' .. domain .. '">',
                '                        <params/>',
                '                        <groups>',
                '                                <group name="default">',
                '                                        <users>',
                '                                                <user id="' .. username .. '">',
                '                                                        <params>'}

        -- Insert parameters from database
        for k, v in pairs(user_params) do
                table.insert(xml, '                                                                <param name="' .. k .. '" value="' .. v .. '"/>')
        end

        table.insert(xml, '                                                        </params>')
        table.insert(xml, '                                                        <variables>')

        -- Insert variables from database
        for k, v in pairs(user_vars) do
                table.insert(xml, '                                                                <variable name="' .. k .. '" value="' .. v .. '"/>')
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
