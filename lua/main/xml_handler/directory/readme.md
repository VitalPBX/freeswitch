# FreeSWITCH XML Directory Handler (Ring2All)

This module handles dynamic XML generation for SIP user registration (`directory` section) in FreeSWITCH. It’s designed for multi-tenant environments and reads user data directly from a PostgreSQL database via ODBC.

## 🔧 What It Does
- Handles `directory` XML requests triggered by SIP REGISTER.
- Looks up the SIP user in the database using `username` and `domain`.
- Resolves the tenant (`core.tenants`) from the domain.
- Pulls SIP user credentials and settings from the view `view_sip_users`.
- Inherits settings from a `sip_user` profile (`core.sip_profiles`) if one is linked to the user.
- Returns FreeSWITCH-compatible `<user>` XML with `<params>` and `<variables>`.

## 🗃️ Database Structure
Requires the following structure:
- `core.tenants`: List of tenant domains.
- `core.sip_users`: SIP user credentials.
- `core.sip_user_settings`: User-specific SIP settings.
- `core.sip_profiles`: Reusable configuration profiles.
- `core.sip_profile_settings`: Settings grouped by profile.
- `view_sip_users`: View joining users and their settings.

Sample SQL for the view:
 ``` console
CREATE OR REPLACE VIEW view_sip_users AS
SELECT
    u.id AS sip_user_id,
    u.tenant_id,
    u.username,
    u.password,
    u.enabled,
    u.sip_profile_id AS user_profile_id,
    s.name AS setting_name,
    s.value AS setting_value,
    s.setting_type
FROM core.sip_users u
LEFT JOIN core.sip_user_settings s ON s.sip_user_id = u.id
WHERE u.enabled = TRUE;
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

## ✅ How It Works
FreeSWITCH receives a SIP REGISTER.
1. FreeSWITCH receives a SIP REGISTER.
2. `main.lua` dispatches the request to `sip_register.lua`.
3. The database is queried to find the tenant and SIP user.
4. If the user is linked to a `sip_user` profile, its settings are loaded.
5. XML is generated and returned to FreeSWITCH.

### 📂 Related Files

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

## 📬 Contact
For contributions or issues, contact [Rodrigo Cuadra](https://github.com/rodrigocuadra) or fork the project on GitHub.<br>
Rodrigo Cuadra<br>
Project: Ring2All
