# IVR Module — Ring2All for FreeSWITCH

This module dynamically generates the `ivr.conf` configuration for FreeSWITCH based on tenant-specific data stored in a PostgreSQL database. It allows full multi-tenant IVR management through database-driven logic.

## 📁 File: `ivr.lua`

The `ivr.lua` script is responsible for generating a valid XML response for the `ivr.conf` configuration section. It connects to the database, fetches all IVR menu definitions from a tenant-specific view (`view_ivr_menu_options`), and returns the expected structure for FreeSWITCH.

### ✅ Features

- Dynamic IVR menu generation via Lua.
- Multi-tenant support (based on domain resolution).
- Fetches data from the `core.tenants` table and `view_ivr_menu_options`.
- Includes full support for `<entry>` attributes such as `action`, `param`, `expression`, and `break`.

### 🏗️ Database Requirements

- Table: `core.tenants`  
  Used to resolve the `tenant_id` based on the domain.

- View: `view_ivr_menu_options`  
  Must include:
  - `tenant_id`
  - `ivr_name`
  - `priority`
  - `action`
  - `digits`
  - `destination` *(optional)*
  - `condition` *(optional)*
  - `break_on_match` *(optional)*

### 🧠 Logic Flow

1. Get the domain using `settings.get_domain()`.
2. Resolve `tenant_id` from the domain.
3. Query all IVR entries for the tenant.
4. Generate `<menu>` and `<entry>` tags grouped by `ivr_name`.
5. Set `_G.XML_STRING` for FreeSWITCH to consume.

### 📄 Example Output

Here’s an example of the generated XML structure:

```xml
<document type="freeswitch/xml">
  <section name="configuration">
    <configuration name="ivr.conf" description="IVR menus">
      <menu name="demo_ivr"
            greet-long="phrase:demo_ivr_main_menu"
            greet-short="phrase:demo_ivr_main_menu_short"
            timeout="10000"
            max-failures="3"
            direct-dial="false">
        <entry action="menu-exec-app" digits="1" param="1001 XML default"/>
        <entry action="menu-top" digits="9"/>
      </menu>
    </configuration>
  </section>
</document>
```

### 🧪 Test Script: tests/ivr_test.lua
To manually test IVR generation without triggering a real SIP call:
```console
-- tests/ivr_test.lua
-- Test the IVR XML generation for a specific domain

local ivr = require("main.xml_handlers.ivr.ivr")

-- Change this to match your test domain
local domain = "192.168.10.21"

ivr(domain)  -- This will populate _G.XML_STRING

freeswitch.consoleLog("INFO", "[Test] IVR XML:\n" .. (_G.XML_STRING or "No XML generated") .. "\n")
```
Run it from the FreeSWITCH CLI:
```console
freeswitch> luarun tests/ivr_test.lua main demo_ivr
```
### 🔄 Integration
The IVR module is loaded by the main dispatcher in index.lua when FreeSWITCH requests:
```console
<configuration name="ivr.conf" ...>
```

Be sure your dispatcher includes:
```console
elseif config_name == "ivr.conf" then
  local domain = settings.get_domain()
  if not domain or domain == "" then
    log("ERR", "Domain not found in XML_REQUEST for IVR")
    return
  end

  local ivr = require("main.xml_handlers.ivr.ivr")
  ivr(domain)
elseif config_name == "ivr.conf" then
  local domain = settings.get_domain()
  if not domain or domain == "" then
    log("ERR", "Domain not found in XML_REQUEST for IVR")
    return
  end

  local ivr = require("main.xml_handlers.ivr.ivr")
  ivr(domain)
```

### 🛠️ Notes
- The ivr_name must match the name used in the dialplan action:
ivr(demo_ivr) → menu name="demo_ivr"
- Always ensure ivr.conf is requested with proper domain context.
- FreeSWITCH expects the <menu> block directly under <configuration>, not inside a <menus> wrapper.

### 📚 Related Files
- ivr.lua — Main IVR generator
- tests/ivr_test.lua — Manual test script
- index.lua — Main section router
- settings.lua — Domain/tenant resolution logic

