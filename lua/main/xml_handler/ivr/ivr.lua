--[[
    ivr/ivr.lua
    Genera configuraciones dinámicas de IVR en FreeSWITCH desde la base de datos.
    Utiliza ODBC para obtener menús IVR y sus opciones.
--]]

return function(settings)
    -- Función para logging
    local function log(level, message)
        if level == "debug" and not settings.debug then return end
        freeswitch.consoleLog(level, "[IVR] " .. message .. "\n")
    end

    -- Conectar a la base de datos con ODBC
    local dbh = freeswitch.Dbh("odbc://ring2all")
    if not dbh:connected() then
        log("ERROR", "No se pudo conectar a la base de datos mediante ODBC")
        return
    end

    log("DEBUG", "Generando configuración para ivr.conf")

    -- Construcción del XML para ivr.conf
    local xml = {
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
        '<document type="freeswitch/xml">',
        '  <section name="configuration">',
        '    <configuration name="ivr.conf" description="IVR Menus">',
        '      <menus>'
    }

    -- Consulta SQL para ivr_menus
    local ivr_query = "SELECT * FROM public.ivr_menus"
    dbh:query(ivr_query, function(row)
        table.insert(xml, '        <menu name="' .. row.ivr_name .. '"')
        table.insert(xml, '              greet-long="' .. (row.greet_long or "") .. '"')
        table.insert(xml, '              greet-short="' .. (row.greet_short or "") .. '"')
        table.insert(xml, '              invalid-sound="' .. (row.invalid_sound or "ivr/ivr-that_was_an_invalid_entry.wav") .. '"')
        table.insert(xml, '              exit-sound="' .. (row.exit_sound or "voicemail/vm-goodbye.wav") .. '"')
        table.insert(xml, '              timeout="' .. (row.timeout or "10000") .. '"')
        table.insert(xml, '              max-failures="' .. (row.max_failures or "3") .. '"')
        table.insert(xml, '              max-timeouts="' .. (row.max_timeouts or "3") .. '">')

        -- Consulta SQL para las opciones del menú
        local options_query = string.format("SELECT * FROM public.ivr_menu_options WHERE ivr_uuid = '%s'", row.ivr_uuid)
        dbh:query(options_query, function(option)
            table.insert(xml, '          <entry action="' .. option.action .. '" digits="' .. option.digits .. '" param="' .. (option.param or "") .. '"/>')
        end)

        table.insert(xml, '        </menu>')
    end)

    table.insert(xml, '      </menus>')
    table.insert(xml, '    </configuration>')
    table.insert(xml, '  </section>')
    table.insert(xml, '</document>')

    -- Convertir tabla a string y asignar a XML_STRING
    XML_STRING = table.concat(xml, "\n")
    log("DEBUG", "IVR XML Generado:\n" .. XML_STRING)

    -- Liberar conexión a la base de datos
    dbh:release()
end
