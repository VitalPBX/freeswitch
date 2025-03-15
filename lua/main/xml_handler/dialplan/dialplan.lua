--[[
    dialplan.lua
    Genera configuraciones dinámicas del dialplan en FreeSWITCH desde la base de datos.
    Utiliza ODBC para obtener contextos, extensiones, condiciones y acciones.
--]]

return function(settings)
    -- Función para logging
    local function log(level, message)
        if level == "debug" and not settings.debug then return end
        freeswitch.consoleLog(level, "[Dialplan] " .. message .. "\n")
    end

    -- Conectar a la base de datos con ODBC
    local dbh = freeswitch.Dbh("odbc://ring2all")
    if not dbh:connected() then
        log("ERROR", "No se pudo conectar a la base de datos mediante ODBC")
        return
    end

    -- Extraer contexto y número de destino de los encabezados SIP
    local context = params:getHeader("Hunt-Context") or params:getHeader("Caller-Context") or "default"
    local destination = params:getHeader("Caller-Destination-Number") or ""

    log("DEBUG", "Contexto: " .. context)
    log("DEBUG", "Destino: " .. destination)

    -- Nueva consulta SQL con el orden corregido
    local query = string.format([[ 
        SELECT dc.context_name, de.extension_name, de.continue, 
               dc2.condition_order, dc2.field, dc2.expression, dc2.break_on_match, 
               da.action_order, da.action_type, da.application, da.data
        FROM public.dialplan_contexts dc
        JOIN public.dialplan_extensions de ON dc.context_uuid = de.context_uuid
        JOIN public.dialplan_conditions dc2 ON de.extension_uuid = dc2.extension_uuid
        JOIN public.dialplan_actions da ON dc2.condition_uuid = da.condition_uuid
        WHERE dc.context_name = '%s'
        ORDER BY de.priority, dc2.condition_order, da.action_order
    ]], context)

    log("DEBUG", "Ejecutando SQL Query: " .. query)

    -- Construcción del XML del dialplan
    local xml = {
        '<?xml version="1.0" encoding="utf-8"?>',
        '<document type="freeswitch/xml">',
        '  <section name="dialplan" description="Dynamic Dialplan">',
        '    <context name="' .. context .. '">'
    }

    local current_ext_name = nil
    local current_cond_order = nil

    -- Ejecutar la consulta y procesar los resultados
    dbh:query(query, function(row)
        if not row then return end

        -- Manejo de <extension>
        if current_ext_name ~= row.extension_name then
            -- Cerrar etiqueta de condition y extension si es necesario
            if current_cond_order then
                table.insert(xml, '        </condition>')
                current_cond_order = nil
            end
            if current_ext_name then
                table.insert(xml, '      </extension>')
            end
            -- Abrir nueva extension
            table.insert(xml, '      <extension name="' .. row.extension_name .. '" continue="' .. (row.continue == "t" and "true" or "false") .. '">')
            current_ext_name = row.extension_name
        end

        -- Manejo de <condition>
        if current_cond_order ~= row.condition_order then
            -- Cerrar condition previa si existía
            if current_cond_order then
                table.insert(xml, '        </condition>')
            end
            -- Abrir nueva condition
            table.insert(xml, '        <condition field="' .. row.field .. '" expression="' .. row.expression .. '" break="' .. row.break_on_match .. '">')
            current_cond_order = row.condition_order
        end

        -- Agregar <action> dentro de la condición
        table.insert(xml, '          <' .. row.action_type .. ' application="' .. row.application .. '" data="' .. row.data .. '"/>')
    end)

    -- Cierre de etiquetas abiertas al finalizar la consulta
    if current_cond_order then table.insert(xml, '        </condition>') end
    if current_ext_name then table.insert(xml, '      </extension>') end

    table.insert(xml, '    </context>')
    table.insert(xml, '  </section>')
    table.insert(xml, '</document>')

    -- Convertir tabla a string y asignar a XML_STRING
    XML_STRING = table.concat(xml, "\n")
    log("DEBUG", "XML Generado:\n" .. XML_STRING)

    -- Liberar conexión a la base de datos
    dbh:release()
end
