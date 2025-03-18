--[[ 
    dialplan.lua (FusionPBX-style)
    Genera configuraciones dinámicas del dialplan en FreeSWITCH desde la base de datos.
    Adaptado para usar public.dialplan con xml_data preformateado como manejador XML.
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
        XML_STRING = '<?xml version="1.0" encoding="UTF-8" standalone="no"?><document type="freeswitch/xml"><section name="dialplan"><context name="default"></context></section></document>'
        return
    end

    -- Extraer contexto, número de destino y hostname desde XML_REQUEST
    local context = XML_REQUEST["context"] or "default"
    local destination = XML_REQUEST["destination-number"] or ""
    local hostname = freeswitch.getGlobalVariable("hostname") or "default"

    log("INFO", "Contexto: " .. context)
    log("INFO", "Destino: " .. destination)
    log("INFO", "Hostname: " .. hostname)

    -- Consulta SQL para obtener las extensiones del contexto
    local query = string.format([[
        SELECT context_name, description, expression, xml_data
        FROM public.dialplan
        WHERE context_name = '%s' AND enabled = TRUE
    ]], context)

    log("INFO", "Ejecutando SQL Query: " .. query)

    -- Construcción del XML del dialplan
    local xml = {
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
        '<document type="freeswitch/xml">',
        '  <section name="dialplan" description="">',
        '    <context name="' .. context .. '" destination_number="' .. destination .. '" hostname="' .. hostname .. '">'
    }

    -- Ejecutar la consulta y procesar los resultados
    local extensions_found = false
    dbh:query(query, function(row)
        extensions_found = true
        -- Cada xml_data ya contiene una <extension> completa
        table.insert(xml, '      ' .. row.xml_data)
    end)

    -- Si no se encontraron extensiones, agregar un contexto vacío
    if not extensions_found then
        log("WARNING", "No se encontraron extensiones para el contexto: " .. context)
    end

    -- Cierre del contexto y documento
    table.insert(xml, '    </context>')
    table.insert(xml, '  </section>')
    table.insert(xml, '</document>')

    -- Convertir tabla a string y asignar a XML_STRING
    XML_STRING = table.concat(xml, "\n")
    log("INFO", "XML Generado:\n" .. XML_STRING)

    -- Liberar conexión a la base de datos
    dbh:release()
end
