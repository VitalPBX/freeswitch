#!/usr/bin/env python3

import os
import uuid
import xml.etree.ElementTree as ET
import pyodbc
from datetime import datetime

# Configuración de conexión ODBC
ODBC_DSN = "ring2all"
DIRECTORY_PATH = "/etc/freeswitch/directory"

# Conexión a la base de datos
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Obtener tenant_uuid del tenant Default
cursor.execute("SELECT tenant_uuid FROM tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("El tenant 'Default' no existe en la base de datos")
tenant_uuid = tenant_row[0]

# Buscar todos los archivos XML en /etc/freeswitch/directory y subdirectorios
xml_files = []
for root_dir, _, files in os.walk(DIRECTORY_PATH):
    for file in files:
        if file.endswith(".xml"):
            xml_files.append(os.path.join(root_dir, file))

for file_path in xml_files:
    tree = ET.parse(file_path)
    root = tree.getroot()

    for user_el in root.findall("./user"):
        user_id = str(uuid.uuid4())
        username = user_el.get("id")
        password = None
        voicemail_enabled = False

        variables = user_el.find("variables")
        if variables is not None:
            for var in variables.findall("variable"):
                if var.get("name") == "password":
                    password = var.get("value")

        # Insertar en core.sip_users
        cursor.execute("""
            INSERT INTO core.sip_users (
                id, tenant_id, username, password, voicemail_enabled, enabled, insert_date
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (
            user_id, tenant_uuid, username, password, voicemail_enabled, True, datetime.utcnow()
        ))

        # Insertar en core.sip_user_settings
        for section in ["params", "variables"]:
            section_el = user_el.find(section)
            if section_el is not None:
                for param in section_el.findall("param") + section_el.findall("variable"):
                    setting_id = str(uuid.uuid4())
                    name = param.get("name")
                    value = param.get("value")
                    setting_type = section[:-1]  # 'param' o 'variable'

                    cursor.execute("""
                        INSERT INTO core.sip_user_settings (
                            id, sip_user_id, name, type, value, enabled, insert_date
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, (
                        setting_id, user_id, name, setting_type, value, True, datetime.utcnow()
                    ))

    conn.commit()

print("Migración de usuarios SIP completada exitosamente desde /etc/freeswitch/directory")

cursor.close()
conn.close()
