# 📄 SIP Profiles and Gateways XML Generator

This Lua script dynamically generates FreeSWITCH-compatible XML configuration for `sofia.conf`. It loads SIP Profiles and Gateways from a PostgreSQL database, replaces FreeSWITCH global variables, and outputs fully structured XML.

---

## 🧩 Features

- ✅ Connects to PostgreSQL via ODBC DSN `ring2all`
- ✅ Dynamic generation of `<profile>`, `<aliases>`, `<gateways>`, `<domains>`, and `<settings>`
- ✅ Replaces both `$${var}` and `${var}` syntax using FreeSWITCH's global variables
- ✅ Efficiently groups gateways per tenant and profile
- ✅ Fully compliant with FreeSWITCH XML configuration format

---

## 📁 Directory Structure
``` console
resources/
└── settings/
    └── settings.lua
scripts/
└── main/
    └── xml_handlers/
        └── sip_profiles/
            └── sip_profiles.lua
```
---

## 🔌 Required FreeSWITCH Configuration

- PostgreSQL database with views:
  - `view_sip_profiles`
  - `view_gateways`
  - core.sip_profile_aliases
- ODBC DSN configured as `ring2all`
- Lua module `resources.settings.settings` with a `debug` flag
- FreeSWITCH with mod_lua and mod_xml_curl configured

---

## 🧠 How It Works

1. **Load Global Variables**
   - Executes `global_getvar` to retrieve all FreeSWITCH global vars.
   - Parses them into a Lua table `global_vars`.
The script uses:
``` console
api:execute("global_getvar", "")
```

2. **Replace Variables**
   - Replaces `$${var}` and `${var}` inside profile and gateway data.
   - Logs a warning if the variable is not found.
If a variable is not found, it's replaced with an empty string and logged as a warning.

3. **Fetch Gateways and Profiles**
   - Queries both views and groups gateways by `tenant_id` and `gateway_name`.
SQL Queries:
``` console
SELECT * FROM view_gateways ORDER BY gateway_id, setting_name;
SELECT * FROM view_sip_profiles ORDER BY sip_profile_id, setting_name;
SELECT sip_profile_id, alias FROM core.sip_profile_aliases;
```
It then groups gateways per tenant and appends them to the corresponding SIP profile.

4. **Generate XML**
   - Constructs valid XML using `table.insert()` and finally uses `table.concat()` to join lines.
   - Stores result in global `XML_STRING`.
The XML structure follows FreeSWITCH standards, e.g.:
``` console
<profile name="external">
  <aliases>
    <alias name="192.168.10.21"/>
  </aliases>
  <gateways>...</gateways>
  <domains>
    <domain name="all" alias="false" parse="false"/>
  </domains>
  <settings>...</settings>
</profile>
```
---

## 🔍 Logging
- Logging is controlled by:
``` console
settings.debug -- boolean from `settings.lua`
```
- Supports log levels: info, debug, warning..

## 🧪 Testing

You can run this manually in FreeSWITCH's CLI:
``` console
freeswitch> luarun /usr/share/freeswitch/scripts/main/xml_handlers/sip_profiles/sip_profiles.lua
```
Or dump to a file for inspection:
``` console
freeswitch> luarun /usr/share/freeswitch/scripts/main/xml_handlers/sip_profiles/sip_profiles.lua > /tmp/sip_profiles.xml
```
Then reload Sofia:
``` console
freeswitch> reload mod_sofia
```
Restart FreeSWITCH completely:
``` console
systemctl restart freeswitch
```
Reload XML configurations:
``` console
freeswitch> reloadxml
```
Reload a specific SIP profile:
``` console
freeswitch> sofia profile **internal** restart
```

## 🔄 Output
The final XML is stored in a global variable:
``` console
XML_STRING = table.concat(xml, "\n")
```
This is picked up by mod_xml_curl or FreeSWITCH's XML handler during runtime.



## 📬 Contact
For contributions or issues, contact [Rodrigo Cuadra](https://github.com/rodrigocuadra) or fork the project on GitHub.<br>
Rodrigo Cuadra<br>
Project: Ring2All
