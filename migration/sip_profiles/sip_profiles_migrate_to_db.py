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

# Utility function to extract port number from bind-address string
def extract_port(bind_address):
    if ":" in bind_address:
        return int(bind_address.split(":")[-1])
    return None

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

        # Handle both root as <profile> or <include> with nested <profile>
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
            settings = profile.find("settings")

            if not profile_name:
                print(f"⚠️  Profile without name in {file_name}, skipping...")
                continue

            bind_address = None
            sip_port = None
            transport = None
            tls_enabled = False

            # Extract relevant fields from the <param> tags
            if settings is not None:
                for param in settings.findall("param"):
                    name = param.get("name")
                    value = param.get("value")
                    if name == "bind-address":
                        bind_address = value
                        sip_port = extract_port(value)
                    elif name == "transport":
                        transport = value
                    elif name == "tls":
                        tls_enabled = value.lower() == "true"

            # Insert the SIP profile into the database
            cursor.execute("""
                INSERT INTO core.sip_profiles (
                    id, name, tenant_id, description, enabled,
                    bind_address, sip_port, transport, tls_enabled,
                    insert_date
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                profile_id, profile_name, tenant_uuid, None, True,
                bind_address, sip_port, transport, tls_enabled,
                datetime.utcnow()
            ))
            print(f"✅ SIP Profile '{profile_name}' migrated successfully.")

            # Insert associated settings into core.sip_profile_settings
            if settings is not None:
                for param in settings.findall("param"):
                    setting_id = str(uuid.uuid4())
                    name = param.get("name")
                    value = param.get("value")

                    cursor.execute("""
                        INSERT INTO core.sip_profile_settings (
                            id, sip_profile_id, name, type, value, enabled, insert_date
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, (
                        setting_id, profile_id, name, None, value, True, datetime.utcnow()
                    ))
                    print(f"   ➕ Setting '{name}' = '{value}' added.")

        # Commit all inserts after processing each file
        conn.commit()

    except Exception as e:
        print(f"❌ Error processing {file_name}: {e}")

# Close the connection when done
cursor.close()
conn.close()

print("✅ SIP Profile migration completed from /etc/freeswitch/sip_profiles.")
