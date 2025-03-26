-- Requiere que exista el archivo main/xml_handlers/ivr/ivr.lua
local ivr_handler = require("main.xml_handlers.ivr.ivr")

-- Recibir argumentos
local domain_arg = argv[1] or "main"
local ivr_name = argv[2] or "demo_ivr"
local domain = domain_arg

-- Conexión ODBC
local dbh = freeswitch.Dbh("odbc://ring2all")
if not dbh:connected() then
    freeswitch.consoleLog("ERR", "Failed to connect to database\n")
    return
end
freeswitch.consoleLog("INFO", "ODBC connection established\n")

-- Si el dominio es 'main', buscar el dominio principal desde la tabla core.tenants
if domain_arg == "main" then
    local sql = [[
        SELECT domain_name FROM core.tenants
        WHERE is_main = TRUE
        LIMIT 1
    ]]
    dbh:query(sql, function(row)
        if row and row.domain_name then
            domain = row.domain_name
        end
    end)

    if domain == "main" then
        freeswitch.consoleLog("ERR", "No se encontró un tenant principal (is_main = TRUE)\n")
        return
    end
end

-- Construcción del request que espera el handler ivr
local xml_request = {
    section = "configuration",
    tag_name = "menus",
    key_name = "name",
    key_value = ivr_name,
    domain = domain
}

-- Ejecutar handler y obtener XML
local result_xml = ivr_handler.process(xml_request)

-- Mostrar resultado
freeswitch.consoleLog("INFO", "Resultado IVR para el dominio '" .. domain .. "', IVR '" .. ivr_name .. "':\n" .. (result_xml or "No se generó XML") .. "\n")

-- Cerrar conexión
dbh:release()
