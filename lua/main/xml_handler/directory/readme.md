# FreeSWITCH XML Directory Handler (Ring2All)

This module handles dynamic XML generation for SIP user registration (`directory` section) in FreeSWITCH. It’s designed for multi-tenant environments and reads user data directly from a PostgreSQL database via ODBC.

## 🔧 What It Does
- Handles `directory` XML requests triggered by SIP REGISTER.
- Looks up the SIP user in the database using `username` and `domain`.
- Resolves the tenant (`core.tenants`) from the domain.
- Pulls SIP user credentials and settings from the view `view_sip_users`.
- Returns FreeSWITCH-compatible `<user>` XML with `<params>` and `<variables>`.

## 🗃️ Database Structure
Requires the following structure:
- core.tenants: List of domains/tenants.
- core.sip_users: SIP user credentials.
- core.sip_user_settings: Settings for users (e.g. caller ID, codecs, etc.).
- view_sip_users: View joining users + settings with filters applied.

Sample SQL for the view:
 ``` console
CREATE OR REPLACE VIEW view_sip_users AS
SELECT
    u.id AS sip_user_id,
    u.tenant_id,
    u.username,
    u.password,
    u.enabled,
    s.name AS setting_name,
    s.value AS setting_value,
    s.type AS setting_type
FROM core.sip_users u
LEFT JOIN core.sip_user_settings s ON s.sip_user_id = u.id
WHERE u.enabled = TRUE
  AND s.enabled = TRUE;
 ```

## 🛠️ Configuration
Ensure your ODBC source is defined in odbc.ini and matches odbc://ring2all.

Example in Lua:
 ``` console
dbh = freeswitch.Dbh("odbc://ring2all")
 ```

## 📦 Directory Structure
 ``` console
/usr/share/freeswitch/scripts/
├── main.lua
├── main/
│   ├── xml_handlers/
│   │   ├── index.lua
│   │   ├── directory/
│   │   │   └── sip_register.lua
│   │   ├── dialplan/
│   │   │   └── dialplan.lua
│   │   └── ...
│   └── resources/
│       └── settings/
│           └── settings.lua
 ```

## 🧩 Components

### 1. `main.lua`
Entry point used by FreeSWITCH to dispatch XML requests.
- Parses the `XML_REQUEST` table.
- Routes to the appropriate handler (`directory`, `dialplan`, `configuration`).
- Loads shared settings and logging.

### 2. `index.lua`
Sub-dispatcher that lives under `scripts/main/<app_name>/index.lua`.
- Handles:
  - SIP registrations and authentication (`directory`)
  - Call routing logic (`dialplan`)
  - Config generation (e.g. `vars.xml`, `sofia.conf`, `ivr.conf`)

### 3. `sip_register.lua`
Dynamically generates the directory XML used in SIP registrations.
- Queries `view_sip_users` using the tenant resolved from the SIP domain.
- Outputs users with `<params>` and `<variables>`, supporting `$${}` substitution from FreeSWITCH global vars.
- Example output:
  ```xml
  <user id="1000">
    <params>
      <param name="password" value="1234"/>
    </params>
    <variables>
      <variable name="user_context" value="default"/>
    </variables>
  </user>

## 🧪 Testing
To test SIP registration:
1. Point a SIP client to your FreeSWITCH instance.
2. Register with username@domain.
3. Confirm logs show:
    - XML request being handled
    - Database connection success
    - XML output generated
