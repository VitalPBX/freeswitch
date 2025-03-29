# 📄 SIP Profiles and Gateways XML Generator

**Project**: Ring2All  
**Author**: Rodrigo Cuadra  
**Component**: Dynamic Sofia SIP Profile XML Generator  
**Database**: PostgreSQL (via ODBC)  
**Target**: FreeSWITCH `<configuration name="sofia.conf">`

---

## 📌 Purpose

This module dynamically generates FreeSWITCH SIP profiles and gateways in XML format using PostgreSQL.  
It is multi-tenant aware and supports inheritance of aliases and gateway configurations.

---

## 🧠 How It Works

### 1. Load FreeSWITCH Global Variables

Executes:

```lua
api:execute("global_getvar", "")
```

All variables are stored in `global_vars`, and the script replaces `${var}` and `$${var}` syntax in profile, alias, and gateway settings.

---

### 2. Fetch Data from PostgreSQL

- **Aliases** from `core.sip_profile_aliases`
- **Gateways** from `view_gateways`
- **Profiles** from `view_sip_profiles` (filtered by `category = 'sofia'`)

---

### 3. Generate XML Structure

The script builds a valid `<configuration name="sofia.conf">` XML block using `table.insert()` and `table.concat()`.  
The result is stored in the global variable `XML_STRING`.

---

## 🧾 XML Tag Reference

### `<profile name="...">`

- **Purpose**: Defines a SIP profile (e.g., internal, external)
- **Source**: `core.sip_profiles.name`
- **Settings Source**: `core.sip_profile_settings`
- **Example**:
```xml
<profile name="internal">
  ...
</profile>
```

---

### `<aliases>`

- **Purpose**: Lists alternate IPs or hostnames for the profile.
- **Source**: `core.sip_profile_aliases.alias`
- **Example**:
```xml
<aliases>
  <alias name="192.168.10.21"/>
</aliases>
```

---

### `<gateways>`

- **Purpose**: Defines outbound gateways within the profile.
- **Source**: `view_gateways`
- **Grouped By**: `tenant_id` and `gateway_name`
- **Example**:
```xml
<gateways>
  <gateway name="my_gateway">
    <param name="username" value="test"/>
    <param name="password" value="1234"/>
  </gateway>
</gateways>
```

---

### `<domains>`

- **Purpose**: Static domain handling for SIP profiles.
- **Usage**: Defaults to:
```xml
<domains>
  <domain name="all" alias="false" parse="false"/>
</domains>
```

---

### `<settings>`

- **Purpose**: Defines parameters like `sip-ip`, `rtp-ip`, `sip-port`.
- **Source**: `core.sip_profile_settings`
- **Fields**:
  - `name`
  - `value`
- **Example**:
```xml
<settings>
  <param name="sip-port" value="5060"/>
  <param name="rtp-ip" value="$${local_ip_v4}"/>
</settings>
```

---

## 🗃️ Database Tables

### `core.sip_profiles`

Defines each SIP profile and associates it with a tenant.

- `name`, `tenant_id`, `category`, `enabled`
- Linked to: `core.sip_profile_settings`, `core.sip_profile_aliases`

---

### `core.sip_profile_settings`

Stores profile-specific parameters.

- `sip_profile_id`, `name`, `value`, `setting_type`
- `enabled` must be true to apply

---

### `core.sip_profile_aliases`

Defines alternative names/IPs for each profile.

- `sip_profile_id`, `alias`

---

### `view_sip_profiles`

Used by the script to fetch profiles and their settings in order.

```sql
SELECT
    p.id AS sip_profile_id,
    p.tenant_id,
    p.name AS profile_name,
    p.category,
    s.name AS setting_name,
    s.value AS setting_value,
    s.setting_order
FROM core.sip_profiles p
LEFT JOIN core.sip_profile_settings s
    ON s.sip_profile_id = p.id
WHERE p.enabled = TRUE AND s.enabled = TRUE;
```

---

## 🧪 Testing

Manual test:

```bash
freeswitch> luarun /usr/share/freeswitch/scripts/main/xml_handlers/sip_profiles/sip_profiles.lua
```

Export to file:

```bash
freeswitch> luarun .../sip_profiles.lua > /tmp/sip_profiles.xml
```

Reloading in FreeSWITCH:

```bash
reloadxml
reload mod_sofia
sofia profile internal restart
```

---

## 🔄 Output

The final XML is stored in:

```lua
XML_STRING = table.concat(xml, "\n")
```

Used by FreeSWITCH's `mod_xml_curl` or static XML directory.

---

## 📁 Directory Structure

```
/usr/share/freeswitch/scripts/
├── main/
│   ├── xml_handlers/
│   │   └── sip_profiles/
│   │       └── sip_profiles.lua
│   └── resources/
│       └── settings/
│           └── settings.lua
```

---

## 📬 Contact

For improvements or bug reports, contact [Rodrigo Cuadra](https://github.com/rodrigocuadra)

---
