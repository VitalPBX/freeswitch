return function(settings)
    local function log(level, message)
        if level == "debug" and not settings.debug then return end
        freeswitch.consoleLog(level, "[Sofia Profiles] " .. message .. "\n")
    end

    log("info", "Initializing SIP profile configuration generation")

    -- Conectar a la base de datos
    local dbh = assert(freeswitch.Dbh("odbc://ring2all"), "Failed to connect to database")

    -- Crear una instancia del API de FreeSWITCH
    local api = freeswitch.API()

    -- Obtener todas las variables globales de FreeSWITCH
    local vars = api:execute("global_getvar", "") or ""
    log("debug", "Retrieved global variables:\n" .. vars)

    -- Almacenar variables en una tabla clave-valor
    local global_vars = {}
    for line in vars:gmatch("[^\n]+") do
        local name, value = line:match("^([^=]+)=(.+)$")
        if name and value then
            global_vars[name] = value
            log("debug", "Parsed global variable: " .. name .. " = " .. value)
        end
    end

    -- Función para reemplazar $${var_name} con su valor correspondiente
    local function replace_vars(str)
        return str:gsub("%$%${([^}]+)}", function(var_name)
            local value = global_vars[var_name] or ""
            if value == "" then
                log("warning", "Variable $$" .. var_name .. " not found, replacing with empty string")
            else
                log("debug", "Resolved $$" .. var_name .. " to: " .. value)
            end
            return value
        end)
    end

    -- Query para obtener los perfiles SIP
    local profile_query = "SELECT profile_name, xml_config FROM public.sip_profiles"
    log("debug", "Executing profile query: " .. profile_query)

    local xml = {
        '<?xml version="1.0" encoding="utf-8"?>',
        '<document type="freeswitch/xml">',
        '  <section name="configuration">',
        '    <configuration name="sofia.conf" description="sofia Endpoint">',
        '      <global_settings>',
        '        <param name="auto-restart" value="true"/>',
        '        <param name="debug-presence" value="0"/>',
        '        <param name="inbound-reg-in-new-thread" value="true"/>',
        '        <param name="log-level" value="0"/>',
        '        <param name="max-reg-threads" value="8"/>',
        '      </global_settings>',
        '      <profiles>' -- Asegurar que <profiles> se abra correctamente
    }

    local processed_profiles = {}  -- Para evitar perfiles duplicados

    dbh:query(profile_query, function(row)
        local profile_name = row.profile_name
        local xml_config = row.xml_config

        -- **Evitar perfiles duplicados**
        if processed_profiles[profile_name] then
            log("warning", "Duplicate profile detected: " .. profile_name .. ". Skipping...")
            return
        end
        processed_profiles[profile_name] = true

        log("info", "Processing SIP profile: " .. profile_name)

        -- **Eliminar etiquetas `<profile>` y `</profile>` en xml_config**
        xml_config = xml_config:gsub("<profile[^>]*>", "")  -- Elimina cualquier <profile ...>
        xml_config = xml_config:gsub("</profile>", "")      -- Elimina cualquier </profile>

        -- **Reemplazar variables en xml_config**
        xml_config = replace_vars(xml_config)

        -- **Asegurar estructura XML válida**
        if not xml_config:match("<aliases>") then
            xml_config = xml_config:gsub("<gateways>", "<aliases></aliases>\n<gateways>", 1)
        end
        if not xml_config:match("<gateways>") then
            xml_config = xml_config:gsub("<domains>", "<gateways></gateways>\n<domains>", 1)
        end
        if not xml_config:match("<settings>") then
            xml_config = xml_config .. "\n<settings></settings>"
        end

        -- **Insertar el perfil correctamente**
        table.insert(xml, '        <profile name="' .. profile_name .. '">')
        table.insert(xml, xml_config)
        table.insert(xml, '        </profile>')
    end)

    -- **Cerrar correctamente la estructura XML**
    table.insert(xml, '      </profiles>')  -- Se asegura que solo se cierre una vez
    table.insert(xml, '    </configuration>')
    table.insert(xml, '  </section>')
    table.insert(xml, '</document>')

    -- Convertir la tabla en una cadena XML final
    XML_STRING = table.concat(xml, "\n")

    -- Guardar en archivo para depuración
    local file = io.open("/tmp/sofia_profiles.xml", "w")
    if file then
        file:write(XML_STRING)
        file:close()
        log("info", "XML configuration saved to /tmp/sofia_profiles.xml")
    else
        log("warning", "Failed to save XML configuration to /tmp/sofia_profiles.xml")
    end

    -- Liberar la conexión de la base de datos
    dbh:release()
end
