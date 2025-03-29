# Dialplan Module (`dialplan.lua`)

**Project:** Ring2All  
**Author:** Rodrigo Cuadra  
**Component:** Dynamic Dialplan XML Generator  
**Database:** PostgreSQL (via ODBC)  
**Target:** FreeSWITCH XML Dialplan Section (`<section name="dialplan">`)

---

## 📌 Purpose

This module dynamically generates the FreeSWITCH dialplan XML for a **multi-tenant** VoIP system. It replaces static XML files by retrieving the entire dialplan structure from a PostgreSQL view called `view_dialplan_expanded`.

Each dialplan is generated **per tenant**, based on the SIP domain of the incoming request.

---

## 🧠 How It Works

### Domain Resolution
   Extracts the SIP domain (`domain`) using FreeSWITCH global variable (`getGlobalVariable("domain")`).

### Tenant Lookup

Maps the domain to a `tenant_id` via:

- **Table**: `core.tenants`  
- **Field**: `domain_name`

---

### SQL Query

Fetches full dialplan logic from:

- **View**: `view_dialplan_expanded`

Internally joins:

- `core.dialplan_contexts`  
- `core.dialplan_extensions`  
- `core.dialplan_conditions`  
- `core.dialplan_actions`

Filtered by:

- `tenant_id`  
- `enabled = true` at all levels

---

## 🧾 XML Structure & Database Mapping

Each level of the generated XML maps directly to database entities:

---

### `<context name="...">`

- **Description**: Represents a call routing context (like a namespace).  
- **Table**: `core.dialplan_contexts`  
- **Fields**:
  - `name` → `<context name="...">`
  - `continue` → (optional, logic handled in Lua)
- **Note**: Each context is scoped to a tenant via `tenant_id`.

---

### `<extension name="...">`

- **Description**: Defines a logical rule set within a context.  
- **Table**: `core.dialplan_extensions`  
- **Fields**:
  - `name` → `<extension name="...">`
  - `continue` → Determines whether to continue to the next extension
  - `position` → Used for sorting/prioritization
- **Relation**: Linked to a context via `context_id`

---

### `<condition field="..." expression="...">`

- **Description**: Specifies matching criteria for a dialplan element.  
- **Table**: `core.dialplan_conditions`  
- **Fields**:
  - `field` → `<condition field="...">`
  - `expression` → Regex or string to match
  - `break` → Optional (`on-true`, `never`, etc.)

---

### `<action application="..." data="..."/>`

- **Description**: Executed if the condition matches.  
- **Table**: `core.dialplan_actions`  
- **Fields**:
  - `application` → Dialplan application to run (e.g., `playback`)
  - `data` → Optional arguments or parameters
  - `inline` → (optional)
  - `is_anti_action` → `false`
- **Relation**: Belongs to a condition (`condition_id`)

---

### `<anti-action application="..." data="..."/>`

- **Description**: Executed if the condition **fails**.  
- **Table**: `core.dialplan_actions`  
- **Fields**:
  - Same as action
  - `is_anti_action` → `true`

---

## 🧱 Database View: `view_dialplan_expanded`

This unified view flattens the normalized schema into a single structure, simplifying retrieval:

Includes:

- `context_name`
- `extension_name`
- `condition_field`
- `condition_expression`
- `action_application`
- `action_data`
- `is_anti_action`
- `position`, `priority`, and other sorting fields

Filtered by:

- `tenant_id`
- `enabled` flags at each level

---

## 🧩 Example XML Output

```xml
<document type="freeswitch/xml">
  <section name="dialplan">
    <context name="default">
      <extension name="9000">
        <condition field="destination_number" expression="^9000$">
          <action application="answer"/>
          <action application="playback" data="ivr/ivr-welcome.wav"/>
        </condition>
      </extension>
    </context>
  </section>
</document>
```
---

## 🔧 Configuration Notes

- Ensure the global variable `domain` is set when the dialplan is requested.
- This module must be triggered from:

```lua
main.lua → xml_handlers/index.lua
```

When:

```lua
section == "dialplan"
```
---

## 📁 File Location

```
/usr/share/freeswitch/scripts/main/xml_handlers/dialplan/dialplan.lua
```
---

## ✅ Status

- ✅ Multi-tenant support  
- ✅ Full context → extension → condition → action hierarchy  
- ✅ `continue` and `break` logic supported  
- ✅ Anti-actions supported  
- ✅ Fully dynamic  
- ✅ Compatible with FreeSWITCH 1.10+

---

## 👀 See Also

- [`sip_register.lua`](../directory/sip_register.lua) — Directory handler for SIP registration  
- [`settings.lua`](../resources/settings/settings.lua) — Global configuration module  
- [`sip_profiles.lua`](../sip_profiles/sip_profiles.lua) — Load SIP Profiles for internal/external routing

---

## 📚 Suggested Improvements

- [ ] Add support for `<pre-process>` and `<post-process>` tags  
- [ ] Add XML validation using `fs_cli xml_locate`  
- [ ] Add caching or memoization for performance optimization

---
