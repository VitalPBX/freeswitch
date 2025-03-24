#!/usr/bin/env python3

import os
import uuid
import xml.etree.ElementTree as ET
import pyodbc
from datetime import datetime

# Configuración de conexión ODBC
ODBC_DSN = "ring2all"

# Carpeta de perfiles SIP XML
SIP_PROFILE_DIR = "/etc/freeswitch/sip_profiles"

# Obtener archivos XML del directorio de perfiles
xml_files = [f for f in os.listdir(SIP_PROFILE_DIR) if f.endswith(".xml")]

# Función para extraer el puerto del bind-address
def extract_port(bind_address):
    if ":" in bind_address:
        return int(bind_address.split(":")[-1])
    return None

# Conexión a la base de datos
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Obtener tenant_uuid del tenant Default
cursor.execute("SELECT id FROM core.tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("El tenant 'Default' no existe en la base de datos")
tenant_uuid = tenant_row[0]

for file_name in xml_files:
    path = os.path.join(SIP_PROFILE_DIR, file_name)
    tree = ET.parse(path)
    root = tree.getroot()

    for profile in root.findall(".//profile"):
        profile_id = str(uuid.uuid4())
        profile_name = profile.get("name")
        settings = profile.find("settings")

        # Valores iniciales para la tabla core.sip_profiles
        bind_address = None
        sip_port = None
        transport = None
        tls_enabled = False

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

        # Insertar en core.sip_profiles
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

        # Insertar cada parámetro como setting
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

    conn.commit()

print("Migración completada exitosamente desde /etc/freeswitch/sip_profiles")

# Cerrar conexión
cursor.close()
conn.close()
