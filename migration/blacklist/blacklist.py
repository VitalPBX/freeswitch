import os
import uuid
import xml.etree.ElementTree as ET
import pyodbc
from datetime import datetime

# Configuración
ODBC_DSN = "ring2all"
BLACKLIST_PATH = "/etc/freeswitch/blacklists/example.list"  # Ajusta si se encuentra en otra ruta

# Conexión a la base de datos
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Obtener tenant_uuid del tenant Default
cursor.execute("SELECT tenant_uuid FROM tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("El tenant 'Default' no existe en la base de datos")
tenant_uuid = tenant_row[0]

def migrate_blacklist(xml_path):
    if not os.path.isfile(xml_path):
        print(f"Archivo no encontrado: {xml_path}")
        return

    tree = ET.parse(xml_path)
    root = tree.getroot()

    for entry in root.findall(".//blacklist"):
        value = entry.get("number") or entry.get("pattern")
        if not value:
            continue

        scope = entry.get("scope", "inbound")
        source = entry.get("source", "manual")
        type_ = "pattern" if entry.get("pattern") else "number"
        description = entry.get("description", "")

        cursor.execute("""
            SELECT 1 FROM core.blacklist 
            WHERE tenant_id = ? AND value = ? AND scope = ?
        """, (tenant_uuid, value, scope))
        if cursor.fetchone():
            print(f"Entrada ya existe: {value}")
            continue

        blacklist_id = str(uuid.uuid4())
        cursor.execute("""
            INSERT INTO core.blacklist (
                id, tenant_id, type, value, description, source, scope,
                enabled, insert_date
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            blacklist_id, tenant_uuid, type_, value, description, source, scope,
            True, datetime.utcnow()
        ))
        print(f"Migrada entrada: {value}")

    conn.commit()

# Ejecutar migración
migrate_blacklist(BLACKLIST_PATH)

cursor.close()
conn.close()
print("Migración de blacklist completada.")
