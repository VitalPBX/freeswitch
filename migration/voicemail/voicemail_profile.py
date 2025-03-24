# Python: migrate_voicemail_conf.py

import xml.etree.ElementTree as ET
import pyodbc
import uuid
from datetime import datetime

ODBC_DSN = "ring2all"
VOICEMAIL_CONF = "/etc/freeswitch/voicemail.conf.xml"

conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Get tenant UUID for 'Default'
cursor.execute("SELECT tenant_uuid FROM tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("Tenant 'Default' not found")
tenant_uuid = tenant_row[0]

tree = ET.parse(VOICEMAIL_CONF)
root = tree.getroot()

for profile_elem in root.findall(".//profile"):
    profile_name = profile_elem.get("name")
    if not profile_name:
        continue

    # Insert voicemail profile
    profile_id = str(uuid.uuid4())
    cursor.execute("""
        INSERT INTO core.voicemail_profiles (
            id, tenant_id, name, enabled, insert_date
        ) VALUES (?, ?, ?, ?, ?)
    """, (profile_id, tenant_uuid, profile_name, True, datetime.utcnow()))

    # Insert settings
    for param in profile_elem.findall("param"):
        setting_id = str(uuid.uuid4())
        name = param.get("name")
        value = param.get("value")
        cursor.execute("""
            INSERT INTO core.voicemail_profile_settings (
                id, voicemail_profile_id, name, value, type, enabled, insert_date
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (setting_id, profile_id, name, value, 'param', True, datetime.utcnow()))

conn.commit()
cursor.close()
conn.close()
print("Migración de voicemail.conf.xml completada.")
