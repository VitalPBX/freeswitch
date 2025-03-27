-- dtmf_check.lua
-- Script to validate that dtmf-type is correctly configured

local settings = require("resources.settings.settings")

-- Logging helper
local function log(level, message)
  if level == "debug" and not settings.debug then return end
  freeswitch.consoleLog(level, "[DTMF-Check] " .. message .. "\n")
end

-- Replace $$vars
local function resolve_vars(str)
  local api = freeswitch.API()
  return str:gsub("%$%${([^}]+)}", function(var)
    return api:execute("global_getvar", var) or ""
  end)
end

-- Check extension setting
local function check_user_setting(dbh, tenant_id, username)
  local dtmf_type = nil
  local sql = string.format([[
    SELECT value FROM core.sip_user_settings
    WHERE sip_user_id = (
      SELECT id FROM core.sip_users
      WHERE username = '%s' AND tenant_id = '%s'
    )
    AND name = 'dtmf-type' AND enabled = true
    LIMIT 1
  ]], username, tenant_id)

  dbh:query(sql, function(row)
    dtmf_type = row.value
  end)

  if dtmf_type then
    log("info", "✅ Extension " .. username .. " has dtmf-type = " .. dtmf_type)
  else
    log("warning", "⚠️  Extension " .. username .. " is missing dtmf-type")
  end
end

-- Check SIP profile setting
local function check_profile_setting(dbh, tenant_id, profile_name)
  local dtmf_type = nil
  local sql = string.format([[
    SELECT value FROM core.sip_profile_settings
    WHERE sip_profile_id = (
      SELECT id FROM core.sip_profiles
      WHERE profile_name = '%s' AND tenant_id = '%s'
    )
    AND name = 'dtmf-type' AND enabled = true
    LIMIT 1
  ]], profile_name, tenant_id)

  dbh:query(sql, function(row)
    dtmf_type = row.value
  end)

  if dtmf_type then
    log("info", "✅ SIP profile '" .. profile_name .. "' has dtmf-type = " .. dtmf_type)
  else
    log("warning", "⚠️  SIP profile '" .. profile_name .. "' is missing dtmf-type")
  end
end

-- === Main Execution ===
local domain = settings.get_domain()
local tenant_id = settings.get_tenant_id_by_domain(domain)

if not domain or domain == "" then
  log("ERR", "No domain found")
  return
end

log("info", "Checking DTMF settings for domain: " .. domain)

local dbh = freeswitch.Dbh("odbc://ring2all")
if not dbh:connected() then
  log("ERR", "Database connection failed")
  return
end

-- CHANGE THESE for the user/profile you want to check
local username = "1000"
local profile_name = "internal"

check_user_setting(dbh, tenant_id, username)
check_profile_setting(dbh, tenant_id, profile_name)

dbh:release()
