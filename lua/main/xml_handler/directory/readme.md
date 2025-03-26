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
