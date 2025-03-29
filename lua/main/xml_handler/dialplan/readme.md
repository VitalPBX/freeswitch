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
Maps the domain to a tenant_id via:
- Table: core.tenants
- Field: domain_name

4. **SQL Query:**
Fetches full dialplan logic from:
- View: view_dialplan_expanded
- Internally joins:
   - core.dialplan_contexts
   - core.dialplan_extensions
   - core.dialplan_conditions
   - core.dialplan_actions
- Filtered by:
 - tenant_id
 - enabled = true at all levels


## 🧾XML Structure & Mapped Tables  
Each level of the XML corresponds to a specific database table:
<context name="...">
- Description: Represents a call routing context (like a namespace).
- Table: core.dialplan_contexts
- Fields:
   - name → context.name
   - continue → optional, processed in Lua
- Tenant Scope: Each context is associated with a tenant_id.

<extension name="...">
- Description: Matches a logical rule set within a context.
- Table: core.dialplan_extensions
- Fields:
   - name → extension.name
   - continue → extension.continue (determines if execution should continue to next extension)
   - position → used for sorting (priority in XML)
- Notes: Each extension belongs to one context (context_id foreign key).

<condition field="..." expression="...">
- Description: Defines a match condition for a call attribute (like destination_number).
- Table: core.dialplan_conditions
- Fields:
   - field
   - expression
   - break → optional (on-true, never, always, etc.)
- Notes: A single extension can have multiple conditions.

<action application="..." data="..."/>
- Description: Action to execute if the condition matches.
- Table: core.dialplan_actions
- Fields:
   - application
   - data
   - inline → optional
   - is_anti_action = false
- Notes: Executed in order. Belongs to a condition (condition_id).

<anti-action application="..." data="..."/>
- Description: Executed when a condition fails.
- Table: core.dialplan_actions
- Fields:
   - Same as above
   - is_anti_action = true



## 🧱 Database View: `view_dialplan_expanded`

This view flattens the normalized tables into a single queryable structure, exposing:
- context_name, extension_name, condition_field, condition_expression, action_application, etc.
- Includes sorting by priority (context/extension/condition order)
- Automatically joins tenant_id across all levels


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
- Ensure global variable domain is available when the dialplan is requested.
- Trigger this module from:
   - main.lua → xml_handlers/index.lua
   - when section == "dialplan"

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

## 📚 Suggested Improvements
- Add support for dialplan tags like <pre-process> and <post-process> (if needed).
- Validate XML output using fs_cli or XSD if available.
- Add caching layer for performance on high-traffic environments.
