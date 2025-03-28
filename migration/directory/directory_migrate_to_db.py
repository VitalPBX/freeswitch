#!/usr/bin/env python3

import os
import uuid
import xml.etree.ElementTree as ET
import pyodbc
from datetime import datetime

# ODBC DSN configuration
ODBC_DSN = "ring2all"
DIRECTORY_PATH = "/etc/freeswitch/directory"

# Connect to the database
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Get tenant ID
cursor.execute("SELECT id FROM core.tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("❌ Tenant 'Default' does not exist in the database")
tenant_uuid = tenant_row[0]

def process_user_file(xml_file):
    try:
        tree = ET.parse(xml_file)
        root = tree.getroot()
    except Exception as e:
        print(f"❌ Error parsing {xml_file}: {e}")
        return

    for user_elem in root.findall(".//user"):
        username = user_elem.get("id")
        if not username:
            continue

        password = user_elem.findtext('params/param[@name="password"]')
        if not password:
            print(f"⚠️ User {username} has no password, assigning default 'r2a1234'.")
            password = "r2a1234"

        settings = [("password", "param", password)]
        voicemail = {}

        for param in user_elem.findall(".//param"):
            name = param.get("name")
            value = param.get("value")
            if name and value and name != "password":
                settings.append((name, "param", value))

        for variable in user_elem.findall(".//variable"):
            name = variable.get("name")
            value = variable.get("value")
            if name and value:
                settings.append((name, "variable", value))
                if name in ["vm-password", "vm-email"]:
                    voicemail[name] = value

        cursor.execute(
            "SELECT id FROM core.sip_users WHERE username = ? AND tenant_id = ?",
            (username, tenant_uuid)
        )
        row = cursor.fetchone()
        if row:
            user_id = row[0]
            print(f"➖ User {username} already exists. Updating settings...")
            cursor.execute("DELETE FROM core.sip_user_settings WHERE sip_user_id = ?", (user_id,))
        else:
            user_id = str(uuid.uuid4())
            cursor.execute("""
                INSERT INTO core.sip_users (
                    id, tenant_id, username, password, enabled, insert_date
                ) VALUES (?, ?, ?, ?, ?, ?)
            """, (user_id, tenant_uuid, username, password, True, datetime.utcnow()))
            print(f"✅ User {username} created.")

        for name, setting_type, value in settings:
            setting_id = str(uuid.uuid4())
            cursor.execute("""
                INSERT INTO core.sip_user_settings (
                    id, sip_user_id, name, type, value, enabled, insert_date
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (setting_id, user_id, name, setting_type, value, True, datetime.utcnow()))

        if voicemail:
            cursor.execute("SELECT 1 FROM core.voicemail WHERE sip_user_id = ?", (user_id,))
            if not cursor.fetchone():
                voicemail_id = str(uuid.uuid4())
                cursor.execute("""
                    INSERT INTO core.voicemail (
                        id, sip_user_id, tenant_id, password, email, enabled, insert_date
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (
                    voicemail_id, user_id, tenant_uuid,
                    voicemail.get("vm-password", "0000"),
                    voicemail.get("vm-email", None),
                    True, datetime.utcnow()
                ))

        conn.commit()
        print(f"✅ User {username} migrated successfully from {xml_file}.")

def migrate_directory():
    for dirpath, _, filenames in os.walk(DIRECTORY_PATH):
        for filename in filenames:
            if filename.endswith(".xml"):
                full_path = os.path.join(dirpath, filename)
                process_user_file(full_path)

# Run
migrate_directory()
cursor.close()
conn.close()
print("✅ SIP user migration completed.")
