#!/usr/bin/env python3

"""
SIP Profile Migration Script

This script parses SIP profile XML files from a FreeSWITCH installation and inserts
profile and setting data into a PostgreSQL database using pyodbc and an ODBC DSN.

It maps <profile> entries from XML to rows in `core.sip_profiles`, and <param> elements
within <settings> to `core.sip_profile_settings`. It sets the "category" to 'sofia' to
ensure only SIP profiles are loaded by the Lua handler, and "setting_type" to 'setting'
for all entries in the context of SIP profiles.

Author: Rodrigo Cuadra
Project: Ring2All
"""

import os
import uuid
import xml.etree.ElementTree as ET
import pyodbc
from datetime import datetime

# ------------------------ Configuration ------------------------ #
# ODBC DSN connection name (must be pre-configured on the system)
ODBC_DSN = "ring2all"

# Path where FreeSWITCH SIP profile XML files are located
SIP_PROFILE_DIR = "/etc/freeswitch/sip_profiles"

# ---------------------- Load XML Files ------------------------ #
xml_files = [f for f in os.listdir(SIP_PROFILE_DIR) if f.endswith(".xml")]

# ------------------- Connect to Database ---------------------- #
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Retrieve the tenant ID for the 'Default' tenant
cursor.execute("SELECT id FROM core.tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("❌ Tenant 'Default' does not exist in the database")
tenant_uuid = tenant_row[0]

# ------------------- Process Each XML File -------------------- #
for file_name in xml_files:
    path = os.path.join(SIP_PROFILE_DIR, file_name)
    try:
        tree = ET.parse(path)
        root = tree.getroot()

        profiles = []
        if root.tag == "profile":
            profiles.append(root)
        else:
            profiles = root.findall(".//profile")

        if not profiles:
            print(f"⚠️  No SIP profiles found in {file_name}")
            continue

        for profile in profiles:
            profile_id = str(uuid.uuid4())
            profile_name = profile.get("name")

            if not profile_name:
                print(f"⚠️  Profile without name in {file_name}, skipping...")
                continue

            # Use profile description or generate one from file name
            description = profile.get("description") or f"Migrated profile from {file_name}"

            # Insert SIP profile
            cursor.execute("""
                INSERT INTO core.sip_profiles (
                    id, name, tenant_id, description, category, enabled, insert_date
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                profile_id, profile_name, tenant_uuid, description, 'sofia', True,
                datetime.utcnow()
            ))
            print(f"✅ SIP Profile '{profile_name}' migrated successfully.")

            # Insert <param> settings as profile settings
            settings = profile.find("settings")
            if settings is not None:
                setting_order = 0
                for param in settings.findall("param"):
                    setting_id = str(uuid.uuid4())
                    name = param.get("name")
                    value = param.get("value")
                    param_description = param.get("description") or f"Imported from {file_name}"

                    # All SIP profile params are treated as 'setting' type
                    setting_type = "setting"

                    # Insert setting
                    cursor.execute("""
                        INSERT INTO core.sip_profile_settings (
                            id, sip_profile_id, name, category, setting_type, subcategory,
                            value, setting_order, description, enabled, insert_date
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        setting_id, profile_id, name, 'sofia', setting_type, 'default',
                        value, setting_order, param_description, True, datetime.utcnow()
                    ))
                    print(f"   ➕ Setting '{name}' = '{value}' added as {setting_type}.")
                    setting_order += 1

        # Commit after each file
        conn.commit()

    except Exception as e:
        print(f"❌ Error processing {file_name}: {e}")

# ------------------------ Cleanup ---------------------------- #
cursor.close()
conn.close()

print("✅ SIP Profile migration completed from /etc/freeswitch/sip_profiles.")
