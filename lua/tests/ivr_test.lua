-- tests/ivr_test.lua
package.path = "/usr/share/freeswitch/scripts/?.lua;" .. package.path

-- Simular entorno freeswitch si no existe (cuando se ejecuta con luarun)
if not freeswitch then
  freeswitch = {
    consoleLog = function(level, message)
      io.write("[" .. level .. "] " .. message)
    end,
    getGlobalVariable = function(name)
      return _G[name]
    end,
    Dbh = require("luasql.odbc").odbc().connect("ring2all")  -- Solo si querés pruebas de verdad con luarun
  }
end

-- Leer argumentos
local domain_arg = argv[1]
local ivr_name = argv[2]

if not domain_arg or not ivr_name then
  print("Uso: luarun tests/ivr_test.lua <dominio|main> <ivr_name>")
  return
end

-- Simular variable global domain
if domain_arg == "main" then
  local env = freeswitch.Dbh("odbc://ring2all")
  local main_id = nil
  env:query("SELECT domain_name FROM core.tenants WHERE is_main = true LIMIT 1", function(row)
    _G["domain"] = row.domain_name
  end)
else
  _G["domain"] = domain_arg
end

-- Cargar settings simulados
local settings = {
  debug = true
}

-- Ejecutar el handler
local ivr_handler = require("main.xml_handlers.ivr.ivr")
ivr_handler(settings)

-- Mostrar XML generado si existe
if _G.XML_STRING then
  print("\n--- XML RESULTADO ---\n")
  print(_G.XML_STRING)
end
