local domain_arg = argv[1] or "main"

-- Si el dominio es "main", usamos el tenant principal
local domain = (domain_arg == "main") and "example.com" or domain_arg  -- ajusta "example.com" al dominio real del tenant principal

-- Creamos el entorno simulado para la llamada XML
local xml_request = {
    section = "configuration",
    tag_name = "menus",
    key_name = "name",
    key_value = "demo_ivr", -- o el IVR que quieras probar
    domain = domain
}

-- Cargar el handler del IVR
local ivr_handler = require("main.xml_handlers.ivr.ivr")
local xml = ivr_handler.process(xml_request)

-- Imprimir el XML generado
freeswitch.consoleLog("INFO", "XML IVR generado:\n" .. (xml or "No se generó XML") .. "\n")
