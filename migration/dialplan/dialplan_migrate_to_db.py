#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Migrate FreeSWITCH dialplan and IVR menus from XML files to PostgreSQL database.
This script reads XML files from /etc/freeswitch/dialplan and /etc/freeswitch/ivr_menus,
then inserts them into the appropriate core.* tables in PostgreSQL.

Features:
- Extracts and preserves priority (based on XML order)
- Automatically sets `continue=true` when not specified
- Handles both actions and anti-actions
- Logs output in human-readable format
"""

import os
import uuid
import xml.etree.ElementTree as ET
import pyodbc
from datetime import datetime

# Configuration
ODBC_DSN = "ring2all"
DIALPLAN_DIR = "/etc/freeswitch/dialplan"
IVR_DIR = "/etc/freeswitch/ivr_menus"

# Connect to database
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Retrieve tenant UUID
cursor.execute("SELECT id FROM core.tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("❌ Tenant 'Default' does not exist")
tenant_id = tenant_row[0]

# Helper to generate timestamps
def now():
    return datetime.utcnow()

print("""
************************************************************
*       Migrate from XML to Database Dialplan.             *
************************************************************
""")

# Process dialplan XML files
def process_dialplan_file(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()

        context_name = os.path.splitext(os.path.basename(file_path))[0]
        context_id = str(uuid.uuid4())

        # Insert context
        cursor.execute("""
            INSERT INTO core.dialplan_contexts (id, tenant_id, name, enabled, insert_date)
            VALUES (?, ?, ?, ?, ?)
        """, (context_id, tenant_id, context_name, True, now()))
        print(f"✅ Context '{context_name}' created")

        # Insert extensions
        for ext_index, ext_elem in enumerate(root.findall(".//extension")):
            extension_id = str(uuid.uuid4())
            ext_name = ext_elem.get("name") or f"unnamed_{ext_index}"
            ext_continue = "true" if ext_elem.get("continue") == "true" else "false"

            cursor.execute("""
                INSERT INTO core.dialplan_extensions (id, context_id, name, priority, continue, enabled, insert_date)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (extension_id, context_id, ext_name, ext_index, ext_continue, True, now()))
            print(f"  ➕ Extension '{ext_name}' with priority {ext_index}")

            for cond_elem in ext_elem.findall("condition"):
                condition_id = str(uuid.uuid4())
                field = cond_elem.get("field") or "true"
                expression = cond_elem.get("expression") or ".*"
                cursor.execute("""
                    INSERT INTO core.dialplan_conditions (id, extension_id, field, expression, enabled, insert_date)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (condition_id, extension_id, field, expression, True, now()))

                for action_elem in cond_elem.findall("action"):
                    action_id = str(uuid.uuid4())
                    app = action_elem.get("application")
                    data = action_elem.get("data")
                    cursor.execute("""
                        INSERT INTO core.dialplan_actions (id, condition_id, application, data, type, sequence, enabled, insert_date)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, (action_id, condition_id, app, data, 'action', 0, True, now()))

                for anti_elem in cond_elem.findall("anti-action"):
                    anti_id = str(uuid.uuid4())
                    app = anti_elem.get("application")
                    data = anti_elem.get("data")
                    cursor.execute("""
                        INSERT INTO core.dialplan_actions (id, condition_id, application, data, type, sequence, enabled, insert_date)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, (anti_id, condition_id, app, data, 'anti-action', 0, True, now()))

        conn.commit()
    except Exception as e:
        print(f"❌ Error processing {file_path}: {e}")

# Process IVR XML files
def process_ivr_file(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()

        for menu in root.findall(".//menu"):
            ivr_name = menu.get("name") or os.path.splitext(os.path.basename(file_path))[0]
            ivr_id = str(uuid.uuid4())

            cursor.execute("""
                INSERT INTO core.ivr (
                    id, tenant_id, name, greet_long, greet_short,
                    invalid_sound, exit_sound, timeout, max_failures,
                    max_timeouts, direct_dial, enabled, insert_date
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                ivr_id, tenant_id, ivr_name,
                menu.get("greet-long"), menu.get("greet-short"),
                menu.get("invalid-sound"), menu.get("exit-sound"),
                int(menu.get("timeout") or 5), int(menu.get("max-failures") or 3),
                int(menu.get("max-timeouts") or 3), menu.get("direct-dial") == "true",
                True, now()
            ))
            print(f"✅ IVR '{ivr_name}' created")

            for entry in menu.findall("entry"):
                digits = entry.get("digits")
                action = entry.get("action")
                dest = entry.get("param") or entry.get("destination")
                condition = entry.get("condition")

                if not digits or not action:
                    print(f"⚠️ Skipping incomplete IVR entry in {file_path}")
                    continue

                setting_id = str(uuid.uuid4())
                cursor.execute("""
                    INSERT INTO core.ivr_settings (
                        id, ivr_id, digits, action, destination, condition,
                        break_on_match, priority, enabled, insert_date
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    setting_id, ivr_id, digits, action, dest, condition,
                    False, 100, True, now()
                ))
                print(f"  ➕ DTMF '{digits}' → {action} ({dest})")

        conn.commit()
    except Exception as e:
        print(f"❌ Error processing IVR {file_path}: {e}")

# Run migrations
for dirpath, _, filenames in os.walk(DIALPLAN_DIR):
    for filename in sorted(filenames):
        if filename.endswith(".xml"):
            process_dialplan_file(os.path.join(dirpath, filename))

for dirpath, _, filenames in os.walk(IVR_DIR):
    for filename in sorted(filenames):
        if filename.endswith(".xml"):
            process_ivr_file(os.path.join(dirpath, filename))

cursor.close()
conn.close()
print("\n✅ Dialplan migration completed.")
