--[[ 
    dialplan.lua (FusionPBX-style)
    Genera configuraciones dinámicas del dialplan en FreeSWITCH desde la base de datos.
    Sustituye variables $${} y aplica tabulación correcta.
--]]

return function()
    -- Función para logging
    local function log(level, message)
        if level == "debug" then return end -- Desactiva debug por defecto, cambia a true si necesitas
        freeswitch.consoleLog(level, "[Dialplan] " .. message .. "\n")
    end

    -- Conectar a la base de datos con ODBC
    local dbh = freeswitch.Dbh("odbc://ring2all")
    if not dbh:connected() then
        log("ERROR", "No se pudo conectar a la base de datos mediante ODBC")
        XML_STRING = '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n<document type="freeswitch/xml">\n    <section name="dialplan">\n        <context name="default"></context>\n    </section>\n</document>'
        return
    end

    -- Extraer contexto, número de destino y hostname desde XML_REQUEST
    local context = XML_REQUEST["context"] or "default"
    local destination = XML_REQUEST["destination-number"] or "" -- Asegurar captura correcta
    local hostname = freeswitch.getGlobalVariable("hostname") or "default"

    -- Si el destino está vacío, intentar obtenerlo desde otras fuentes
    if destination == "" then
        destination = freeswitch.getGlobalVariable("destination_number") or ""
    end

    log("INFO", "Contexto: " .. context)
    log("INFO", "Destino: " .. destination)
    log("INFO", "Hostname: " .. hostname)

    -- Consulta SQL para obtener las extensiones del contexto
    local query = string.format([[
        SELECT context_name, description, expression, xml_data
        FROM core.dialplan
        WHERE context_name = '%s' AND enabled = TRUE
    ]], context)

    log("INFO", "Ejecutando SQL Query: " .. query)

    -- Construcción del XML del dialplan con tabulación
    local xml = {
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
        '<document type="freeswitch/xml">',
        '    <section name="dialplan" description="">',
        '        <context name="' .. context .. '" destination_number="' .. destination .. '" hostname="' .. hostname .. '">'
    }

    -- Función para reemplazar variables $${} en el texto
    local function replace_vars(text)
        return text:gsub("%${(%w+)}", function(var_name)
            local value = freeswitch.getGlobalVariable(var_name)
            return value or ("${" .. var_name .. "}") -- Si no existe, mantener la variable sin sustituir
        end)
    end

    -- Ejecutar la consulta y procesar los resultados
    local extensions_found = false
    dbh:query(query, function(row)
        extensions_found = true
        -- Reemplazar variables en xml_data y ajustar tabulación
        local ext_lines = {}
        for line in row.xml_data:gmatch("[^\n]+") do
            local trimmed_line = line:match("^%s*(.*)%s*$") -- Eliminar espacios iniciales/finales
            local replaced_line = replace_vars(trimmed_line)
            -- Ajustar tabulación relativa
            local indent_level = 3 -- Dentro de <context> (12 espacios base)
            if replaced_line:match("^<%w+") then
                indent_level = indent_level + 1 -- Aumentar para <extension>, <condition>, etc.
            elseif replaced_line:match("^</%w+") then
                indent_level = indent_level - 1 -- Reducir para cierres
            end
            table.insert(ext_lines, string.rep("    ", indent_level) .. replaced_line)
        end
        table.insert(xml, table.concat(ext_lines, "\n"))
    end)

    -- Si no se encontraron extensiones, agregar un contexto vacío
    if not extensions_found then
        log("WARNING", "No se encontraron extensiones para el contexto: " .. context)
    end

    -- Cierre del contexto y documento
    table.insert(xml, '        </context>')
    table.insert(xml, '    </section>')
    table.insert(xml, '</document>')

    -- Convertir tabla a string y asignar a XML_STRING
    XML_STRING = table.concat(xml, "\n")
    log("INFO", "XML Generado:\n" .. XML_STRING)

    -- Liberar conexión a la base de datos
    dbh:release()
end
