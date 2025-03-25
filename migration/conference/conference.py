#!/usr/bin/env python3

import xml.etree.ElementTree as ET
import uuid
import pyodbc
from datetime import datetime

# Configuration
ODBC_DSN = "ring2all"
XML_PATH = "/etc/freeswitch/autoload_configs/conference.conf.xml"

# Connect to the database
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Retrieve tenant UUID for 'Default'
cursor.execute("SELECT id FROM core.tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("❌ Tenant 'Default' does not exist in the database")
tenant_uuid = tenant_row[0]

# Current UTC time generator
def now():
    return datetime.utcnow()

# Migration logic for conference profiles
def migrate_conference_profiles(xml_path):
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()

        for profile in root.findall(".//profile"):
            profile_name = profile.attrib.get("name")
            if not profile_name:
                print("⚠️  Skipping profile without a name.")
                continue

            room_id = str(uuid.uuid4())

            # Insert one conference room per profile
            cursor.execute("""
                INSERT INTO core.conference_rooms (
                    id, tenant_id, name, profile, enabled, insert_date
                ) VALUES (?, ?, ?, ?, ?, ?)
            """, (room_id, tenant_uuid, profile_name, profile_name, True, now()))
            print(f"✅ Conference profile '{profile_name}' inserted as room")

            # Insert profile parameters as room settings
            for param in profile.findall("param"):
                param_name = param.attrib.get("name")
                param_value = param.attrib.get("value")

                if param_name and param_value:
                    setting_id = str(uuid.uuid4())
                    cursor.execute("""
                        INSERT INTO core.conference_room_settings (
                            id, conference_room_id, name, value, setting_type, insert_date
                        ) VALUES (?, ?, ?, ?, ?, ?)
                    """, (setting_id, room_id, param_name, param_value, 'media', now()))
                    print(f"   ➕ Setting '{param_name}' = '{param_value}'")

            conn.commit()

    except Exception as e:
        print(f"❌ Error processing conference profiles: {e}")

# Run migration
migrate_conference_profiles(XML_PATH)

# Close database connection
cursor.close()
conn.close()
print("\n✅ Conference profile migration completed.")
