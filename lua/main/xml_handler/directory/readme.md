# FreeSWITCH Dynamic XML Handler – Ring2All

This project provides a modular and scalable way to handle FreeSWITCH XML requests such as `directory`, `dialplan`, and `configuration` using Lua scripts and a PostgreSQL database via ODBC. Built for multi-tenant environments.

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

## 🗃️ Database
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

## 🧪 Testing
To test SIP registration:
1. Point a SIP client to your FreeSWITCH instance.
2. Register with username@domain.
3. Confirm logs show:
  -XML request being handled
  - Database connection success
  - XML output generated
