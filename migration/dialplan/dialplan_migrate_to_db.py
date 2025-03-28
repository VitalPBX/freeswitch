#!/usr/bin/env python3

import os
import uuid
import xml.etree.ElementTree as ET
import pyodbc
from datetime import datetime

# Configuración
ODBC_DSN = "ring2all"
DIALPLAN_DIR = "/etc/freeswitch/dialplan"
IVR_DIR = "/etc/freeswitch/ivr_menus"

# Conexión a la base de datos
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Obtener tenant 'Default'
cursor.execute("SELECT id FROM core.tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("❌ Tenant 'Default' no existe")
tenant_id = tenant_row[0]

def now():
    return datetime.utcnow()

# Procesar archivos de dialplan
def process_dialplan_file(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()

        context_name = os.path.splitext(os.path.basename(file_path))[0]
        context_id = str(uuid.uuid4())

        # Insertar contexto
        cursor.execute("""
            INSERT INTO core.dialplan_contexts (id, tenant_id, name, enabled, insert_date)
            VALUES (?, ?, ?, ?, ?)
        """, (context_id, tenant_id, context_name, True, now()))
        print(f"✅ Contexto '{context_name}' creado")

        priority_counter = 0

        for ext_elem in root.findall(".//extension"):
            extension_id = str(uuid.uuid4())
            ext_name = ext_elem.get("name") or "unnamed"

            # Leer prioridad desde XML si existe, si no usar incremental
            xml_priority = ext_elem.get("priority")
            priority = int(xml_priority) if xml_priority and xml_priority.isdigit() else (priority_counter := priority_counter + 100)

            ext_continue = ext_elem.get("continue")
            ext_continue = ext_continue.lower() if ext_continue else None

            cursor.execute("""
                INSERT INTO core.dialplan_extensions (id, context_id, name, priority, "continue", enabled, insert_date)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (extension_id, context_id, ext_name, priority, ext_continue, True, now()))
            print(f"  ➕ Extension '{ext_name}' con prioridad {priority}")

            for cond_elem in ext_elem.findall("condition"):
                condition_id = str(uuid.uuid4())
                field = cond_elem.get("field") or "true"
                expression = cond_elem.get("expression") or ".*"
                cond_continue = cond_elem.get("continue")
                cursor.execute("""
                    INSERT INTO core.dialplan_conditions (id, extension_id, field, expression, enabled, "continue", insert_date)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (condition_id, extension_id, field, expression, True, cond_continue, now()))

                for action_elem in cond_elem.findall("action"):
                    action_id = str(uuid.uuid4())
                    app = action_elem.get("application")
                    data = action_elem.get("data")
                    cursor.execute("""
                        INSERT INTO core.dialplan_actions (id, condition_id, application, data, type, sequence, insert_date)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, (action_id, condition_id, app, data, 'action', 0, now()))

                for anti_elem in cond_elem.findall("anti-action"):
                    anti_id = str(uuid.uuid4())
                    app = anti_elem.get("application")
                    data = anti_elem.get("data")
                    cursor.execute("""
                        INSERT INTO core.dialplan_actions (id, condition_id, application, data, type, sequence, insert_date)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, (anti_id, condition_id, app, data, 'anti-action', 0, now()))

        conn.commit()
    except Exception as e:
        print(f"❌ Error procesando {file_path}: {e}")

# Procesar archivos de IVR
def process_ivr_file(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()

        for menu in root.findall(".//menu"):
            ivr_name = menu.get("name") or os.path.splitext(os.path.basename(file_path))[0]
            ivr_id = str(uuid.uuid4())

            cursor.execute("""
                INSERT INTO core.ivr (
                    id, tenant_id, name, greet_long, greet_short,
                    invalid_sound, exit_sound, timeout, max_failures,
                    max_timeouts, direct_dial, enabled, insert_date
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                ivr_id, tenant_id, ivr_name,
                menu.get("greet-long"), menu.get("greet-short"),
                menu.get("invalid-sound"), menu.get("exit-sound"),
                int(menu.get("timeout") or 5), int(menu.get("max-failures") or 3),
                int(menu.get("max-timeouts") or 3), menu.get("direct-dial") == "true",
                True, now()
            ))
            print(f"✅ IVR '{ivr_name}' creado")

            for entry in menu.findall("entry"):
                digits = entry.get("digits")
                action = entry.get("action")
                dest = entry.get("param") or entry.get("destination")
                condition = entry.get("condition")

                if not digits or not action:
                    print(f"⚠️ Entrada IVR incompleta en {file_path}")
                    continue

                setting_id = str(uuid.uuid4())
                cursor.execute("""
                    INSERT INTO core.ivr_settings (
                        id, ivr_id, digits, action, destination, condition,
                        break_on_match, priority, enabled, insert_date
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    setting_id, ivr_id, digits, action, dest, condition,
                    False, 100, True, now()
                ))
                print(f"  ➕ DTMF '{digits}' → {action} ({dest})")

        conn.commit()
    except Exception as e:
        print(f"❌ Error procesando IVR {file_path}: {e}")

# Ejecutar migración
for dirpath, _, filenames in os.walk(DIALPLAN_DIR):
    for filename in filenames:
        if filename.endswith(".xml"):
            process_dialplan_file(os.path.join(dirpath, filename))

for dirpath, _, filenames in os.walk(IVR_DIR):
    for filename in filenames:
        if filename.endswith(".xml"):
            process_ivr_file(os.path.join(dirpath, filename))

cursor.close()
conn.close()
print("\n✅ Migración de Dialplan e IVR completada.")
