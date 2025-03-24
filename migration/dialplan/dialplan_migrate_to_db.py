import os
import uuid
import pyodbc
import xml.etree.ElementTree as ET
from datetime import datetime

# Configuración ODBC
ODBC_DSN = "ring2all"
BASE_PATHS = [
    "/etc/freeswitch/dialplan",
    "/etc/freeswitch/ivr_menus"
]

# Conexión a la base de datos
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Obtener tenant_uuid del tenant Default
cursor.execute("SELECT tenant_uuid FROM tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("El tenant 'Default' no existe en la base de datos")
tenant_uuid = tenant_row[0]

def migrate_dialplan_from_file(xml_path):
    tree = ET.parse(xml_path)
    root = tree.getroot()

    for context in root.findall(".//context"):
        context_name = context.attrib.get("name")
        if not context_name:
            continue

        dialplan_id = str(uuid.uuid4())
        cursor.execute("""
            INSERT INTO core.dialplan (
                id, tenant_id, name, context, enabled, insert_date
            ) VALUES (?, ?, ?, ?, ?, ?)
        """, (dialplan_id, tenant_uuid, context_name, context_name, True, datetime.utcnow()))

        for extension in context.findall("extension"):
            for condition in extension.findall("condition"):
                condition_field = condition.attrib.get("field")
                condition_expression = condition.attrib.get("expression")
                setting_id = str(uuid.uuid4())
                cursor.execute("""
                    INSERT INTO core.dialplan_settings (
                        id, dialplan_id, name, value, type, enabled, insert_date
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (setting_id, dialplan_id, condition_field, condition_expression, "condition", True, datetime.utcnow()))

                for action in condition.findall("action"):
                    action_application = action.attrib.get("application")
                    action_data = action.attrib.get("data")
                    setting_id = str(uuid.uuid4())
                    cursor.execute("""
                        INSERT INTO core.dialplan_settings (
                            id, dialplan_id, name, value, type, enabled, insert_date
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, (setting_id, dialplan_id, action_application, action_data, "action", True, datetime.utcnow()))

                for anti_action in condition.findall("anti-action"):
                    anti_app = anti_action.attrib.get("application")
                    anti_data = anti_action.attrib.get("data")
                    setting_id = str(uuid.uuid4())
                    cursor.execute("""
                        INSERT INTO core.dialplan_settings (
                            id, dialplan_id, name, value, type, enabled, insert_date
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, (setting_id, dialplan_id, anti_app, anti_data, "anti-action", True, datetime.utcnow()))

        print(f"Contexto '{context_name}' migrado correctamente desde {os.path.basename(xml_path)}")
        conn.commit()

for base_path in BASE_PATHS:
    for root_dir, _, files in os.walk(base_path):
        for file in files:
            if file.endswith(".xml"):
                migrate_dialplan_from_file(os.path.join(root_dir, file))

cursor.close()
conn.close()
print("Migración de dialplans y IVRs completada.")
