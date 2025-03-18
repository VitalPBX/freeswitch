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

    -- Niveles de indentación
    local level0 = ""
    local level1 = indent
    local level2 = indent .. indent
    local level3 = indent .. indent .. indent
    local level4 = indent .. indent .. indent .. indent

    -- Construir el XML base
    local xml = {
        level0 .. '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
        level0 .. '<document type="freeswitch/xml">',
        level1 .. '<section name="' .. section_name .. '">'
    }

    -- Si hay domain_name, agregar la estructura de dominio
    if domain_name and domain_name ~= "" then
        local domain_line = level2 .. '<domain name="' .. domain_name .. '"'
        if alias then
            domain_line = domain_line .. ' alias="true"'
        end
        domain_line = domain_line .. '>'
        table.insert(xml, domain_line)
        -- Ajustar la indentación del contenido para que esté al nivel correcto
        for line in content:gmatch("[^\n]+") do
            table.insert(xml, level3 .. line)
        end
        table.insert(xml, level2 .. '</domain>')
    else
        -- Si no hay dominio, agregar el contenido directamente con indentación
        for line in content:gmatch("[^\n]+") do
            table.insert(xml, level2 .. line)
        end
    end

    -- Cerrar la sección y el documento
    table.insert(xml, level1 .. '</section>')
    table.insert(xml, level0 .. '</document>')

    -- Unir con saltos de línea para tabulación clara
    return table.concat(xml, "\n")
end

-- Exportar el módulo
return settings
