#!/usr/bin/env python3

import os
import uuid
import xml.etree.ElementTree as ET
import pyodbc
import logging

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('migration_voicemail.log'),
        logging.StreamHandler()
    ]
)

# Configuracion general
ODBC_DSN = "ring2all"
VOICEMAIL_DIR = "/etc/freeswitch/voicemail/default"
DEFAULT_TENANT_NAME = "Default"

# Conexion a base de datos
def connect_db():
    try:
        conn = pyodbc.connect(f"DSN={ODBC_DSN}")
        logging.info("✅ Conexión a la base de datos establecida correctamente.")
        return conn
    except Exception as e:
        logging.error(f"❌ Error conectando a la base de datos: {e}")
        raise

# Obtener UUID del tenant

def get_tenant_uuid(conn):
    cur = conn.cursor()
    cur.execute("SELECT tenant_uuid FROM tenants WHERE name = ?", (DEFAULT_TENANT_NAME,))
    result = cur.fetchone()
    cur.close()
    if result:
        logging.info(f"🔍 Tenant '{DEFAULT_TENANT_NAME}' encontrado con UUID: {result[0]}")
        return result[0]
    else:
        raise Exception(f"Tenant '{DEFAULT_TENANT_NAME}' no encontrado.")

# Procesar XML de voicemail

def process_voicemail_file(file_path):
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        vm_elem = root.find("user")
        if vm_elem is None:
            logging.warning(f"⚠️ No se encontró <user> en {file_path}")
            return None

        mailbox_id = vm_elem.get("id")
        vm_password = vm_elem.find("params/param[@name='vm-password']")
        password = vm_password.get("value") if vm_password is not None else None

        return {
            "mailbox": mailbox_id,
            "password": password,
            "enabled": True
        }
    except Exception as e:
        logging.error(f"❌ Error procesando {file_path}: {e}")
        return None

# Insertar en base de datos

def insert_voicemail_box(conn, tenant_uuid, vm_data):
    try:
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO core.voicemail_boxes (
                voicemail_uuid, tenant_uuid, mailbox, password, enabled
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (tenant_uuid, mailbox)
            DO UPDATE SET password = EXCLUDED.password, enabled = EXCLUDED.enabled
        """, (
            str(uuid.uuid4()),
            tenant_uuid,
            vm_data['mailbox'],
            vm_data['password'],
            vm_data['enabled']
        ))
        conn.commit()
        cur.close()
        logging.info(f"✅ Buzón de voz {vm_data['mailbox']} insertado/actualizado correctamente.")
    except Exception as e:
        conn.rollback()
        logging.error(f"❌ Error insertando buzón {vm_data['mailbox']}: {e}")

# Ejecutar migración

def migrate_voicemail():
    logging.info("🌟 Iniciando migración de buzones de voz...")
    conn = connect_db()
    tenant_uuid = get_tenant_uuid(conn)

    for root_dir, _, files in os.walk(VOICEMAIL_DIR):
        for file in files:
            if file.endswith(".xml"):
                file_path = os.path.join(root_dir, file)
                vm_data = process_voicemail_file(file_path)
                if vm_data:
                    insert_voicemail_box(conn, tenant_uuid, vm_data)

    conn.close()
    logging.info("🏁 Migración de buzones de voz completada.")

if __name__ == "__main__":
    migrate_voicemail()
