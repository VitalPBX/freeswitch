#!/usr/bin/env python3

import os
import uuid
import xml.etree.ElementTree as ET
import pyodbc
from datetime import datetime

# ODBC DSN connection name (must be pre-configured on the system)
ODBC_DSN = "ring2all"

# Path where FreeSWITCH SIP profile XML files are located
SIP_PROFILE_DIR = "/etc/freeswitch/sip_profiles"

# Collect all XML files from the directory
xml_files = [f for f in os.listdir(SIP_PROFILE_DIR) if f.endswith(".xml")]

# Connect to the database via ODBC
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Retrieve the tenant ID for the 'Default' tenant
cursor.execute("SELECT id FROM core.tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("❌ Tenant 'Default' does not exist in the database")
tenant_uuid = tenant_row[0]

# Begin processing each XML file
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

            # Get description from the profile attribute or preceding comment
            description = profile.get("description")

            # Fallback: Use previous sibling comment as description if no description attribute is set
            if not description:
                prev = profile.getprevious() if hasattr(profile, 'getprevious') else None
                if prev is not None and isinstance(prev, ET.Comment):
                    description = prev.text.strip()

            # Insert the SIP profile into the database
            cursor.execute("""
                INSERT INTO core.sip_profiles (
                    id, name, tenant_id, description, enabled,
                    insert_date
                ) VALUES (?, ?, ?, ?, ?, ?)
            """, (
                profile_id, profile_name, tenant_uuid, description, True,
                datetime.utcnow()
            ))
            print(f"✅ SIP Profile '{profile_name}' migrated successfully.")

            # Insert associated settings into core.sip_profile_settings
            settings = profile.find("settings")
            if settings is not None:
                setting_order = 0
                for param in settings.findall("param"):
                    setting_id = str(uuid.uuid4())
                    name = param.get("name")
                    value = param.get("value")
                    param_description = param.get("description")  # Attempt to read description from param

                    cursor.execute("""
                        INSERT INTO core.sip_profile_settings (
                            id, sip_profile_id, name, category, subcategory,
                            value, setting_order, description, enabled, insert_date
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        setting_id, profile_id, name, 'default', 'default',
                        value, setting_order, param_description, True, datetime.utcnow()
                    ))
                    print(f"   ➕ Setting '{name}' = '{value}' added.")
                    setting_order += 1

        # Commit all inserts after processing each file
        conn.commit()

    except Exception as e:
        print(f"❌ Error processing {file_name}: {e}")

# Close the connection when done
cursor.close()
conn.close()

print("✅ SIP Profile migration completed from /etc/freeswitch/sip_profiles.")
