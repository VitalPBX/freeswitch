import xml.etree.ElementTree as ET
import uuid
import pyodbc
from datetime import datetime

# Configuración ODBC
ODBC_DSN = "ring2all"
XML_PATH = "/etc/freeswitch/autoload_configs/conference.conf.xml"

# Conexión a la base de datos
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Obtener tenant_uuid del tenant Default
cursor.execute("SELECT tenant_uuid FROM tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("El tenant 'Default' no existe en la base de datos")
tenant_uuid = tenant_row[0]

def migrate_conference_profiles(xml_path):
    tree = ET.parse(xml_path)
    root = tree.getroot()

    for profile in root.findall(".//profile"):
        profile_name = profile.attrib.get("name")
        if not profile_name:
            continue

        room_id = str(uuid.uuid4())

        # Insertar una sala por perfil
        cursor.execute("""
            INSERT INTO core.conference_rooms (
                id, tenant_id, name, profile, enabled, insert_date
            ) VALUES (?, ?, ?, ?, ?, ?)
        """, (room_id, tenant_uuid, profile_name, profile_name, True, datetime.utcnow()))

        # Insertar configuraciones del perfil
        for param in profile.findall("param"):
            param_name = param.attrib.get("name")
            param_value = param.attrib.get("value")
            if param_name and param_value:
                setting_id = str(uuid.uuid4())
                cursor.execute("""
                    INSERT INTO core.conference_room_settings (
                        id, conference_room_id, name, value, setting_type, insert_date
                    ) VALUES (?, ?, ?, ?, ?, ?)
                """, (setting_id, room_id, param_name, param_value, 'media', datetime.utcnow()))

        print(f"Perfil de conferencia '{profile_name}' migrado correctamente.")
        conn.commit()

migrate_conference_profiles(XML_PATH)
cursor.close()
conn.close()
print("Migración de perfiles de conferencia completada.")
