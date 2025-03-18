--[[
    settings.lua
    Common settings and utility functions for FreeSWITCH scripts.
--]]

-- Tabla para almacenar configuraciones y funciones
local settings = {
    debug = true  -- Cambia a false para deshabilitar logs de depuración
}

-- Función para formatear y tabular el XML
function settings.format_xml(domain_name, user_xml)
    local xml = {
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
        '<document type="freeswitch/xml">',
        '    <section name="directory">',
        '        <domain name="' .. domain_name .. '" alias="true">',
        '            <params>',
        '                <param name="jsonrpc-allowed-methods" value="verto"/>',
        '                <param name="jsonrpc-allowed-event-channels" value="demo,conference,presence"/>',
        '            </params>',
        '            <groups>',
        '                <group name="default">',
        '                    <users>',
        '                        ' .. user_xml,  -- Insertar el XML del usuario directamente
        '                    </users>',
        '                </group>',
        '            </groups>',
        '        </domain>',
        '    </section>',
        '</document>'
    }
    
    -- Unir con saltos de línea para tabulación clara
    return table.concat(xml, "\n")
end

-- Exportar el módulo
return settings
