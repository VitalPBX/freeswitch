--[[
    dialplan.lua
    Generates dynamic FreeSWITCH dialplan configurations from the database.
    Uses ODBC to retrieve dialplan contexts, extensions, conditions, and actions.
--]]

return function(settings)
    -- Logging function
    local function log(level, message)
        if level == "debug" and not settings.debug then return end
        freeswitch.consoleLog(level, "[Dialplan] " .. message .. "\n")
    end

    -- Connect to the database using ODBC
    local dbh = freeswitch.Dbh("odbc://ring2all")
    if not dbh:connected() then
        log("ERROR", "Failed to connect to the database using ODBC")
        return
    end

    -- Extract context and destination from SIP headers
    local context = params:getHeader("Hunt-Context") or params:getHeader("Caller-Context") or "default"
    local destination = params:getHeader("Caller-Destination-Number") or ""

    log("DEBUG", "Context: " .. context)
    log("DEBUG", "Destination: " .. destination)

    -- Retrieve dialplan data
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

    -- Execute query
    local xml = {
        '<?xml version="1.0" encoding="utf-8"?>',
        '<document type="freeswitch/xml">',
        '  <section name="dialplan" description="Dynamic Dialplan">',
        '    <context name="' .. context .. '">' }
    
    dbh:query(query, function(row)
        if not row then return end
        
        -- Open <extension> tag if needed
        if not current_ext_name or current_ext_name ~= row.extension_name then
            if current_ext_name then table.insert(xml, '</extension>') end
            table.insert(xml, '<extension name="' .. row.extension_name .. '" continue="' .. (row.continue == "t" and "true" or "false") .. '">')
            current_ext_name, current_cond_order = row.extension_name, nil
        end
        
        -- Open <condition> tag if needed
        if not current_cond_order or current_cond_order ~= row.condition_order then
            if current_cond_order then table.insert(xml, '</condition>') end
            table.insert(xml, '<condition field="' .. row.field .. '" expression="' .. row.expression .. '" break="' .. row.break_on_match .. '">')
            current_cond_order = row.condition_order
        end
        
        -- Add action
        table.insert(xml, '<' .. row.action_type .. ' application="' .. row.application .. '" data="' .. row.data .. '"/>')
    end)
    
    -- Close open tags
    if current_cond_order then table.insert(xml, '</condition>') end
    if current_ext_name then table.insert(xml, '</extension>') end
    table.insert(xml, '    </context>')
    table.insert(xml, '  </section>')
    table.insert(xml, '</document>')
    
    -- Convert table to string
    XML_STRING = table.concat(xml, "\n")
    log("DEBUG", "Generated XML:\n" .. XML_STRING)
    
    -- Release database connection
    dbh:release()
end
