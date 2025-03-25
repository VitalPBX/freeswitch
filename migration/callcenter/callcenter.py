#!/usr/bin/env python3

import xml.etree.ElementTree as ET
import uuid
import pyodbc
from datetime import datetime

# Configuration
ODBC_DSN = "ring2all"
XML_PATH = "/etc/freeswitch/autoload_configs/callcenter.conf.xml"

# Connect to the database
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Retrieve tenant UUID
cursor.execute("SELECT id FROM core.tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("❌ Tenant 'Default' does not exist in the database")
tenant_uuid = tenant_row[0]

# Utility: current timestamp
def now():
    return datetime.utcnow()

# Helper: find SIP user ID from extension
def get_user_id_by_extension(extension):
    cursor.execute("""
        SELECT id FROM core.sip_users
        WHERE username = ? AND tenant_id = ?
    """, (extension, tenant_uuid))
    row = cursor.fetchone()
    return row[0] if row else None

# Main migration logic
def migrate_callcenter(xml_path):
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()

        for queue_elem in root.findall(".//queue"):
            name = queue_elem.attrib.get("name")
            if not name:
                print("⚠️  Skipping queue without name")
                continue

            queue_name = name.split("@")[0].strip()
            queue_id = str(uuid.uuid4())

            # Insert queue into call_center_queues
            cursor.execute("""
                INSERT INTO core.call_center_queues (
                    id, tenant_id, name, enabled, insert_date
                ) VALUES (?, ?, ?, ?, ?)
            """, (queue_id, tenant_uuid, queue_name, True, now()))
            print(f"✅ Queue '{queue_name}' created")

            # Insert queue settings
            for param in queue_elem.findall("param"):
                param_name = param.attrib.get("name")
                param_value = param.attrib.get("value")
                if param_name:
                    setting_id = str(uuid.uuid4())
                    cursor.execute("""
                        INSERT INTO core.call_center_queue_settings (
                            id, queue_id, name, value, setting_type, insert_date
                        ) VALUES (?, ?, ?, ?, ?, ?)
                    """, (setting_id, queue_id, param_name, param_value, 'behavior', now()))
                    print(f"   ➕ Param '{param_name}' = '{param_value}'")

            # Insert agents and tiers
            for agent_elem in queue_elem.findall("agent"):
                agent_name = agent_elem.attrib.get("name")
                if not agent_name:
                    print("⚠️  Skipping agent without name")
                    continue

                user_id = get_user_id_by_extension(agent_name)
                agent_id = str(uuid.uuid4())

                cursor.execute("""
                    INSERT INTO core.call_center_agents (
                        id, tenant_id, user_id, contact, status, ready, enabled, insert_date
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    agent_id, tenant_uuid, user_id, agent_name,
                    "Logged Out", False, True, now()
                ))
                print(f"   ✅ Agent '{agent_name}' inserted")

                tier_id = str(uuid.uuid4())
                cursor.execute("""
                    INSERT INTO core.call_center_tiers (
                        id, queue_id, agent_id, level, position, insert_date
                    ) VALUES (?, ?, ?, ?, ?, ?)
                """, (tier_id, queue_id, agent_id, 1, 1, now()))
                print(f"      ➕ Tier created for agent '{agent_name}'")

            conn.commit()

    except Exception as e:
        print(f"❌ Error processing call center config: {e}")

# Run migration
migrate_callcenter(XML_PATH)

# Close connection
cursor.close()
conn.close()
print("\n✅ Call Center migration completed.")
