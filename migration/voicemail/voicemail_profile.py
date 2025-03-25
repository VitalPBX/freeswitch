#!/usr/bin/env python3

import xml.etree.ElementTree as ET
import pyodbc
import uuid
from datetime import datetime

# Configuration
ODBC_DSN = "ring2all"
VOICEMAIL_CONF = "/etc/freeswitch/autoload_configs/voicemail.conf.xml"

# Connect to the database
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Retrieve tenant UUID for 'Default'
cursor.execute("SELECT id FROM core.tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("❌ Tenant 'Default' not found")
tenant_uuid = tenant_row[0]

# Utility: current timestamp
def now():
    return datetime.utcnow()

# Parse voicemail config XML and insert into database
def migrate_voicemail_profiles(xml_path):
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()

        for profile_elem in root.findall(".//profile"):
            profile_name = profile_elem.get("name")
            if not profile_name:
                print("⚠️  Skipping profile without a name.")
                continue

            profile_id = str(uuid.uuid4())

            # Insert voicemail profile
            cursor.execute("""
                INSERT INTO core.voicemail_profiles (
                    id, tenant_id, name, enabled, insert_date
                ) VALUES (?, ?, ?, ?, ?)
            """, (profile_id, tenant_uuid, profile_name, True, now()))
            print(f"✅ Voicemail profile '{profile_name}' created")

            # Insert profile settings
            for param in profile_elem.findall("param"):
                setting_id = str(uuid.uuid4())
                name = param.get("name")
                value = param.get("value")

                cursor.execute("""
                    INSERT INTO core.voicemail_profile_settings (
                        id, voicemail_profile_id, name, value, type, enabled, insert_date
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (setting_id, profile_id, name, value, 'param', True, now()))
                print(f"   ➕ Setting '{name}' = '{value}'")

        conn.commit()
    except Exception as e:
        print(f"❌ Error processing voicemail config: {e}")

# Run migration
migrate_voicemail_profiles(VOICEMAIL_CONF)

# Close connection
cursor.close()
conn.close()
print("\n✅ Voicemail configuration migration completed.")
