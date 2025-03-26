local pg = require("luasql.postgres").postgres()
local env = pg:connect("dbname=ring2all user=postgres password=postgres hostaddr=127.0.0.1")
local domain_arg = argv[1] or "main"
local domain = domain_arg

-- Si es "main", buscamos el dominio principal
if domain_arg == "main" then
    local cur = assert(env:execute([[
        SELECT domain_name FROM core.tenants
        WHERE is_main = TRUE
        LIMIT 1
    ]]))
    local row = cur:fetch({}, "a")
    if row and row.domain_name then
        domain = row.domain_name
    else
        freeswitch.consoleLog("ERR", "No se encontró el tenant principal (is_main = TRUE)\n")
        return
    end
end

-- Construimos el XML Request
local xml_request = {
    section = "configuration",
    tag_name = "menus",
    key_name = "name",
    key_value = "demo_ivr",  -- Puedes cambiar esto según el IVR que deseas probar
    domain = domain
}

-- Cargar el handler del IVR
local ivr_handler = require("main.xml_handlers.ivr.ivr")
local xml = ivr_handler.process(xml_request)

-- Mostrar resultado
freeswitch.consoleLog("INFO", "XML IVR generado para el dominio '" .. domain .. "':\n" .. (xml or "No se generó XML") .. "\n")

-- Cerrar conexión
env:close()
