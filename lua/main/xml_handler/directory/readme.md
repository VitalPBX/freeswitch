# FreeSWITCH XML Directory Handler (`sip_register.lua`)

**Project**: Ring2All  
**Author**: Rodrigo Cuadra  
**Component**: Dynamic SIP Directory XML Generator  
**Database**: PostgreSQL (via ODBC)  
**Target**: FreeSWITCH `<section name="directory">`

---

## 📌 Purpose

This module dynamically generates FreeSWITCH directory XML used during SIP user registration (`REGISTER` requests).  
It is fully compatible with multi-tenant environments and retrieves user and profile settings from PostgreSQL.

---

## 🧠 How It Works

### Domain Resolution

Extracts the SIP domain from:

```lua
params:getHeader("domain") or params:getHeader("sip_host")
```

---

### Tenant Lookup

Maps the domain to a `tenant_id` using:

- **Table**: `core.tenants`  
- **Field**: `domain_name`

---

### SIP User Lookup

Retrieves the SIP user based on `username` and `tenant_id`:

- **View**: `view_sip_users`  
- **Fields**:
  - `username`
  - `sip_profile_id`
  - `enabled`

---

### User Settings

Loaded from:

- **Table**: `core.sip_user_settings`  
- **Fields**:
  - `name` → Parameter or variable name
  - `type` → Must be `param` or `variable`
  - `value` → Actual value

Only `enabled = TRUE` entries are included.

---

### Profile Inheritance

If the SIP user has a linked profile (`sip_profile_id`), and it belongs to category `sip_user`, then:

- **Table**: `core.sip_profiles`
- **Table**: `core.sip_profile_settings`  
- **Category**: `'sip_user'`  
- **Logic**: Profile settings are only inherited if not already defined in the user.

---

### Variable Substitution

Supports FreeSWITCH-style global variable substitution via:

```lua
${var} or $${var}
```

Using:

```lua
api:execute("global_getvar", "")
```

---

## 🧾 Database Structure

### `core.sip_users`

Stores basic SIP credentials.

- `tenant_id` → Foreign key to `core.tenants`  
- `username`, `password`  
- `sip_profile_id` → Optional inheritance  
- `enabled` → Must be true to allow registration

---

### `core.sip_user_settings`

Defines per-user SIP parameters and variables.

- `sip_user_id` → Foreign key to `core.sip_users`  
- `name`, `type`, `value`  
- `type` = `'param'` or `'variable'`  
- `enabled` → Must be true

---

### `view_sip_users`

Provides a flattened view joining users and their settings.

```sql
CREATE OR REPLACE VIEW view_sip_users AS
SELECT
    su.username,
    su.enabled,
    su.sip_profile_id,
    su.id AS sip_user_id,
    sus.name AS setting_name,
    sus.type AS type,
    sus.value AS setting_value,
    sus.enabled AS setting_enabled,
    su.tenant_id
FROM
    core.sip_users su
LEFT JOIN core.sip_user_settings sus ON sus.sip_user_id = su.id
WHERE
    sus.enabled = true;
```

---

## 🧩 Example XML Output

```xml
<user id="1000">
  <params>
    <param name="password" value="1234"/>
  </params>
  <variables>
    <variable name="user_context" value="default"/>
  </variables>
</user>
```

---

## 🛠️ Configuration

Ensure your ODBC source is configured properly:

```lua
dbh = freeswitch.Dbh("odbc://ring2all")
```

---

## 📁 Directory Structure

```
/usr/share/freeswitch/scripts/
├── main.lua
├── main/
│   ├── xml_handlers/
│   │   ├── directory/
│   │   │   └── sip_register.lua
│   └── resources/
│       └── settings/
│           └── settings.lua
```

---

## ✅ Runtime Flow

1. FreeSWITCH receives a SIP REGISTER request.
2. `main.lua` dispatches it to `sip_register.lua`.
3. The script resolves the tenant and SIP user.
4. Settings are fetched and profile inheritance is applied.
5. XML is constructed and returned to FreeSWITCH.

---

## 🧪 Testing

1. Point a SIP client to FreeSWITCH.
2. Use `username@domain` to register.
3. Check logs for:
   - Domain and username extraction
   - Database lookup success
   - XML output generation

---

## 👀 Related Files

- `main.lua`: Entry point for handling XML requests  
- `index.lua`: Dispatches requests to modules  
- `settings.lua`: Shared settings and logging

---

## 📬 Contact

For questions or contributions, contact [Rodrigo Cuadra](https://github.com/rodrigocuadra)  
Rodrigo Cuadra

---
