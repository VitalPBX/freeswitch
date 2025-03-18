--[[
    settings.lua
    Common settings and utility functions for FreeSWITCH scripts.
--]]

-- Tabla para almacenar configuraciones y funciones
local settings = {
    debug = true  -- Cambia a false para deshabilitar logs de depuración
}

-- Función genérica para formatear y tabular XML
function settings.format_xml(section_name, content, options)
    -- Opciones por defecto
    local opts = options or {}
    local indent = opts.indent or "    "  -- Indentación por nivel (4 espacios por defecto)
    local domain_name = opts.domain_name or ""  -- Nombre del dominio (opcional)
    local alias = opts.alias or false  -- Atributo alias para domain (opcional)
    local extra_attrs = opts.extra_attrs or {}  -- Atributos adicionales para la sección (opcional)

    -- Construir el XML base
    local xml = {
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
        '<document type="freeswitch/xml">',
        indent .. '<section name="' .. section_name .. '">'
    }

    -- Si hay domain_name, agregar la estructura de dominio
    if domain_name and domain_name ~= "" then
        local domain_line = indent .. indent .. '<domain name="' .. domain_name .. '"'
        if alias then
            domain_line = domain_line .. ' alias="true"'
        end
        domain_line = domain_line .. '>'
        table.insert(xml, domain_line)
        table.insert(xml, indent .. indent .. indent .. content)
        table.insert(xml, indent .. indent .. '</domain>')
    else
        -- Si no hay dominio, agregar el contenido directamente
        table.insert(xml, indent .. indent .. content)
    end

    -- Cerrar la sección y el documento
    table.insert(xml, indent .. '</section>')
    table.insert(xml, '</document>')

    -- Unir con saltos de línea para tabulación clara
    return table.concat(xml, "\n")
end

-- Exportar el módulo
return settings
