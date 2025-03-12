--[[
    handler.lua (dialplan)
    Handles FreeSWITCH dialplan requests (e.g., call routing).
    Supports connection via ODBC or LuaSQL for PostgreSQL.
--]]

-- Return a function that accepts settings as a parameter
return function(settings)
    -- Define a logging function that respects the debug setting from settings
    local function log(level, message)
        if level == "debug" and not settings.debug then
            return  -- Skip debug messages if debug is false
        end
        freeswitch.consoleLog(level, "[Dialplan] " .. message .. "\n")
    end

    -- Try connecting via ODBC first
    local dbh = freeswitch.Dbh("odbc://ring2all")
    
    if not dbh:connected() then
        log("WARNING", "ODBC connection failed. Falling back to LuaSQL.")
        
        -- Load PostgreSQL LuaSQL library as a fallback
        local luasql = require "luasql.postgres"
        local env = assert(luasql.postgres(), "Failed to initialize PostgreSQL environment")
        dbh = assert(env:connect("ring2all", "ring2all", "ring2all", "localhost", 5432), "Failed to connect to PostgreSQL via LuaSQL")
    end

    -- Extract context and destination from request parameters
    local context = params:getHeader("Hunt-Context") or params:getHeader("Caller-Context") or "default"
    local destination = params:getHeader("Caller-Destination-Number") or ""

    -- Log the extracted context and destination for debugging
    log("DEBUG", "Context: " .. context)
    log("DEBUG", "Destination: " .. destination)

    -- SQL Query to fetch dialplan data
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

    -- Log the SQL query for debugging
    log("DEBUG", "Executing SQL Query: " .. query)

    -- Execute query and fetch results
    local row, cur = nil, nil
    if dbh:connected() then
        cur = dbh:query(query, function(result)
            row = result
        end)
    else
        cur = assert(dbh:execute(query), "SQL execution failed")
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
    if cur then cur:close() end
    if dbh and dbh.close then dbh:close() end
end
