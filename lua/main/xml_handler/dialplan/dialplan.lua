--[[ 
    dialplan.lua (FusionPBX-style)
    Genera configuraciones dinámicas del dialplan en FreeSWITCH desde la base de datos.
    Adaptado para seguir el formato utilizado por FusionPBX.
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

    -- Extraer contexto, número de destino y hostname
    local context = params:getHeader("Hunt-Context") or params:getHeader("Caller-Context") or "default"
    local destination = params:getHeader("Caller-Destination-Number") or ""
    local hostname = freeswitch.getGlobalVariable("hostname") or "default"

    log("DEBUG", "Contexto: " .. context)
    log("DEBUG", "Destino: " .. destination)
    log("DEBUG", "Hostname: " .. hostname)

    -- Consulta SQL
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
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
        '<document type="freeswitch/xml">',
        '  <section name="dialplan" description="">',
        '    <context name="' .. context .. '" destination_number="' .. destination .. '" hostname="' .. hostname .. '">'
    }

    local current_ext_name = nil
    local current_cond_order = nil

    -- Ejecutar la consulta y procesar los resultados
    dbh:query(query, function(row)
        if not row then return end

        -- Depurar el valor de continue
        log("DEBUG", "Procesando extensión: " .. row.extension_name .. ", continue: " .. tostring(row.continue))

        -- Manejo de <extension>
        if current_ext_name ~= row.extension_name then
            if current_cond_order then
                table.insert(xml, '        </condition>')
                current_cond_order = nil
            end
            if current_ext_name then
                table.insert(xml, '      </extension>')
            end
            -- Manejar valores de continue como "t", true, o 1
            local continue_value = (row.continue == "t" or row.continue == true or row.continue == "1" or row.continue == 1) and "true" or "false"
            table.insert(xml, '      <extension name="' .. row.extension_name .. '" continue="' .. continue_value .. '">')
            current_ext_name = row.extension_name
        end

        -- Manejo de <condition>
        if current_cond_order ~= row.condition_order then
            if current_cond_order then
                table.insert(xml, '        </condition>')
            end
            table.insert(xml, '        <condition field="' .. (row.field or "") .. '" expression="' .. (row.expression or "") .. '" break="' .. (row.break_on_match or "on-false") .. '">')
            current_cond_order = row.condition_order
        end

        -- Agregar <action> dentro de la condición
        table.insert(xml, '          <action application="' .. row.application .. '" data="' .. (row.data or "") .. '"/>')
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
