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

### Example XML Output

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

### `<context name="...">`

- **Description**: Represents a call routing context (like a namespace).  
- **Table**: `core.dialplan_contexts`  
- **Fields**:
  - `name` → `<context name="...">`
- **Note**: Contexts are filtered by `enabled = TRUE` and scoped to a `tenant_id`.

---

### `<extension name="...">`

- **Description**: Defines a logical rule set within a context.  
- **Table**: `core.dialplan_extensions`  
- **Fields**:
  - `name` → `<extension name="...">`
  - `priority` → Determines execution order
  - `continue` → Optional; if set to `'true'`, proceeds to next extension
- **Note**: Extensions are filtered by `enabled = TRUE` and linked to a context.

---

### `<condition field="..." expression="...">`

- **Description**: Specifies matching criteria for a dialplan element.  
- **Table**: `core.dialplan_conditions`  
- **Fields**:
  - `field` → Field to evaluate
  - `expression` → Regex or pattern to match
- **Note**: Conditions are filtered by `enabled = TRUE` and linked to an extension.

---

### `<action application="..." data="..."/>`

- **Description**: Executed if the condition matches.  
- **Table**: `core.dialplan_actions`  
- **Fields**:
  - `application` → FreeSWITCH application (e.g., `playback`)
  - `data` → Arguments for the application
  - `type` → Must be `'action'`
  - `sequence` → Execution order
- **Note**: Actions are filtered by `enabled = TRUE` and linked to a condition.

---

### `<anti-action application="..." data="..."/>`

- **Description**: Executed if the condition **fails**.  
- **Same Table**: `core.dialplan_actions`  
- **Fields**:
  - Same as actions
  - `type` → Must be `'anti-action'`

---

## 🗃️ Database View: `view_dialplan_expanded`

This view flattens the normalized schema into a single structure, simplifying retrieval:

Includes:

- `tenant_id`
- `context_name`
- `extension_id`, `extension_name`, `extension_priority`, `continue`
- `condition_id`, `condition_field`, `condition_expr`
- `action_id`, `app_name`, `app_data`, `action_type`, `action_sequence`

Filtered by:

- `ctx.enabled = TRUE`  
- `ext.enabled = TRUE`  
- `cond.enabled = TRUE`  
- `act.enabled = TRUE`

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

## 📒 Default FreeSWITCH Dialplan Extensions

This is a list of default dialplan extensions that come bundled with **FreeSWITCH** out of the box. These extensions provide demos, system functions, test tools, voicemail access, conference rooms, call parking, and more.

| Extension       | Description                                                                 |
|-----------------|-----------------------------------------------------------------------------|
| 1000 -1019      | Local extension 1000-1019                                                   |
| 101             | LADSPA audio processing demo (autotalent, chorus, phaser effects)          |
| 9170            | Talking clock: announce current time                                       |
| 9171            | Talking clock: announce current date                                       |
| 9172            | Talking clock: announce current date and time                              |
| 2000            | Group call to "sales" group                                                 |
| 2001            | Group call to "support" group                                               |
| 2002            | Group call to "billing" group                                               |
| 3000            | SNOM demo conference room                                                   |
| 4000 / *98      | Voicemail main menu                                                         |
| vmain           | Voicemail access                                                            |
| 5000            | IVR demo (interactive voice menu)                                           |
| 5001            | Dynamic conference with outbound call                                       |
| 5900            | Call parking: park a call in FIFO                                           |
| 5901            | Unpark call from FIFO                                                       |
| 6000            | Valet Parking (interactive)                                                 |
| 60XX (≠6000)    | Direct valet parking slot access                                            |
| 6070-moderator  | Join conference as moderator                                                |
| 7243 / pagegroup| Multicast paging (group broadcast)                                          |
| 779            | Eavesdrop all calls (admin mode)                                            |
| 8XXX           | Intercom or call group                                                      |
| 886            | Intercept last global call                                                  |
| 869 / *69      | Call return (redial last received call)                                     |
| 870 / redial   | Redial last dialed number                                                   |
| 9000           | SNOM demo: activate DND button                                              |
| 9001           | SNOM demo: deactivate DND button                                            |
| 9178           | Receive FAX                                                                 |
| 9179           | Send FAX                                                                    |
| 9180           | Ringback 180 tone                                                           |
| 9181           | Ringback 183 with UK ring tone                                              |
| 9182           | Ringback 183 with music                                                     |
| 9183           | Post-answer ringback with UK tone                                           |
| 9184           | Post-answer ringback with music                                             |
| 9191           | ClueCon IVR (bridge to conference)                                          |
| 9192           | Call debug: print channel info                                              |
| 9193           | Record video (FSV format)                                                   |
| 9194           | Playback recorded video                                                     |
| 9195           | Delay echo test                                                             |
| 9196           | Standard echo test                                                          |
| 9197           | Milliwatt test tone                                                         |
| 9198           | Tone stream playback (e.g., Tetris)                                         |
| 9386           | Laugh break playback                                                        |
| 9664           | Auto outcall from conference (loopback test)                                |
| 0911 / 0912    | “Mad Boss” intercom with auto-answer calls to group                         |
| 0913           | “Mad Boss” intercom (no mute, basic mode)                                   |

> 🔁 **Pattern-based extensions:**
>
> - `^10[01][0-9]$`: Internal extensions range (1000–1019)
> - `^11[01][0-9]$`: Likely SKINNY SIP devices
> - `^3[5-8][01][0-9]$`: High-quality conference rooms (NB, WB, UWB, CD, etc.)
> - `^82\d{2}$`, `^83\d{2}$`: Group calls (simultaneous or ordered)
> - `^\*\*XXXX$`, `^\*8$`, `^886$`: Intercept call functions
> - `^(operator|0)$`: Operator access

---

You can use these built-in extensions for testing, training, and learning how FreeSWITCH routes calls via the default dialplan.


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
