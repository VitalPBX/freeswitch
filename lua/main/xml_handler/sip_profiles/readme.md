# SIP Profiles and Gateways XML Generator

This Lua script dynamically generates FreeSWITCH-compatible XML configuration for `sofia.conf`. It loads SIP Profiles and Gateways from a PostgreSQL database, replaces FreeSWITCH global variables, and outputs fully structured XML.

---

## Features

- Connects to PostgreSQL via ODBC DSN `ring2all`
- Dynamic generation of `<profile>`, `<gateways>`, `<domains>`, and `<settings>`
- Replaces both `$${var}` and `${var}` syntax using FreeSWITCH's global variables
- Groups gateways per tenant and profile
- Fully compliant with FreeSWITCH XML configuration format

---

## Directory Structure


---

## Requirements

- PostgreSQL database with views:
  - `view_sip_profiles`
  - `view_gateways`
- ODBC DSN configured as `ring2all`
- Lua module `resources.settings.settings` with a `debug` flag
- FreeSWITCH with mod_lua and mod_xml_curl configured

---

## How It Works

1. **Load Global Variables**
   - Executes `global_getvar` to retrieve all FreeSWITCH global vars.
   - Parses them into a Lua table `global_vars`.

2. **Replace Variables**
   - Replaces `$${var}` and `${var}` inside profile and gateway data.
   - Logs a warning if the variable is not found.

3. **Fetch Gateways and Profiles**
   - Queries both views and groups gateways by `tenant_id` and `gateway_name`.

4. **Generate XML**
   - Constructs valid XML using `table.insert()` and finally uses `table.concat()` to join lines.
   - Stores result in global `XML_STRING`.

---

## Usage in FreeSWITCH

Execute manually:

```bash
freeswitch> luarun /usr/share/freeswitch/scripts/main/xml_handlers/sip_profiles/sip_profiles.lua

