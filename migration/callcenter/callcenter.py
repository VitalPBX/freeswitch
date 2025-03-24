import xml.etree.ElementTree as ET
import uuid
import pyodbc
from datetime import datetime

# Configuración ODBC
ODBC_DSN = "ring2all"
XML_PATH = "/etc/freeswitch/autoload_configs/callcenter.conf.xml"

# Conexión a la base de datos
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Obtener tenant_uuid del tenant Default
cursor.execute("SELECT tenant_uuid FROM tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("El tenant 'Default' no existe en la base de datos")
tenant_uuid = tenant_row[0]

def get_user_id_by_extension(extension):
    cursor.execute("""
        SELECT id FROM core.sip_users
        WHERE username = ? AND tenant_id = ?
    """, (extension, tenant_uuid))
    row = cursor.fetchone()
    return row[0] if row else None

def migrate_callcenter(xml_path):
    tree = ET.parse(xml_path)
    root = tree.getroot()

    for queue_elem in root.findall(".//queue"):
        name = queue_elem.attrib.get("name")
        if not name:
            continue

        name_parts = name.split("@")
        queue_name = name_parts[0].strip()

        queue_id = str(uuid.uuid4())

        # Insertar cola en core.call_center_queues
        cursor.execute("""
            INSERT INTO core.call_center_queues (
                id, tenant_id, name, enabled, insert_date
            ) VALUES (?, ?, ?, ?, ?)
        """, (queue_id, tenant_uuid, queue_name, True, datetime.utcnow()))

        for param in queue_elem.findall("param"):
            param_name = param.attrib.get("name")
            param_value = param.attrib.get("value")
            if param_name:
                setting_id = str(uuid.uuid4())
                cursor.execute("""
                    INSERT INTO core.call_center_queue_settings (
                        id, queue_id, name, value, setting_type, insert_date
                    ) VALUES (?, ?, ?, ?, ?, ?)
                """, (setting_id, queue_id, param_name, param_value, 'behavior', datetime.utcnow()))

        # Procesar agentes
        for agent_elem in queue_elem.findall("agent"):
            agent_name = agent_elem.attrib.get("name")
            if agent_name:
                user_id = get_user_id_by_extension(agent_name)
                agent_id = str(uuid.uuid4())
                cursor.execute("""
                    INSERT INTO core.call_center_agents (
                        id, tenant_id, user_id, contact, status, ready, enabled, insert_date
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    agent_id, tenant_uuid, user_id, agent_name, "Logged Out", False, True, datetime.utcnow()
                ))

                # Insertar relación tier
                tier_id = str(uuid.uuid4())
                cursor.execute("""
                    INSERT INTO core.call_center_tiers (
                        id, queue_id, agent_id, level, position, insert_date
                    ) VALUES (?, ?, ?, ?, ?, ?)
                """, (tier_id, queue_id, agent_id, 1, 1, datetime.utcnow()))

        print(f"Cola '{queue_name}' y sus agentes migrados correctamente.")
        conn.commit()

migrate_callcenter(XML_PATH)
cursor.close()
conn.close()
print("Migración de cola de Call Center completada.")
