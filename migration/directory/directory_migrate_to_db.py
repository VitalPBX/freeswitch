import os
import uuid
import xml.etree.ElementTree as ET
import pyodbc
from datetime import datetime

# Configuración ODBC
ODBC_DSN = "ring2all"
DIRECTORY_PATH = "/etc/freeswitch/directory"

# Conexión a la base de datos
conn = pyodbc.connect(f"DSN={ODBC_DSN}")
cursor = conn.cursor()

# Obtener tenant_uuid del tenant Default
cursor.execute("SELECT id FROM core.tenants WHERE name = 'Default'")
tenant_row = cursor.fetchone()
if not tenant_row:
    raise Exception("El tenant 'Default' no existe en la base de datos")
tenant_uuid = tenant_row[0]

def process_user_file(xml_file):
    tree = ET.parse(xml_file)
    root = tree.getroot()
    for user_elem in root.findall(".//user"):
        username = user_elem.get("id")
        if not username:
            continue

        # Intentar obtener el password
        password = user_elem.findtext('params/param[@name="password"]')
        if not password:
            print(f"Usuario {username} sin password definido, asignando 'r2a1234'.")
            password = "r2a1234"

        settings = []
        voicemail = {}

        for param in user_elem.findall(".//param"):
            name = param.get("name")
            value = param.get("value")
            if name != "password":  # Ya procesamos password
                settings.append((name, "param", value))

        for variable in user_elem.findall(".//variable"):
            name = variable.get("name")
            value = variable.get("value")
            settings.append((name, "variable", value))

            # Captura básica de configuración de voicemail
            if name in ["vm-password", "vm-email"]:
                voicemail[name] = value

        # Comprobar si el usuario ya existe
        cursor.execute("SELECT id FROM core.sip_users WHERE username = ? AND tenant_id = ?", (username, tenant_uuid))
        existing = cursor.fetchone()
        if existing:
            print(f"Usuario {username} ya existe. Saltando...")
            continue

        # Insertar en core.sip_users
        user_id = str(uuid.uuid4())
        cursor.execute("""
            INSERT INTO core.sip_users (
                id, tenant_id, username, password, enabled, insert_date
            ) VALUES (?, ?, ?, ?, ?, ?)
        """, (user_id, tenant_uuid, username, password, True, datetime.utcnow()))

        # Insertar settings
        for name, setting_type, value in settings:
            setting_id = str(uuid.uuid4())
            cursor.execute("""
                INSERT INTO core.sip_user_settings (
                    id, sip_user_id, name, type, value, enabled, insert_date
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (setting_id, user_id, name, setting_type, value, True, datetime.utcnow()))

        # Insertar voicemail si hay datos
        if voicemail:
            voicemail_id = str(uuid.uuid4())
            cursor.execute("""
                INSERT INTO core.voicemail (
                    id, sip_user_id, tenant_id, password, email, enabled, insert_date
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                voicemail_id, user_id, tenant_uuid,
                voicemail.get("vm-password", "0000"),
                voicemail.get("vm-email", None),
                True, datetime.utcnow()
            ))

        conn.commit()
        print(f"Usuario {username} migrado exitosamente.")

def migrate_directory():
    for dirpath, _, filenames in os.walk(DIRECTORY_PATH):
        for filename in filenames:
            if filename.endswith(".xml"):
                full_path = os.path.join(dirpath, filename)
                try:
                    process_user_file(full_path)
                except Exception as e:
                    print(f"Error procesando {full_path}: {e}")

migrate_directory()

cursor.close()
conn.close()
print("Migración de usuarios SIP completada.")
