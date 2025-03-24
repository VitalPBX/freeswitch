#!/usr/bin/env python3

import os
import uuid
import xml.etree.ElementTree as ET
import pyodbc
from datetime import datetime

# Configuration for ODBC DSN (must be set up in your system)
ODBC_DSN = "ring2all"

# Path to the SIP profiles directory in FreeSWITCH
SIP_PROFILE_DIR = "/etc/freeswitch/sip_profiles"

# Collect all XML files from the SIP profiles directory
xml_files = [f for f in os.listdir(SIP_PROFILE_DIR) if f.endswith(".xml")]

# Function to extract port from the bind-address field (e.g., 0.0.0.0:5060)
def extract_port(bind_address):
    if ":" in bind_address:
        return int(bind_address.split(":")[-1])
    return None

# Connect to the database using ODBC DSN
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Retrieve tenant ID for the Default tenant
cursor.execute("SELECT id FROM core.tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("❌ Tenant 'Default' does not exist in the database")
tenant_uuid = tenant_row[0]

# Loop through each XML file found
for file_name in xml_files:
    path = os.path.join(SIP_PROFILE_DIR, file_name)
    try:
        tree = ET.parse(path)
        root = tree.getroot()

        # Loop through each <profile> in the XML
        for profile in root.findall(".//profile"):
            profile_id = str(uuid.uuid4())
            profile_name = profile.get("name")
            settings = profile.find("settings")

            # Default fields for the main sip_profiles table
            bind_address = None
            sip_port = None
            transport = None
            tls_enabled = False

            # Extract key fields from <param> tags
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

            # Insert SIP profile into core.sip_profiles
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

            # Insert all <param> elements as settings in core.sip_profile_settings
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

        conn.commit()

    except Exception as e:
        print(f"❌ Error processing {file_name}: {e}")

# Close the DB connection
cursor.close()
conn.close()

# Final confirmation
print("✅ SIP Profile migration completed from /etc/freeswitch/sip_profiles.")
