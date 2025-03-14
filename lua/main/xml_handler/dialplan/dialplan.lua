--[[
    handler.lua (dialplan)
    Handles FreeSWITCH dialplan requests (e.g., call routing).
    Uses ODBC for PostgreSQL database connection.
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

    -- SQL query to retrieve dialplan data
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

    -- Execute the query
    local cur, err = dbh:query(query)
    if not cur then
        log("ERROR", "SQL query execution failed: " .. (err or "Unknown error"))
        return
    end

    -- Fetch the first row
    local row = cur:fetch({}, "a")
    if not row then
        log("WARNING", "No dialplan entries found for context: " .. context)
        return
    end

    -- Construct the XML response
    local xml = {
        '<?xml version="1.0" encoding="utf-8"?>',
        '<document type="freeswitch/xml">',
        '  <section name="dialplan" description="Dynamic Dialplan">',
        '    <context name="' .. context .. '">'
    }

    local current_ext_name, current_cond_order

    while row do
        -- Open a new <extension> block if necessary
        if current_ext_name ~= row.extension_name then
            if current_ext_name then table.insert(xml, '</extension>') end
            table.insert(xml, '<extension name="' .. row.extension_name .. '" continue="' .. (row.continue == "t" and "true" or "false") .. '">')
            current_ext_name, current_cond_order = row.extension_name, nil
        end

        -- Open a new <condition> block if necessary
        if current_cond_order ~= row.condition_order then
            if current_cond_order then table.insert(xml, '</condition>') end
            table.insert(xml, '<condition field="' .. row.field .. '" expression="' .. row.expression .. '" break="' .. row.break_on_match .. '">')
            current_cond_order = row.condition_order
        end

        -- Add action
        table.insert(xml, '<' .. row.action_type .. ' application="' .. row.application .. '" data="' .. row.data .. '"/>')

        -- Fetch next row
        row = cur:fetch({}, "a")
    end

    -- Close any open tags
    if current_cond_order then table.insert(xml, '</condition>') end
    if current_ext_name then table.insert(xml, '</extension>') end
    table.insert(xml, '    </context>')
    table.insert(xml, '  </section>')
    table.insert(xml, '</document>')

    -- Convert table to string
    XML_STRING = table.concat(xml, "\n")
    log("DEBUG", "Generated XML:\n" .. XML_STRING)

    -- Close database connection
    if cur and cur.close then cur:close() end
    if dbh and dbh.close then dbh:close() end
end
