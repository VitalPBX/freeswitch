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

1. **Domain Resolution:**  
   Extracts the SIP domain (`domain`) using FreeSWITCH global variable (`getGlobalVariable("domain")`).

2. **Tenant Lookup:**  
   Maps the domain to a `tenant_id` via the `core.tenants` table.

3. **SQL Query:**  
   Fetches full dialplan logic from the `view_dialplan_expanded` view for that tenant:
   - Contexts
   - Extensions
   - Conditions
   - Actions / Anti-actions

4. **XML Generation:**  
   Constructs the FreeSWITCH-compliant `<dialplan>` structure dynamically and returns it as `_G.XML_STRING`.

---

## 🧱 Database View: `view_dialplan_expanded`

This view joins multiple normalized tables into a single queryable structure:
- `core.dialplan_contexts`
- `core.dialplan_extensions`
- `core.dialplan_conditions`
- `core.dialplan_actions`

Filtered by:
- `tenant_id`
- Enabled status on each level (context, extension, condition)

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

## 🔧 Configuration Notes
Ensure that the domain is available as a global variable (domain) when the dialplan is requested.
This module must be triggered from main.lua → xml_handlers/index.lua when section == "dialplan".

## 📁 Location
``` console
/usr/share/freeswitch/scripts/main/xml_handlers/dialplan/dialplan.lua
```

## ✅ Status
- ✅ Multi-tenant support
- ✅ Context, extension, condition, action hierarchy
- ✅ Anti-actions supported
- ✅ Fully dynamic
- ✅ Compatible with FreeSWITCH 1.10+

## 👀 See Also
- sip_register.lua — Directory handler for SIP registration
- settings.lua — Global configuration module
- sip_proifiles.lua - Load Sip Profiles for Main Tenant (internal, external, etc)
