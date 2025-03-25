--[[
    settings.lua
    Common settings and utility functions for FreeSWITCH scripts.
--]]

-- Table to store configuration and utility functions
local settings = {
    debug = true  -- Set to false to disable debug-level logging
}

-- Generic function to format and indent XML responses
function settings.format_xml(section_name, content, options)
    -- Default options
    local opts = options or {}
    local indent = opts.indent or "   "               -- Indentation per level (default: 4 spaces)
    local domain_name = opts.domain_name or ""        -- Domain name (optional)
    local alias = opts.alias or false                 -- Add alias="true" to domain tag (optional)
    local extra_attrs = opts.extra_attrs or {}        -- Additional attributes for the section tag (optional)

    -- Indentation levels
    local level0 = ""
    local level1 = indent
    local level2 = indent .. indent
    local level3 = indent .. indent .. indent
    local level4 = indent .. indent .. indent .. indent

    -- Start building the base XML structure
    local xml = {
        level0 .. '<?xml version="1.0" encoding="UTF-8" standalone="no"?>',
        level0 .. '<document type="freeswitch/xml">',
        level1 .. '<section name="' .. section_name .. '">'
    }

    -- If domain_name is provided, wrap content inside a <domain> block
    if domain_name and domain_name ~= "" then
        local domain_line = level2 .. '<domain name="' .. domain_name .. '"'
        if alias then
            domain_line = domain_line .. ' alias="true"'
        end
        domain_line = domain_line .. '>'
        table.insert(xml, domain_line)
        -- Indent content to proper level
        for line in content:gmatch("[^\n]+") do
            table.insert(xml, level3 .. line)
        end
        table.insert(xml, level2 .. '</domain>')
    else
        -- Otherwise, insert the content directly under the section
        for line in content:gmatch("[^\n]+") do
            table.insert(xml, level2 .. line)
        end
    end

    -- Close the section and document tags
    table.insert(xml, level1 .. '</section>')
    table.insert(xml, level0 .. '</document>')

    -- Return the full XML string
    return table.concat(xml, "\n")
end

-- Utility function to retrieve tenant_id from a given domain
function settings.get_tenant_id_by_domain(domain)
    local dbh = env:connect("ring2all")
    if not dbh then
        freeswitch.consoleLog("ERR", "[settings] Failed to connect to DB for tenant_id lookup\n")
        return "00000000-0000-0000-0000-000000000000"
    end

    local tenant_id = nil
    local sql = string.format(
        "SELECT id FROM core.tenants WHERE domain = '%s' LIMIT 1", domain
    )

    dbh:query(sql, function(row)
        tenant_id = row.id
    end)

    return tenant_id or "00000000-0000-0000-0000-000000000000"
end

-- Export the settings module
return settings
