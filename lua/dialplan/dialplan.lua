--[[
    handler.lua (dialplan)
    Handles FreeSWITCH dialplan requests (e.g., call routing).
    Supports connection via ODBC or LuaSQL for PostgreSQL.
--]]

return function(settings)
    -- Logging function
    local function log(level, message)
        if level == "debug" and not settings.debug then
            return
        end
        freeswitch.consoleLog(level, "[Dialplan] " .. message .. "\n")
    end

    -- Attempt to connect via ODBC
    local dbh = freeswitch.Dbh("odbc://ring2all")
    
    if not dbh:connected() then
        log("WARNING", "ODBC connection failed. Trying LuaSQL...")

        -- Load LuaSQL for PostgreSQL
        local luasql = require "luasql.postgres"
        local env = luasql.postgres()
        if not env then
            log("ERROR", "Failed to initialize PostgreSQL environment")
            return
        end
        dbh = env:connect("ring2all", "ring2all", "ring2all", "localhost", 5432)
        
        if not dbh then
            log("ERROR", "Failed to connect to PostgreSQL via LuaSQL")
            return
        end
    end

    -- Extract context and destination
    local context = params:getHeader("Hunt-Context") or params:getHeader("Caller-Context") or "default"
    local destination = params:getHeader("Caller-Destination-Number") or ""

    log("DEBUG", "Context: " .. context)
    log("DEBUG", "Destination: " .. destination)

    -- SQL Query
    local query = string.format([[
        SELECT dc.context_name, de.extension_name, de.continue, 
               dc2.field, dc2.expression, dc2.break_on_match, dc2.condition_order,
               da.action_type, da.application, da.data, da.action_order
        FROM public.dialplan_contexts dc
        JOIN public.dialplan_extensions de ON dc.context_uuid = de.context_uuid
        JOIN public.dialplan_conditions dc2 ON de.extension_uuid = dc2.extension_uuid
        JOIN public.dialplan_actions da ON dc2.condition_uuid = da.action_uuid
        WHERE dc.context_name = '%s'
        ORDER BY de.priority, dc2.condition_order, da.action_order
    ]], context)

    log("DEBUG", "Executing SQL Query: " .. query)

    -- Execute query and check for errors
    local cur
    local success, err = pcall(function()
        cur = dbh:query(query)
    end)

    if not success or not cur then
        log("ERROR", "SQL execution failed: " .. (err or "Unknown error"))
        return
    end

    -- Check if the query returned results
    local row = cur:fetch({}, "a")
    if not row then
        log("WARNING", "No results found for context: " .. context)
        return
    end

    -- Build XML response
    local xml = [[<?xml version="1.0" encoding="utf-8"?>
<document type="freeswitch/xml">
  <section name="dialplan" description="Dynamic Dialplan">
    <context name="]] .. context .. [[">]]

    local current_ext_name = nil
    local current_cond_order = nil

    while row do
        -- Open a new extension block if needed
        if current_ext_name ~= row.extension_name then
            if current_ext_name then xml = xml .. [[</extension>]] end
            xml = xml .. [[<extension name="]] .. row.extension_name .. [[" continue="]] .. (row.continue == "t" and "true" or "false") .. [[">]]
            current_ext_name = row.extension_name
            current_cond_order = nil
        end

        -- Open a new condition block if needed
        if current_cond_order ~= row.condition_order then
            if current_cond_order then xml = xml .. [[</condition>]] end
            xml = xml .. [[<condition field="]] .. row.field .. [[" expression="]] .. row.expression .. [[" break="]] .. row.break_on_match .. [[">]]
            current_cond_order = row.condition_order
        end

        -- Add action
        xml = xml .. [[<]] .. row.action_type .. [[ application="]] .. row.application .. [[" data="]] .. row.data .. [["/>]]

        -- Fetch next row
        row = cur:fetch({}, "a")
    end

    -- Close any open condition or extension tags
    if current_cond_order then xml = xml .. [[</condition>]] end
    if current_ext_name then xml = xml .. [[</extension>]] end

    xml = xml .. [[
    </context>
  </section>
</document>]]

    -- Log the generated XML for debugging
    log("DEBUG", "Generated XML: " .. xml)

    -- Set the XML response for FreeSWITCH
    XML_STRING = xml

    -- Close database connections
    if cur and cur.close then cur:close() end
    if dbh and dbh.close then dbh:close() end
end
