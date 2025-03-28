#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Dialplan Migration Script for FreeSWITCH (from XML to PostgreSQL)
Author: Rodrigo Cuadra
Project: Ring2All

Description:
This script parses existing FreeSWITCH dialplan XML files and migrates the data to
PostgreSQL tables using an ODBC connection. It creates entries for contexts,
extensions, conditions, and actions. This version uses the `continue` flag from
the extension level, not the condition level.

Note: Ensure PostgreSQL has the correct schema and that FreeSWITCH ODBC is configured.
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

# Get default tenant ID
cursor.execute("SELECT id FROM core.tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("❌ Tenant 'Default' does not exist")
tenant_id = tenant_row[0]

# Current UTC timestamp
def now():
    return datetime.utcnow()

# Process dialplan XML files
def process_dialplan_file(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()

        context_name = os.path.splitext(os.path.basename(file_path))[0]
        context_id = str(uuid.uuid4())

        cursor.execute("""
            INSERT INTO core.dialplan_contexts (id, tenant_id, name, enabled, insert_date)
            VALUES (?, ?, ?, ?, ?)
        """, (context_id, tenant_id, context_name, True, now()))
        print(f"✅ Context '{context_name}' created")

        for ext_elem in root.findall(".//extension"):
            extension_id = str(uuid.uuid4())
            ext_name = ext_elem.get("name") or "unnamed"
            ext_continue = ext_elem.get("continue")
            ext_priority = ext_elem.get("priority")
            ext_priority = int(ext_priority) if ext_priority and ext_priority.isdigit() else 100

            cursor.execute("""
                INSERT INTO core.dialplan_extensions (id, context_id, name, priority, "continue", enabled, insert_date)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (extension_id, context_id, ext_name, ext_priority, ext_continue, True, now()))
            print(f"  ➕ Extension '{ext_name}' with priority {ext_priority}")

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

# Run migration
print("""
************************************************************
*       Migrate from XML to Database Dialplan.             *
************************************************************
""")

for dirpath, _, filenames in os.walk(DIALPLAN_DIR):
    for filename in filenames:
        if filename.endswith(".xml"):
            process_dialplan_file(os.path.join(dirpath, filename))

print("\n✅ Dialplan migration completed.")
